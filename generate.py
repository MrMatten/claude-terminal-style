#!/usr/bin/env python3
"""Render every target config from one palette file.

Usage: ./generate.py [palette/nord.json]
Writes build/claude-theme.json, build/tmux.snippet.conf, build/ghostty.snippet.conf
"""
import json, sys, pathlib

root = pathlib.Path(__file__).resolve().parent
src = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / "palette" / "nord.json"
p = json.loads(src.read_text())
c, L = p["colors"], p["layout"]
out = root / "build"
out.mkdir(exist_ok=True)

# --- Claude Code theme -------------------------------------------------------
# Only tokens verified against the running binary and working theme files.
theme = {
    "name": p["name"],
    "base": "dark",
    "overrides": {
        "text":                       c["prose"],
        "subtle":                     c["prose_subtle"],
        "inactive":                   c["prose_faint"],
        "claude":                     c["accent"],
        "suggestion":                 c["info"],
        "success":                     c["success"],
        "error":                      c["error"],
        "warning":                     c["warning"],
        "userMessageBackground":      c["bg"],
        "userMessageBackgroundHover": c["bg_alt"],
        "bashMessageBackgroundColor": c["bg_deep"],
        "bashBorder":                 c["border_accent"],
        "memoryBackgroundColor":      c["bg"],
        "promptBorder":               c["border"],
        "secondaryBorder":            c["bg_alt"],
    },
}
slug = p["name"].lower().replace(" ", "-")
(out / "claude-theme.json").write_text(json.dumps(theme, indent=2) + "\n")

# --- tmux --------------------------------------------------------------------
(out / "tmux.snippet.conf").write_text(f"""\
# >>> claude-terminal-style >>>
# Centre single-pane windows while claude runs in them. Adaptive: windows at or
# below @claude-width stay full width. Never touches a window you have split.
# Reset one window with: prefix W
set -g @claude-width {L["text_width"]}
set -g @claude-pad-bg "{L["pad_background"]}"
set-hook -g after-select-window 'run-shell -b "~/.tmux/scripts/claude-width.sh sync #{{session_name}}:#{{window_index}}"'
set-hook -g after-select-pane   'run-shell -b "~/.tmux/scripts/claude-width.sh sync #{{session_name}}:#{{window_index}}"'
set-hook -g client-attached     'run-shell -b "~/.tmux/scripts/claude-width.sh sync #{{session_name}}:#{{window_index}}"'
set-hook -g client-resized      'run-shell -b "~/.tmux/scripts/claude-width.sh sync #{{session_name}}:#{{window_index}}"'
set-hook -g window-layout-changed 'run-shell -b "~/.tmux/scripts/claude-width.sh sync #{{session_name}}:#{{window_index}}"'
set-hook -g pane-exited           'run-shell -b "~/.tmux/scripts/claude-width.sh sync #{{session_name}}:#{{window_index}}"'
bind W run-shell '~/.tmux/scripts/claude-width.sh restore "#{{session_name}}:#{{window_index}}"'
# <<< claude-terminal-style <<<
""")

# --- ghostty -----------------------------------------------------------------
(out / "ghostty.snippet.conf").write_text(f"""\
# >>> claude-terminal-style >>>
# Claude Code highlights code with plain ANSI colour names, so the terminal
# palette decides how code looks. This theme matches nvim (LazyVim tokyonight
# style=moon), which uses truecolor and is unaffected by the ANSI palette.
theme = {L["ghostty_theme"]}
# <<< claude-terminal-style <<<
""")

print(f"palette : {src}")
for f in ("claude-theme.json", "tmux.snippet.conf", "ghostty.snippet.conf"):
    print(f"wrote   : build/{f}")
print(f"slug    : {slug}  (activate with \"theme\": \"custom:{slug}\")")

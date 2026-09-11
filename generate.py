#!/usr/bin/env python3
"""Render every target config from one palette file.

Usage: ./generate.py [palette/nord.json]
Writes build/claude-theme.json, build/tmux.snippet.conf, build/ghostty.snippet.conf
"""
import json, sys, pathlib

root = pathlib.Path(__file__).resolve().parent
src = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / "palette" / "frappe.json"
p = json.loads(src.read_text())
c, L = p["colors"], p["layout"]
out = root / "build"
out.mkdir(exist_ok=True)

# --- Claude Code theme -------------------------------------------------------
# Only tokens verified against the running binary and working theme files.
theme = {
    "name": p["name"],
    # This base stores `permission` as ansi:blueBright, which is the ONLY way to
    # make inline code themeable - see README.
    "base": L.get("theme_base", "dark"),
    "overrides": {
        "text":                       c["prose"],
        "subtle":                     c["prose_subtle"],
        "inactive":                   c["prose_faint"],
        "claude":                     c["accent"],
        # `permission` is the ONLY themeable markdown element: the terminal
        # renderer does `case "codespan": return Vo("permission", ...)`.
        # It also colours permission prompts.
        "permission":                 c["code_inline"],
        "suggestion":                 c["info"],
        "success":                     c["success"],
        "error":                      c["error"],
        "warning":                     c["warning"],
        # must stay distinct from the chat pane background, which the tmux
        # layer paints with colors.bg - otherwise the band is invisible
        "userMessageBackground":      c["bg_alt"],
        "userMessageBackgroundHover": c["bg_raised"],
        "bashMessageBackgroundColor": c["bg_deep"],
        "bashBorder":                 c["border_accent"],
        "memoryBackgroundColor":      c["bg_alt"],
        "promptBorder":               c["border"],
    },
}
slug = p["name"].lower().replace(" ", "-")
(out / "claude-theme.json").write_text(json.dumps(theme, indent=2) + "\n")

# --- tmux --------------------------------------------------------------------
(out / "tmux.snippet.conf").write_text(f"""\
# >>> claude-terminal-style >>>
# While claude runs alone in a window: darken the pane background and centre the
# text in a @claude-width column. Adaptive - a window at or below that width is
# left full width. Never touches a window you have split.
# Reset one window with: prefix W
# Claude Code quantises colours to the 256-palette unless chalk reports level 3.
# TERM inside tmux is screen/tmux-256color, which caps it there even when
# COLORTERM=truecolor, so force it. Without this every theme hex is rounded.
set-environment -g FORCE_COLOR 3

set -g @claude-width {L["text_width"]}
set -g @claude-bg "{L["claude_background"]}"
set -g @claude-surround "{L["claude_surround"]}"
set -g @claude-pad {L["pad_columns"]}
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
# Claude Code highlights fenced code blocks with plain ANSI colour NAMES, so the
# terminal's 16-colour palette decides how code looks. This theme matches nvim
# (LazyVim tokyonight style=moon), which uses truecolor and is unaffected by it.
theme = {L["ghostty_theme"]}

# Claude Code emits NO colour for assistant prose, so it renders in the terminal
# default foreground. Dimming that is the only way to make prose recede, and it
# is what separates prose from inline code (which is hardcoded to #b1b9f9 and
# cannot be themed - see README). Warm rather than blue-grey: inline code is a
# cool periwinkle, so hue separation does far more work than brightness. Chosen
# by maximising the MINIMUM deltaE to every colour that appears in code
# (periwinkle, keyword blue, cyan, green, red, yellow) - a warm sand scores
# better against inline code but collides with the yellow used for functions.
# Must come after `theme`, which also sets the foreground.
foreground = {L["terminal_foreground"]}

# Inline code resolves to `ansi:blueBright` on this theme base, i.e. palette slot
# 12. The syntax highlighter only uses the NORMAL slots, so 12 is free to
# repurpose. This is the only way to colour inline code at all.
palette = 12={L["inline_code_ansi12"]}

# With truecolor unavailable, Claude Code quantises to the 256-palette and inline
# code lands on index 105 (measured - nothing else uses it). Setting both covers
# either case.
palette = 105={L["inline_code_index105"]}
# <<< claude-terminal-style <<<
""")

print(f"palette : {src}")
for f in ("claude-theme.json", "tmux.snippet.conf", "ghostty.snippet.conf"):
    print(f"wrote   : build/{f}")
print(f"slug    : {slug}  (activate with \"theme\": \"custom:{slug}\")")

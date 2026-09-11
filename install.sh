#!/usr/bin/env bash
# Install (or remove) claude-terminal-style.
#
#   ./install.sh              install / update, idempotent
#   ./install.sh --uninstall  remove every change it made
#
# Touches: ~/.tmux/scripts/, ~/.claude/themes/, ~/.claude/settings.json,
#          ~/.tmux.conf, Ghostty config. Marker-delimited, so re-running is safe.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BEGIN="# >>> claude-terminal-style >>>"
END="# <<< claude-terminal-style <<<"

TMUX_CONF="${TMUX_CONF:-$HOME/.tmux.conf}"
GHOSTTY_CONF="${GHOSTTY_CONF:-$HOME/.config/ghostty/config}"
SETTINGS="$HOME/.claude/settings.json"

say() { printf '  %s\n' "$*"; }

# Replace the marker block in $1 with the contents of $2 (or remove it if $2 empty).
# Inserts before the tpm line when adding to a tmux.conf for the first time.
block() {
  BEGIN="$BEGIN" END="$END" python3 - "$1" "${2:-}" <<'PY'
import sys, os, pathlib
target, snippet = pathlib.Path(sys.argv[1]), sys.argv[2]
begin, end = os.environ["BEGIN"], os.environ["END"]
if not target.exists():
    target.parent.mkdir(parents=True, exist_ok=True); target.write_text("")
text = target.read_text()
new = pathlib.Path(snippet).read_text() if snippet else ""
i, j = text.find(begin), text.find(end)
if i != -1 and j != -1:
    text = text[:i] + new + text[j + len(end):].lstrip("\n")
elif new:
    tpm = "# Initialize TMUX plugin manager"
    if tpm in text:
        text = text.replace(tpm, new + "\n" + tpm, 1)
    else:
        text = text.rstrip("\n") + "\n\n" + new
target.write_text(text)
print(("removed from " if not new else "wrote ") + str(target))
PY
}

if [[ "${1:-}" == "--uninstall" ]]; then
  echo "Removing claude-terminal-style…"
  block "$TMUX_CONF" ""
  block "$GHOSTTY_CONF" ""
  rm -f "$HOME/.tmux/scripts/claude-width.sh"
  say "deleted ~/.tmux/scripts/claude-width.sh"
  python3 - "$SETTINGS" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
if p.exists():
    d = json.loads(p.read_text())
    if str(d.get("theme", "")).startswith("custom:"):
        d.pop("theme"); print("  cleared theme from settings.json")
    hooks = d.get("hooks", {})
    for event in ("SessionStart", "SessionEnd"):
        kept = [e for e in hooks.get(event, [])
                if not any("claude-width.sh" in h.get("command", "")
                           for h in e.get("hooks", []))]
        if kept: hooks[event] = kept
        else: hooks.pop(event, None)
    if not hooks: d.pop("hooks", None)
    print("  removed session hooks from settings.json")
    p.write_text(json.dumps(d, indent=2) + "\n")
PY
  # tear down any live padding before the script disappears
  if command -v tmux >/dev/null && tmux info >/dev/null 2>&1; then
    for w in $(tmux list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null); do
      for pane in $(tmux list-panes -t "$w" -F '#{pane_id} #{@claude-pad}' 2>/dev/null | awk '$2=="1"{print $1}'); do
        tmux kill-pane -t "$pane" 2>/dev/null || true
      done
      tmux set-option -w -t "$w" -u @claude-narrowed 2>/dev/null || true
      tmux set-option -w -t "$w" -u pane-border-style 2>/dev/null || true
      tmux set-option -w -t "$w" -u pane-active-border-style 2>/dev/null || true
    done
    for h in after-select-window after-select-pane client-attached; do
      tmux set-hook -gu "$h" 2>/dev/null || true
    done
    say "unhooked and un-padded the running tmux server"
  fi
  echo "Done. Reload Ghostty with Cmd+Shift+, to drop the theme."
  exit 0
fi

echo "Installing claude-terminal-style…"
"$ROOT/generate.py" >/dev/null
say "generated build/ from palette"

mkdir -p "$HOME/.tmux/scripts" "$HOME/.claude/themes"
install -m 0755 "$ROOT/tmux/claude-width.sh" "$HOME/.tmux/scripts/claude-width.sh"
say "installed ~/.tmux/scripts/claude-width.sh"

SLUG="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["name"].lower().replace(" ","-"))' "$ROOT/palette/frappe.json")"
cp "$ROOT/build/claude-theme.json" "$HOME/.claude/themes/$SLUG.json"
say "installed ~/.claude/themes/$SLUG.json"

block "$TMUX_CONF"    "$ROOT/build/tmux.snippet.conf"
block "$GHOSTTY_CONF" "$ROOT/build/ghostty.snippet.conf"

SLUG="$SLUG" python3 - "$SETTINGS" <<'PY'
import json, os, pathlib, sys
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text()) if p.exists() else {}
p.parent.mkdir(parents=True, exist_ok=True)
if p.exists():
    (p.parent / "settings.json.bak").write_text(p.read_text())
d["theme"] = "custom:" + os.environ["SLUG"]
d.setdefault("showMessageTimestamps", True)
d.setdefault("tui", "fullscreen")   # userMessageBackground only renders here

# Centre at the moment a session starts, un-centre when it ends. Catches every
# launch path (shell, tmux teammates, --worktree), unlike a shell wrapper.
SCRIPT = "~/.tmux/scripts/claude-width.sh"
hooks = d.setdefault("hooks", {})
for event, mode in (("SessionStart", "apply"), ("SessionEnd", "restore")):
    entries = [e for e in hooks.get(event, [])
               if not any(SCRIPT in h.get("command", "")
                          for h in e.get("hooks", []))]
    entries.append({"hooks": [{"type": "command",
                               "command": f"{SCRIPT} {mode}"}]})
    hooks[event] = entries
p.write_text(json.dumps(d, indent=2) + "\n")
print("  set theme/showMessageTimestamps/tui in settings.json (backup: settings.json.bak)")
PY

if command -v tmux >/dev/null && tmux info >/dev/null 2>&1; then
  tmux source-file "$TMUX_CONF" && say "reloaded tmux config"
fi

cat <<'MSG'

Done. Two manual steps:
  1. Ghostty: press Cmd+Shift+, to reload (config changes are not picked up automatically)
  2. Claude Code: the theme hot-reloads, but timestamps need a restart

Tune by editing palette/nord.json, then re-run ./install.sh
Remove everything with ./install.sh --uninstall
MSG

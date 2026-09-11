#!/usr/bin/env bash
# Centre a tmux window while Claude Code runs alone in it, using two blank
# padding panes. Adaptive: a window at or below the target width is left alone.
#
#   sync    [target]  reconcile: centre, re-centre or restore as needed
#   apply   [target]  centre now (SessionStart hook)
#   restore [target]  remove padding
#
# State is derived from the panes themselves, never from the active pane, so a
# split or resize is always reconciled correctly.
set -u

mode=${1:-sync}
target=${2:-}
[ -n "$target" ] || target=$(tmux display-message -p '#{session_name}:#{window_index}' 2>/dev/null)
[ -n "$target" ] || exit 0

width=$(tmux show-options -gqv @claude-width 2>/dev/null); [ -n "$width" ] || width=100
bg=$(tmux show-options -gqv @claude-bg 2>/dev/null); [ -n "$bg" ] || bg="#16161e"

get() { tmux display-message -p -t "$target" "$1" 2>/dev/null; }
PADCMD='printf "\033[?25l"; exec cat'

# Hooks fire with run-shell -b, so several reconciliations can overlap and clobber
# each other. Serialise them per window; mkdir is atomic.
LOCK="${TMPDIR:-/tmp}/claude-width.$(printf '%s' "$target" | tr -c 'A-Za-z0-9_.-' '_').lock"
acquire() {
  local i=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    # drop a lock left behind by a killed process
    if [ -d "$LOCK" ]; then
      local age
      age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
      [ "$age" -gt 10 ] && rm -rf "$LOCK" && continue
    fi
    i=$((i+1)); [ "$i" -gt 20 ] && return 1
    sleep 0.1
  done
  trap 'rm -rf "$LOCK"' EXIT INT TERM
  return 0
}
acquire || exit 0

# id|padflag|command|width for every pane that is NOT one of our pads
real_panes() {
  tmux list-panes -t "$target" -F '#{pane_id}|#{@claude-pad}|#{pane_current_command}|#{pane_width}' 2>/dev/null \
    | awk -F'|' '$2!="1"'
}
# A hook can fire before tmux has finished removing a pane, so reconciling
# immediately would see the dying pane and wrongly decide to un-centre. Wait
# until the pane list stops changing.
settle() {
  local a b i=0
  a=$(tmux list-panes -t "$target" -F '#{pane_id}|#{pane_width}' 2>/dev/null)
  while [ "$i" -lt 10 ]; do
    sleep 0.12
    b=$(tmux list-panes -t "$target" -F '#{pane_id}|#{pane_width}' 2>/dev/null)
    [ "$a" = "$b" ] && return 0
    a=$b; i=$((i+1))
  done
}

is_padded() {
  [ "$(tmux show-options -qv -w -t "$target" @claude-narrowed 2>/dev/null)" = "1" ]
}

add_pads() {
  local cur pane total left right lp rp
  cur=$(get '#{window_width}')
  [ -n "$cur" ] || return 1
  [ "$cur" -gt "$((width + 4))" ] || return 1
  pane=$(real_panes | head -1 | cut -d'|' -f1)
  [ -n "$pane" ] || return 1
  total=$(( cur - width - 2 )); left=$(( total / 2 )); right=$(( total - left ))
  [ "$left" -ge 1 ] && [ "$right" -ge 1 ] || return 1

  lp=$(tmux split-window -h -b -d -l "$left"  -t "$pane" -P -F '#{pane_id}' "$PADCMD" 2>/dev/null) || return 1
  [ -n "$lp" ] && tmux set-option -p -t "$lp" @claude-pad 1
  rp=$(tmux split-window -h    -d -l "$right" -t "$pane" -P -F '#{pane_id}' "$PADCMD" 2>/dev/null) || true
  [ -n "$rp" ] && tmux set-option -p -t "$rp" @claude-pad 1

  tmux set-option -w -t "$target" @claude-narrowed 1
}

# Darken the whole window and paint the pane borders to match, so the padding
# panes are seamless. Applied whenever claude owns the window, independent of
# whether the window is wide enough to actually pad.
style_on() {
  tmux set-option -w -t "$target" window-style             "bg=$bg"
  tmux set-option -w -t "$target" window-active-style      "bg=$bg"
  tmux set-option -w -t "$target" pane-border-style        "fg=$bg"
  tmux set-option -w -t "$target" pane-active-border-style "fg=$bg"
  tmux set-option -w -t "$target" @claude-styled 1
}
style_off() {
  [ "$(tmux show-options -qv -w -t "$target" @claude-styled 2>/dev/null)" = "1" ] || return 0
  tmux set-option -w -t "$target" -u window-style
  tmux set-option -w -t "$target" -u window-active-style
  tmux set-option -w -t "$target" -u pane-border-style
  tmux set-option -w -t "$target" -u pane-active-border-style
  tmux set-option -w -t "$target" -u @claude-styled
}

drop_pads() {
  is_padded || return 0
  local p
  for p in $(tmux list-panes -t "$target" -F '#{pane_id}|#{@claude-pad}' 2>/dev/null | awk -F'|' '$2=="1"{print $1}'); do
    tmux kill-pane -t "$p" 2>/dev/null
  done
  tmux set-option -w -t "$target" -u @claude-narrowed
}

# Should this window be centred? Only when exactly one real pane, running claude.
wants_centre() {
  local rows
  rows=$(real_panes)
  [ "$(printf '%s\n' "$rows" | grep -c . )" = "1" ] || return 1
  [ "$(printf '%s\n' "$rows" | cut -d'|' -f3)" = "claude" ] || return 1
}

case "$mode" in
  apply)
    style_on
    is_padded && exit 0
    add_pads || true
    ;;
  restore)
    drop_pads
    style_off
    ;;
  sync)
    settle
    if wants_centre; then
      style_on
      if is_padded; then
        # already centred - correct the width if the window was resized
        cw=$(real_panes | cut -d'|' -f4)
        if [ -n "$cw" ] && [ "$cw" != "$width" ]; then
          drop_pads
          add_pads || true
        fi
      else
        add_pads || true
      fi
    else
      drop_pads
      style_off
    fi
    ;;
esac

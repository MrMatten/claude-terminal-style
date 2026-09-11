#!/usr/bin/env bash
# While Claude Code owns a tmux window: darken the window, and centre the chat
# in a fixed-width column with padding either side.
#
#   sync    [target]  reconcile: style/centre/restore as the window requires
#   apply   [target]  style and centre now (SessionStart hook)
#   restore [target]  undo everything
#
# Layout when padded (5 panes):
#   [ outer ][ inner ][ CHAT ][ inner ][ outer ]
#   outer = surround colour   inner = chat colour, i.e. the padding
# Borders are painted in the chat colour so the padded block has no seams.
set -u

mode=${1:-sync}
target=${2:-}
[ -n "$target" ] || target=$(tmux display-message -p '#{session_name}:#{window_index}' 2>/dev/null)
[ -n "$target" ] || exit 0

opt() { local v; v=$(tmux show-options -gqv "$1" 2>/dev/null); [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$2"; }
width=$(opt @claude-width 110)
bg=$(opt @claude-bg "#303446")
surround=$(opt @claude-surround "#232634")
pad=$(opt @claude-pad 4)

LOCK="${TMPDIR:-/tmp}/claude-width.$(printf '%s' "$target" | tr -c 'A-Za-z0-9_.-' '_').lock"
acquire() {
  local i=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    if [ -d "$LOCK" ]; then
      local age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
      [ "$age" -gt 10 ] && rm -rf "$LOCK" && continue
    fi
    i=$((i+1)); [ "$i" -gt 20 ] && return 1
    sleep 0.1
  done
  trap 'rm -rf "$LOCK"' EXIT INT TERM
}
acquire || exit 0

get() { tmux display-message -p -t "$target" "$1" 2>/dev/null; }
real_panes() {
  tmux list-panes -t "$target" -F '#{pane_id}|#{@claude-pad-pane}|#{pane_current_command}|#{pane_width}' 2>/dev/null \
    | awk -F'|' '$2!="1"'
}
is_padded() { [ "$(tmux show-options -qv -w -t "$target" @claude-narrowed 2>/dev/null)" = "1" ]; }

# A blank pane. The inner ones paint themselves in the chat colour, because
# window-style makes every inactive pane the surround colour.
plain_pad='printf "\033[?25l"; exec cat'
colour_pad() {
  local h=${1#\#}
  printf 'printf "\\033[?25l\\033[48;2;%d;%d;%dm\\033[2J"; exec cat' \
    "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}

mkpad() { # mkpad <before|after> <size> <cmd>
  local dir=$1 size=$2 cmd=$3 id
  [ "$size" -ge 1 ] || return 0
  if [ "$dir" = before ]; then
    id=$(tmux split-window -h -b -d -l "$size" -t "$CHAT" -P -F '#{pane_id}' "$cmd" 2>/dev/null)
  else
    id=$(tmux split-window -h    -d -l "$size" -t "$CHAT" -P -F '#{pane_id}' "$cmd" 2>/dev/null)
  fi
  [ -n "$id" ] && tmux set-option -p -t "$id" @claude-pad-pane 1
}

add_pads() {
  local cur inner seps total left right
  cur=$(get '#{window_width}')
  [ -n "$cur" ] || return 1
  CHAT=$(real_panes | head -1 | cut -d'|' -f1)
  [ -n "$CHAT" ] || return 1

  inner=$pad
  # 5 panes need 4 separator columns plus both inner pads plus 1 outer each side
  if [ "$cur" -le "$((width + 6 + 2 * inner))" ]; then
    inner=0
    [ "$cur" -gt "$((width + 4))" ] || return 1
  fi
  seps=$([ "$inner" -gt 0 ] && echo 4 || echo 2)
  total=$(( cur - width - seps - 2 * inner ))
  left=$(( total / 2 )); right=$(( total - left ))
  [ "$left" -ge 1 ] && [ "$right" -ge 1 ] || return 1

  # Every split takes its columns FROM the chat pane, so the wide outer pads
  # must be carved first, while the chat pane is still full width.
  mkpad before "$left"  "$plain_pad"
  mkpad after  "$right" "$plain_pad"
  if [ "$inner" -gt 0 ]; then
    local fill; fill=$(colour_pad "$bg")
    mkpad before "$inner" "$fill"
    mkpad after  "$inner" "$fill"
  fi
  tmux set-option -w -t "$target" @claude-narrowed 1
}

drop_pads() {
  is_padded || return 0
  local p
  for p in $(tmux list-panes -t "$target" -F '#{pane_id}|#{@claude-pad-pane}' 2>/dev/null | awk -F'|' '$2=="1"{print $1}'); do
    tmux kill-pane -t "$p" 2>/dev/null
  done
  tmux set-option -w -t "$target" -u @claude-narrowed
}

style_on() {
  tmux set-option -w -t "$target" window-active-style      "bg=$bg"
  tmux set-option -w -t "$target" window-style             "bg=$surround"
  tmux set-option -w -t "$target" pane-border-style        "fg=$bg,bg=$bg"
  tmux set-option -w -t "$target" pane-active-border-style "fg=$bg,bg=$bg"
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

wants_centre() {
  local rows; rows=$(real_panes)
  [ "$(printf '%s\n' "$rows" | grep -c . )" = "1" ] || return 1
  [ "$(printf '%s\n' "$rows" | cut -d'|' -f3)" = "claude" ] || return 1
}

case "$mode" in
  apply)
    style_on
    is_padded || add_pads || true
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
        cw=$(real_panes | cut -d'|' -f4)
        if [ -n "$cw" ] && [ "$cw" != "$width" ]; then drop_pads; add_pads || true; fi
      else
        add_pads || true
      fi
    else
      drop_pads
      style_off
    fi
    ;;
esac

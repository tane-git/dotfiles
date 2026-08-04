#!/usr/bin/env bash
# pane-move-or-split.sh L|D|U|R — move to the adjacent pane in that
# direction, or split one into existence if none exists yet.
#
# This is the one place that logic lives. .tmux.conf's M-hjkl binding calls
# it for plain (non-vim) panes, and nvim's after/plugin/tmux-navigator.lua
# calls it when M-hjkl hits the edge of vim's own splits — so both ends of
# the M-hjkl handoff move-or-create identically without duplicating the
# split/select command text in two languages.
set -u

dir=$1

case "$dir" in
    L) at=pane_at_left;   split=(-h -b) ;;
    D) at=pane_at_bottom; split=(-v) ;;
    U) at=pane_at_top;    split=(-v -b) ;;
    R) at=pane_at_right;  split=(-h) ;;
esac

if [ "$(tmux display-message -p "#{$at}")" = 1 ]; then
    tmux split-window "${split[@]}" -c "#{pane_current_path}"
else
    tmux select-pane "-$dir"
fi

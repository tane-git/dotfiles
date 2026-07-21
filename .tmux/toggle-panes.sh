#!/usr/bin/env bash
# toggle-panes.sh — toggle the current session's windows <-> panes.
#
#   MERGE  (active window has 1 pane): every window LEFT of the active one
#          becomes a pane to the left, every window RIGHT becomes a pane to
#          the right, order preserved, active window stays focused.
#   UNMERGE (active window has >1 pane): the reverse — panes left of the
#          active pane break out as windows to the left, panes to the right
#          break out as windows to the right, active stays put.
#
# Safety:
#   * No recursion: never triggers the M-a binding, only tmux pane/window ops.
#   * No unbounded loops: every loop iterates a one-time snapshot, so it is
#     bounded by the current window/pane count.
#   * Stable references: source windows by window_id (@N), source panes by
#     pane_id (%N), the anchor window by window_id — consuming/breaking items
#     never invalidates a later reference.
set -u

npanes=$(tmux display-message -p '#{window_panes}')

if [ "$npanes" -le 1 ]; then
  # ---------- MERGE: windows -> panes ----------
  active=$(tmux display-message -p '#{window_index}')
  apane=$(tmux display-message -p '#{pane_id}')

  # Left windows, ASCENDING, each joined with -b (immediately left of active)
  # so low->high index preserves left-to-right order.
  for wid in $(tmux list-windows -F '#{window_index} #{window_id}' \
               | awk -v a="$active" '$1 < a' | sort -n | awk '{print $2}'); do
    tmux join-pane -d -h -b -s "$wid" -t "$apane"
  done
  # Right windows, DESCENDING, each joined without -b (immediately right of
  # active) so high->low index preserves order.
  for wid in $(tmux list-windows -F '#{window_index} #{window_id}' \
               | awk -v a="$active" '$1 > a' | sort -rn | awk '{print $2}'); do
    tmux join-pane -d -h -s "$wid" -t "$apane"
  done

  # Each join halves the target's space; normalize to equal-width columns.
  tmux select-layout -t "$apane" even-horizontal
  tmux select-pane -t "$apane"

else
  # ---------- UNMERGE: panes -> windows ----------
  awin=$(tmux display-message -p '#{window_id}')          # stable anchor
  aleft=$(tmux display-message -p '#{pane_left}')         # active pane's x

  # Left panes (x < active), ASCENDING, each broken out with -b (immediately
  # before the anchor window) so low->high x preserves order.
  for pid in $(tmux list-panes -F '#{pane_left} #{pane_id}' \
               | awk -v a="$aleft" '$1 < a' | sort -n | awk '{print $2}'); do
    tmux break-pane -d -b -s "$pid" -t "$awin"
  done
  # Right panes (x > active), DESCENDING, each broken out with -a (immediately
  # after the anchor window) so high->low x preserves order.
  for pid in $(tmux list-panes -F '#{pane_left} #{pane_id}' \
               | awk -v a="$aleft" '$1 > a' | sort -rn | awk '{print $2}'); do
    tmux break-pane -d -a -s "$pid" -t "$awin"
  done
fi

#!/usr/bin/env bash
# toggle-panes.sh — toggle between "every window in the session" and "every
# pane in one window".
#
#   MERGE (more than one window exists): every other window's panes join the
#     current window as panes — windows left of it join left, windows right
#     join right, order preserved. Each pane is tagged with its origin
#     window's name, only if it isn't already tagged, so the name survives
#     even if a pane passes through more than one merge before being undone.
#
#   UNMERGE (exactly one window exists): every pane except the currently
#     active one breaks out into its own window, renamed from its tag if it
#     has one. The active pane's window is never touched, so it stays
#     focused automatically. Left/right position and order are decided by
#     each pane's current on-screen position, not stored state.
#
#   This intentionally does not try to rebuild a window that originally had
#   several panes as one window again — every pane always becomes its own
#   window. Simpler, and good enough for now; revisit if that's ever missed.
#
# Safety:
#   * No recursion: never triggers the M-a binding, only tmux pane/window ops.
#   * No unbounded loops: bounded by current window/pane count.
#   * Stable references: windows by window_id (@N), panes by pane_id (%N).
set -u

OPT_NAME="@toggle-name"

tag_if_unset() {
  local pid="$1" name="$2" existing
  existing=$(tmux display-message -p -t "$pid" "#{$OPT_NAME}")
  [ -z "$existing" ] && tmux set-option -p -t "$pid" "$OPT_NAME" "$name"
}

window_count=$(tmux list-windows | wc -l)

if [ "$window_count" -gt 1 ]; then
  # ---------- MERGE ----------
  active=$(tmux display-message -p '#{window_index}')
  awin=$(tmux display-message -p '#{window_id}')
  apane=$(tmux display-message -p '#{pane_id}')

  # Container's own existing panes just get tagged, never moved.
  while IFS= read -r pid; do
    tag_if_unset "$pid" "$(tmux display-message -p -t "$awin" '#{window_name}')"
  done < <(tmux list-panes -t "$awin" -F '#{pane_id}')

  # Tag and drain every pane of $1's windows (ids, one per line) into $apane.
  # $2 is "-b" for left-side windows, "" for right-side — same
  # order-preserving convention as before (ascending+before / descending+
  # after keeps left-to-right order intact either way).
  merge_side() {
    local wid wname pid
    while IFS= read -r wid; do
      [ -z "$wid" ] && continue
      wname=$(tmux display-message -p -t "$wid" '#{window_name}')
      while IFS= read -r pid; do
        tag_if_unset "$pid" "$wname"
        if [ "$2" = "-b" ]; then
          tmux join-pane -d -h -b -s "$pid" -t "$apane"
        else
          tmux join-pane -d -h -s "$pid" -t "$apane"
        fi
      done < <(tmux list-panes -t "$wid" -F '#{pane_id}')
    done <<< "$1"
  }

  left_wids=$(tmux list-windows -F '#{window_index} #{window_id}' \
              | awk -v a="$active" '$1 < a' | sort -n | awk '{print $2}')
  right_wids=$(tmux list-windows -F '#{window_index} #{window_id}' \
              | awk -v a="$active" '$1 > a' | sort -rn | awk '{print $2}')

  merge_side "$left_wids" "-b"
  merge_side "$right_wids" ""

  # Each join halves the target's space; normalize to equal-width columns.
  tmux select-layout -t "$apane" even-horizontal
  tmux select-pane -t "$apane"

else
  # ---------- UNMERGE ----------
  awin=$(tmux display-message -p '#{window_id}')
  apane=$(tmux display-message -p '#{pane_id}')
  aleft=$(tmux display-message -p '#{pane_left}')

  # Break out one pane per line (pane_left	pane_top	pane_id, ordered),
  # $2 is "-b" (insert before $awin) or "-a" (insert after).
  break_out() {
    local pid name newwin
    while IFS=$'\t' read -r _ _ pid; do
      [ -z "$pid" ] && continue
      name=$(tmux show-options -p -t "$pid" -v "$OPT_NAME" 2>/dev/null)
      tmux break-pane -d "$2" -s "$pid" -t "$awin"
      newwin=$(tmux display-message -p -t "$pid" '#{window_id}')
      [ -n "$name" ] && tmux rename-window -t "$newwin" "$name"
      tmux set-option -p -u -t "$pid" "$OPT_NAME" 2>/dev/null
    done <<< "$1"
  }

  # Left of active, ASCENDING + insert-before; right of active (ties with the
  # active pane's own x-position default to the right) DESCENDING +
  # insert-after — preserves order, and a pane stacked directly above/below
  # the active one no longer gets silently skipped like the old version.
  left=$(tmux list-panes -t "$awin" -F '#{pane_left}	#{pane_top}	#{pane_id}' \
    | awk -F'\t' -v a="$aleft" -v ap="$apane" '$3 != ap && $1 < a' | sort -t$'\t' -k1,1n -k2,2n)
  right=$(tmux list-panes -t "$awin" -F '#{pane_left}	#{pane_top}	#{pane_id}' \
    | awk -F'\t' -v a="$aleft" -v ap="$apane" '$3 != ap && $1 >= a' | sort -t$'\t' -k1,1rn -k2,2rn)

  break_out "$left" "-b"
  break_out "$right" "-a"

  # $awin keeps whatever it was already named, but the pane left inside it
  # (the active one) may have been tagged from a different original window —
  # rename $awin to match so the surviving window reflects what's really in it.
  aname=$(tmux show-options -p -t "$apane" -v "$OPT_NAME" 2>/dev/null)
  [ -n "$aname" ] && tmux rename-window -t "$awin" "$aname"
  tmux set-option -p -u -t "$apane" "$OPT_NAME" 2>/dev/null
fi

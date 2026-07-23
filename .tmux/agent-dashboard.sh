#!/usr/bin/env bash
# agent-dashboard.sh — (re)build a session with one window per running agent.
#
#   Scans every pane on the server for an agent process (currently
#   `opencode`/`claude`) and rebuilds the "agents" session from scratch: one
#   window per agent found, each window's pane running `tmux attach` nested
#   onto a dedicated clone session grouped with the agent's real session
#   (see agent-lib.sh). Nothing about the source sessions is ever touched —
#   session-group membership and attach only add views, they never move or
#   modify the real windows/panes.
#
#   Attaching to a clone rather than the real session directly means each
#   tile can have its own status bar turned off (session options are
#   independent per group member) without touching the real session's own
#   status bar — fixing the double-status-bar row mismatch a direct attach
#   would otherwise cause.
#
#   If the agent pane shares its window with other panes, that window gets
#   zoomed onto the agent pane so the tile shows just it — but only if the
#   window wasn't already zoomed (zoom is a window-level flag shared with
#   the real session, so a pre-existing zoom is left alone and never
#   touched by dashboard cleanup either; see agent-lib.sh's $ZOOM_OPTION).
#
# Safety:
#   * Only ever creates/kills the dashboard session by its fixed name
#     ($DASHBOARD), plus its own tagged clone sessions — never a bare/
#     ambiguous kill-session or kill-server.
#   * Rebuilding is safe: dashboard panes only ever run `tmux attach`, so
#     killing the dashboard session (and its clones) detaches those nested
#     clients and never touches the real agent sessions/windows/panes.
#   * If the invoking client is currently attached to the dashboard session,
#     it's switched to another real session first, so a rebuild never
#     silently detaches the user's terminal.
#   * Every switch-client/display-message call is pinned with -c to the
#     client that pressed the hotkey ($trigger_tty, passed in by the
#     keybinding via #{client_tty}), instead of relying on tmux's own
#     "current client" guess. Per `man tmux` (switch-client): with no -c,
#     tmux "attempts to work out the client currently in use" — from a
#     run-shell subprocess that guess can silently land on the wrong client.
set -u
source ~/.tmux/agent-lib.sh

trigger_tty="${1:?agent-dashboard.sh: missing trigger tty argument}"

AGENT_CMDS="opencode|claude"

# One row per session:window containing an agent pane, plus that pane's id
# (used to zoom it below). If a window has more than one agent pane, only
# the first found is tracked/zoomed — isolating multiple agent panes out of
# the same window is the open TODO in .tmux.conf, not handled here.
mapfile -t agent_windows < <(
  tmux list-panes -a -F '#{session_name}	#{window_index}	#{pane_current_command}	#{pane_id}' \
    | awk -F'\t' -v dash="$DASHBOARD" -v cmds="^($AGENT_CMDS)\$" \
        '$1 != dash && $3 ~ cmds && !seen[$1 SUBSEP $2]++ { print $1 "\t" $2 "\t" $4 }'
)

if [ "${#agent_windows[@]}" -eq 0 ]; then
  tmux display-message "agent-dashboard: no agent panes found"
  exit 0
fi

# Don't let a rebuild detach the client that triggered it.
current_session=$(tmux display-message -p -c "$trigger_tty" '#{session_name}' 2>/dev/null || true)
if [ "$current_session" = "$DASHBOARD" ]; then
  fallback=$(tmux list-sessions -F '#{session_name}' | grep -vx "$DASHBOARD" | head -n1 || true)
  [ -n "$fallback" ] && tmux switch-client -c "$trigger_tty" -t "$fallback"
fi

if tmux has-session -t "$DASHBOARD" 2>/dev/null; then
  tmux kill-session -t "$DASHBOARD"
fi
agent_dashboard_kill_clones

# TMUX= clears the var each new pane otherwise inherits (pointing at this
# dashboard session), which makes a nested `tmux attach` to a *different*
# session exit immediately instead of actually attaching.
first=1
tile=0
for entry in "${agent_windows[@]}"; do
  IFS=$'\t' read -r src_session src_window src_pane <<< "$entry"
  tile=$((tile + 1))
  clone="agentdash-${tile}"

  # Grouped session: shares src_session's windows, but its own current
  # window, status bar and other session options stay independent (see
  # `man tmux`, new-session -t).
  tmux new-session -d -t "$src_session" -s "$clone"
  tmux select-window -t "${clone}:${src_window}"
  tmux set-option -t "$clone" status off
  tmux set-option -t "$clone" "$CLONE_OPTION" "$src_session"

  # Zoom is a *window*-level flag shared with the real session (see
  # agent-lib.sh), so only zoom if nothing was already zoomed — never
  # clobber a zoom the user had set before the dashboard existed, and
  # remember whether we did it so cleanup knows whether to undo it.
  if [ "$(tmux display-message -p -t "$clone" '#{window_zoomed_flag}')" = "1" ]; then
    tmux set-option -t "$clone" "$ZOOM_OPTION" 0
  else
    tmux resize-pane -Z -t "$src_pane"
    tmux set-option -t "$clone" "$ZOOM_OPTION" 1
  fi

  if [ "$first" -eq 1 ]; then
    tmux new-session -d -s "$DASHBOARD" -n "$src_session" "TMUX= tmux attach -t '$clone'"
    first=0
  else
    tmux new-window -t "$DASHBOARD" -n "$src_session" "TMUX= tmux attach -t '$clone'"
  fi
done

tmux switch-client -c "$trigger_tty" -t "$DASHBOARD"

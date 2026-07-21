#!/usr/bin/env bash
# agent-dashboard.sh — (re)build a session with one window per running agent.
#
#   Scans every pane on the server for an agent process (currently just
#   `opencode`) and rebuilds the "agents" session from scratch: one window
#   per agent found, each window's pane running `tmux attach` nested onto the
#   agent's real session:window. Nothing about the source sessions is ever
#   touched — attach only adds a client, it never moves or modifies panes.
#
# Safety:
#   * Only ever creates/kills the dashboard session by its fixed name
#     ($DASHBOARD) — never a bare/ambiguous kill-session or kill-server.
#   * Rebuilding is safe: dashboard panes only ever run `tmux attach`, so
#     killing the dashboard session detaches those nested clients and never
#     touches the real agent sessions/windows/panes.
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

AGENT_CMDS="opencode"   # extend later, e.g. "opencode|claude"

# Unique session:window pairs whose active pane is running an agent command.
mapfile -t agent_windows < <(
  tmux list-panes -a -F '#{session_name}	#{window_index}	#{pane_current_command}' \
    | awk -F'\t' -v dash="$DASHBOARD" -v cmds="^($AGENT_CMDS)\$" \
        '$1 != dash && $3 ~ cmds { print $1 "\t" $2 }' \
    | sort -u
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

# TMUX= clears the var each new pane otherwise inherits (pointing at this
# dashboard session), which makes a nested `tmux attach` to a *different*
# session exit immediately instead of actually attaching.
first=1
for entry in "${agent_windows[@]}"; do
  IFS=$'\t' read -r src_session src_window <<< "$entry"
  target="${src_session}:${src_window}"
  if [ "$first" -eq 1 ]; then
    tmux new-session -d -s "$DASHBOARD" -n "$src_session" "TMUX= tmux attach -t '$target'"
    first=0
  else
    tmux new-window -t "$DASHBOARD" -n "$src_session" "TMUX= tmux attach -t '$target'"
  fi
done

tmux switch-client -c "$trigger_tty" -t "$DASHBOARD"

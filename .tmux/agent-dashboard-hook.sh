#!/usr/bin/env bash
# agent-dashboard-hook.sh — bound to the client-session-changed hook; tears
# down the dashboard the instant a client leaves it, however it left (M-s,
# M-b, anything). A nested tmux-attach client left running inside a
# dashboard tile stays a contender for that window's size (window-size
# latest), which can steal the real session's rendering back down to the
# tile's smaller size — killing the dashboard and its clone sessions
# cleanly detaches all its nested clients (see agent-dashboard.sh) without
# touching anything real.
#
#   tmux 3.6a's hook formats don't expose the client's *previous* session
#   directly, only its current one — so this tracks each client's last-seen
#   session itself in a small state file (one per client tty) and diffs
#   against the session it's on now.
set -u
source ~/.tmux/agent-lib.sh

client_tty="${1:?agent-dashboard-hook.sh: missing client tty argument}"
new_session="${2:?agent-dashboard-hook.sh: missing session argument}"

state_dir="/tmp/agent-dashboard-state"
mkdir -p "$state_dir"
state_file="$state_dir/$(echo "$client_tty" | tr '/' '_')"

old_session=""
[ -f "$state_file" ] && old_session=$(cat "$state_file")
echo "$new_session" > "$state_file"

if [ "$old_session" = "$DASHBOARD" ] && [ "$new_session" != "$DASHBOARD" ]; then
  tmux kill-session -t "$DASHBOARD" 2>/dev/null || true
  agent_dashboard_kill_clones
fi

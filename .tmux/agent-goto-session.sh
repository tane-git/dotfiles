#!/usr/bin/env bash
# agent-goto-session.sh — from the agent dashboard, switch the base client to
# whichever real session the currently focused tile is actually showing.
#
#   Each dashboard pane runs a nested `tmux attach` client. Rather than
#   tagging panes with the session they were created against (a second,
#   driftable copy of the truth), this asks the nested client itself what
#   it's currently attached to: the outer pane's tty is the nested client's
#   controlling terminal, so matching pane_tty against client_tty finds the
#   right client, and its client_session is always live and correct — even
#   if the source session gets renamed, or the nested client is ever pointed
#   elsewhere after creation.
#
#   Nested clients attach to a per-tile clone session (see agent-dashboard.sh
#   / agent-lib.sh), not the real session directly, so client_session here is
#   a clone name — its $CLONE_OPTION value is the real session to switch to.
#
# Safety: only acts while attached to the dashboard session. If no matching
# nested client is found, it says so instead of switching anywhere.
# Every call is pinned with -c to the client that pressed the hotkey
# ($trigger_tty, passed in by the keybinding via #{client_tty}) instead of
# relying on tmux's own "current client" guess — see agent-dashboard.sh.
set -u
source ~/.tmux/agent-lib.sh

trigger_tty="${1:?agent-goto-session.sh: missing trigger tty argument}"

if [ "$(tmux display-message -p -c "$trigger_tty" '#{session_name}')" != "$DASHBOARD" ]; then
  exit 0
fi

pane_tty=$(tmux display-message -p -c "$trigger_tty" '#{pane_tty}')
clone=$(
  tmux list-clients -F '#{client_tty}	#{client_session}' \
    | awk -F'\t' -v tty="$pane_tty" '$1 == tty { print $2; exit }'
)

if [ -z "$clone" ]; then
  tmux display-message "agent-goto-session: no agent client found for this pane"
  exit 0
fi

target=$(tmux show-options -t "$clone" -v "$CLONE_OPTION" 2>/dev/null || true)
[ -z "$target" ] && target="$clone"

tmux switch-client -c "$trigger_tty" -t "$target"

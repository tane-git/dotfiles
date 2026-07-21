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
# Safety: only acts while attached to the dashboard session. If no matching
# nested client is found, it says so instead of switching anywhere.
set -u
source ~/.tmux/agent-lib.sh

if [ "$(tmux display-message -p '#{session_name}')" != "$DASHBOARD" ]; then
  exit 0
fi

pane_tty=$(tmux display-message -p '#{pane_tty}')
target=$(
  tmux list-clients -F '#{client_tty}	#{client_session}' \
    | awk -F'\t' -v tty="$pane_tty" '$1 == tty { print $2; exit }'
)

if [ -z "$target" ]; then
  tmux display-message "agent-goto-session: no agent client found for this pane"
  exit 0
fi

tmux switch-client -t "$target"

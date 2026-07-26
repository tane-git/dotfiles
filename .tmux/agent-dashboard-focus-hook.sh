#!/usr/bin/env bash
# agent-dashboard-focus-hook.sh — bound to the global pane-focus-in hook;
# tracks which dashboard tile is focused so clone status bars can highlight
# themselves.
#
#   Each dashboard tile is an outer pane (in $DASHBOARD) running a nested
#   `tmux attach` into a clone session. A clone's own status-format can't
#   query "is my outer pane focused" directly — that's state in a different,
#   unrelated session (see agent-dashboard.sh design notes) — so instead
#   this hook does the lookup once per focus change and writes the answer
#   into a single global option, $FOCUS_OPTION, holding the real session
#   name behind the currently-focused tile. Every clone's status-format
#   independently compares its own real-session name (via $CLONE_OPTION)
#   against that one shared value — see agent-dashboard.sh's status-format
#   template — so no per-clone pushes are needed and focus-out never needs
#   its own handler: the old tile's comparison just goes false as soon as
#   the value changes.
#
#   Same tty-join used by agent-goto-session.sh: the outer pane's pane_tty
#   is the nested attach client's controlling terminal, so matching
#   pane_tty against client_tty finds the nested client, and its
#   client_session is the clone name.
#
# Safety: fires for every pane focus change server-wide — including once
# more right after, when focus lands on the nested attach client's own
# inner pane inside its clone session — so it exits immediately unless the
# session passed in is actually $DASHBOARD.
#
#   tmux 3.4 doesn't have the newer hook_session_name format variable (it
#   silently expands to empty, breaking the "$1" arg with no error at
#   bind time), so the session name is instead passed in via plain
#   #{session_name}, which the binding in .tmux.conf resolves correctly
#   against the newly-focused pane at hook-fire time.
set -u
source ~/.tmux/agent-lib.sh

pane_session="${1:?agent-dashboard-focus-hook.sh: missing session argument}"
pane_id="${2:?agent-dashboard-focus-hook.sh: missing pane argument}"

[ "$pane_session" = "$DASHBOARD" ] || exit 0

pane_tty=$(tmux display-message -p -t "$pane_id" '#{pane_tty}')
clone=$(
  tmux list-clients -F '#{client_tty}	#{client_session}' \
    | awk -F'\t' -v tty="$pane_tty" '$1 == tty { print $2; exit }'
)
[ -z "$clone" ] && exit 0

real_session=$(tmux show-options -t "$clone" -v "$CLONE_OPTION" 2>/dev/null || true)
[ -z "$real_session" ] && exit 0

tmux set-option -g "$FOCUS_OPTION" "$real_session"

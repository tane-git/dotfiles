# oc-lib.sh — shared constants/helpers for the opencode session console
# (oc-list.sh, oc-pick.sh, oc-open.sh).
#
#   The opencode server is the source of truth. Every session lives there,
#   keeps running whether or not anything is attached, and survives both the
#   tmux server and the machine this runs on. These scripts never create,
#   prompt or destroy an agent session — they only *list* sessions and
#   materialise a tmux view onto one. That's what makes the tmux side
#   disposable: kill a view, or the whole tmux server, and nothing is lost
#   but the view.
#
#   Everything is addressed by $OPENCODE_URL alone, so the same scripts run
#   unchanged against a local daily-driver server, or from inside the Inferno
#   opencode pod against loopback.

OC_URL="${OPENCODE_URL:-http://127.0.0.1:4599}"
OC_LIMIT="${OPENCODE_LIST_LIMIT:-10}"
OC_TIMEOUT="${OPENCODE_API_TIMEOUT:-15}"

# Prefix for tmux sessions holding a console view. Keeps them greppable, and
# leaves room to filter them out of the M-s chooser later the same way
# dashboard clones already are (see agent-lib.sh).
OC_PREFIX="oc/"

# Session-scoped user option tagging a tmux session as a console view; its
# value is the opencode session id being shown (single source of truth:
# presence marks it as ours, value says which agent session it displays).
OC_SESSION_OPTION="@oc-session"

# GET $1 from the opencode server. Fails loudly — a silent empty list would
# be indistinguishable from "no sessions running", which is exactly the case
# the console must never get wrong.
oc_api() {
  curl -sS --fail --max-time "$OC_TIMEOUT" "${OC_URL}$1"
}

# Full shell command for a view onto session $1, as a single string for
# tmux new-session. The server may require basic auth
# ($OPENCODE_SERVER_PASSWORD is set on the Inferno opencode container), so
# pass it through only when present — an unsecured local server stays
# argument-free rather than being handed an empty password.
#
# When the user quits the TUI this command exits, its pane dies, and the view
# session disappears on its own. That's deliberate: the agent session keeps
# running on the server regardless, so a closed view is just a closed window,
# never a lost review.
oc_attach_cmd() {
  local session_id="$1" cmd
  cmd="opencode attach '$OC_URL' --session '$session_id'"
  [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && cmd="$cmd -p '$OPENCODE_SERVER_PASSWORD'"
  printf '%s' "$cmd"
}

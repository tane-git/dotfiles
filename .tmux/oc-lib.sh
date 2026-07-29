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
# Was 10 when the console was a tmux menu, which cannot scroll. fzf can, and
# it filters as you type, so the list may as well be everything — the limit
# now exists only to bound the response, not the UI.
#
# Deliberately far above any realistic session count, because a limit that
# quietly clips the list is indistinguishable from the bug this console just
# had — and 5000 was already not enough: the dev machine holds 6661. Cost at
# that size is 0.44s end to end for the whole list, so the headroom is close
# to free.
OC_LIMIT="${OPENCODE_LIST_LIMIT:-50000}"
OC_TIMEOUT="${OPENCODE_API_TIMEOUT:-15}"

# The picker needs fzf >= 0.57 for --with-nth/--accept-nth templates, which
# is what lets a row carry a hidden session id and still render as clean
# columns. Ubuntu focal (the Inferno opencode base image) packages no fzf at
# all, and distro builds elsewhere are routinely years old — 0.29 locally at
# the time of writing, which silently lacks all of it. So we pin our own
# static binary and only fall back to $PATH if it is missing.
OC_FZF="${OPENCODE_FZF:-}"
if [ -z "$OC_FZF" ]; then
  if [ -x "$HOME/.local/bin/fzf" ]; then OC_FZF="$HOME/.local/bin/fzf"
  else                                   OC_FZF="fzf"
  fi
fi

# Sentinel for "this facet is not filtered". Shown as a real row in the
# facet pickers so clearing a filter is the same gesture as setting one.
OC_FACET_ALL="(all)"

# --- console (two-pane picker + live session view) -------------------------
#
# The console is a persistent tmux session: fzf on the left, a real opencode
# client on the right that follows whatever row is selected. M-S switches to
# it, creating it only if it is not already there.
OC_CONSOLE_SESSION="${OPENCODE_CONSOLE_SESSION:-OC SEARCH}"

# The right-hand client talks to its OWN opencode server, not the one your
# real views use. This is not an optimisation, it is the whole reason the
# design works: POST /tui/select-session broadcasts to every client attached
# to a server — verified, two clients both jumped — so driving the console
# from the main server would drag every open oc/ view along with the cursor.
# Servers are isolated from each other (also verified), so a second instance
# on the same storage gives us exactly one client to steer.
OC_PREVIEW_PORT="${OPENCODE_PREVIEW_PORT:-4699}"
OC_PREVIEW_URL="http://127.0.0.1:${OC_PREVIEW_PORT}"

# Start the private server unless it is already answering. Idempotent, so
# every console open can call it blindly.
#
# TODO: nothing ever stops this. Killing the OC SEARCH session leaves the
# server running with no client attached, and the only way to stop it is to
# find the process by port and kill it by hand. Wants either a teardown hook
# on the console session dying, or an idle timeout.
#
# It inherits $OPENCODE_SERVER_PASSWORD when set, so that `opencode attach`
# — which defaults its credentials from that same variable — lines up with
# what the server expects instead of being handed a password nobody asked
# for.
oc_ensure_preview_server() {
  curl -sS --fail --max-time 2 -o /dev/null "${OC_PREVIEW_URL}/session?limit=1" 2>/dev/null && return 0

  nohup opencode serve --port "$OC_PREVIEW_PORT" --hostname 127.0.0.1 \
    >"${TMPDIR:-/tmp}/oc-preview-server-$(id -u).log" 2>&1 &
  disown 2>/dev/null || true

  # Cold start is around a second; poll rather than sleeping a fixed amount.
  local i
  for i in $(seq 1 60); do
    curl -sS --fail --max-time 1 -o /dev/null "${OC_PREVIEW_URL}/session?limit=1" 2>/dev/null && return 0
    command sleep 0.25 2>/dev/null || true
  done
  return 1
}

# Prefix for tmux sessions holding a console view. Keeps them greppable, and
# leaves room to filter them out of the M-s chooser later the same way
# dashboard clones already are (see agent-lib.sh).
OC_PREFIX="oc/"

# Session-scoped user option tagging a tmux session as a console view; its
# value is the opencode session id being shown (single source of truth:
# presence marks it as ours, value says which agent session it displays).
OC_SESSION_OPTION="@oc-session"

# The opencode server can require HTTP basic auth — the Inferno container
# sets $OPENCODE_SERVER_PASSWORD, and `opencode attach` defaults its username
# to "opencode" (see `opencode attach --help`), so match that exactly. Sent
# only when a password is present, so an unsecured local server is not handed
# a half-empty credential.
OC_CURL_ARGS=(-sS --max-time "$OC_TIMEOUT")
if [ -n "${OPENCODE_SERVER_PASSWORD:-}" ]; then
  OC_CURL_ARGS+=(--user "${OPENCODE_SERVER_USERNAME:-opencode}:${OPENCODE_SERVER_PASSWORD}")
fi

# GET $1 from the opencode server. Fails loudly — a silent empty list would
# be indistinguishable from "no sessions running", which is exactly the case
# the console must never get wrong.
#
# Diagnostics go to stderr, not to a variable: every caller invokes this
# inside a command substitution, which is a subshell, so an assignment here
# would be discarded before the caller could ever read it. stderr is the only
# channel that survives that. Being specific matters — a 401, a wrong port
# and a genuinely dead server all used to render as "cannot reach the
# server", which reads as a network problem and sends you looking in the
# wrong place.
oc_api() {
  local body code rc err tmp
  # curl's own stderr is kept out of the response rather than folded in with
  # 2>&1 — mixing them means the transport error ("Failed to connect") and
  # the -w status code end up in the same string, and the useful half gets
  # thrown away while parsing out the other.
  #
  # --fail is deliberately absent: it makes curl discard the response and
  # report only a generic error, which is the opposite of what is wanted
  # here. The status code is read explicitly instead.
  tmp=$(mktemp)
  body=$(curl "${OC_CURL_ARGS[@]}" -w '\n%{http_code}' "${OC_URL}$1" 2>"$tmp")
  rc=$?
  err=$(tr '\n' ' ' < "$tmp")
  rm -f "$tmp"

  if [ "$rc" -ne 0 ]; then
    echo "${err:-curl exited $rc} (${OC_URL})" >&2
    return 1
  fi

  code="${body##*$'\n'}"
  body="${body%$'\n'*}"

  case "$code" in
    2*) printf '%s' "$body"; return 0 ;;
    401|403)
      if [ -n "${OPENCODE_SERVER_PASSWORD:-}" ]; then
        echo "HTTP $code from ${OC_URL} — basic auth rejected" >&2
      else
        echo "HTTP $code from ${OC_URL} — needs OPENCODE_SERVER_PASSWORD" >&2
      fi
      return 1 ;;
    000) echo "no response from ${OC_URL} (timed out after ${OC_TIMEOUT}s)" >&2; return 1 ;;
    *)   echo "HTTP $code from ${OC_URL}$1" >&2; return 1 ;;
  esac
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

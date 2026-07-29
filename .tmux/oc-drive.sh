#!/usr/bin/env bash
# oc-drive.sh — point the console's right-hand pane at one session.
#
#   usage: oc-drive.sh <session-id>
#
#   Bound to fzf's `focus` event, so it fires on every cursor movement in the
#   picker. That budget is the entire design constraint: measured repaint is
#   35-150 ms for an already-running client, against 1.8 s to cold-start a
#   new `opencode attach` — which is why the client stays warm and gets
#   steered, rather than being respawned per row.
#
#   Deliberately does almost nothing: one POST, no output, no error surface.
#   A failure here means the right pane keeps showing the previous session,
#   which is a far better outcome during fast scrolling than an error
#   splattered over the picker.
#
# Safety:
#   Only ever talks to the private preview server ($OC_PREVIEW_URL), never to
#   the server holding your real views — see oc-lib.sh for why that
#   distinction is load-bearing.
set -u
source ~/.tmux/oc-lib.sh

session_id="${1:-}"

# The picker shows an inert placeholder row (empty id) when a filter matches
# nothing; there is nothing to steer to.
case "$session_id" in
  ses*) ;;
  *) exit 0 ;;
esac

curl -sS --max-time 3 -o /dev/null \
  ${OPENCODE_SERVER_PASSWORD:+--user "${OPENCODE_SERVER_USERNAME:-opencode}:${OPENCODE_SERVER_PASSWORD}"} \
  -X POST "${OC_PREVIEW_URL}/tui/select-session" \
  -H 'content-type: application/json' \
  -d "{\"sessionID\":\"${session_id}\"}" 2>/dev/null || true

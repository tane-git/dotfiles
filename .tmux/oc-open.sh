#!/usr/bin/env bash
# oc-open.sh — open (or jump to) a tmux view onto one opencode session.
#
#   usage: oc-open.sh <session-id> [client-tty] [switch]
#
#   Creates a tmux session named "$OC_PREFIX<title>" whose single pane runs
#   `opencode attach --session <id>`.
#
#   `switch` defaults to 1. Multi-select in the picker calls this once per
#   chosen session with switch=0 for all but the first, so a bulk open
#   creates every view but only ever moves you to one of them.
#
#   The title is fetched here rather than passed in. It is the only argument
#   that could contain spaces, quotes or newlines, and it changes underneath
#   us as the agent renames the session — so re-reading it at open time is
#   both safer to plumb and always current.
#
# Identity:
#   A view is identified by the $OC_SESSION_OPTION tag holding its opencode
#   session id, never by its name. Names are derived from titles and titles
#   change, so matching on the name would silently create a second view onto
#   a session that already had one. Matching on the tag also means the view
#   can be renamed in place when the title moves on, which is what keeps the
#   session list readable over the life of a long review.
#
# Safety:
#   * Only ever creates, renames or switches to a tmux session. Never kills
#     one, and never writes to the opencode server.
#   * Every target is matched with "=" so tmux's default prefix matching
#     can't resolve a short name onto some unrelated session that merely
#     starts with the same characters — a real hazard, confirmed: `-t
#     oc/witty` silently resolves to an existing `oc/witty-cactus`.
set -u
source ~/.tmux/oc-lib.sh

session_id="${1:?oc-open.sh: missing session id argument}"
client_tty="${2:-}"
switch="${3:-1}"

err_file=$(mktemp)
trap 'rm -f "$err_file"' EXIT
session_json=$(oc_api "/session/${session_id}" 2>"$err_file") || {
  tmux display-message "oc-open: $(tr '\n' ' ' < "$err_file")"
  exit 1
}
title=$(jq -r '.title // ""' <<< "$session_json")

# tmux stores session names with "." and ":" rewritten to "_" (verified — it
# accepts the name but mangles it silently). Doing the same rewrite here
# keeps the computed name identical to the stored one, which everything
# below relies on when comparing and targeting. Whitespace is collapsed
# because a title can carry newlines, and those would break the -F parsing.
name=$(printf '%s' "$title" \
  | tr '\n\t' '  ' \
  | tr '.:' '__' \
  | sed 's/  */ /g; s/^ //; s/ $//' \
  | cut -c1-40)
[ -z "$name" ] && name="$session_id"
name="${OC_PREFIX}${name}"

# First free variant of $1. Only ever called when the desired name is known
# to belong to somebody else, so it never renames a view onto itself.
unique_name() {
  local base="$1" candidate="$1" n=2
  while tmux has-session -t "=$candidate" 2>/dev/null; do
    candidate="${base}-${n}"
    n=$((n + 1))
  done
  printf '%s' "$candidate"
}

# Existing view for this opencode session, by tag rather than by name.
existing=$(tmux list-sessions -F "#{session_name}	#{${OC_SESSION_OPTION}}" 2>/dev/null \
  | awk -F'\t' -v id="$session_id" '$2 == id { print $1; exit }')

if [ -z "$existing" ]; then
  target=$(unique_name "$name")
  tmux new-session -d -s "$target" "$(oc_attach_cmd "$session_id")"
  # set-option's -t is a *target-pane* (see `man tmux`), so a bare "=name"
  # fails to resolve where it works fine for has-session/switch-client. The
  # trailing colon makes it an explicit session target, which then accepts
  # the "=" exact-match prefix — "=name:" is the only form that both works
  # and refuses to prefix-match.
  tmux set-option -t "=$target:" "$OC_SESSION_OPTION" "$session_id"
else
  target="$existing"
  if [ "$existing" != "$name" ]; then
    tmux rename-session -t "=$existing" "$(unique_name "$name")" 2>/dev/null \
      && target=$(tmux list-sessions -F "#{session_name}	#{${OC_SESSION_OPTION}}" 2>/dev/null \
           | awk -F'\t' -v id="$session_id" '$2 == id { print $1; exit }')
  fi
fi

[ "$switch" = "1" ] || exit 0

# Inside tmux the client moves; outside it we're being run from a plain shell
# (e.g. straight after ssh'ing into the pod), so attach instead.
#
# When invoked from the M-S popup the tty is passed in and switch-client is
# pinned to it with -c, rather than letting tmux guess. Per `man tmux`
# (switch-client): with no -c it "attempts to work out the client currently in
# use" — and a display-popup runs its command in a pane that isn't a normal
# window pane, so that guess is exactly the kind tmux's own docs hedge on.
if [ -z "${TMUX:-}" ]; then
  tmux attach-session -t "=$target"
elif [ -n "$client_tty" ]; then
  tmux switch-client -c "$client_tty" -t "=$target"
else
  tmux switch-client -t "=$target"
fi

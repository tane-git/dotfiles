#!/usr/bin/env bash
# oc-open.sh — open (or jump to) a tmux view onto one opencode session.
#
#   usage: oc-open.sh <session-id> <slug> [client-tty] [switch]
#
#   `switch` defaults to 1. Multi-select in the picker calls this once per
#   chosen session with switch=0 for all but the first, so a bulk open
#   creates every view but only ever moves you to one of them.
#
#   Creates a tmux session named "$OC_PREFIX<slug>" whose single pane runs
#   `opencode attach --session <id>`. Idempotent: if that view already exists
#   it's selected rather than duplicated, so picking the same session twice
#   from the console lands you back in the one you already had — with its
#   scrollback intact — instead of opening a second client onto it.
#
#   Session names use the server's own `slug` ("witty-cactus"), not the
#   title. Titles are long, contain spaces and punctuation, and change as the
#   agent renames the session; slugs are short, stable and already unique.
#
# Safety:
#   * Only ever *creates* a tmux session, or switches to one. Never kills a
#     session, never touches the opencode server (no writes at all), and
#     never runs against a target it didn't construct from $OC_PREFIX.
#   * Every target is matched with "=" so tmux's default prefix matching can't
#     resolve a short slug onto some unrelated session that merely starts with
#     the same characters — confirmed to be a real hazard: `-t oc/witty`
#     silently resolves to the existing `oc/witty-cactus`.
set -u
source ~/.tmux/oc-lib.sh

session_id="${1:?oc-open.sh: missing session id argument}"
slug="${2:?oc-open.sh: missing slug argument}"
client_tty="${3:-}"
switch="${4:-1}"

name="${OC_PREFIX}${slug}"

if ! tmux has-session -t "=$name" 2>/dev/null; then
  tmux new-session -d -s "$name" "$(oc_attach_cmd "$session_id")"
  # set-option's -t is a *target-pane* (see `man tmux`), so a bare "=name"
  # fails to resolve where it works fine for has-session/switch-client. The
  # trailing colon makes it an explicit session target, which then accepts
  # the "=" exact-match prefix — "=name:" is the only form that both works
  # and refuses to prefix-match.
  tmux set-option -t "=$name:" "$OC_SESSION_OPTION" "$session_id"
fi

# Inside tmux the client moves; outside it we're being run from a plain shell
# (e.g. straight after ssh'ing into the pod), so attach instead.
#
# When invoked from the M-S popup the tty is passed in and switch-client is
# pinned to it with -c, rather than letting tmux guess. Per `man tmux`
# (switch-client): with no -c it "attempts to work out the client currently in
# use" — and a display-popup runs its command in a pane that isn't a normal
# window pane, so that guess is exactly the kind tmux's own docs hedge on.
# Same reasoning (and the same #{client_tty} plumbing) as agent-dashboard.sh.
[ "$switch" = "1" ] || exit 0

if [ -z "${TMUX:-}" ]; then
  tmux attach-session -t "=$name"
elif [ -n "$client_tty" ]; then
  tmux switch-client -c "$client_tty" -t "=$name"
else
  tmux switch-client -t "=$name"
fi

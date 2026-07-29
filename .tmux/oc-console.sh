#!/usr/bin/env bash
# oc-console.sh — open the opencode console: fzf on the left, a live
# opencode client on the right that follows the selected row.
#
#   usage: oc-console.sh [client-tty]
#
#   Bound to M-S. The console is a persistent session, so this switches to it
#   when it already exists and builds it when it does not — reopening is
#   instant, and the warm client keeps its place.
#
# Why two real panes rather than an fzf preview:
#   fzf's preview is fzf painting inside one pane; tmux cannot see it, so
#   M-h/M-l cannot reach it and it can only ever show captured text. Real
#   panes give opencode's own rendering, and the right-hand one is a genuine
#   interactive client — you can move into it and work.
#
# Why the left pane loops:
#   Enter hands off to oc-open.sh and fzf exits. Without the loop the pane
#   would die on the first selection and take the layout with it.
#
# Safety:
#   Creates only the console session, by its fixed name, plus a private
#   opencode server on loopback. Never kills anything.
set -u
source ~/.tmux/oc-lib.sh

client_tty="${1:-}"

switch_to_console() {
  if [ -z "${TMUX:-}" ]; then
    tmux attach-session -t "=$OC_CONSOLE_SESSION"
  elif [ -n "$client_tty" ]; then
    tmux switch-client -c "$client_tty" -t "=$OC_CONSOLE_SESSION"
  else
    tmux switch-client -t "=$OC_CONSOLE_SESSION"
  fi
}

# Already built — just go there. This is the common path.
if tmux has-session -t "=$OC_CONSOLE_SESSION" 2>/dev/null; then
  switch_to_console
  exit 0
fi

if ! command -v "$OC_FZF" >/dev/null 2>&1; then
  tmux display-message "oc-console: fzf not found (looked for '$OC_FZF')"
  exit 0
fi

if ! oc_ensure_preview_server; then
  tmux display-message "oc-console: could not start preview server on $OC_PREVIEW_URL"
  exit 0
fi

# Left: the picker, restarted forever. --client is deliberately not passed —
# in a normal pane tmux resolves the current client correctly, and unlike the
# old popup the console has no reason to second-guess it.
tmux new-session -d -s "$OC_CONSOLE_SESSION" \
  "while :; do ~/.tmux/oc-pick.sh; done"

# Right: the warm client. No --session, so it lands on whatever was last
# active; oc-pick.sh steers it to the highlighted row as soon as fzf paints.
attach="opencode attach '$OC_PREVIEW_URL'"
[ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && attach="$attach -p '$OPENCODE_SERVER_PASSWORD'"
tmux split-window -h -l 55% -t "=$OC_CONSOLE_SESSION:" "$attach"

# Land on the picker, not the client. Addressed by direction rather than by
# index: split-window leaves the new (right) pane active, and a numeric
# target would have to know about pane-base-index, which is 1 in this config
# — "-t .0" silently resolves to nothing and leaves you typing into the
# opencode client instead of the picker.
tmux select-pane -L -t "=$OC_CONSOLE_SESSION:"

switch_to_console

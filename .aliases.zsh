alias v="nvim"

# Attach to the tmux session console inside the Inferno opencode pod.
#
# A function rather than an alias because the pod name changes on every
# restart, so it has to be resolved by label each time. `new-session -A`
# attaches to "main" if it exists and creates it otherwise, which makes this
# safe to re-run — including straight after a pod restart, when the old tmux
# server is gone but /home/opencode (the PVC) still holds everything.
#
# OPENCODE_URL is passed explicitly because the console scripts default to
# the local daily-driver server on 4599; inside the pod the server is on
# loopback 4096.
inferno() {
  local ctx=apc-web ns=inferno pod
  pod=$(kubectl --context="$ctx" -n "$ns" get pod \
          -l app.kubernetes.io/name=opencode \
          -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [[ -z "$pod" ]]; then
    echo "inferno: no opencode pod found in $ctx/$ns" >&2
    return 1
  fi

  # Mark this pane as holding a nested tmux, so the outer F12 passthrough
  # binding knows it is safe to inject F10/F11 here and nowhere else. Cleared
  # on the way out, however the connection ends.
  [[ -n "$TMUX" ]] && tmux set-option -p @nested 1

  # The inner tmux starts purple: on connect you are not in passthrough yet,
  # so the outer server still has the keys. Created detached first because a
  # session started with -A attaches immediately and would block the
  # set-option that follows.
  kubectl --context="$ctx" -n "$ns" exec -it "$pod" -- \
    env OPENCODE_URL=http://127.0.0.1:4096 sh -c '
      tmux new-session -A -d -s main
      tmux set -g @accent colour141
      exec tmux attach -t main
    '

  [[ -n "$TMUX" ]] && tmux set-option -p -u @nested
}

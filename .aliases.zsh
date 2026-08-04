alias v="nvim"

# SSH into t.wilson@DT-APC-TWILS-96 (see ~/.ssh/config's "desk" Host entry)
# and attach/create the "main" tmux session there. Mirrors `inferno` below:
# tag this pane @nested first so the F12 passthrough binding in .tmux.conf
# knows it's safe to route keys into the remote session, start the remote
# session detached so its accent can be set to purple (not listening yet —
# same convention F12 itself uses) before attaching, then clear the tag on
# the way out however the connection ends.
desk() {
  [[ -n "$TMUX" ]] && tmux set-option -p @nested 1

  ssh -t desk '
    tmux new-session -A -d -s main
    tmux set -g @accent colour141
    exec tmux attach -t main
  '

  [[ -n "$TMUX" ]] && tmux set-option -p -u @nested
}

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
  # OPENCODE_URL is set with tmux set-environment rather than by wrapping the
  # command in `env`, because the console runs from the *tmux server's*
  # environment (M-S goes run-shell -> display-popup, and both inherit from
  # the server, not from this pane). An `env` wrapper only reaches the server
  # on the connection that happens to create it — reconnect to a server that
  # is already running and the variable is simply absent, the console falls
  # back to the laptop default of 4599, and it fails with "connection
  # refused" on a port nothing is listening to. set-environment -g applies
  # either way, and is picked up by run-shell and popups alike (verified).
  kubectl --context="$ctx" -n "$ns" exec -it "$pod" -- \
    sh -c '
      tmux new-session -A -d -s main
      tmux set-environment -g OPENCODE_URL http://127.0.0.1:4096
      tmux set -g @accent colour141
      exec tmux attach -t main
    '

  [[ -n "$TMUX" ]] && tmux set-option -p -u @nested
}

# Open tmux with the demo config, from the demo directory.
tmux-demo() {
  command tmux -L demo kill-server 2>/dev/null
  : > ~/tmux-demo/.tmux.conf.demo
  cd ~/tmux-demo
  command tmux -L demo -f ~/tmux-demo/.tmux.conf.demo set-option -g default-shell "$(command -v zsh)" \; new-session -s demo
}

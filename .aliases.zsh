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

  kubectl --context="$ctx" -n "$ns" exec -it "$pod" -- \
    env OPENCODE_URL=http://127.0.0.1:4096 tmux new-session -A -s main
}

# agent-lib.sh — shared constants/helpers for agent-dashboard.sh,
# agent-goto-session.sh and agent-dashboard-hook.sh.
DASHBOARD="agents"

# Session-scoped user option tagging a dashboard clone session; its value is
# the name of the real session it mirrors (single source of truth: presence
# marks it as a clone, value says which real session to treat it as). Used
# to hide clones from choose-tree, translate a clone back to its real
# session (agent-goto-session.sh), and find every clone to tear down.
CLONE_OPTION="@agent-dashboard-clone"

# Kill every dashboard clone session currently on the server. Safe: a clone
# is just one member of a tmux session group sharing the real session's
# windows — per `man tmux` (new-session), "any session in a group may be
# killed without affecting the others", so this never touches the real
# sessions the clones mirror.
agent_dashboard_kill_clones() {
  tmux list-sessions -f "#{!=:#{${CLONE_OPTION}},}" -F '#{session_name}' 2>/dev/null \
    | while IFS= read -r clone; do
        tmux kill-session -t "$clone" 2>/dev/null || true
      done
}

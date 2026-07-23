# agent-lib.sh — shared constants/helpers for agent-dashboard.sh,
# agent-goto-session.sh and agent-dashboard-hook.sh.
DASHBOARD="agents"

# Session-scoped user option tagging a dashboard clone session; its value is
# the name of the real session it mirrors (single source of truth: presence
# marks it as a clone, value says which real session to treat it as). Used
# to hide clones from choose-tree, translate a clone back to its real
# session (agent-goto-session.sh), and find every clone to tear down.
CLONE_OPTION="@agent-dashboard-clone"

# Session-scoped user option on a clone: "1" if agent-dashboard.sh had to
# zoom the agent pane to isolate it from other panes in its window (only
# set when the window wasn't already zoomed — see agent-dashboard.sh), "0"
# if it left an existing zoom alone. Read on teardown so cleanup only
# unzooms windows the dashboard itself zoomed, never a zoom the user had
# set before the dashboard touched it.
ZOOM_OPTION="@agent-dashboard-zoomed"

# Kill every dashboard clone session currently on the server. Safe: a clone
# is just one member of a tmux session group sharing the real session's
# windows — per `man tmux` (new-session), "any session in a group may be
# killed without affecting the others", so this never touches the real
# sessions the clones mirror.
agent_dashboard_kill_clones() {
  tmux list-sessions -f "#{!=:#{${CLONE_OPTION}},}" -F '#{session_name}' 2>/dev/null \
    | while IFS= read -r clone; do
        if [ "$(tmux show-options -t "$clone" -v "$ZOOM_OPTION" 2>/dev/null)" = "1" ]; then
          tmux resize-pane -Z -t "$clone" 2>/dev/null || true
        fi
        tmux kill-session -t "$clone" 2>/dev/null || true
      done
}

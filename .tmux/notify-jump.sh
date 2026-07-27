#!/usr/bin/env bash
# notify-jump.sh — invoked by desktop-notify.js when a desktop notification is
# clicked. Switches the (single) attached tmux client onto the pane that
# raised the notification, then raises the terminal window itself, since a
# GNOME notification click only activates our script, not a real window.
#
# Assumes one attached tmux client and one Alacritty window, matching this
# machine's normal setup. Multiple attached clients/windows aren't
# disambiguated - see desktop-notify.js.
set -u

pane="${1:?notify-jump.sh: missing pane argument}"

tmux has-session 2>/dev/null || exit 0

target=$(tmux display-message -p -t "$pane" '#{session_name}:#{window_index}' 2>/dev/null) || exit 0

client_tty=$(tmux list-clients -F '#{client_tty}' 2>/dev/null | head -n1)
[ -z "$client_tty" ] && exit 0

tmux switch-client -c "$client_tty" -t "$target"
tmux select-pane -t "$pane" 2>/dev/null

wmctrl -a Alacritty 2>/dev/null

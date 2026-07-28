#!/usr/bin/env bash
# Toggle opencode desktop notifications on/off. The desktop-notify.js plugin
# checks for this marker file's existence before sending; present = disabled.
# Bound to M-c n (config-mode n) in .tmux.conf.
set -euo pipefail

FLAG="${HOME}/.config/opencode/desktop-notify.disabled"

if [ -e "$FLAG" ]; then
  rm -f "$FLAG"
  tmux display-message "opencode notifications: ON"
else
  touch "$FLAG"
  tmux display-message "opencode notifications: OFF"
fi

#!/usr/bin/env bash
# spinner.sh — print one frame of a braille spinner, chosen from the current
# second so all windows referencing it animate in sync. Called from
# window-status-format via #(), re-run once per status-interval.
frames="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
i=$(( $(date +%s) % ${#frames} ))
printf '%s' "${frames:$i:1}"

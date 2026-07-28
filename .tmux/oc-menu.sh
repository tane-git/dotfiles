#!/usr/bin/env bash
# oc-menu.sh — pop up a list of opencode sessions; picking one opens a tmux
# view onto it (oc-open.sh).
#
#   usage: oc-menu.sh [client-tty]
#
#   The list is drawn by tmux's own display-menu: arrow keys navigate, Enter
#   picks, and 1-9/0 jump straight to a row. No external picker is involved,
#   so nothing beyond tmux itself has to exist on the machine this runs on —
#   which matters for the Inferno opencode container, where every extra
#   dependency is a Dockerfile line.
#
#   display-menu has no scrolling, so it's bounded by the terminal height.
#   Fine at $OC_LIMIT of 10; if this ever needs to show hundreds of sessions
#   with search, that's the point to replace it with a real TUI rather than
#   stretch a menu.
#
#   Ordering is the server's own default — most recently *updated* first, not
#   created. Verified empirically against a real server: GET /session returns
#   updated-descending, which is what a triage list wants anyway (whatever
#   moved last is on top) and costs no client-side sorting.
#
#   State comes from GET /session/status, which returns a map holding only
#   sessions currently doing something — an idle session is simply absent. So
#   "in the map" means busy/retrying, "absent" means idle; there's no separate
#   idle lookup to make.
#
# Safety:
#   * Read-only against the opencode server: two GETs, no writes. Nothing is
#     created, prompted or destroyed there.
#   * Every menu entry runs oc-open.sh, which only ever creates or switches to
#     a tmux session — see its own header.
set -u
source ~/.tmux/oc-lib.sh

client_tty="${1:-}"

sessions=$(oc_api "/session?limit=${OC_LIMIT}") || {
  tmux display-message "oc-menu: cannot reach opencode server at $OC_URL"
  exit 0
}

# Not fatal: without it every session just reads as idle, which beats
# refusing to show the list at all.
status=$(oc_api "/session/status" 2>/dev/null) || status='{}'

rows=$(jq -r --argjson status "$status" '
  # jq 1.6 has no string padding, and `" " * 0` yields null rather than "" —
  # so the zero/negative case must be handled explicitly or the whole line
  # becomes null and the row silently vanishes.
  def pad($n): (. // "") as $s
    | $s + (if $n > ($s | length) then (" " * ($n - ($s | length))) else "" end);
  def clip($n): (. // "") | if ($n < length) then .[:$n-1] + "…" else . end;

  def age($ms): (now - ($ms / 1000)) as $s
    | if   $s <    60 then "\($s | floor)s"
      elif $s <  3600 then "\(($s /    60) | floor)m"
      elif $s < 86400 then "\(($s /  3600) | floor)h"
      else                 "\(($s / 86400) | floor)d"
      end;

  .[]
  | . as $s
  | ($status[$s.id].type // "idle") as $state
  | (if   $state == "busy"  then "⠹"
     elif $state == "retry" then "↻"
     else                        " "
     end) as $glyph
  # Menu item names are format strings, so a literal "#" in a session title
  # would start a #{...}/#[...] expansion. Double it to escape.
  # Widths are kept narrow deliberately: a menu is clamped to the width of
  # the client showing it, and an 80-column terminal is the realistic floor
  # (that is what an ssh into the pod lands in). Overshooting truncates the
  # row rather than wrapping it.
  | ($s.title | clip(38) | gsub("#"; "##")) as $title
  | [$s.id, $s.slug, "\($glyph) \($s.slug | clip(16) | pad(16))  \($title | pad(38))  \(age($s.time.updated))"]
  | @tsv
' <<< "$sessions")

if [ -z "$rows" ]; then
  tmux display-message "oc-menu: no opencode sessions on $OC_URL"
  exit 0
fi

# display-menu takes items as (name, key, command) triples. An empty key
# means "no shortcut"; 1-9 then 0 gives the first ten rows a direct key,
# which is the whole list at the default $OC_LIMIT.
# -S styles the menu border, matching the green used for the active pane
# border and active tab in .tmux.conf. Note it needs tmux >= 3.4 — worth
# remembering when this runs in the Inferno opencode container, whose
# ubuntu-focal base ships tmux 3.0a from apt.
keys="1234567890"
args=(-S 'fg=green' -T " opencode sessions " -x C -y C)
[ -n "$client_tty" ] && args=(-c "$client_tty" "${args[@]}")

i=0
while IFS=$'\t' read -r id slug display; do
  [ -z "$id" ] && continue
  if [ "$i" -lt "${#keys}" ]; then key="${keys:$i:1}"; else key=""; fi
  # Session ids and slugs are server-generated ([A-Za-z0-9_] and
  # lowercase-hyphen respectively), so single-quoting them here is enough —
  # the untrusted part of a row is the title, and that never reaches a shell.
  args+=("$display" "$key" "run-shell \"~/.tmux/oc-open.sh '$id' '$slug' '$client_tty'\"")
  i=$((i + 1))
done <<< "$rows"

tmux display-menu "${args[@]}"

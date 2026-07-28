#!/usr/bin/env bash
# oc-list.sh — emit one tab-separated row per opencode session, for oc-pick.sh.
#
#   usage: oc-list.sh [--dir=X] [--state=X] [--mr=X]
#
#   Row layout (tabs between fields):
#
#     1  id           opencode session id, never displayed
#     2  glyph+title  activity glyph and what the session is about
#     3  dir          basename of the session's directory
#     4  age          time since last activity
#
#   The server's `slug` ("witty-cactus") is deliberately not shown or used.
#   It is a generated label that means nothing to a reader; the title is what
#   identifies a session at a glance, and oc-open.sh names the tmux view
#   after it too.
#
#   Fields 2-4 are pre-padded to fixed widths here rather than left to fzf,
#   because the tabs between them exist for --nth field addressing, not for
#   layout — oc-pick.sh renders them at --tabstop=1, so the padding is what
#   actually lines the columns up.
#
#   Ordering is the server's own default: most recently updated first. That
#   is what a triage list wants (whatever moved last is on top) and it costs
#   no client-side sorting.
#
# Safety: two GETs against the opencode server, nothing else. Read-only.
set -u
source ~/.tmux/oc-lib.sh

f_dir="" f_state="" f_mr=""
for arg in "$@"; do
  case "$arg" in
    --dir=*)   f_dir="${arg#--dir=}" ;;
    --state=*) f_state="${arg#--state=}" ;;
    --mr=*)    f_mr="${arg#--mr=}" ;;
    *) echo "oc-list: unknown argument '$arg'" >&2; exit 1 ;;
  esac
done

# /experimental/session rather than /session, because /session is scoped to
# the server's *current* project and silently hides everything else. On the
# Inferno pod that meant 44 sessions out of 3994: opencode runs in
# /home/opencode (projectID "global") while every MR review lives in a
# per-repo project such as /home/opencode/flame, each with its own
# projectID. There is no parameter on /session that lifts that scoping.
#
# The tradeoff is the "experimental" path, which upstream may move or
# rename. It exists on both 1.17.7 (the pod) and 1.17.19 (dev machines), and
# returns GlobalSession — a superset of Session carrying every field used
# here, metadata and parentID included. If it ever disappears, the fallback
# is /session queried once per directory, which is strictly more code.
#
# oc_api has already written the reason to stderr; callers capture it there.
sessions=$(oc_api "/experimental/session?limit=${OC_LIMIT}") || exit 1

# Not fatal: without it every session reads as idle, which beats refusing to
# show the list at all.
status=$(oc_api "/session/status" 2>/dev/null) || status='{}'

jq -r --argjson status "$status" \
      --arg fdir "$f_dir" --arg fstate "$f_state" --arg fmr "$f_mr" '
  # jq has no string padding, and `" " * 0` yields null rather than "" — so
  # the zero/negative case must be handled explicitly or the whole line
  # becomes null and the row silently vanishes.
  def pad($n): (. // "") as $s
    | $s + (if $n > ($s | length) then (" " * ($n - ($s | length))) else "" end);
  def clip($n): (. // "") | if ($n < length) then .[:$n-1] + "…" else . end;
  def fit($n): clip($n) | pad($n);

  def age($ms): (now - ($ms / 1000)) as $s
    | if   $s <    60 then "\($s | floor)s"
      elif $s <  3600 then "\(($s /    60) | floor)m"
      elif $s < 86400 then "\(($s /  3600) | floor)h"
      else                 "\(($s / 86400) | floor)d"
      end;

  .[]
  | . as $s
  | ($status[$s.id].type // "idle")            as $state
  | ($s.directory // "" | split("/") | last)   as $dir
  | ($s.metadata.mr_state // "")               as $mr

  # Facet filters. An empty filter means "unset", so it matches everything —
  # that is what "(all)" collapses to in oc-pick.sh.
  | select($fdir   == "" or $dir   == $fdir)
  | select($fstate == "" or $state == $fstate)
  | select($fmr    == "" or $mr    == $fmr)

  | (if   $state == "busy"  then "⠹"
     elif $state == "retry" then "↻"
     else                        " "
     end) as $glyph

  # Widths are sized for the narrowest realistic client: an 80-column ssh
  # into the Inferno pod, inside a popup that leaves ~72 usable columns,
  # minus the 2-column pointer/marker gutter fzf draws. 1+1+48 +1+ 12 +1+ 3
  # = 67. Overshooting truncates the row rather than wrapping it.
  | [ $s.id,
      "\($glyph) \($s.title | fit(48))",
      ($dir | fit(12)),
      age($s.time.updated)
    ]
  | @tsv
' <<< "$sessions"

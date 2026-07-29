#!/usr/bin/env bash
# oc-preview.sh — render one opencode session for the picker's preview pane.
#
#   usage: oc-preview.sh <session-id>
#
#   Two calls: the session itself for the header, and the tail of its
#   conversation for the body.
#
#   The tail is fetched with ?limit=N, which returns the *last* N messages —
#   verified against a full fetch. That distinction is the whole reason this
#   is viable: the largest session here returns 9.7 MB and takes 0.44s for
#   its full history, versus 4 KB and 5 ms for the last three. This runs on
#   every cursor movement, so the full fetch would make the list unusable.
#
# Safety:
#   Read-only. Two GETs, no writes, no tmux commands.
set -u
source ~/.tmux/oc-lib.sh

session_id="${1:-}"

# The picker shows an inert placeholder row (empty id) when a filter matches
# nothing — there is nothing to preview, and an error here would be noise.
[ -n "$session_id" ] || exit 0

C_TITLE=$'\033[1;32m'
C_META=$'\033[2m'
C_USER=$'\033[1;36m'
C_ASSIST=$'\033[1;33m'
C_TOOL=$'\033[2;35m'
C_RULE=$'\033[2;32m'
C_OFF=$'\033[0m'

session=$(oc_api "/session/${session_id}" 2>/dev/null) || {
  printf '%s  could not load session%s\n' "$C_META" "$C_OFF"
  exit 0
}

printf '\n'
jq -r --arg t "$C_TITLE" --arg m "$C_META" --arg o "$C_OFF" '
  def ago($ms): (now - ($ms / 1000)) as $s
    | if   $s <    60 then "\($s | floor)s ago"
      elif $s <  3600 then "\(($s /    60) | floor)m ago"
      elif $s < 86400 then "\(($s /  3600) | floor)h ago"
      else                 "\(($s / 86400) | floor)d ago"
      end;
  def n($x): ($x // 0) | if . > 1000 then "\((. / 1000) | floor)k" else "\(.)" end;

  "  \($t)\(.title // "untitled")\($o)",
  "  \($m)\(.directory // "?")\($o)",
  "  \($m)\(.model.id // "no model")   \(n(.tokens.input)) in / \(n(.tokens.output)) out   \(ago(.time.updated))\($o)"
' <<< "$session"

# Column width is whatever fzf gave the pane; FZF_PREVIEW_COLUMNS is set for
# exactly this. Falling back to 60 keeps it sane if run by hand.
width="${FZF_PREVIEW_COLUMNS:-60}"
rule=$(printf '%*s' "$((width > 4 ? width - 4 : 40))" '' | tr ' ' '-')
printf '\n  %s%s%s\n\n' "$C_RULE" "$rule" "$C_OFF"

messages=$(oc_api "/session/${session_id}/message?limit=6" 2>/dev/null) || messages='[]'

jq -r --arg u "$C_USER" --arg a "$C_ASSIST" --arg t "$C_TOOL" --arg o "$C_OFF" \
      --argjson w "$width" '
  # Tool calls are shown as a single dim line rather than their output: the
  # output is the bulk of a session (and of that 9.7 MB) while telling you
  # almost nothing about what the session is for.
  def body:
    [ .parts[]?
      | if   .type == "text" then (.text // "")
        elif .type == "tool" then "[\(.tool // "tool")]"
        else empty
        end ]
    | join(" ") | gsub("\\s+"; " ") | ltrimstr(" ");

  if length == 0 then "  \($t)no messages\($o)"
  else
    .[]
    | (.info.role // "?") as $role
    | body as $text
    | select($text != "")
    | (if $role == "user" then "\($u)>\($o) " else "\($a)*\($o) " end) as $marker
    | ($text | if length > ($w * 3) then .[:($w * 3)] + "…" else . end) as $clipped
    | "  \($marker)\($clipped)\n"
  end
' <<< "$messages"

#!/usr/bin/env bash
# oc-pick.sh — the opencode session console. Bound to M-S, run inside a
# tmux display-popup.
#
#   usage: oc-pick.sh [--client=TTY] [--query=Q]
#                     [--facet=NAME] [--dir=X] [--state=X] [--mr=X]
#
#   Two layers, deliberately kept apart:
#
#     * Typing searches titles and session names, nothing else. It is for
#       "the one about auth retries".
#     * Facets — dir, state, MR status — are hotkeys, not words. Each has a
#       small fixed set of values, so ^p/^s/^r swap the list for a picker of
#       those values and come back with the list narrowed.
#
#   The split exists because fzf matches whatever it displays. If the
#   directory is a visible column then typing "flame" also matches every
#   session that merely lives there, and there is no way to say "I meant the
#   title". --nth pins typed search to the name and title fields so the
#   other columns are visible but not searchable, and facets cover the
#   filtering those columns would otherwise be used for.
#
#   Verified: --nth indexes the *transformed* line, i.e. the result of
#   --with-nth, not the raw input. So the template has to keep the tabs
#   between fields (rendered at --tabstop=1) or every field collapses into
#   one and --nth silently matches nothing at all.
#
# Filter state:
#   Carried in argv across re-execs rather than in a temp file. ^p replaces
#   this process with itself in --facet mode (fzf's `become`), which picks a
#   value and then re-execs back into list mode with the new filter appended.
#   No state outlives the popup, and nothing needs cleaning up if it dies.
#
# Safety:
#   Read-only against the opencode server. The only side effect is
#   oc-open.sh, which creates or switches to a tmux session and nothing else.
set -u
source ~/.tmux/oc-lib.sh

# Fail with something actionable rather than "command not found" buried in a
# popup that closes the instant the script exits. The version floor is real,
# not defensive: on an older fzf the --accept-nth template is rejected
# outright, and the failure mode for --with-nth is worse — it is accepted and
# silently makes --nth match nothing at all.
if ! command -v "$OC_FZF" >/dev/null 2>&1; then
  tmux display-message "oc-pick: fzf not found (looked for '$OC_FZF') — see oc-lib.sh"
  exit 0
fi
fzf_ver=$("$OC_FZF" --version 2>/dev/null | cut -d' ' -f1)
if [ "$(printf '%s\n0.57.0\n' "$fzf_ver" | sort -V | head -1)" != "0.57.0" ]; then
  tmux display-message "oc-pick: fzf $fzf_ver is too old, need >= 0.57"
  exit 0
fi

self="$HOME/.tmux/oc-pick.sh"
client_tty="" facet="" query=""
f_dir="" f_state="" f_mr=""

for arg in "$@"; do
  case "$arg" in
    --client=*) client_tty="${arg#--client=}" ;;
    --facet=*)  facet="${arg#--facet=}" ;;
    --query=*)  query="${arg#--query=}" ;;
    --dir=*)    f_dir="${arg#--dir=}" ;;
    --state=*)  f_state="${arg#--state=}" ;;
    --mr=*)     f_mr="${arg#--mr=}" ;;
    *) echo "oc-pick: unknown argument '$arg'" >&2; exit 1 ;;
  esac
done

# Re-invocation of this script carrying the current filters. Used both to
# re-exec after a facet pick (as an array) and to build the `become` bindings
# (as a %q-quoted string, since fzf hands those to sh -c).
self_args=()
[ -n "$client_tty" ] && self_args+=( "--client=$client_tty" )
[ -n "$f_dir" ]      && self_args+=( "--dir=$f_dir" )
[ -n "$f_state" ]    && self_args+=( "--state=$f_state" )
[ -n "$f_mr" ]       && self_args+=( "--mr=$f_mr" )

self_cmd=$(printf '%q' "$self")
for a in ${self_args[@]+"${self_args[@]}"}; do
  self_cmd+=" $(printf '%q' "$a")"
done

# --- facet mode: pick one value, then hand back to list mode --------------
if [ -n "$facet" ]; then
  values=$(~/.tmux/oc-facets.sh "$facet") || exit 0

  # A cancelled picker (Esc, exit 130) must leave the filter alone, which is
  # why the exit status is tested rather than the emptiness of $chosen —
  # "(all)" legitimately maps to an empty value.
  if chosen=$(printf '%s\n' "$values" | "$OC_FZF" \
                --prompt="$facet > " \
                --header="filter by $facet   (esc to keep current)" \
                --header-first \
                --no-multi \
                --reverse \
                --info=inline); then
    [ "$chosen" = "$OC_FACET_ALL" ] && chosen=""
    case "$facet" in
      dir)   f_dir="$chosen" ;;
      state) f_state="$chosen" ;;
      mr)    f_mr="$chosen" ;;
    esac
  fi

  args=( "--client=$client_tty" "--query=$query" )
  [ -n "$f_dir" ]   && args+=( "--dir=$f_dir" )
  [ -n "$f_state" ] && args+=( "--state=$f_state" )
  [ -n "$f_mr" ]    && args+=( "--mr=$f_mr" )
  exec "$self" "${args[@]}"
fi

# --- list mode ------------------------------------------------------------
list_args=()
[ -n "$f_dir" ]   && list_args+=( "--dir=$f_dir" )
[ -n "$f_state" ] && list_args+=( "--state=$f_state" )
[ -n "$f_mr" ]    && list_args+=( "--mr=$f_mr" )

if ! rows=$(~/.tmux/oc-list.sh ${list_args[@]+"${list_args[@]}"}); then
  tmux display-message "oc-pick: cannot reach opencode server at $OC_URL"
  exit 0
fi

if [ -z "$rows" ]; then
  # Distinguish "nothing running" from "your filters hid everything", since
  # the fix is completely different.
  if [ -n "$f_dir$f_state$f_mr" ]; then
    tmux display-message "oc-pick: no sessions match the current filters"
  else
    tmux display-message "oc-pick: no opencode sessions on $OC_URL"
  fi
  exit 0
fi

TAB=$'\t'

# Two lines: what is filtered, then what the keys do. --header-first puts
# them above the prompt so the active filters read as a title for the list.
header="dir:${f_dir:-all}   state:${f_state:-all}   mr:${f_mr:-all}
^p dir   ^s state   ^r mr   tab multi-select   enter open"

selection=$(printf '%s\n' "$rows" | "$OC_FZF" \
  --delimiter="$TAB" \
  --with-nth="{2}$TAB{3}$TAB{4}$TAB{5}" \
  --accept-nth='{1}' \
  --nth=1,2 \
  --tabstop=1 \
  --multi \
  --reverse \
  --info=inline \
  --query="$query" \
  --prompt='session > ' \
  --header="$header" \
  --header-first \
  --bind "ctrl-p:become($self_cmd --facet=dir --query={q})" \
  --bind "ctrl-s:become($self_cmd --facet=state --query={q})" \
  --bind "ctrl-r:become($self_cmd --facet=mr --query={q})" \
) || exit 0

# --accept-nth hands back field 1, "id|slug", one line per selected row.
# First one wins the client; the rest are created in the background so a
# bulk open doesn't fight over where you end up.
switch=1
while IFS= read -r line; do
  [ -z "$line" ] && continue
  ~/.tmux/oc-open.sh "${line%%|*}" "${line#*|}" "$client_tty" "$switch"
  switch=0
done <<< "$selection"

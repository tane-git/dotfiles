#!/usr/bin/env bash
# oc-pick.sh — the session picker half of the opencode console.
#
#   usage: oc-pick.sh [--client=TTY] [--query=Q]
#                     [--facet=NAME] [--dir=X] [--state=X] [--mr=X]
#
#   Runs as the left pane of the OC SEARCH session built by oc-console.sh,
#   looping so that Enter can hand off to oc-open.sh without the pane dying.
#   The right pane is a real opencode client which this steers via
#   oc-drive.sh on every selection change.
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
#   No state outlives the picker, and nothing needs cleaning up if it dies.
#
# Safety:
#   Read-only against the opencode server. The only side effect is
#   oc-open.sh, which creates or switches to a tmux session and nothing else.
set -u
source ~/.tmux/oc-lib.sh

# Fail with something actionable rather than "command not found" buried in a
# pane that may vanish the instant the script exits. The version floor is
# real, not defensive: on an older fzf the --accept-nth template is rejected
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
  facet_err=$(mktemp)
  if ! values=$(~/.tmux/oc-facets.sh "$facet" 2>"$facet_err"); then
    tmux display-message "oc-pick: $(tr '\n' ' ' < "$facet_err")"
    rm -f "$facet_err"
    exit 0
  fi
  rm -f "$facet_err"

  # A cancelled picker (Esc, exit 130) must leave the filter alone, which is
  # why the exit status is tested rather than the emptiness of $chosen —
  # "(all)" legitimately maps to an empty value.
  # Themed to match list mode, in yellow rather than green: you are inside a
  # filter picker, and the colour you are about to put on the list is the
  # colour the picker itself wears.
  if chosen=$(printf '%s\n' "$values" | "$OC_FZF" \
                --prompt="$facet > " \
                --header='esc  keep current' \
                --header-first \
                --no-multi \
                --reverse \
                --info=inline \
                --border=rounded \
                --border-label=" filter by $facet " \
                --border-label-pos=3 \
                --color='border:bright-yellow,label:bright-yellow:bold:reverse,prompt:bright-yellow:bold,pointer:bright-yellow:bold,header:dim,info:dim,hl:bright-yellow,hl+:bright-yellow:bold'); then
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

err_file=$(mktemp)
trap 'rm -f "$err_file"' EXIT
if ! rows=$(~/.tmux/oc-list.sh ${list_args[@]+"${list_args[@]}"} 2>"$err_file"); then
  tmux display-message "oc-pick: $(tr '\n' ' ' < "$err_file")"
  exit 0
fi

if [ -z "$rows" ]; then
  # Two very different situations, and only one of them is terminal.
  if [ -z "$f_dir$f_state$f_mr" ]; then
    # Genuinely nothing on the server — there is no filter to relax, so an
    # empty picker would just be a dead end.
    tmux display-message "oc-pick: no opencode sessions on $OC_URL"
    exit 0
  fi

  # Filtered down to nothing. Closing here was wrong: the filter is precisely
  # what needs undoing, and quitting takes away the keys that would undo it.
  # This is easy to hit because the state facet always offers busy/retry even
  # when nothing happens to be busy, which is deliberate — you want to be able
  # to arm that filter while waiting for something to start.
  #
  # An id field left empty makes the row inert: the open loop below skips
  # blank ids, so Enter on it does nothing rather than opening a phantom.
  rows=$(printf '\t  nothing matches — ^p ^s ^r to change the filter\t\t')
fi

TAB=$'\t'

# Help lives in the preview pane, hidden until "?" — the keys matter once,
# when you are learning them, and then never again, whereas the filter state
# matters on every single keystroke. Putting both in the header gave the
# permanent space to the thing you stop reading.
#
# A fixed path rather than mktemp: `become` replaces this process without
# running EXIT traps, so a per-run temp file would leak one copy on every
# filter change. Overwriting the same file each run costs nothing and leaves
# exactly one behind.
help_file="${TMPDIR:-/tmp}/oc-pick-help-$(id -u).txt"
{
  cat <<'HELP'

  MOVE      up / down        move
            enter            open
            tab              add to selection
            esc              cancel

  FILTER    ctrl-p           directory
            ctrl-s           state
            ctrl-r           MR status

  VIEW      ?                this help
            alt-l / alt-h    move to the session pane and back

  The right pane is a live opencode client, not a
  picture of one — it follows the selection, and you
  can move into it and type.


  Typing searches session titles only. Directory and
  state are filter keys, so a word like "flame" can
  never match a column you did not mean.

  Selecting several rows opens all of them and moves
  you to the first.

HELP
} > "$help_file"

# Active filters are drawn as a reversed yellow chip in the header. They used
# to be a border label, but the console puts fzf in a real tmux pane which
# already draws its own border — a second frame inside it was two wasted
# columns and two competing green outlines.
#
# There is deliberately nothing shown when no filter is set: a permanent
# "opencode sessions" title tells you something you already know, and the
# point of the chip is that its presence *is* the signal.
active=""
for chip in "dir:$f_dir" "state:$f_state" "mr:$f_mr"; do
  [ -n "${chip#*:}" ] || continue
  [ -n "$active" ] && active="$active  "
  active="$active$chip"
done

chip_style=$'\033[1;7;93m'
dim=$'\033[2m'
off=$'\033[0m'

# Green is reserved for one thing only: the row you are on. Everything
# structural — prompt, separator rule, both scrollbars, the preview divider,
# the match count — is medium grey, so the eye has exactly one place to land.
# Chrome that is the same colour as the selection competes with it for
# attention and makes the list harder to scan, not easier.
#
# Matches are yellow rather than grey: greying them would hide the thing you
# just typed. Yellow also ties them to the filter chip and the multi-select
# marker, which are the other two "pay attention here" signals.
# Numeric, not "colour244" — that is tmux's spelling and fzf rejects it
# outright with "invalid color specification".
GREY=244
fzf_colors="border:${GREY},label:${GREY},prompt:${GREY},separator:${GREY}"
fzf_colors="${fzf_colors},scrollbar:${GREY},preview-border:${GREY},preview-scrollbar:${GREY}"
fzf_colors="${fzf_colors},info:${GREY},header:${GREY}"
fzf_colors="${fzf_colors},pointer:green:bold,marker:bright-yellow:bold"
fzf_colors="${fzf_colors},hl:bright-yellow,hl+:bright-yellow:bold"

header_hint="${dim}?  help${off}"
[ -n "$active" ] && header_hint="${chip_style} ● ${active} ${off}  ${header_hint}"

# No fzf border: the console runs this in a real tmux pane which draws its
# own, and nesting a second one wastes two columns on a duplicate outline.
#
# No fzf preview of the session either — the pane to the right *is* the
# session, live and interactive, so anything drawn here would be a worse copy
# of what is already on screen. The preview window is kept for the help text
# alone.
#
# start fires once when the list first paints and focus on every subsequent
# move, which together mean the right pane always matches the highlighted
# row — including the very first one, before you have touched anything.
selection=$(printf '%s\n' "$rows" | "$OC_FZF" \
  --bind "start:execute-silent(~/.tmux/oc-drive.sh {1})" \
  --bind "focus:execute-silent(~/.tmux/oc-drive.sh {1})" \
  --preview "cat \"$help_file\"" \
  --preview-window 'down,45%,border-top,wrap,hidden' \
  --delimiter="$TAB" \
  --with-nth="{2}$TAB{3}$TAB{4}" \
  --accept-nth='{1}' \
  --nth=1 \
  --tabstop=1 \
  --multi \
  --reverse \
  --info=inline \
  --color="$fzf_colors" \
  --query="$query" \
  --prompt='search > ' \
  --header="$header_hint" \
  --header-first \
  --bind "?:change-preview(cat \"$help_file\")+change-preview-window(down,45%,border-top,wrap|hidden)" \
  --bind "ctrl-p:become($self_cmd --facet=dir --query={q})" \
  --bind "ctrl-s:become($self_cmd --facet=state --query={q})" \
  --bind "ctrl-r:become($self_cmd --facet=mr --query={q})" \
) || exit 0

# --accept-nth hands back field 1, the session id, one line per selected row.
# First one wins the client; the rest are created in the background so a
# bulk open doesn't fight over where you end up.
switch=1
while IFS= read -r id; do
  [ -z "$id" ] && continue
  ~/.tmux/oc-open.sh "$id" "$client_tty" "$switch"
  switch=0
done <<< "$selection"

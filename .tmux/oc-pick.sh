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
client_tty="" facet="" query="" console=""
f_dir="" f_state="" f_mr=""

for arg in "$@"; do
  case "$arg" in
    --client=*) client_tty="${arg#--client=}" ;;
    --facet=*)  facet="${arg#--facet=}" ;;
    --query=*)  query="${arg#--query=}" ;;
    --dir=*)    f_dir="${arg#--dir=}" ;;
    --state=*)  f_state="${arg#--state=}" ;;
    --mr=*)     f_mr="${arg#--mr=}" ;;
    --console)  console=1 ;;
    *) echo "oc-pick: unknown argument '$arg'" >&2; exit 1 ;;
  esac
done

# Re-invocation of this script carrying the current filters. Used both to
# re-exec after a facet pick (as an array) and to build the `become` bindings
# (as a %q-quoted string, since fzf hands those to sh -c).
self_args=()
[ -n "$client_tty" ] && self_args+=( "--client=$client_tty" )
[ -n "$console" ]    && self_args+=( "--console" )
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
  [ -n "$console" ] && args+=( "--console" )
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
cat > "$help_file" <<'HELP'

  MOVE      up / down        move
            enter            open
            tab              add to selection
            esc              cancel

  FILTER    ctrl-p           directory
            ctrl-s           state
            ctrl-r           MR status

  VIEW      ctrl-o           preview the selected session
            ?                this help

  Typing searches session titles only. Directory and
  state are filter keys, so a word like "flame" can
  never match a column you did not mean.

  Selecting several rows opens all of them and moves
  you to the first.

HELP

# The active filters become the border label, and the colour changes with
# them. Unfiltered is calm green; the moment anything is narrowing the list
# the label goes reversed yellow, so "why am I only seeing 30 sessions" is
# answerable at a glance instead of by reading a line of text that looks the
# same either way.
active=""
for chip in "dir:$f_dir" "state:$f_state" "mr:$f_mr"; do
  [ -n "${chip#*:}" ] || continue
  [ -n "$active" ] && active="$active  "
  active="$active$chip"
done

if [ -n "$active" ]; then
  label=" ● $active "
  label_color="label:bright-yellow:bold:reverse"
else
  label=" opencode sessions "
  label_color="label:green:bold"
fi

# The preview earns its space only when there is space. A 50% split of an
# ssh'd 80-column pod leaves ~36 columns for a row that wants 68, so titles
# would be shredded to make room for a pane nobody asked for. Wide terminals
# get it open by default because that is where it is genuinely useful;
# narrow ones get it on ctrl-o.
term_cols=$(tput cols 2>/dev/null || echo 80)
if [ "$term_cols" -ge 120 ]; then
  preview_window='right,50%,border-left,wrap'
else
  preview_window='right,50%,border-left,wrap,hidden'
fi

# In console mode the pane to the right *is* the session, live and
# interactive, so fzf's own preview has nothing left to do — it would be a
# worse copy of what is already on screen. The preview window stays wired up
# for the help text alone, and ctrl-o is dropped rather than left bound to
# something redundant.
#
# start fires once when the list first paints and focus on every subsequent
# move, which together mean the right pane always matches the highlighted
# row — including the very first one, before you have touched anything.
mode_binds=()
if [ -n "$console" ]; then
  mode_binds+=( --bind "start:execute-silent(~/.tmux/oc-drive.sh {1})" )
  mode_binds+=( --bind "focus:execute-silent(~/.tmux/oc-drive.sh {1})" )
  mode_binds+=( --preview "cat \"$help_file\"" )
  mode_binds+=( --preview-window 'down,45%,border-top,wrap,hidden' )
  header_hint='?  help'
else
  mode_binds+=( --preview "~/.tmux/oc-preview.sh {1}" )
  mode_binds+=( --preview-window "$preview_window" )
  mode_binds+=( --bind "ctrl-o:change-preview(~/.tmux/oc-preview.sh {1})+change-preview-window(right,50%,border-left,wrap|hidden)" )
  header_hint='?  help      ctrl-o  preview'
fi

selection=$(printf '%s\n' "$rows" | "$OC_FZF" \
  --delimiter="$TAB" \
  --with-nth="{2}$TAB{3}$TAB{4}" \
  --accept-nth='{1}' \
  --nth=1 \
  --tabstop=1 \
  --multi \
  --reverse \
  --info=inline \
  --border=rounded \
  --border-label="$label" \
  --border-label-pos=3 \
  --color="border:green,${label_color},prompt:green:bold,pointer:green:bold,marker:bright-yellow:bold,header:dim,info:dim,hl:bright-green,hl+:bright-green:bold" \
  --query="$query" \
  --prompt='search > ' \
  --header="$header_hint" \
  --header-first \
  "${mode_binds[@]}" \
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

#!/usr/bin/env bash
# oc-facets.sh — list the distinct values of one facet across all opencode
# sessions, for the drill-down pickers in oc-pick.sh.
#
#   usage: oc-facets.sh <facet>
#
#   A "facet" is any session attribute with a small fixed set of values —
#   the things you slice the list by rather than search for. Typing is for
#   titles; facets get a hotkey and a picker, because choosing from four
#   options beats typing a word that might also appear in a title.
#
#   Facets are deliberately derived here and not baked into oc-list.sh, so
#   adding one later means adding a case to both and nothing else.
#
#   "(all)" is always first and means "no filter" — oc-pick.sh maps it back
#   to an empty value.
set -u
source ~/.tmux/oc-lib.sh

facet="${1:?usage: oc-facets.sh <facet>}"

sessions=$(oc_api "/session?limit=${OC_LIMIT}") || exit 1

case "$facet" in
  # Sessions currently doing something appear in /session/status; idle ones
  # are simply absent. The value set is therefore fixed, not data-derived —
  # listing it statically means the picker still offers "busy" when nothing
  # happens to be busy right now, which is what you want when you are
  # waiting for something to start.
  state)
    printf '%s\n' "$OC_FACET_ALL" busy retry idle
    exit 0
    ;;
  dir) expr='(.directory // "" | split("/") | last)' ;;
  # Empty on every session until Inferno starts tagging them (see
  # oc-lib.sh); the picker then shows just "(all)" and this facet is inert
  # rather than broken.
  mr)  expr='(.metadata.mr_state // "")' ;;
  *)
    echo "oc-facets: unknown facet '$facet'" >&2
    exit 1
    ;;
esac

{
  printf '%s\n' "$OC_FACET_ALL"
  jq -r "[.[] | $expr | select(. != \"\")] | unique | .[]" <<< "$sessions"
}

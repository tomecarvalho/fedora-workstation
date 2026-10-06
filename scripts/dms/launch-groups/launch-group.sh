#!/usr/bin/env bash

# Launch a group of applications on monitor/workspace positions selected from
# the currently connected Niri outputs.
#
# Usage:
#   launch-group.sh <group>
#   launch-group.sh --list
#
# The group definitions live in config.yaml next to this script.

set -u

script_dir=$(dirname "$(readlink -f "$0")")
config=${LAUNCH_GROUPS_CONFIG:-"$script_dir/config.yaml"}
poll_attempts=${LAUNCH_GROUPS_POLL_ATTEMPTS:-40}
poll_delay=${LAUNCH_GROUPS_POLL_DELAY:-0.25}

die() {
  printf 'launch-group: %s\n' "$*" >&2
  exit 1
}

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Launch groups" "$1" "${2:-}"
  elif command -v dms >/dev/null 2>&1; then
    dms ipc call toast info "$1${2:+ ($2)}" >/dev/null 2>&1 || true
  fi
}

command -v niri >/dev/null 2>&1 || die "niri is not available"
command -v jq >/dev/null 2>&1 || die "jq is not available"
command -v yq >/dev/null 2>&1 || die "yq is not available (install the yq package)"
[ -r "$config" ] || die "missing config: $config"

outputs_json=$(niri msg -j outputs 2>/dev/null) ||
  die "could not query Niri outputs"
profile=$(printf '%s\n' "$outputs_json" | jq -er 'keys | sort | join("+")') ||
  die "Niri returned invalid output data"

list_groups() {
  yq -r '.groups | keys[]' "$config"
}

if [ "${1:-}" = "--list" ]; then
  list_groups
  exit 0
fi

group=${1:-}
[ -n "$group" ] || die "usage: $0 <group>"

matches=$(GROUP="$group" PROFILE="$profile" yq -r '
  .groups[strenv(GROUP)].displays[strenv(PROFILE)][] |
  [.app_id, .output, (.workspace | tostring), .command, (.reuse | tostring)] | @tsv
' "$config" 2>/dev/null) ||
  die "could not read display profile '$profile' for group '$group' from $config"
[ -n "$matches" ] ||
  die "no definition for group '$group' on display profile '$profile'"

windows_json() {
  niri msg -j windows 2>/dev/null
}

window_for_app() {
  local app_regex=$1
  windows_json | jq -er --arg app "$app_regex" '
    first(.[] | select((.app_id // "") | test($app))) | .id // empty
  ' 2>/dev/null || true
}

window_for_new_app() {
  local app_regex=$1 existing_ids=$2
  windows_json | jq -er --arg app "$app_regex" --arg existing "$existing_ids" '
    ($existing | split("\n") | map(select(length > 0) | tonumber)) as $old_ids |
    first(.[] | select(((.app_id // "") | test($app)) and
      (.id as $id | ($old_ids | index($id) | not)))) |
    .id // empty
  ' 2>/dev/null || true
}

move_window() {
  local window_id=$1 output=$2 workspace=$3

  niri msg action move-window-to-monitor --id "$window_id" "$output" >/dev/null ||
    die "could not move window $window_id to output '$output'"
  niri msg action move-window-to-workspace --window-id "$window_id" "$workspace" \
    >/dev/null ||
    die "could not move window $window_id to workspace $workspace"
}

launched=0
failed=0
while IFS=$'\t' read -r app_regex output workspace command reuse; do
  [ -n "${command:-}" ] || {
    printf 'launch-group: empty command for app %s\n' "$app_regex" >&2
    failed=1
    continue
  }

  case "$reuse" in
    true)
      window_id=$(window_for_app "$app_regex")
      ;;
    false)
      window_id=
      ;;
    *)
      printf 'launch-group: reuse must be true or false for app %s\n' "$app_regex" >&2
      failed=1
      continue
      ;;
  esac

  if [ -z "$window_id" ]; then
    existing_ids=$(windows_json | jq -r '.[].id' 2>/dev/null || true)
    niri msg action spawn-sh -- "$command" >/dev/null ||
      die "could not launch '$command'"

    for ((attempt = 0; attempt < poll_attempts; attempt++)); do
      sleep "$poll_delay"
      if [ "$reuse" = true ]; then
        window_id=$(window_for_app "$app_regex")
      else
        window_id=$(window_for_new_app "$app_regex" "$existing_ids")
      fi
      [ -n "$window_id" ] && break
    done
  fi

  if [ -z "$window_id" ]; then
    printf 'launch-group: timed out waiting for app matching %s\n' "$app_regex" >&2
    failed=1
    continue
  fi

  move_window "$window_id" "$output" "$workspace"
  launched=$((launched + 1))
done <<< "$matches"

[ "$failed" -eq 0 ] ||
  die "group '$group' completed with errors"

notify "Launch group: $group" "$launched applications on $profile"
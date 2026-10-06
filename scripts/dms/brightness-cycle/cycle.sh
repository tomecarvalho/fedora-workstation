#!/usr/bin/env sh

# Usage: cycle.sh [next|<PresetName>]
#
# Cycles (or directly applies) brightness presets defined in
# brightness-cycle.yaml, which lives next to this script.
# Override its location with BRIGHTNESS_CONFIG=/path.
#
# The YAML config contains a devices map of IDs to labels/output names and a
# presets map of preset names to device IDs and percentages. Presets cycle in
# YAML order.

script_dir=$(dirname "$(readlink -f "$0")")

config="${BRIGHTNESS_CONFIG:-$script_dir/brightness-cycle.yaml}"

# Remembers the last applied preset. XDG_RUNTIME_DIR is a per-user tmpfs
# (cleared on reboot/logout), with /tmp as a fallback.
state="${XDG_RUNTIME_DIR:-/tmp}/brightness-preset"

# Show a notification: notify <title> [body]
# Prefers notify-send (title + body); falls back to a one-line DMS toast.
# The x-canonical-private-synchronous hint asks the notification daemon to
# replace the previous brightness notification instead of stacking new ones.
# The transient hint asks the daemon not to keep it in the notification history.
notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Brightness" -h boolean:transient:true -h string:x-canonical-private-synchronous:brightness-preset "$1" "$2"
  else
    # ${2:+ ($2)} appends " (body)" only if a body was given
    dms ipc call toast info "$1${2:+ ($2)}" >/dev/null 2>&1
  fi
}

# Print the label for a device id, or nothing if there is none.
# The label is optional; callers fall back to the device ID when it is empty.
label_for() {
  DEVICE="$1" yq -r '.devices[strenv(DEVICE)].label // ""' "$config"
}

output_for() {
  DEVICE="$1" yq -r '.devices[strenv(DEVICE)].output // ""' "$config"
}

# Bail out early if the config can't be read.
command -v yq >/dev/null 2>&1 ||
  { notify "Brightness: yq is unavailable"; exit 1; }
command -v niri >/dev/null 2>&1 ||
  { notify "Brightness: niri is unavailable"; exit 1; }
command -v jq >/dev/null 2>&1 ||
  { notify "Brightness: jq is unavailable"; exit 1; }
[ -r "$config" ] || { notify "Brightness: missing config" "$config"; exit 1; }

# Build the ordered list of preset names from the config.
presets=$(yq -r '.presets | to_entries[] | .key' "$config" 2>/dev/null) ||
  { notify "Brightness: invalid config" "$config"; exit 1; }
[ -n "$presets" ] || { notify "Brightness: no presets in config"; exit 1; }

# Decide which preset to apply: the one named on the command line,
# or the next one after the last applied (default).
arg="${1:-next}"
if [ "$arg" = next ]; then
  cur=$(cat "$state" 2>/dev/null) # Last applied preset (empty on first run)
  # Walk the preset list and print the entry after $cur, wrapping to the first:
  #   NR==1    - Remember the first name (for wrap-around)
  #   take     - Previous line matched $cur, so print this line and stop
  #   $0==cur  - Found the current preset, set the flag for the next line
  #   END      - If we never printed anything (cur was last, or unknown), use the first
  target=$(printf '%s\n' "$presets" | awk -v cur="$cur" '
    NR==1   {first=$0}
    take    {print; done=1; exit}
    $0==cur {take=1}
    END     {if (!done) print first}')
else
  target="$arg"
  # grep -x matches the whole line only; -- stops a preset name from being read as a flag.
  printf '%s\n' "$presets" | grep -qx -- "$target" || { notify "Brightness: unknown preset" "$target"; exit 1; }
fi

# Ask DMS which brightness devices exist right now, and Niri which displays
# are active. DMS may retain an unplugged DDC device, so active outputs are
# the source of truth for notification membership.
devices=$(dms ipc call brightness list 2>/dev/null)
outputs=$(niri msg -j outputs 2>/dev/null) || {
  notify "Brightness: could not query displays"
  exit 1
}
printf '%s\n' "$outputs" | jq -e 'type == "object"' >/dev/null 2>&1 || {
  notify "Brightness: invalid display data"
  exit 1
}
summary=""
preset_devices=$(CONFIG="$config" PRESET="$target" yq -r \
  '.presets[strenv(PRESET)] | to_entries[] | [.key, (.value | tostring)] | @tsv' \
  "$config" 2>/dev/null) || {
  notify "Brightness: invalid config" "$config"
  exit 1
}

# Read the selected preset's device/value pairs from YAML.
while read -r dev val; do
  printf '%s\n' "$devices" | grep -q "^$dev " || continue   # skip unknown devices
  output=$(output_for "$dev")
  [ -n "$output" ] || continue
  printf '%s\n' "$outputs" | jq -e --arg output "$output" 'has($output)' \
    >/dev/null 2>&1 || continue # skip outputs that aren't currently active

  # Run in the background (&) so slow DDC monitors don't delay the laptop panel.
  dms ipc call brightness set "$val" "$dev" >/dev/null 2>&1 &

  # Build the notification body. ${summary:+$summary, } adds ", " only if
  # summary is already non-empty. ${label:-${dev#*:}} uses the label from the
  # devices file if there is one, otherwise the device id with its
  # "backlight:" / "ddc:" prefix stripped.
  label=$(label_for "$dev")
  summary="${summary:+$summary, }${label:-${dev#*:}} ${val}%"
done <<EOF
$preset_devices
EOF
wait   # block until all the background brightness calls have finished

# Nothing matched: the preset exists but none of its devices are present here.
if [ -z "$summary" ]; then
  notify "Brightness Preset: $target" "No matching devices"
  exit 1
fi

# Save the preset so the next "next" call continues from here, then notify.
echo "$target" > "$state"
notify "Brightness Preset: $target" "$summary"
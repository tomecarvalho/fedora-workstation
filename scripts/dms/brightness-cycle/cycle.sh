#!/usr/bin/env sh

# Usage: cycle.sh [next|<PresetName>]
#
# Cycles (or directly applies) brightness presets defined in
# presets.conf, which lives next to this script.
# Friendly device names come from devices.conf (also next to it).
# Override the locations with BRIGHTNESS_PRESETS=/path and BRIGHTNESS_DEVICES=/path.
#
# presets.conf, one line per preset/device pair (# starts a comment):
#   <PresetName>  <device-id>  <percent>
# Presets cycle in the order they first appear in the config.
# Lines for devices that aren't present on this machine are skipped.
#
# devices.conf, one line per device:
#   <device-id>  <label>
# The label is shown in the notification (may contain spaces). It is optional:
# a device without one is shown by its id minus the "backlight:"/"ddc:" prefix.

script_dir=$(dirname "$(readlink -f "$0")")

# Config paths: use the env override if set, otherwise the files next to the script.
# ${VAR:-default} means "value of VAR, or default if VAR is unset/empty".
conf="${BRIGHTNESS_PRESETS:-$script_dir/presets.conf}"
devconf="${BRIGHTNESS_DEVICES:-$script_dir/devices.conf}"

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
#   $1 == d          - first column matches the device id
#   $1 = ""; sub(...) - drop the id and the whitespace after it, leaving the label
label_for() {
  [ -r "$devconf" ] || return 0
  awk -v d="$1" '$1 == d { $1 = ""; sub(/^[[:space:]]+/, ""); print; exit }' "$devconf"
}

# Bail out early if the config can't be read.
[ -r "$conf" ] || { notify "Brightness: missing config" "$conf"; exit 1; }

# Build the ordered list of unique preset names from the config.
#   !/^[[:space:]]*(#|$)/ - Skip comment lines and blank lines
#   !seen[$1]++           - True only the first time a name appears (dedupe, keeps order)
#   {print $1}            - Print the first column (preset name)
presets=$(awk '!/^[[:space:]]*(#|$)/ && !seen[$1]++ {print $1}' "$conf")
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

# Ask DMS which brightness devices exist right now, so we can skip config
# lines for hardware that isn't connected (other laptop, unplugged monitor).
devices=$(dms ipc call brightness list 2>/dev/null)
summary=""

# Read the config line by line, splitting each line into fields:
#   name = preset, dev = device id, val = percent, _ = anything extra (ignored)
while read -r name dev val _; do
  case $name in ''|'#'*) continue ;; esac            # skip blank and comment lines
  [ "$name" = "$target" ] || continue                # only lines for the chosen preset
  printf '%s\n' "$devices" | grep -q "^$dev " || continue   # skip devices not on this machine

  # Run in the background (&) so slow DDC monitors don't delay the laptop panel.
  dms ipc call brightness set "$val" "$dev" >/dev/null 2>&1 &

  # Build the notification body. ${summary:+$summary, } adds ", " only if
  # summary is already non-empty. ${label:-${dev#*:}} uses the label from the
  # devices file if there is one, otherwise the device id with its
  # "backlight:" / "ddc:" prefix stripped.
  label=$(label_for "$dev")
  summary="${summary:+$summary, }${label:-${dev#*:}} ${val}%"
done < "$conf"
wait   # block until all the background brightness calls have finished

# Nothing matched: the preset exists but none of its devices are present here.
if [ -z "$summary" ]; then
  notify "Brightness Preset: $target" "No matching devices"
  exit 1
fi

# Save the preset so the next "next" call continues from here, then notify.
echo "$target" > "$state"
notify "Brightness Preset: $target" "$summary"
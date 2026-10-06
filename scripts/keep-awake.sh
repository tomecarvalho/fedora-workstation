#!/usr/bin/env bash

# Keeps the system awake by moving the mouse and pressing Shift periodically.
# Dims the given backlight devices to 1% while running, then restores them
# (helps prevent OLED burn-in).
# Example usage:
#   BACKLIGHT_DEVICES="intel_backlight nvidia_0" ./dim-awake.sh

set -u

readonly LEFT_SHIFT=42
readonly INTERVAL=5

read -r -a devices <<<"${BACKLIGHT_DEVICES:-intel_backlight}"

for cmd in ydotool ydotoold brightnessctl; do
    command -v "$cmd" >/dev/null || { echo "$cmd is not installed." >&2; exit 1; }
done

declare -A saved_brightness
ydotoold_pid=
stop_daemon=(kill)

cleanup() {
    local dev
    for dev in "${!saved_brightness[@]}"; do
        brightnessctl -d "$dev" set "${saved_brightness[$dev]}" >/dev/null 2>&1
    done

    if [[ -n $ydotoold_pid ]]; then
        "${stop_daemon[@]}" "$ydotoold_pid" 2>/dev/null
    fi
}

trap cleanup EXIT
trap 'exit 0' INT TERM

# Start ydotoold if needed. A socket can remain after the daemon exits, so
# checking only for the socket file is not enough.
export YDOTOOL_SOCKET="${YDOTOOL_SOCKET:-${XDG_RUNTIME_DIR:-/run/user/$UID}/.ydotool_socket}"

ydotool_ready() {
    [[ -S $YDOTOOL_SOCKET ]] && ydotool mousemove -x 0 -y 0 >/dev/null 2>&1
}

if ! ydotool_ready; then
    if [[ -e $YDOTOOL_SOCKET ]]; then
        rm -f -- "$YDOTOOL_SOCKET" \
            || { echo "Could not remove stale ydotool socket: $YDOTOOL_SOCKET" >&2; exit 1; }
    fi

    if [[ -r /dev/uinput && -w /dev/uinput ]]; then
        ydotoold --socket-path "$YDOTOOL_SOCKET" >/dev/null 2>&1 &
    else
        sudo -v || exit 1
        sudo -n ydotoold --socket-path "$YDOTOOL_SOCKET" --socket-perm 666 >/dev/null 2>&1 &
        stop_daemon=(sudo -n kill)
    fi

    ydotoold_pid=$!

    for _ in {1..20}; do
        ydotool_ready && break
        sleep 0.1
    done

    ydotool_ready || { echo "ydotoold is not responding on socket: $YDOTOOL_SOCKET" >&2; exit 1; }
fi

# Save every device's brightness before touching any of them
for dev in "${devices[@]}"; do
    value="$(brightnessctl -d "$dev" get 2>/dev/null)"
    [[ -n $value ]] || { echo "Could not read the current brightness of '$dev'." >&2; exit 1; }
    saved_brightness[$dev]=$value
done

for dev in "${devices[@]}"; do
    brightnessctl -d "$dev" set 1 >/dev/null 2>&1 \
        || { echo "Could not lower the brightness of '$dev'." >&2; exit 1; }
done

move_mouse() { ydotool mousemove -x "$1" -y 0; }

echo "Keeping awake. Press Q to quit."

while true; do
    for step in 5 -5; do
        move_mouse "$step"
        ydotool key "$LEFT_SHIFT:1" "$LEFT_SHIFT:0"

        if read -r -n 1 -s -t "$INTERVAL" key && [[ $key == [Qq] ]]; then
            exit 0
        fi
    done
done
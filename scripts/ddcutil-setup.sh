#!/usr/bin/env bash

# Set up ddcutil as instructed on:
# https://github.com/daitj/gnome-display-brightness-ddcutil
# https://extensions.gnome.org/extension/2645/brightness-control-using-ddcutil/
# Allows the extension to control the brightness of compatible displays via DDC/CI.

set -euo pipefail

RULES_DST_DIR="/etc/udev/rules.d"
MODULES_LOAD_FILE="/etc/modules-load.d/i2c.conf"

ensure_ddcutil_installed() {
	echo "[install] Installing ddcutil"
	sudo dnf in -y ddcutil
}

load_i2c_module_now() {
	echo "[module] Loading i2c-dev module"
	sudo modprobe i2c-dev
}

setup_udev_rules() {
	echo "[udev] Configuring ddcutil udev rule"

	local src_rule=""
	local dst_rule=""

	if [[ -f "/usr/share/ddcutil/data/60-ddcutil-i2c.rules" ]]; then
		src_rule="/usr/share/ddcutil/data/60-ddcutil-i2c.rules"
		dst_rule="$RULES_DST_DIR/60-ddcutil-i2c.rules"
	elif [[ -f "/usr/share/ddcutil/data/45-ddcutil-i2c.rules" ]]; then
		src_rule="/usr/share/ddcutil/data/45-ddcutil-i2c.rules"
		dst_rule="$RULES_DST_DIR/45-ddcutil-i2c.rules"
	else
		echo "[udev] Could not find ddcutil rule template under /usr/share/ddcutil/data" >&2
		exit 1
	fi

	sudo cp "$src_rule" "$dst_rule"

	# Fedora 40+ may require this rule line to be uncommented.
	if [[ "$dst_rule" == *"60-ddcutil-i2c.rules" ]]; then
		if sudo grep -q '^# KERNEL=="i2c-\[0-9\]\*", GROUP="i2c", MODE="0660"' "$dst_rule"; then
			echo "[udev] Uncommenting i2c kernel permission rule for Fedora"
			sudo sed -i 's/^# KERNEL=="i2c-\[0-9\]\*", GROUP="i2c", MODE="0660"/KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"/' "$dst_rule"
		fi
	fi

	sudo udevadm control --reload-rules
	sudo udevadm trigger
}

ensure_i2c_group_and_membership() {
	echo "[group] Ensuring i2c group exists"
	if ! getent group i2c > /dev/null; then
		sudo groupadd --system i2c
	fi

	echo "[group] Ensuring user '$USER' is in i2c group"
	if id -nG "$USER" | tr ' ' '\n' | grep -qx i2c; then
		echo "[group] User '$USER' already in i2c group"
	else
		sudo usermod -aG i2c "$USER"
		echo "[group] Added '$USER' to i2c group"
	fi
}

persist_i2c_module() {
	echo "[module] Persisting i2c-dev module in $MODULES_LOAD_FILE"
	sudo touch "$MODULES_LOAD_FILE"

	if sudo grep -qx 'i2c-dev' "$MODULES_LOAD_FILE"; then
		echo "[module] i2c-dev already present"
	else
		echo 'i2c-dev' | sudo tee -a "$MODULES_LOAD_FILE" > /dev/null
	fi
}

verify_brightness_feature() {
	echo "[verify] Checking if DDC/CI brightness feature (VCP 0x10) is available"

	if ddcutil capabilities 2>/dev/null | grep -q "Feature: 10"; then
		echo "[verify] Brightness control feature detected"
	else
		echo "[verify] Brightness feature not detected yet. This can happen on unsupported displays or before reboot."
	fi
}

main() {
	ensure_ddcutil_installed
	load_i2c_module_now
	setup_udev_rules
	ensure_i2c_group_and_membership
	persist_i2c_module
	verify_brightness_feature

	cat <<EOF

Setup complete.
Next steps:
	1. Reboot.
	2. Test with:
		 ddcutil getvcp 10
		 ddcutil setvcp 10 100
EOF
}

main "$@"


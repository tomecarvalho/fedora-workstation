#!/usr/bin/env bash

set -euo pipefail

ECHO_PREFIX="[dconf-push]"

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
UTILS_DIR="${SCRIPT_DIR}/../utils"

source "${UTILS_DIR}/core.sh"
source "${UTILS_DIR}/git.sh"

# Navigate to repository root.
util_cd_repo_root_from_script "$0" 2 "$ECHO_PREFIX"

util_require_commands "$ECHO_PREFIX" git dconf

# Abort if working tree is dirty.
util_git_assert_clean_worktree "$ECHO_PREFIX"

# Check whether local branch is in sync with upstream.
SYNC_STATE="$(util_git_get_sync_state)"

case "$SYNC_STATE" in
	synced)
		:
		;;
	behind)
		util_die "$ECHO_PREFIX" "Local branch is behind upstream. Run 'git pull --ff-only' first."
		;;
	ahead)
		util_die "$ECHO_PREFIX" "Local branch is ahead of upstream. Push or reconcile before running this script."
		;;
	diverged)
		util_die "$ECHO_PREFIX" "Local and upstream branches have diverged. Reconcile branches before running this script."
		;;
	no-upstream)
		util_die "$ECHO_PREFIX" "No upstream is configured for the current branch."
		;;
	*)
		util_die "$ECHO_PREFIX" "Unexpected git sync state: $SYNC_STATE"
		;;
esac

# Repo-root-relative path to the tracked dconf snapshot.
CONFIG_FILE="gnome/dconf/config.dconf"
mkdir -p "$(dirname "$CONFIG_FILE")"

TMP_CONFIG="$(mktemp)"
trap 'rm -f "$TMP_CONFIG"' EXIT

# Curated set of stable settings to keep under version control.
DCONF_EXPORT_PATHS=(
	"/org/gnome/desktop/background/"
	"/org/gnome/desktop/interface/"
	"/org/gnome/desktop/input-sources/"
	"/org/gnome/desktop/peripherals/keyboard/"
	"/org/gnome/desktop/peripherals/mouse/"
	"/org/gnome/desktop/peripherals/touchpad/"
	"/org/gnome/desktop/wm/keybindings/"
	"/org/gnome/desktop/wm/preferences/"
	"/org/gnome/mutter/"
	"/org/gnome/mutter/keybindings/"
	"/org/gnome/settings-daemon/plugins/media-keys/"
	"/org/gnome/settings-daemon/plugins/color/"
	"/org/gnome/settings-daemon/plugins/power/"
	"/org/gnome/shell/keybindings/"
	"/org/gnome/shell/extensions/appindicator/"
	"/org/gnome/shell/extensions/copyous/"
	"/org/gnome/shell/extensions/copyous/file-item/"
	"/org/gnome/shell/extensions/copyous/link-item/"
	"/org/gnome/shell/extensions/display-brightness-ddcutil/"
	"/org/gnome/desktop/sound/"
	"/org/gnome/login-screen/"
	"/org/gnome/system/location/"
	"/org/gtk/settings/color-chooser/"
	"/org/gnome/desktop/search-providers/"
	"/org/gnome/desktop/privacy/"
	"/org/gnome/nautilus/preferences/"
	"/org/gnome/nautilus/icon-view/"
)

for path in "${DCONF_EXPORT_PATHS[@]}"; do
	dconf dump "$path" >> "$TMP_CONFIG"
done

# Keep selected root shell preferences while excluding transient keys.
SHELL_ROOT_KEYS=(
	"enabled-extensions"
	"disabled-extensions"
	"favorite-apps"
)

WROTE_SHELL_SECTION=false
for key in "${SHELL_ROOT_KEYS[@]}"; do
	value="$(dconf read "/org/gnome/shell/${key}" 2>/dev/null || true)"
	if [[ -n "$value" ]]; then
		if [[ "$WROTE_SHELL_SECTION" == false ]]; then
			echo "[org/gnome/shell]" >> "$TMP_CONFIG"
			WROTE_SHELL_SECTION=true
		fi
		echo "${key}=${value}" >> "$TMP_CONFIG"
	fi
done

if [[ "$WROTE_SHELL_SECTION" == true ]]; then
	echo >> "$TMP_CONFIG"
fi

[[ -s "$TMP_CONFIG" ]] || util_die "$ECHO_PREFIX" "Curated dconf export is empty; refusing to overwrite ${CONFIG_FILE}."
mv "$TMP_CONFIG" "$CONFIG_FILE"
trap - EXIT

git add "$CONFIG_FILE"

if git diff --cached --quiet; then
	echo "${ECHO_PREFIX} No changes in ${CONFIG_FILE}; nothing to commit."
	exit 0
fi

read -r -p "${ECHO_PREFIX} Commit and push updated config.dconf? [y/n] (default: y): " CONFIRM
CONFIRM="${CONFIRM:-y}"

case "$CONFIRM" in
	y|Y)
		;;
	n|N)
		echo "${ECHO_PREFIX} Operation cancelled by user."
		exit 0
		;;
	*)
		util_die "$ECHO_PREFIX" "Invalid response '$CONFIRM'. Expected y or n."
		;;
esac

git commit -m "Update dconf config"
git push
echo "${ECHO_PREFIX} Updated and pushed ${CONFIG_FILE} successfully."
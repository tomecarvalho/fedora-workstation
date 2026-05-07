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
FULL_DUMP="$(mktemp)"
trap 'rm -f "$TMP_CONFIG" "$FULL_DUMP"' EXIT

# Dump full tree once, then filter to curated sections/keys while preserving
# absolute section headers and spacing expected by `dconf load /`.
dconf dump / > "$FULL_DUMP"

KEEP_SECTIONS_CSV="org/gnome/desktop/background,org/gnome/desktop/interface,org/gnome/desktop/input-sources,org/gnome/desktop/peripherals/keyboard,org/gnome/desktop/peripherals/mouse,org/gnome/desktop/peripherals/touchpad,org/gnome/desktop/wm/keybindings,org/gnome/desktop/wm/preferences,org/gnome/mutter,org/gnome/mutter/keybindings,org/gnome/settings-daemon/plugins/media-keys,org/gnome/settings-daemon/plugins/color,org/gnome/settings-daemon/plugins/power,org/gnome/shell/keybindings,org/gnome/shell/extensions/appindicator,org/gnome/shell/extensions/copyous,org/gnome/shell/extensions/copyous/file-item,org/gnome/shell/extensions/copyous/link-item,org/gnome/shell/extensions/display-brightness-ddcutil,org/gnome/desktop/sound,org/gtk/settings/color-chooser,org/gnome/desktop/search-providers,org/gnome/desktop/privacy,org/nautilus/preferences,org/gnome/nautilus/icon-view"
SHELL_ROOT_KEYS_CSV="enabled-extensions,disabled-extensions,favorite-apps"

awk \
	-v keep_sections_csv="$KEEP_SECTIONS_CSV" \
	-v shell_root_keys_csv="$SHELL_ROOT_KEYS_CSV" '
	BEGIN {
		n = split(keep_sections_csv, keep_sections, ",")
		for (i = 1; i <= n; i++) {
			keep[keep_sections[i]] = 1
		}
		m = split(shell_root_keys_csv, shell_keys, ",")
		for (i = 1; i <= m; i++) {
			keep_shell_key[shell_keys[i]] = 1
		}
		printed_any_section = 0
		current_section = ""
	}

	function start_section(section_name) {
		if (printed_any_section) {
			print ""
		}
		print "[" section_name "]"
		printed_any_section = 1
	}

	/^\[[^]]+\]$/ {
		current_section = substr($0, 2, length($0) - 2)
		section_started = 0
		next
	}

	/^[[:space:]]*$/ {
		next
	}

	{
		if (current_section == "") {
			next
		}

		if (keep[current_section]) {
			if (current_section == "org/gnome/settings-daemon/plugins/color" && $0 ~ /^night-light-last-coordinates=/) {
				next
			}
			if (!section_started) {
				start_section(current_section)
				section_started = 1
			}
			print $0
			next
		}

		if (current_section == "org/gnome/shell") {
			split($0, kv, "=")
			key = kv[1]
			if (keep_shell_key[key]) {
				if (!section_started) {
					start_section(current_section)
					section_started = 1
				}
				print $0
			}
		}
	}
' "$FULL_DUMP" > "$TMP_CONFIG"

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
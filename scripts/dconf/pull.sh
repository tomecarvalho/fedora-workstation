#!/usr/bin/env bash

set -euo pipefail

ECHO_PREFIX="[dconf-pull]"

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
UTILS_DIR="${SCRIPT_DIR}/../utils"

source "${UTILS_DIR}/core.sh"
source "${UTILS_DIR}/git.sh"

# Navigate to repository root.
util_cd_repo_root_from_script "$0" 2 "$ECHO_PREFIX"

util_require_commands "$ECHO_PREFIX" git dconf

# Check whether local branch needs a pull from upstream.
SYNC_STATE="$(util_git_get_sync_state)"

case "$SYNC_STATE" in
	synced)
		:
		;;
	behind)
		git pull --ff-only
		;;
	ahead)
		echo "${ECHO_PREFIX} Local branch is ahead of upstream; continuing (no pull needed)."
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
[[ -f "$CONFIG_FILE" ]] || util_die "$ECHO_PREFIX" "Missing ${CONFIG_FILE}."

dconf load / < "$CONFIG_FILE"

echo "${ECHO_PREFIX} Applied ${CONFIG_FILE} successfully."
#!/usr/bin/env bash

# Sync the same home paths (and optional project dirs) that the backup scripts
# cover to another machine on the local network via rsync over SSH.
# On conflicts, this machine (the sender) wins.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/core.sh
source "$SCRIPT_DIR/../utils/core.sh"

ECHO_PREFIX="[sync-local]"

DIRS_TO_SYNC=(
	"$HOME/.ssh"
	"$HOME/.oh-my-zsh"
	"$HOME/.cursor"
	"$HOME/.config/Cursor"
	"$HOME/.thunderbird"
	"$HOME/.mozilla"
	"$HOME/.vpn"
)

FILES_TO_SYNC=(
	"$HOME/.zsh_history"
	"$HOME/.zshrc"
	"$HOME/.bashrc"
	"$HOME/.bash_history"
	"$HOME/.profile"
	"$HOME/.bash_profile"
	"$HOME/.private.aliases"
)

# Same excludes as backup-projects.sh
PROJECT_EXCLUDE_PATTERNS=(
	"build"
	"dist"
	"out"
	"output"
	"node_modules"
	".npm"
	".pnpm-store"
	".yarn/cache"
	"venv"
	".venv"
	"__pycache__"
	".pytest_cache"
	".tox"
	"*.egg-info"
	".mypy_cache"
	"target"
	".gradle"
	".m2"
	"vendor"
)

usage() {
	cat <<EOF
Usage: $(basename "$0") [options] <host>

Copy home backup paths (and optional project directories) to another machine
over SSH. Local (sender) files win on conflicts.

Arguments:
  host                 SSH target, e.g. laptop or user@192.168.1.50

Options:
  -p, --project DIR    Project directory to sync (repeatable; must be under \$HOME)
  -n, --dry-run        Show what would be transferred without writing
  -d, --delete         Remove files on the remote that are gone locally
  -h, --help           Show this help

Examples:
  $(basename "$0") laptop
  $(basename "$0") user@192.168.1.50 -p ~/projects/app
  $(basename "$0") --dry-run laptop -p ~/Code/foo -p ~/Code/bar
EOF
}

DRY_RUN=0
DELETE=0
REMOTE=""
PROJECT_DIRS=()

while [[ $# -gt 0 ]]; do
	case "$1" in
	-p | --project)
		if [[ $# -lt 2 || "$2" == -* ]]; then
			util_die "$ECHO_PREFIX" "$1 requires a directory argument."
		fi
		PROJECT_DIRS+=("$2")
		shift 2
		;;
	-n | --dry-run)
		DRY_RUN=1
		shift
		;;
	-d | --delete)
		DELETE=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	-*)
		util_die "$ECHO_PREFIX" "Unknown option: $1"
		;;
	*)
		if [[ -n "$REMOTE" ]]; then
			util_die "$ECHO_PREFIX" "Unexpected argument: $1 (use -p/--project for project directories)."
		fi
		REMOTE="$1"
		shift
		;;
	esac
done

if [[ -z "$REMOTE" ]]; then
	usage >&2
	exit 1
fi

util_require_commands "$ECHO_PREFIX" rsync ssh

RSYNC_OPTS=(-aH --partial --human-readable --info=progress2)
if [[ "$DRY_RUN" -eq 1 ]]; then
	RSYNC_OPTS+=(--dry-run)
fi
if [[ "$DELETE" -eq 1 ]]; then
	RSYNC_OPTS+=(--delete)
fi

echo "$ECHO_PREFIX Checking SSH connectivity to ${REMOTE}..."
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE" "true" 2>/dev/null; then
	util_die "$ECHO_PREFIX" "Cannot reach '${REMOTE}' over SSH (is the host up and key-based auth set up?)."
fi

remote_home_path() {
	local abs_path="$1"
	local rel="${abs_path#"$HOME"/}"
	if [[ "$rel" == "$abs_path" ]]; then
		util_die "$ECHO_PREFIX" "Path is not under \$HOME: $abs_path"
	fi
	printf '%s\n' "$rel"
}

sync_dir() {
	local src="$1"
	local dest_rel
	dest_rel="$(remote_home_path "$src")"

	if [[ ! -d "$src" ]]; then
		echo "$ECHO_PREFIX Skipping missing directory: $src"
		return 0
	fi

	echo "$ECHO_PREFIX Syncing directory: $src -> ${REMOTE}:${dest_rel}/"
	rsync "${RSYNC_OPTS[@]}" -e ssh "${src}/" "${REMOTE}:${dest_rel}/"
}

sync_file() {
	local src="$1"
	local dest_rel
	dest_rel="$(remote_home_path "$src")"

	if [[ ! -f "$src" ]]; then
		echo "$ECHO_PREFIX Skipping missing file: $src"
		return 0
	fi

	echo "$ECHO_PREFIX Syncing file: $src -> ${REMOTE}:${dest_rel}"
	rsync "${RSYNC_OPTS[@]}" -e ssh "$src" "${REMOTE}:${dest_rel}"
}

sync_project() {
	local src="$1"
	local dest_rel
	local exclude_args=()
	local pattern

	if [[ ! -d "$src" ]]; then
		util_die "$ECHO_PREFIX" "Project directory does not exist: $src"
	fi

	# Resolve to absolute path for home-relative destination mapping
	src="$(cd "$src" && pwd)"
	dest_rel="$(remote_home_path "$src")"

	for pattern in "${PROJECT_EXCLUDE_PATTERNS[@]}"; do
		exclude_args+=(--exclude="$pattern")
	done

	echo "$ECHO_PREFIX Syncing project: $src -> ${REMOTE}:${dest_rel}/"
	rsync "${RSYNC_OPTS[@]}" "${exclude_args[@]}" -e ssh "${src}/" "${REMOTE}:${dest_rel}/"
}

if [[ "$DRY_RUN" -eq 1 ]]; then
	echo "$ECHO_PREFIX Dry run — no files will be written on ${REMOTE}"
fi

echo "$ECHO_PREFIX Syncing home paths to ${REMOTE}..."
for dir in "${DIRS_TO_SYNC[@]}"; do
	sync_dir "$dir"
done
for file in "${FILES_TO_SYNC[@]}"; do
	sync_file "$file"
done

if [[ ${#PROJECT_DIRS[@]} -gt 0 ]]; then
	echo "$ECHO_PREFIX Syncing project directories to ${REMOTE}..."
	for project in "${PROJECT_DIRS[@]}"; do
		sync_project "$project"
	done
fi

echo "$ECHO_PREFIX Done."

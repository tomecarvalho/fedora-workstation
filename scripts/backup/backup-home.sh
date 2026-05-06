#!/usr/bin/env bash

# Script to backup select directories and files from the home directory.

set -euo pipefail

# Configuration: keep all archives in ~/backups and add a timestamp to each archive
BACKUP_DIR="${HOME}/backups"
# Use UTC timestamp in format YYYYMMDDTHHMMSSZ
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_SUBDIR="${BACKUP_DIR}/home-${TIMESTAMP}"
mkdir -p "$BACKUP_SUBDIR"
trap 'rm -rf "$BACKUP_SUBDIR"' EXIT

# Directories to backup
DIRS_TO_BACKUP=(
	"$HOME/.ssh"
	"$HOME/.oh-my-zsh"
	"$HOME/.cursor"
	"$HOME/.config/Cursor"
	"$HOME/.thunderbird"
	"$HOME/.mozilla"
	"$HOME/.vpn"
)

# Files to backup
FILES_TO_BACKUP=(
	"$HOME/.zsh_history"
	"$HOME/.zshrc"
	"$HOME/.bashrc"
	"$HOME/.bash_history"
	"$HOME/.profile"
	"$HOME/.bash_profile"
	"$HOME/.private.aliases"
)

# Create backup directory (subdir for this run)
echo "Starting backup to: $BACKUP_SUBDIR"

# Backup directories
for dir in "${DIRS_TO_BACKUP[@]}"; do
	if [[ -d "$dir" ]]; then
		echo "Backing up directory: $dir"
		cp -r "$dir" "$BACKUP_SUBDIR/"
	else
		echo "Warning: Directory not found: $dir"
	fi
done

# Backup files
for file in "${FILES_TO_BACKUP[@]}"; do
	if [[ -f "$file" ]]; then
		echo "Backing up file: $file"
		cp "$file" "$BACKUP_SUBDIR/"
	else
		echo "Warning: File not found: $file"
	fi
done

# Create tar archive with timestamp in filename
ARCHIVE="${BACKUP_DIR}/home-${TIMESTAMP}.tar.gz"
echo "Creating archive: $ARCHIVE"
tar -czf "$ARCHIVE" -C "$BACKUP_DIR" "home-${TIMESTAMP}"

# Clean up the uncompressed backup subdirectory
rm -rf "$BACKUP_SUBDIR"

echo "Backup completed successfully!"
echo "Archive saved to: $ARCHIVE"
echo "Archive size: $(du -h "$ARCHIVE" | cut -f1)"
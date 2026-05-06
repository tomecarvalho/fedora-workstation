#!/usr/bin/env bash

set -euo pipefail

# Script to backup a project directory, excluding common package manager caches and dependencies.
# Ignores files with permission errors.

# Check if directory argument is provided
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <directory>" >&2
    exit 1
fi

PROJECT_DIR="$1"

# Verify directory exists
if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "Error: Directory '$PROJECT_DIR' does not exist" >&2
    exit 1
fi

# Create backups directory if it doesn't exist
BACKUP_DIR="${HOME}/backups"
mkdir -p "$BACKUP_DIR"

# Get the directory name
DIR_NAME=$(basename "$PROJECT_DIR")

# Define backup file path with UTC timestamp
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_FILE="${BACKUP_DIR}/${DIR_NAME}-${TIMESTAMP}.tar.gz"

# Exclude patterns for common package managers and caches
EXCLUDE_PATTERNS=(
  # Common build directories
  "build"
  "dist"
  "out"
  "output"

  # Node.js
  "node_modules"
  ".npm"
  ".pnpm-store"
  ".yarn/cache"
  
  # Python
  "venv"
  ".venv"
  "__pycache__"
  ".pytest_cache"
  ".tox"
  "*.egg-info"
  ".mypy_cache"
  
  # Rust
  "target"
  
  # Java/Gradle/Maven
  ".gradle"
  ".m2"
  
  # Go and PHP
  "vendor"
)

# Build tar exclude arguments as an array
TAR_EXCLUDE_ARGS=()
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
  TAR_EXCLUDE_ARGS+=("--exclude=${pattern}")
done

# Create the backup
echo "Creating backup of '$PROJECT_DIR' to '$BACKUP_FILE'..."
tar --ignore-failed-read --exclude-caches "${TAR_EXCLUDE_ARGS[@]}" -czf "$BACKUP_FILE" -C "$(dirname "$PROJECT_DIR")" "$DIR_NAME"

# Check if backup was successful
if [[ -f "$BACKUP_FILE" ]]; then
  SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
  echo "✓ Backup completed!"
  echo "  Location: $BACKUP_FILE"
  echo "  Size: $SIZE"
  echo "  (Some files may have been skipped due to permission errors)"
else
  echo "Error: Backup file was not created" >&2
  exit 1
fi


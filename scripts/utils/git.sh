#!/usr/bin/env bash

# Git-specific utility helpers shared by shell scripts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=core.sh
source "$SCRIPT_DIR/core.sh"

# Abort when repository has uncommitted changes.
util_git_assert_clean_worktree() {
  local prefix="$1"

  if [[ -n "$(git status --porcelain)" ]]; then
    util_die "$prefix" "There are uncommitted changes in the repository. Commit or stash them first."
  fi
}

# Return branch sync state compared to upstream: synced|behind|ahead|diverged|no-upstream
util_git_get_sync_state() {
  local upstream_ref
  local local_commit
  local upstream_commit
  local base_commit

  git fetch --quiet
  upstream_ref="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"

  if [[ -z "$upstream_ref" ]]; then
    echo "no-upstream"
    return 0
  fi

  local_commit="$(git rev-parse @)"
  upstream_commit="$(git rev-parse '@{u}')"
  base_commit="$(git merge-base @ '@{u}')"

  if [[ "$local_commit" == "$upstream_commit" ]]; then
    echo "synced"
  elif [[ "$local_commit" == "$base_commit" ]]; then
    echo "behind"
  elif [[ "$upstream_commit" == "$base_commit" ]]; then
    echo "ahead"
  else
    echo "diverged"
  fi
}

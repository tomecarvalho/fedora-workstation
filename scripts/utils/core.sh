#!/usr/bin/env bash

# Core utility helpers shared by shell scripts.

# Print an error with a prefix and exit.
util_die() {
  local prefix="$1"
  shift
  echo "${prefix} $*" >&2
  exit 1
}

# Ensure required commands are available in PATH.
util_require_commands() {
  local prefix="$1"
  shift
  local cmd

  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || util_die "$prefix" "$cmd is not installed."
  done
}

# Change current directory to repository root based on script location.
# Arguments: <script_path> <levels_up> <error_prefix>
util_cd_repo_root_from_script() {
  local script_path="$1"
  local levels_up="$2"
  local prefix="$3"
  local root
  local i

  root="$(dirname "$(realpath "$script_path")")"

  for ((i = 0; i < levels_up; i++)); do
    root="${root}/.."
  done

  root="$(realpath "$root")"
  cd "$root" || util_die "$prefix" "Failed to access repository root."
}

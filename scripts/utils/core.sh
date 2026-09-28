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

# Install a font archive into a system font directory.
# Arguments: <prefix> <font_name> <font_url> <font_dir>
util_install_font() {
  local prefix="$1"
  local font_name="$2"
  local font_url="$3"
  local font_dir="$4"

  if fc-list | grep -q "$font_name"; then
    echo "$prefix $font_name is already installed"
    return
  fi

  sudo mkdir -p "$font_dir"

  local tmp_zip
  tmp_zip="$(mktemp --suffix=.zip)"
  curl -L -o "$tmp_zip" "$font_url"
  sudo unzip -o "$tmp_zip" -d "$font_dir"
  rm -f "$tmp_zip"

  sudo fc-cache -fv

  echo "$prefix Installed $font_name to $font_dir"
}

# Install individual font files into a system font directory.
# Arguments: <prefix> <font_name> <font_dir> <font_url>...
util_install_font_files() {
  local prefix="$1"
  local font_name="$2"
  local font_dir="$3"
  shift 3

  if fc-list | grep -Fq "$font_name"; then
    echo "$prefix $font_name is already installed"
    return
  fi

  sudo mkdir -p "$font_dir"

  local font_url
  local font_file
  local tmp_font
  for font_url in "$@"; do
    font_file="${font_url##*/}"
    tmp_font="$(mktemp)"
    curl --globoff -fL -o "$tmp_font" "$font_url"
    sudo install -m 644 "$tmp_font" "$font_dir/$font_file"
    rm -f "$tmp_font"
  done

  sudo fc-cache -fv

  echo "$prefix Installed $font_name to $font_dir"
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

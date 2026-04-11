#!/usr/bin/env bash

# Shared utility functions for installation scripts

# Read package list from a file, filtering out empty lines and comments
read_package_list() {
  local pkg_file="$1"
  
  if [[ ! -f "$pkg_file" ]]; then
    echo "Package list not found: $pkg_file" >&2
    exit 1
  fi
  
  mapfile -t packages < <(grep -vE '^\s*($|#)' "$pkg_file")
  echo "${packages[@]}"
}

#!/usr/bin/env sh

if [ $# -eq 0 ]; then
  echo "Usage: fct <file1> [file2] ..." >&2
  exit 1
fi

_uris="cut"
_n=0
for _file in "$@"; do
  if [ -e "$_file" ]; then
    _uris="${_uris}
file://$(realpath "$_file")"
    _n=$((_n + 1))
  else
    echo "Warning: '$_file' does not exist, skipping." >&2
  fi
done

if [ "$_n" -eq 0 ]; then
  exit 1
fi

printf "%s" "$_uris" | wl-copy --type x-special/gnome-copied-files

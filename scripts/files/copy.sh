#!/usr/bin/env sh

if [ $# -eq 0 ]; then
  echo "Usage: wl-copyfile <file1> [file2] ..." >&2
  exit 1
fi

_uris=""
for _file in "$@"; do
  if [ -e "$_file" ]; then
    _uris="${_uris}file://$(realpath "$_file")
"
  else
    echo "Warning: '$_file' does not exist, skipping." >&2
  fi
done

printf "%s" "${_uris%?}" | wl-copy --type text/uri-list

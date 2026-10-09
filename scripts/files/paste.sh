#!/usr/bin/env sh

_dest=${1:-.}
if [ ! -d "$_dest" ]; then
  echo "fpst: '$_dest' is not a directory" >&2
  exit 1
fi

_list=$(wl-paste --no-newline --type text/uri-list 2>/dev/null) ||
_list=$(wl-paste --no-newline --type x-special/gnome-copied-files 2>/dev/null) || {
  echo "fpst: no files on the clipboard" >&2
  exit 1
}

_fpst_urldecode() {
  _s=$1
  _out=
  while [ -n "$_s" ]; do
    case $_s in
      %[0-9A-Fa-f][0-9A-Fa-f]*)
        _h=${_s#%}
        _h=${_h%"${_h#??}"}
        _out="$_out$(printf "\\$(printf '%03o' "0x$_h")")"
        _s=${_s#???}
        ;;
      *)
        _c=${_s%"${_s#?}"}
        _out="$_out$_c"
        _s=${_s#?}
        ;;
    esac
  done
  printf '%s' "$_out"
}

printf '%s\n' "$_list" | tr -d '\r' | while IFS= read -r _line; do
  case $_line in
    file://*) ;;
    *) continue ;;
  esac
  _path=$(_fpst_urldecode "${_line#file://}")
  if [ -e "$_path" ]; then
    cp -Rp -- "$_path" "$_dest"/
  else
    echo "Warning: '$_path' does not exist, skipping." >&2
  fi
done

#!/usr/bin/env sh

if [ $# -lt 1 ]; then
  echo "Usage: ghostty_terminfo <host>" >&2
  exit 1
fi

infocmp -x xterm-ghostty | ssh "$1" -- tic -x -

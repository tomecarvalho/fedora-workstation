#!/usr/bin/env bash

set -euo pipefail

if command -v snapper >/dev/null 2>&1 &&
  command -v btrfs >/dev/null 2>&1 &&
  [[ -f /etc/snapper/configs/root ]] &&
  [[ "$(findmnt -n -o FSTYPE /)" == btrfs ]]; then
  echo "[update] Create a Snapper snapshot before updating packages"
  sudo snapper -c root create --description "Before system update"
else
  echo "[update] Snapper/Btrfs not configured, skipping snapshot"
fi

echo "[update] Update DNF packages"
sudo dnf update -y

echo "[update] Update Flatpaks"
flatpak update -y

echo "[update] Update Snaps"
sudo snap refresh

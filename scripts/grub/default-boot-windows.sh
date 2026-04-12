#!/usr/bin/env bash

# Sets Windows Boot Manager as the default GRUB entry, if Windows appears to be installed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../utils/core.sh"

LOG_PREFIX='[default-boot-windows]'

DEFAULTS_FILE="/etc/default/grub"

WINDOWS_BOOT_MANAGER_LABEL="Windows Boot Manager"

log() {
  printf '%s %s\n' "$LOG_PREFIX" "$*"
}

warn() {
  printf '%s %s\n' "$LOG_PREFIX" "$*" >&2
}

die() {
  util_die "$LOG_PREFIX" "$*"
}

run_as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    util_require_commands "$LOG_PREFIX" sudo
    sudo "$@"
  fi
}

find_grub_cfg() {
  local candidates=(
    "/boot/grub2/grub.cfg"
    "/boot/grub/grub.cfg"
    "/etc/grub2-efi.cfg"
    "/etc/grub2.cfg"
    "/boot/efi/EFI/fedora/grub.cfg"
  )
  local c
  for c in "${candidates[@]}"; do
    [[ -f "$c" ]] || continue
    if [[ -L "$c" ]]; then
      readlink -f "$c"
    else
      printf '%s\n' "$c"
    fi
    return 0
  done
  return 1
}

windows_appears_installed() {
  if command -v efibootmgr >/dev/null 2>&1; then
    if efibootmgr 2>/dev/null | grep -qi "$WINDOWS_BOOT_MANAGER_LABEL"; then
      return 0
    fi
  fi

  local cfg
  cfg="$(find_grub_cfg 2>/dev/null || true)"
  [[ -n "${cfg:-}" ]] && grep -qi "$WINDOWS_BOOT_MANAGER_LABEL" "$cfg"
}

ensure_grub_default_saved() {
  [[ -f "$DEFAULTS_FILE" ]] || die "Missing $DEFAULTS_FILE"

  util_require_commands "$LOG_PREFIX" mktemp cmp

  local tmp_file
  local confirm
  tmp_file="$(mktemp)"
  trap 'rm -f "$tmp_file"' RETURN

  cp "$DEFAULTS_FILE" "$tmp_file"

  if grep -qE '^GRUB_DEFAULT=' "$tmp_file"; then
    sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' "$tmp_file"
  else
    printf '\nGRUB_DEFAULT=saved\n' >> "$tmp_file"
  fi

  if cmp -s "$DEFAULTS_FILE" "$tmp_file"; then
    log "No changes needed in $DEFAULTS_FILE"
    return 0
  fi

  log "About to modify $DEFAULTS_FILE"
  printf '%s\n' "----- BEFORE: $DEFAULTS_FILE -----"
  cat "$DEFAULTS_FILE"
  printf '%s\n' "----- AFTER: $DEFAULTS_FILE -----"
  cat "$tmp_file"

  read -r -p "$LOG_PREFIX Apply these changes? [y/n]: " confirm
  case "$confirm" in
    y|Y)
      run_as_root cp "$tmp_file" "$DEFAULTS_FILE"
      log "Updated $DEFAULTS_FILE"
      ;;
    *)
      log "Cancelled by user. No changes made."
      exit 0
      ;;
  esac
}

rebuild_grub() {
  util_require_commands "$LOG_PREFIX" grub2-mkconfig

  local cfg_link cfg_out
  if [[ -d /sys/firmware/efi ]]; then
    cfg_link="/etc/grub2-efi.cfg"
  else
    cfg_link="/etc/grub2.cfg"
  fi

  cfg_out="$(readlink -f "$cfg_link" 2>/dev/null || true)"
  [[ -n "${cfg_out:-}" ]] || cfg_out="$cfg_link"

  log "Regenerating GRUB config: $cfg_out" >&2
  run_as_root grub2-mkconfig -o "$cfg_out" >/dev/null
  printf '%s\n' "$cfg_out"
}

find_windows_entry() {
  local cfg="$1"
  run_as_root cat "$cfg" \
    | grep -E "^menuentry '.*$WINDOWS_BOOT_MANAGER_LABEL.*'" \
    | head -n1 \
    | sed -E "s/^menuentry '([^']+)'.*/\1/"
}

set_grub_saved_entry() {
  local entry="$1"
  util_require_commands "$LOG_PREFIX" grub2-set-default
  run_as_root grub2-set-default "$entry"
}

if ! windows_appears_installed; then
  log "Windows does not appear to be installed. Nothing to do."
  exit 0
fi

log "Windows appears to be installed."
ensure_grub_default_saved
cfg_file="$(rebuild_grub)"

entry="$(find_windows_entry "$cfg_file" || true)"
if [[ -z "${entry:-}" ]]; then
  warn "No GRUB menu entry matching 'Windows Boot Manager' was found."
  warn "If needed, enable os-prober and regenerate GRUB."
  exit 0
fi

set_grub_saved_entry "$entry"
log "Set GRUB default entry to: $entry"
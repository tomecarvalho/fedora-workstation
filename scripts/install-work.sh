#!/usr/bin/env bash

# Installs work-related software

set -euo pipefail

# Default, ordered list of descriptive step names
ALL_STEPS=(
  copr
  dnf_install
  snap_install
  cursor
  chrome
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKGS_DIR="$SCRIPT_DIR/../packages/work"

source "$SCRIPT_DIR/utils.sh"

copr() {
  echo "[copr] Enable COPR repositories"
  
  local copr_file="$PKGS_DIR/copr.txt"
  local repos=($(read_package_list "$copr_file"))

  echo "[copr] Enabling ${#repos[@]} COPR repositories..."

  for repo in "${repos[@]}"; do
    sudo dnf copr enable -y "$repo"
  done
}

dnf_install() {
  echo "[dnf_install] Install DNF packages"
  PKG_FILE="$PKGS_DIR/dnf.txt"

  local packages=($(read_package_list "$PKG_FILE"))

  echo "[dnf_install] Installing ${#packages[@]} packages with dnf..."
  sudo dnf in -y "${packages[@]}"
}

snap_install() {
  echo "[snap_install] Install Snap packages"
  PKG_FILE="$PKGS_DIR/snap.txt"

  local packages=($(read_package_list "$PKG_FILE"))

  if [[ ${#packages[@]} -eq 0 ]]; then
    echo "[snap_install] No packages to install"
    return
  fi

  echo "[snap_install] Installing ${#packages[@]} packages with snap..."
  for package in "${packages[@]}"; do
    sudo snap install "$package"
  done
}

cursor() {
  echo "[cursor] Add Cursor repository"
  sudo tee /etc/yum.repos.d/cursor.repo << 'EOF'
[cursor]
name=Cursor
baseurl=https://downloads.cursor.com/yumrepo
enabled=1
gpgcheck=1
gpgkey=https://downloads.cursor.com/keys/anysphere.asc
EOF
  
  echo "[cursor] Install Cursor"
  sudo dnf in -y cursor
}

chrome() {
  echo "[chrome] Enable Chrome repository and install it"
  sudo dnf config-manager setopt google-chrome.enabled=1
  sudo dnf in -y google-chrome-stable
}

usage() {
  cat <<EOF
Usage: $0 [-s "step1,step2" | -s "name1,name2"] [-l]

Options:
  -s, --steps   Comma-separated list of steps to run. Accepts either descriptive names or (deprecated) numbers.
                Steps run in the default order; duplicates are ignored.
                Examples: -s "copr,dnf_install" or -s "1,2"
  -l, --list    List all available steps in order.
  -h, --help    Show this help message.

Available steps (in order):
$(
  i=1
  for name in "${ALL_STEPS[@]}"; do
    printf "  %2d) %s\n" "$i" "$name"
    ((i++))
  done
)
EOF
}

# Parse args
STEPS_ARG=""
LIST_ONLY=false
while [[ $# > 0 ]]; do
  case "$1" in
    -s|--steps)
      if [[ -n "${2-}" ]]; then
        STEPS_ARG="$2"
        shift 2
        continue
      else
        echo "Error: --steps requires an argument" >&2
        usage
        exit 2
      fi
      ;;
    -l|--list)
      LIST_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ "$LIST_ONLY" == true ]]; then
  usage
  exit 0
fi

# Build ordered list of steps to run (names)
declare -a RUN_STEPS=()
if [[ -z "$STEPS_ARG" ]]; then
  RUN_STEPS=("${ALL_STEPS[@]}")
else
  declare -A requested=()
  IFS=',' read -ra raw <<< "$STEPS_ARG"
  for token in "${raw[@]}"; do
    # trim whitespace
    step=$(echo "$token" | xargs)
    if [[ -z "$step" ]]; then
      continue
    fi
    if [[ "$step" =~ ^[0-9]+$ ]]; then
      idx=$((10#$step))
      if (( idx < 1 || idx > ${#ALL_STEPS[@]} )); then
        echo "Invalid step number: $step" >&2
        exit 2
      fi
      name="${ALL_STEPS[$((idx-1))]}"
      requested["$name"]=1
    else
      # Validate name is in ALL_STEPS
      valid=false
      for name in "${ALL_STEPS[@]}"; do
        if [[ "$name" == "$step" ]]; then
          valid=true
          requested["$name"]=1
          break
        fi
      done
      if [[ "$valid" != true ]]; then
        echo "Invalid step name: $step" >&2
        exit 2
      fi
    fi
  done
  # Maintain default order and dedupe
  for name in "${ALL_STEPS[@]}"; do
    if [[ -n "${requested[$name]+x}" ]]; then
      RUN_STEPS+=("$name")
    fi
  done
fi

# Dispatch by name with validation
for s in "${RUN_STEPS[@]}"; do
  if declare -F "$s" > /dev/null; then
    "$s"
  else
    echo "Unknown step function: $s" >&2
    exit 3
  fi
done

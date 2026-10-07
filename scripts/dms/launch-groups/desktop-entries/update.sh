#!/usr/bin/env bash

# Generate DMS/application-launcher entries for the groups in config.yaml.
#
# Entries use a dedicated launch-group prefix so this helper overwrites only
# entries it owns.

set -u

script_dir=$(dirname "$(readlink -f "$0")")
project_dir=$(dirname "$script_dir")
config=${LAUNCH_GROUPS_CONFIG:-"$project_dir/config.yaml"}
data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
applications_dir="$data_home/applications"
launcher="$project_dir/launch-group.sh"

die() {
  printf 'update-desktop-entries: %s\n' "$*" >&2
  exit 1
}

command -v yq >/dev/null 2>&1 ||
  die "yq is not available (install the yq package)"
[ -r "$config" ] || die "missing config: $config"
[ -x "$launcher" ] || die "launcher is not executable: $launcher"
mkdir -p "$applications_dir" ||
  die "could not create application directory: $applications_dir"

desktop_quote() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '"%s"' "$value"
}

groups=$(yq -r '.groups | keys[]' "$config" 2>/dev/null) ||
  die "could not read groups from $config"

while IFS= read -r group; do
  [ -n "$group" ] || continue
  [[ "$group" =~ ^[A-Za-z0-9._-]+$ ]] ||
    die "group name '$group' contains unsupported filename characters"

  label=$(GROUP="$group" yq -r '.groups[strenv(GROUP)].label // ""' "$config") ||
    die "could not read label for group '$group'"
  [ -n "$label" ] || label="${group^}"
  icon=$(GROUP="$group" yq -r '.groups[strenv(GROUP)].icon // ""' "$config") ||
    die "could not read icon for group '$group'"
  [ -n "$icon" ] || icon=applications-office
  [[ "$icon" != *$'\n'* && "$icon" != *$'\r'* ]] ||
    die "icon for group '$group' contains a newline"

  desktop_file="$applications_dir/launch-group-$group.desktop"
  temporary_file=$(mktemp "$applications_dir/.launch-group-$group.XXXXXX") ||
    die "could not create temporary desktop entry"

  {
    printf '%s\n' '[Desktop Entry]'
    printf '%s\n' 'Type=Application'
    printf 'Name=%s\n' "$label"
    printf 'Comment=Launch the %s application group\n' "$label"
    printf 'Exec=%s %s\n' "$(desktop_quote "$launcher")" "$group"
    printf 'Icon=%s\n' "$icon"
    printf '%s\n' 'Terminal=false'
    printf '%s\n' 'Categories=Utility;'
  } >"$temporary_file" || {
    rm -f "$temporary_file"
    die "could not write desktop entry for group '$group'"
  }

  mv -f "$temporary_file" "$desktop_file" ||
    die "could not install desktop entry: $desktop_file"
  printf 'updated %s\n' "$desktop_file"
done <<< "$groups"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$applications_dir" >/dev/null ||
    die "could not update desktop database"
fi
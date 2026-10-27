#!/usr/bin/env bash

# Sets up each vault in vaults.yaml as a git repo and installs the vault-push command.
vault_setup() {
  local prefix="[vault-setup]"
  local dir cfg bin root i n

  # Locate this script's directory, the config file, and the install target
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cfg="$dir/vaults.yaml"
  bin="$HOME/.local/bin/vault-push"

  # Parse the config file
  command -v yq &>/dev/null || {
    echo "$prefix yq is required" >&2
    return 1
  }

  # Read the vaults root and expand a leading ~ to $HOME
  root=$(yq '.root' "$cfg")
  root="${root/#\~/$HOME}"

  # Trust GitHub's host key so the first push doesn't prompt
  mkdir -p "$HOME/.ssh" "$(dirname "$bin")"
  touch "$HOME/.ssh/known_hosts"
  grep -q '^github.com' "$HOME/.ssh/known_hosts" ||
    ssh-keyscan -t ed25519 github.com >>"$HOME/.ssh/known_hosts" 2>/dev/null

  # Loop over every vault entry in the YAML
  n=$(yq '.vaults | length' "$cfg")
  for ((i = 0; i < n; i++)); do
    local name host repo gname gemail vdir
    name=$(yq ".vaults[$i].name" "$cfg")
    host=$(yq ".vaults[$i].ssh_host" "$cfg")
    repo=$(yq ".vaults[$i].repo" "$cfg")
    gname=$(yq ".vaults[$i].git_name" "$cfg")
    gemail=$(yq ".vaults[$i].git_email" "$cfg")
    vdir="$root/$name"

    echo "$prefix configuring $name"
    mkdir -p "$vdir"

    # Init the repo only if it isn't one already
    [ -d "$vdir/.git" ] || git -C "$vdir" init -q -b main

    # Per-repo identity (keeps personal and work commits separate)
    git -C "$vdir" config user.name "$gname"
    git -C "$vdir" config user.email "$gemail"

    # Add the remote via the SSH host alias (selects the right key); skip if it exists
    git -C "$vdir" remote get-url origin &>/dev/null ||
      git -C "$vdir" remote add origin "git@$host:$repo.git"

    # Ignore volatile Obsidian files; don't overwrite an existing .gitignore
    [ -f "$vdir/.gitignore" ] ||
      printf '.obsidian/workspace*.json\n.trash/\n' >"$vdir/.gitignore"
  done

  # If Obsidian is a Flatpak, let it access the vaults folder
  if command -v flatpak &>/dev/null && flatpak info md.obsidian.Obsidian &>/dev/null; then
    flatpak override --user --filesystem="$root" md.obsidian.Obsidian
  fi

  echo "$prefix done. Run: vault_push [name ...]"
}

# Run the function when executed directly (not when sourced)
[[ "${BASH_SOURCE[0]}" == "$0" ]] && vault_setup "$@"

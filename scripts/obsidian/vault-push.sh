#!/usr/bin/env bash
# Commits and pushes vaults. Usage: vault-push [vault-name ...]  (default: all)

# Find vaults.yaml next to the real script (resolves the ~/.local/bin symlink)
cfg="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/vaults.yaml"
root=$(yq '.root' "$cfg")
root="${root/#\~/$HOME}"
root="${root/#\~/$HOME}"

# Use the names given as arguments, otherwise every vault in the YAML
names=("$@")
[ ${#names[@]} -eq 0 ] && mapfile -t names < <(yq '.vaults[].name' "$cfg")

for n in "${names[@]}"; do
  v="$root/$n"
  echo "== Vault: $n"

  # Stage everything; commit only if something changed
  git -C "$v" add -A
  git -C "$v" diff --cached --quiet || git -C "$v" commit -qm "Manual $(date -Is)"

  # Skip vaults with no commits yet (e.g. still empty)
  git -C "$v" rev-parse HEAD &>/dev/null || {
    echo "Nothing to push"
    continue
  }

  # Push the current branch and set upstream
  git -C "$v" push -q -u origin HEAD || echo "Push failed: $n" >&2
done

#!/usr/bin/env bash
# Install the notification plugins used by the compatibility tests.
# Usage: install-test-plugins.sh [pinned|latest]
set -euo pipefail

mode="${1:-pinned}"
if [ "$mode" != 'pinned' ] && [ "$mode" != 'latest' ]; then
  printf 'Unknown mode "%s". Use "pinned" or "latest".\n' "$mode" >&2
  exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pins="$root/tests/compat/pins.txt"
target="${HERDR_TEST_PLUGIN_DIR:-$root/.test-plugins}"
mkdir -p "$target"

while read -r name repository commit; do
  case "$name" in
    ''|'#'*) continue ;;
  esac

  directory="$target/$name"
  if [ ! -d "$directory/.git" ]; then
    rm -rf "$directory"
    git init --quiet "$directory"
    git -C "$directory" remote add origin "$repository"
  fi

  if [ "$mode" = 'latest' ]; then
    git -C "$directory" fetch --quiet --depth 1 origin HEAD
  else
    git -C "$directory" fetch --quiet --depth 1 origin "$commit"
  fi
  git -C "$directory" checkout --quiet --detach FETCH_HEAD

  head="$(git -C "$directory" rev-parse HEAD)"
  if [ "$mode" = 'pinned' ] && [ "$head" != "$commit" ]; then
    printf '%s pins %s but checked out %s. The pin must be a commit.\n' "$name" "$commit" "$head" >&2
    exit 1
  fi
  printf '%-14s %s %s\n' "$name" "$mode" "$head"
done < "$pins"

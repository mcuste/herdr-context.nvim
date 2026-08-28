#!/usr/bin/env bash
# Rewrite tests/compat/pins.txt from the commits checked out in the test
# plugin directory. Exits 0 and changes nothing when the pins already match.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pins="$root/tests/compat/pins.txt"
target="${HERDR_TEST_PLUGIN_DIR:-$root/.test-plugins}"
updated="$(mktemp)"
trap 'rm -f "$updated"' EXIT

while IFS= read -r line; do
  case "$line" in
    ''|'#'*)
      printf '%s\n' "$line" >> "$updated"
      continue
      ;;
  esac

  read -r name repository _commit <<< "$line"
  directory="$target/$name"
  if [ ! -d "$directory/.git" ]; then
    printf 'Missing test plugin: %s\n' "$directory" >&2
    exit 1
  fi
  printf '%s %s %s\n' "$name" "$repository" "$(git -C "$directory" rev-parse HEAD)" >> "$updated"
done < "$pins"

if cmp --silent "$updated" "$pins"; then
  printf 'The pins already match the checked out commits.\n'
  exit 0
fi

cp "$updated" "$pins"
printf 'Updated %s\n' "$pins"

#!/bin/sh
# sdd — detect duplicate docs/specs/NNN-* prefixes in the current workspace.
set -eu

root=.
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  root=$(git rev-parse --show-toplevel 2>/dev/null || printf '.')
fi

specs="$root/docs/specs"
[ -d "$specs" ] || { echo "sdd: no docs/specs under $root" >&2; exit 2; }

tmp=${TMPDIR:-/tmp}/sdd-check-ids.$$
trap 'rm -f "$tmp" "$tmp.dups"' EXIT INT TERM

find "$specs" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; \
  | sed -n 's/^\([0-9][0-9][0-9]\)-.*/\1/p' \
  | sort > "$tmp"

uniq -d "$tmp" > "$tmp.dups"
if [ -s "$tmp.dups" ]; then
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    printf 'sdd: duplicate spec id %s:\n' "$id" >&2
    find "$specs" -mindepth 1 -maxdepth 1 -type d -name "$id-*" -print | sort >&2
  done < "$tmp.dups"
  exit 1
fi

echo "sdd: spec ids unique"

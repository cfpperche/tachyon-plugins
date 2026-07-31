#!/usr/bin/env bash
# <this-skill-dir>/scripts/clear-target.sh
# selective clear of a /product-foundation --out target.
#
# Removes every top-level entry of <out> that is NOT in the runtime/harness
# allowlist, so a /product-foundation overwrite regenerates the docs foundation WITHOUT
# destroying .git/ history or the project's runtime harness (.claude / .agents /
# .tachyon). Selective clear instead of a blunt `rm -r <out>`, an unrecoverable foot-gun.

#
# Usage:  clear-target.sh <out>
# Exit:   0 success · 2 usage error (missing / non-directory <out>)

set -euo pipefail

# Runtime/harness allowlist — top-level entries preserved across a /product-foundation
# overwrite. The CANONICAL list lives in SKILL.md Phase 0 step 1; this is a copy. On a
# change, audit both (same drift caveat SKILL.md's overwrite note carries).
ALLOWLIST=(
  ".claude" ".agents" ".tachyon" ".githooks" ".gitignore"
  "CLAUDE.md" "AGENTS.md" ".git"
)

OUT="${1:-}"
if [ -z "$OUT" ]; then
  printf 'clear-target: missing <out>\nusage: clear-target.sh <out>\n' >&2
  exit 2
fi
OUT="${OUT%/}"
if [ ! -d "$OUT" ]; then
  printf 'clear-target: not a directory: %s\n' "$OUT" >&2
  exit 2
fi

in_allowlist() {
  local name="$1" entry
  for entry in "${ALLOWLIST[@]}"; do
    [ "$name" = "$entry" ] && return 0
  done
  return 1
}

removed=0
for path in "$OUT"/* "$OUT"/.*; do
  [ -e "$path" ] || continue          # unmatched glob → literal; skip
  name="$(basename "$path")"
  case "$name" in
    . | .. ) continue ;;              # the dir itself / its parent
  esac
  # Defense in depth: never remove the runtime harness, whatever the allowlist says.
  case "$name" in
    .git | .claude | .agents | .tachyon ) continue ;;
  esac
  if in_allowlist "$name"; then
    continue
  fi
  rm -r "$path"                        # -r only, never -rf (governance gate)
  printf 'removed %s\n' "$name"
  removed=$((removed + 1))
done

printf 'clear-target: %d non-harness top-level entr(ies) removed from %s\n' \
  "$removed" "$OUT" >&2
exit 0

#!/bin/sh
# sdd — scaffold a new spec: docs/specs/NNN-<slug>/{spec,plan,tasks,notes}.md
#
# Portable POSIX sh — runs identically under any runtime that has a shell
# (claude, codex). Resolves its own bundled templates relative to this script,
# so it works regardless of where the skill was materialized
# (.claude/skills/sdd or .agents/skills/sdd). Run from the WORKSPACE ROOT.
#
# Usage: new.sh <slug>
set -eu

# Resolve this script's dir → the templates live one level up, in ../templates.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMPLATES="$SCRIPT_DIR/../templates"
[ -d "$TEMPLATES" ] || { echo "sdd: templates not found at $TEMPLATES" >&2; exit 1; }

# 1. Sanitize the slug: lowercase, spaces/underscores → hyphens, drop anything
#    that is not [a-z0-9-], collapse repeats, trim leading/trailing hyphens.
raw=${1:-}
[ -n "$raw" ] || { echo "usage: new.sh <slug>" >&2; exit 2; }
slug=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' \
  | sed 's/[^a-z0-9-]//g; s/-\{2,\}/-/g; s/^-//; s/-$//')
[ -n "$slug" ] || { echo "sdd: slug is empty after sanitizing '$raw'" >&2; exit 2; }

# 2. Next NNN: strictly NNN-* dirs only (ignore non-numeric/malformed), default 001.
mkdir -p docs/specs
max=$(ls -1 docs/specs 2>/dev/null | sed -n 's/^\([0-9][0-9][0-9]\)-.*/\1/p' | sort -n | tail -1)
# Strip leading zeros before arithmetic — POSIX `$(( ))` reads a leading-zero number
# as OCTAL (041 → 33, and 08/09 error out). Keep at least one digit.
max=$(printf '%s' "${max:-0}" | sed 's/^0*\([0-9]\)/\1/')
n=$(( max + 1 ))

# 3. Allocate the dir ATOMICALLY (mkdir fails if it exists) so two agents racing
#    the same number don't collide — bump and retry on a taken number.
while :; do
  nnn=$(printf '%03d' "$n")
  dir="docs/specs/$nnn-$slug"
  if mkdir "$dir" 2>/dev/null; then break; fi
  [ -d "$dir" ] || { echo "sdd: cannot create $dir" >&2; exit 1; }
  n=$(( n + 1 ))
done

# 4. Copy each template, substituting ONLY the known values (NNN, slug, date).
#    Content placeholders like {{starting state}} are left intact for the author.
today=$(date +%Y-%m-%d)
for f in spec plan tasks notes; do
  sed -e "s/NNN/$nnn/g" -e "s/{{slug}}/$slug/g" -e "s/{{date}}/$today/g" \
    "$TEMPLATES/$f.md.tmpl" > "$dir/$f.md"
done

# 5. Report the four paths.
echo "Scaffolded $dir:"
for f in spec plan tasks notes; do echo "  $dir/$f.md"; done
echo "Next: fill spec.md (intent first) — do not auto-fill; the human owns intent."

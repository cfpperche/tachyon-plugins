#!/usr/bin/env bash
# sdd-cookbook.sh — opt-in: scaffold cookbook.md for an existing spec from the template.
#
# Does NOT run on `new`. Copies templates/cookbook.md.tmpl → <spec>/cookbook.md when
# missing, and prints a one-line reminder to declare **Cookbook:** yes in tasks.md.
#
# Usage:
#   sdd-cookbook.sh <spec-dir|NNN>
#
# Exit: 0 ok · 1 already exists / write error · 64 usage

set -euo pipefail

SELF="sdd-cookbook"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TEMPLATES="$SCRIPT_DIR/../templates"
TMPL="$TEMPLATES/cookbook.md.tmpl"

usage() { sed -n '2,12p' "$0"; }

[ $# -eq 1 ] || { usage >&2; exit 64; }
[ -f "$TMPL" ] || { printf '%s: template missing: %s\n' "$SELF" "$TMPL" >&2; exit 1; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$ROOT" ]; then
  if [ -d "$PWD/docs/specs" ]; then ROOT="$PWD"; else
    printf '%s: not in a git work tree and no docs/specs under cwd\n' "$SELF" >&2
    exit 64
  fi
fi
ROOT="$(cd "$ROOT" && pwd -P)"
SPECS_ROOT="$(cd "$ROOT/docs/specs" 2>/dev/null && pwd -P || true)"
[ -n "$SPECS_ROOT" ] || { printf '%s: no docs/specs under %s\n' "$SELF" "$ROOT" >&2; exit 64; }

arg="$1"
cand=""
if printf '%s' "$arg" | grep -qE '^[0-9]+$'; then
  n=0
  for m in "$SPECS_ROOT/$arg"-*/; do
    [ -d "$m" ] || continue
    cand="${m%/}"; n=$((n + 1))
  done
  [ "$n" -eq 1 ] || { printf '%s: %s for NNN %s\n' "$SELF" "$([ "$n" -eq 0 ] && printf 'no spec' || printf 'multiple specs')" "$arg" >&2; exit 64; }
elif [ -d "$arg" ]; then cand="$arg"
elif [ -d "$ROOT/$arg" ]; then cand="$ROOT/$arg"
else printf '%s: spec dir not found: %s\n' "$SELF" "$arg" >&2; exit 64; fi

abs="$(cd "$cand" && pwd -P)"
case "$abs/" in "$SPECS_ROOT"/*/) ;; *)
  printf '%s: refusing a target outside docs/specs: %s\n' "$SELF" "$arg" >&2; exit 64 ;;
esac

out="$abs/cookbook.md"
if [ -f "$out" ]; then
  printf '%s: already exists: %s\n' "$SELF" "$out" >&2
  exit 1
fi

slug="$(basename "$abs" | sed -E 's/^[0-9]+-//')"
date_str="$(date +%Y-%m-%d)"
# Portable subst: only {{slug}} and {{date}} are known at scaffold time.
sed -e "s/{{slug}}/$slug/g" -e "s/{{date}}/$date_str/g" "$TMPL" > "$out"

rel="docs/specs/$(basename "$abs")/cookbook.md"
printf '%s: wrote %s\n' "$SELF" "$rel"
printf '%s: declare in tasks.md (or spec.md): **Cookbook:** yes\n' "$SELF"
printf '%s: or opt out with: **Cookbook-Opt-Out:** <reason>\n' "$SELF"

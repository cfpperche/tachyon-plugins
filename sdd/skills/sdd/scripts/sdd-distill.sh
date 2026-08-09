#!/usr/bin/env bash
# sdd-distill.sh — collapse a CLOSED spec to `spec.md` alone.
#
# A spec is four files while it is being built and one file once it has shipped.
# `plan.md` is how it was going to be done, `tasks.md` is a list of boxes that are
# all ticked, and `notes.md` is the conversation that got there. Once the work has
# landed, what a future reader needs is the intent, the acceptance boundary, the
# rejected alternatives and the measurements — and those belong in `spec.md`.
#
# WHY THIS DELETES INSTEAD OF ARCHIVING: git already keeps every byte. Removing
# these from the working tree loses nothing and stops 3 files per shipped spec from
# accumulating in `ls`, in grep, and in every agent's search results. Measured in the
# repository this skill was written for, 2026-08-09: 308 specs, 222 of them shipped,
# 1193 files, 108k lines — more than half the size of the product's own source.
#
# THE PART THAT IS NOT DELETION, and the reason this is `distill` and not `rm`:
# anything durable has to be IN `spec.md` before the other three go. This script
# refuses when it can see that something durable would be lost, and it can only see
# one such thing mechanically — the `**Verify:**` declaration. The rest (rejected
# alternatives, measurements) is the author's judgement, and the preview exists so
# that judgement happens with the files still on disk.
#
# Complements the other three: `spec-verify.sh` re-runs the command, `sdd-dogfood.sh`
# exercises the behavior, `sdd-close.sh` audits the artifacts (and never writes).
# This is the only verb in the skill that removes anything.
#
# Usage:
#   sdd-distill.sh <spec-dir|NNN> [--run] [-h]
#   no --run → PREVIEW: prints what would be removed and exits without touching disk
#
# Exit codes:
#   0  preview shown, or --run and the spec was distilled
#   1  refused: the spec is not distillable (reason printed)
#   64 usage error
#
# Requires bash (not POSIX sh).

set -uo pipefail

SELF="sdd-distill"
SPEC_DIR=""
DO_RUN=0

usage() { sed -n '2,35p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --run) DO_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) printf '%s: unknown flag: %s\n' "$SELF" "$1" >&2; exit 64 ;;
    *) if [ -z "$SPEC_DIR" ]; then SPEC_DIR="$1"; else printf '%s: unexpected arg: %s\n' "$SELF" "$1" >&2; exit 64; fi; shift ;;
  esac
done

[ -n "$SPEC_DIR" ] || { printf '%s: a spec is required (dir or NNN)\n' "$SELF" >&2; usage >&2; exit 64; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
SPECS_ROOT="$ROOT/docs/specs"
[ -d "$SPECS_ROOT" ] || { printf '%s: no docs/specs under %s\n' "$SELF" "$ROOT" >&2; exit 64; }

# Resolve a dir or a bare NNN, and refuse anything outside docs/specs — the same
# containment guard sdd-close.sh applies, and it matters more here because this writes.
resolve_spec() {
  local arg="$1" cand
  if [ -d "$arg" ]; then cand="$arg"
  elif [ -d "$SPECS_ROOT/$arg" ]; then cand="$SPECS_ROOT/$arg"
  elif printf '%s' "$arg" | grep -qE '^[0-9]{3}$'; then
    local matches n
    matches="$(find "$SPECS_ROOT" -maxdepth 1 -type d -name "$arg-*" 2>/dev/null)"
    n="$(printf '%s' "$matches" | grep -c . || true)"
    [ "$n" -eq 1 ] || { printf '%s: %s for NNN '\''%s'\''\n' "$SELF" "$([ "$n" -eq 0 ] && printf 'no spec' || printf 'multiple specs')" "$arg" >&2; exit 64; }
    cand="$matches"
  else printf '%s: spec dir not found: %s\n' "$SELF" "$arg" >&2; exit 64; fi
  local abs; abs="$(cd "$cand" 2>/dev/null && pwd -P)" || { printf '%s: cannot resolve: %s\n' "$SELF" "$arg" >&2; exit 64; }
  case "$abs/" in "$SPECS_ROOT"/*/) ;; *) printf '%s: refusing a target outside docs/specs: %s\n' "$SELF" "$arg" >&2; exit 64 ;; esac
  printf '%s' "$abs"
}

SDIR="$(resolve_spec "$SPEC_DIR")" || exit 64
REL="docs/specs/$(basename "$SDIR")"
SPEC_MD="$SDIR/spec.md"

refuse() { printf '%s: refusing %s — %s\n' "$SELF" "$REL" "$1" >&2; exit 1; }

[ -f "$SPEC_MD" ] || refuse "no spec.md"

grep -qiE '^\*\*Status:\*\*[[:space:]]*shipped(-partial)?\b' "$SPEC_MD" \
  || refuse "status is not shipped; distilling an open spec would delete work in progress"

grep -qE '^\*\*Closure:\*\*' "$SPEC_MD" \
  || refuse "no **Closure:** line — what shipped was never recorded, so there is nothing to distil TO"

# tasks.md is the canonical home of **Verify:**, and spec.md is its documented fallback.
# If the declaration lives only in tasks.md, deleting tasks.md silently disarms
# `sdd verify` for this spec — the command would still be declared nowhere and the
# spec would look like it never had one.
verify_in() { grep -qE '^\*\*(Verify|Dogfood):\*\*' "$1" 2>/dev/null; }
if verify_in "$SDIR/tasks.md" && ! verify_in "$SPEC_MD"; then
  refuse "tasks.md declares **Verify:**/**Dogfood:** and spec.md does not — move the declaration into spec.md first, or verify stops working after this"
fi

DOOMED=""
for f in plan.md tasks.md notes.md; do
  [ -f "$SDIR/$f" ] && DOOMED="$DOOMED $f"
done
[ -n "$DOOMED" ] || { printf '%s: %s is already distilled\n' "$SELF" "$REL"; exit 0; }

if [ "$DO_RUN" -eq 0 ]; then
  printf '%s: PREVIEW — nothing was removed.\n' "$SELF"
  printf '  spec:    %s\n' "$REL"
  printf '  keeping: spec.md\n'
  for f in $DOOMED; do
    printf '  removing: %s (%s lines)\n' "$f" "$(wc -l < "$SDIR/$f" | tr -d ' ')"
  done
  printf '\nRead them once before running. Anything durable — rejected alternatives, measurements —\nbelongs in spec.md and this script cannot tell whether you moved it.\nRe-run with --run to remove.\n'
  exit 0
fi

for f in $DOOMED; do
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 && git -C "$ROOT" ls-files --error-unmatch "$REL/$f" >/dev/null 2>&1; then
    git -C "$ROOT" rm -q "$REL/$f" || exit 1
  else
    rm -f "$SDIR/$f" || exit 1
  fi
  printf '%s: removed %s/%s\n' "$SELF" "$REL" "$f"
done
printf '%s: %s is now spec.md alone; git still has the rest.\n' "$SELF" "$REL"

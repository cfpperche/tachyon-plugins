#!/bin/sh
# verify-gate — run the project's verification before a push reaches a protected branch.
#
# git runs hooks with cwd = repo root and feeds pre-push one line per ref on STDIN:
#   <local ref> <local sha> <remote ref> <remote sha>
# We use that to scope the gate: a push to a feature branch costs nothing, a push to the
# trunk pays for the verification.
#
# Configure (both optional, both read from the environment so nothing here is project-specific):
#   VERIFY_GATE_BRANCHES  space/comma list of protected branch names   (default: "main master")
#   VERIFY_GATE_CMD       the command to run                           (default: resolved from package.json)
#   VERIFY_GATE_SKIP=1    documented, auditable opt-out for one push
#
# Fail-closed: if the gate cannot tell what to run, it refuses the push instead of passing.
set -u

SELF="verify-gate"
ZERO="0000000000000000000000000000000000000000"

say() { printf '%s: %s\n' "$SELF" "$1" >&2; }

# ── 1. Is any ref in this push targeting a protected branch? ────────────────────────────────
BRANCHES=$(printf '%s' "${VERIFY_GATE_BRANCHES:-main master}" | tr ',' ' ')
PROTECTED=""

while read -r _local_ref local_sha remote_ref _remote_sha; do
  [ -n "${remote_ref:-}" ] || continue
  # A deletion (local sha all zeros) lands no code — nothing to verify.
  [ "$local_sha" = "$ZERO" ] && continue
  for b in $BRANCHES; do
    [ "$remote_ref" = "refs/heads/$b" ] && PROTECTED="$b"
  done
done

if [ -z "$PROTECTED" ]; then
  exit 0
fi

if [ "${VERIFY_GATE_SKIP:-}" = "1" ]; then
  say "VERIFY_GATE_SKIP=1 — gate bypassed for a push to '$PROTECTED'. This is recorded in your shell history, not by the gate."
  exit 0
fi

# ── 2. What do we run? ──────────────────────────────────────────────────────────────────────
CMD="${VERIFY_GATE_CMD:-}"

if [ -z "$CMD" ] && [ -f package.json ]; then
  # Prefer an explicit full-verification script, then the conventional test script.
  for candidate in verify:full verify test; do
    if node -e "process.exit(((require('./package.json').scripts)||{})['$candidate']?0:1)" 2>/dev/null; then
      CMD="npm run $candidate"
      [ "$candidate" = "test" ] && CMD="npm test"
      break
    fi
  done
fi

if [ -z "$CMD" ]; then
  say "refusing the push to '$PROTECTED': no verification command could be resolved."
  say "  Set VERIFY_GATE_CMD, or add a 'verify:full', 'verify' or 'test' script to package.json."
  say "  (Installing this plugin IS the opt-in to gating — so an unconfigured gate refuses rather than passes.)"
  exit 1
fi

# ── 3. Run it. ──────────────────────────────────────────────────────────────────────────────
say "push to '$PROTECTED' — running: $CMD"
say "  (set VERIFY_GATE_SKIP=1 to bypass once; VERIFY_GATE_CMD to change what runs)"

# The hook's stdin is the ref list, already consumed. Give the command a clean stdin so an
# interactive-ish tool does not read leftovers or block on a closed pipe.
sh -c "$CMD" < /dev/null
RC=$?

if [ "$RC" -ne 0 ]; then
  say "REFUSED: '$CMD' exited $RC — the push to '$PROTECTED' was not sent."
  exit "$RC"
fi

say "passed — pushing to '$PROTECTED'."
exit 0

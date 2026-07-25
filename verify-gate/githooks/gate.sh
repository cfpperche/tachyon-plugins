#!/bin/sh
# verify-gate — run the project's verification before a push reaches a protected branch.
#
# git runs hooks with cwd = repo root and feeds pre-push one line per ref on STDIN:
#   <local ref> <local sha> <remote ref> <remote sha>
# We use that to scope the gate: a push to a feature branch costs nothing, a push to the
# trunk pays for the verification.
#
# Configure (all optional, all read from the environment so nothing here is project-specific):
#   VERIFY_GATE_BRANCHES       space/comma list of protected branch names  (default: "main master")
#   VERIFY_GATE_CMD            the command to run                         (default: resolved from package.json)
#   VERIFY_GATE_SKIP=1         documented, auditable opt-out for one push
#   VERIFY_GATE_BUSY_EXIT      exit code meaning "unavailable, retry"      (default: 75; empty disables)
#   VERIFY_GATE_BUSY_WAIT_SEC  how long to keep retrying a busy command    (default: 300; 0 = do not wait)
#
# Fail-closed: if the gate cannot tell what to run, it refuses the push instead of passing.
#
# UNAVAILABLE IS NOT FAILURE. A verification command that could not run — because another one holds a
# lock, a runner is saturated — has proven nothing. Reporting that as "REFUSED" reads as a red suite and
# teaches the operator to distrust the gate, which ends with a reflex reach for VERIFY_GATE_SKIP. Both
# outcomes still refuse the push; only a verification that actually RAN and passed lets it through.
#
# 75 is the default because it is EX_TEMPFAIL from sysexits.h — the long-standing convention for "not
# really an error, try again later" — not a convention of any single project. Set the variable empty to
# turn the distinction off for a command that does not use it.
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

BUSY_EXIT="${VERIFY_GATE_BUSY_EXIT-75}"
BUSY_WAIT="${VERIFY_GATE_BUSY_WAIT_SEC:-300}"
POLL=10
WAITED=0

while :; do
  # The hook's stdin is the ref list, already consumed. Give the command a clean stdin so an
  # interactive-ish tool does not read leftovers or block on a closed pipe.
  sh -c "$CMD" < /dev/null
  RC=$?

  # Not the declared "unavailable" code → this is a real verdict, pass or fail.
  [ -n "$BUSY_EXIT" ] && [ "$RC" = "$BUSY_EXIT" ] || break

  if [ "$WAITED" -ge "$BUSY_WAIT" ]; then
    say "NOT VERIFIED: '$CMD' reported unavailable (exit $RC) for ${WAITED}s — it never ran."
    say "  The push to '$PROTECTED' was NOT sent, and nothing was verified. This is not a failing suite."
    say "  Try again when the other run finishes, or raise VERIFY_GATE_BUSY_WAIT_SEC."
    exit "$RC"
  fi

  [ "$WAITED" -eq 0 ] && say "unavailable (exit $RC) — something else is verifying. Waiting up to ${BUSY_WAIT}s…"
  sleep "$POLL"
  WAITED=$((WAITED + POLL))
done

if [ "$RC" -ne 0 ]; then
  say "REFUSED: '$CMD' exited $RC — the push to '$PROTECTED' was not sent."
  exit "$RC"
fi

[ "$WAITED" -gt 0 ] && say "  (waited ${WAITED}s for another verification to finish)"
say "passed — pushing to '$PROTECTED'."
exit 0

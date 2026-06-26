#!/bin/sh
# secrets-guard — LAYER 2: a PreToolUse(Bash) shape-gate.
#
# Layer 1 (the pre-commit git-hook + gitleaks) scans staged changes — but `git commit --no-verify`
# bypasses ANY git hook by design, and a compound `git add … && git commit` / `git commit -a` can slip
# changes past it. This layer runs at the AGENT-RUNTIME level (claude/codex PreToolUse), BEFORE git runs,
# so it stops the agent (or any tool-driven commit) from SILENTLY bypassing the gitleaks gate.
#
# It does NOT scan secrets — it gates the commit *shape* and lets clean commits fall through to the
# git-hook (which does the real scan). A deliberate human-authorized bypass: put an inline
# `# OVERRIDE: <reason ≥10 chars>` line in the command.
#
# Contract: stdin = the PreToolUse JSON ({tool_input:{command}}); exit 2 = block (stderr shown to the
# agent), exit 0 = allow. jq is required; if it is missing the gate FAILS OPEN (exit 0) — the git-hook
# still scans. POSIX sh (no bashisms).
set -u

INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
[ -z "$CMD" ] && exit 0

# Only gate `git commit` invocations (git, git -C <path> commit, && git commit, git commit --amend, …).
# The start-of-word anchor avoids matching `gitcommit` / `git-commit`. A pathological miss is acceptable —
# one unscanned commit is cheaper than blocking valid non-commit git calls.
is_git_commit() {
  printf '%s' "$1" | grep -qE '(^|[^A-Za-z0-9_-])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)?)*[[:space:]]+commit([[:space:]]|$)'
}
is_git_commit "$CMD" || exit 0

# Deliberate bypass: a `# OVERRIDE: <reason ≥10 chars>` line (anchored at start-of-line so a marker inside
# a quoted -m string never matches). Valid override → allow; too-short → block.
ovr="$(printf '%s' "$CMD" | grep -E '^[[:space:]]*# OVERRIDE: ' | head -1 | sed -e 's/^[[:space:]]*# OVERRIDE: //' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' 2>/dev/null || true)"
if [ -n "$ovr" ]; then
  if [ "${#ovr}" -ge 10 ]; then exit 0; fi
  echo "secrets-guard: override reason must be ≥10 characters." >&2
  exit 2
fi

# Detect a bypass shape (first match wins).
shape=""
printf '%s' "$CMD" | grep -qE '&&[[:space:]]*git[[:space:]]+commit' && shape="compound"
if [ -z "$shape" ]; then printf '%s' "$CMD" | grep -qE ';[[:space:]]*git[[:space:]]+commit' && shape="compound"; fi
if [ -z "$shape" ]; then
  after="$(printf '%s' "$CMD" | sed -e 's/.*git[[:space:]]\{1,\}commit//')"
  printf '%s' "$after" | grep -qE '(^|[[:space:]])-[A-Za-z]*a[A-Za-z]*([[:space:]]|$)' && shape="dash-a"
fi
if [ -z "$shape" ]; then printf '%s' "$CMD" | grep -qE '(^|[[:space:]])--no-verify([[:space:]]|$)' && shape="no-verify"; fi

# Clean shape → allow; the git-hook (layer 1) does the actual gitleaks scan.
[ -z "$shape" ] && exit 0

# A bypass shape with no override → block with an actionable message.
case "$shape" in
  compound)
    echo "secrets-guard: a compound 'git add … && git commit' can slip a later --no-verify past the gitleaks gate." >&2
    echo "  Run the add and the commit as two separate steps, or add a '# OVERRIDE: <reason ≥10 chars>' line." >&2
    ;;
  dash-a)
    echo "secrets-guard: 'git commit -a' auto-stages past the gate." >&2
    echo "  Use: git add -u   then   git commit   (separate steps), or add a '# OVERRIDE: <reason ≥10 chars>' line." >&2
    ;;
  no-verify)
    echo "secrets-guard: '--no-verify' skips the gitleaks pre-commit gate." >&2
    echo "  Remove the flag, or add a '# OVERRIDE: <reason ≥10 chars>' line if the bypass is deliberate." >&2
    ;;
esac
exit 2

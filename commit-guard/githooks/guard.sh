#!/bin/sh
# commit-guard — a demonstrable pre-commit gate (Tachyon spec 264 proof).
# Blocks the commit when the STAGED diff contains the marker DONOTCOMMIT.
# Bypass (as documented): git commit --no-verify.
if git diff --cached -U0 | grep -qE 'DONOTCOMMIT'; then
  echo "commit-guard: staged changes contain 'DONOTCOMMIT' — commit blocked." >&2
  echo "  remove the marker, or bypass with: git commit --no-verify" >&2
  exit 1
fi
exit 0

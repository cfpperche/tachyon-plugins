#!/usr/bin/env bash
# spec-verify.sh — run a spec's declared verification command(s). PREVIEW BY DEFAULT.
#
# A spec opts in to mechanical re-verification by declaring one or more
#   **Verify:** `<command>`
# lines in its tasks.md (canonical) or spec.md (fallback). This tool extracts
# those commands.
#
# SECURITY — the command is selected indirectly from a markdown file, so by
# default this tool only PREVIEWS the resolved spec + the extracted command(s)
# and exits WITHOUT running or writing anything. Pass --run to actually execute
# (each command runs from the repo root; results are appended to the spec's
# notes.md under `## Verification log`). Only pass --run after the user has
# authorized the displayed command(s). No interactive prompt — a flag only.
#
# Usage:
#   spec-verify.sh <spec-dir> [--run] [--json] [--quiet] [-h]
#
# Exit codes:
#   0  preview shown (no --run), OR --run and every command passed
#   1  --run and at least one command failed
#   2  no **Verify:** command declared (notes.md is never touched)
#   64 usage error
#
# Requires bash (not POSIX sh). Runs on-demand only (no validator coupling).

set -uo pipefail

SELF="spec-verify"
SPEC_DIR=""
OUT_JSON=0
QUIET=0
RUN=0

usage() { sed -n '2,26p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --run)   RUN=1 ;;
    --json)  OUT_JSON=1 ;;
    --quiet) QUIET=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf '%s: unknown flag: %s\n' "$SELF" "$1" >&2; exit 64 ;;
    *) if [ -z "$SPEC_DIR" ]; then SPEC_DIR="$1"; else printf '%s: unexpected arg: %s\n' "$SELF" "$1" >&2; exit 64; fi ;;
  esac
  shift
done

[ -n "$SPEC_DIR" ] || { printf '%s: a spec directory is required (e.g. docs/specs/NNN-slug)\n' "$SELF" >&2; exit 64; }

# Workspace root: git first; else $PWD only if it holds docs/specs (D1 — never the
# materialized skill path, which is not a repo anchor). PHYSICAL paths (pwd -P) so a
# symlinked spec dir cannot escape containment.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$ROOT" ]; then
  if [ -d "$PWD/docs/specs" ]; then ROOT="$PWD"; else
    printf '%s: not in a git work tree and no docs/specs under the cwd — run from the workspace root\n' "$SELF" >&2
    exit 64
  fi
fi
ROOT="$(cd "$ROOT" && pwd -P)"
SPECS_ROOT="$(cd "$ROOT/docs/specs" 2>/dev/null && pwd -P || true)"
# REQUIRE docs/specs to exist — else the containment glob below would degrade to `/*/` and accept anything (BLOCKER).
[ -n "$SPECS_ROOT" ] || { printf '%s: no docs/specs under the workspace root (%s) — nothing to verify\n' "$SELF" "$ROOT" >&2; exit 64; }

# Resolve <arg> (an NNN alias, or a spec dir relative to cwd/root) to a CONTAINED physical path.
resolve_spec() {
  local arg="$1" cand="" m _n=0
  if printf '%s' "$arg" | grep -qE '^[0-9]+$'; then
    for m in "$SPECS_ROOT/$arg"-*/; do
      [ -d "$m" ] || continue
      cand="${m%/}"; _n=$((_n + 1))
    done
    [ "$_n" -eq 1 ] || { printf '%s: %s for NNN '\''%s'\'' under docs/specs\n' "$SELF" "$([ "$_n" -eq 0 ] && printf 'no spec' || printf 'multiple specs')" "$arg" >&2; exit 64; }
    printf '%s: NNN %s → docs/specs/%s\n' "$SELF" "$arg" "${cand##*/}" >&2
  elif [ -d "$arg" ]; then cand="$arg"
  elif [ -d "$ROOT/$arg" ]; then cand="$ROOT/$arg"
  else printf '%s: spec dir not found: %s\n' "$SELF" "$arg" >&2; exit 64; fi
  local abs; abs="$(cd "$cand" 2>/dev/null && pwd -P)" || { printf '%s: cannot resolve: %s\n' "$SELF" "$arg" >&2; exit 64; }
  # Contained: physically under <root>/docs/specs/* (a trailing `/` in the pattern blocks the
  # `docs/specs-evil` prefix collision; pwd -P above blocks a symlink escape; SPECS_ROOT itself
  # does not match `<SPECS_ROOT>/*/`).
  case "$abs/" in "$SPECS_ROOT"/*/) ;; *) printf '%s: refusing a target outside docs/specs: %s\n' "$SELF" "$arg" >&2; exit 64 ;; esac
  printf '%s' "$abs"
}
ABS_SPEC="$(resolve_spec "$SPEC_DIR")" || exit 64

SPEC_NAME="${ABS_SPEC##*/}"
REL_SPEC="docs/specs/$SPEC_NAME"
TASKS_MD="$ABS_SPEC/tasks.md"
SPEC_MD="$ABS_SPEC/spec.md"
NOTES_MD="$ABS_SPEC/notes.md"

# Extract `**Verify:** `<cmd>`` commands. tasks.md is canonical; fall back to
# spec.md. Only the FIRST backtick-fenced span on each matching line is taken.
extract_cmds() {
  local f="$1"
  [ -f "$f" ] || return 0
  grep -nE '^\*\*Verify:\*\*[[:space:]]*`' "$f" 2>/dev/null \
    | sed -E 's/^[0-9]+:\*\*Verify:\*\*[[:space:]]*`([^`]*)`.*/\1/'
}

json_escape() {
  local s="$1"
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  s=${s//$'\b'/\\b}; s=${s//$'\f'/\\f}
  s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

CMDS="$(extract_cmds "$TASKS_MD")"
SRC="tasks.md"
if [ -z "$CMDS" ]; then
  CMDS="$(extract_cmds "$SPEC_MD")"
  SRC="spec.md"
fi

# No declaration → exit 2, do not touch notes.md.
if [ -z "$CMDS" ]; then
  if [ "$OUT_JSON" -eq 1 ]; then
    printf '{"status":"no-verify-declared","spec":"%s","commands":[],"passed":0,"failed":0,"declared":false,"ran":false}\n' \
      "$(json_escape "$SPEC_NAME")"
  elif [ "$QUIET" -eq 0 ]; then
    printf '%s: no verify command declared in %s — nothing to run (declare a **Verify:** `<cmd>` line)\n' "$SELF" "$REL_SPEC"
  fi
  exit 2
fi

# --- PREVIEW (default — no --run): show commands, run nothing, write nothing ---
if [ "$RUN" -eq 0 ]; then
  if [ "$OUT_JSON" -eq 1 ]; then
    _items=""
    old_ifs="$IFS"; IFS='
'
    for cmd in $CMDS; do
      [ -n "$cmd" ] || continue
      _items="${_items}${_items:+,}\"$(json_escape "$cmd")\""
    done
    IFS="$old_ifs"
    printf '{"status":"preview","spec":"%s","source":"%s","commands":[%s],"declared":true,"ran":false}\n' \
      "$(json_escape "$SPEC_NAME")" "$SRC" "$_items"
  elif [ "$QUIET" -eq 0 ]; then
    _n="$(printf '%s' "$CMDS" | grep -c .)"
    printf '%s: preview — %s declares %s command(s) (source: %s). NOTHING was run.\n' "$SELF" "$REL_SPEC" "$_n" "$SRC"
    _i=0; old_ifs="$IFS"; IFS='
'
    for cmd in $CMDS; do [ -n "$cmd" ] || continue; _i=$((_i+1)); printf '  %d. %s\n' "$_i" "$cmd"; done
    IFS="$old_ifs"
    printf 'Pass --run to execute (only after the user authorized these command(s)).\n'
  fi
  exit 0
fi

# --- RUN (--run): execute each command from the repo root; log to notes.md -----
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PASSED=0
FAILED=0
RESULT_LINES=""
JSON_ITEMS=""

old_ifs="$IFS"; IFS='
'
for cmd in $CMDS; do
  [ -n "$cmd" ] || continue
  # Always announce the command BEFORE it runs (the human must see what executes), even in --json mode.
  [ "$QUIET" -eq 0 ] && printf '%s: running: %s\n' "$SELF" "$cmd" >&2
  if ( cd "$ROOT" && bash -c "$cmd" >/dev/null 2>&1 ); then
    res="pass"; PASSED=$((PASSED + 1))
  else
    res="fail"; FAILED=$((FAILED + 1))
  fi
  RESULT_LINES="${RESULT_LINES}- \`${cmd}\` — ${res}
"
  JSON_ITEMS="${JSON_ITEMS}${JSON_ITEMS:+,}{\"command\":\"$(json_escape "$cmd")\",\"result\":\"$res\"}"
  [ "$QUIET" -eq 0 ] && [ "$OUT_JSON" -eq 0 ] && printf '  [%s] %s\n' "$res" "$cmd"
done
IFS="$old_ifs"

OVERALL="pass"; [ "$FAILED" -gt 0 ] && OVERALL="fail"
TOTAL=$((PASSED + FAILED))

# Append a result block to notes.md under `## Verification log`.
[ -f "$NOTES_MD" ] || printf '# %s — notes\n' "$SPEC_NAME" > "$NOTES_MD"
grep -qE '^## Verification log' "$NOTES_MD" || printf '\n## Verification log\n' >> "$NOTES_MD"
{
  printf '\n### %s — %s (%d/%d) — source: %s\n' "$TS" "$OVERALL" "$PASSED" "$TOTAL" "$SRC"
  printf '%s' "$RESULT_LINES"
} >> "$NOTES_MD"

if [ "$OUT_JSON" -eq 1 ]; then
  printf '{"status":"%s","spec":"%s","source":"%s","commands":[%s],"passed":%d,"failed":%d,"declared":true,"ran":true}\n' \
    "$OVERALL" "$(json_escape "$SPEC_NAME")" "$SRC" "$JSON_ITEMS" "$PASSED" "$FAILED"
elif [ "$QUIET" -eq 0 ]; then
  printf '%s: %s — %d/%d passed (source: %s, logged to %s/notes.md)\n' \
    "$SELF" "$OVERALL" "$PASSED" "$TOTAL" "$SRC" "$REL_SPEC"
fi

[ "$FAILED" -eq 0 ] && exit 0
exit 1

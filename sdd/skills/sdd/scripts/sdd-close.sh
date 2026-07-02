#!/usr/bin/env bash
# sdd-close.sh — static closure-consistency auditor for shipped specs (READ-ONLY).
#
# For each shipped (or shipped-partial) spec, report where the spec's own
# artifacts disagree with its declared status:
#   tasks-unchecked      — tasks.md still has `- [ ]` boxes
#   acceptance-unchecked — spec.md `## Acceptance criteria` still has `- [ ]` boxes
#   placeholders         — surviving `{{...}}` template placeholders in spec/tasks
#   missing-closure      — no uncommented `**Closure:**` line
#   dogfood-missing      — no `**Dogfood:**` declaration and no valid opt-out
#   dogfood-unrun        — `**Dogfood:**` declared but no passing Dogfood log
#   dogfood-opt-out-empty — `**Dogfood-Opt-Out:**` exists but has no reason
#   visual-qa-missing    — warning-only: likely UI/interface spec without visual proof or opt-out
#
# Writes nothing, ever. Complements `spec-verify.sh` and `sdd-dogfood.sh`:
# verify proves the spec's COMMAND still passes; dogfood proves the shipped
# behavior was exercised; close proves the spec's ARTIFACTS agree with its status.
#
# Usage:
#   sdd-close.sh [<spec-dir>] [--json] [-h]
#   no <spec-dir> → audit every docs/specs/* ; one <spec-dir> → just that spec
#
# Exit codes:
#   0  no findings (clean)
#   1  at least one finding across the targeted specs
#   64 usage error
#
# Requires bash (not POSIX sh). Runs on-demand only (no validator coupling).

set -uo pipefail

SELF="sdd-close"
SPEC_DIR=""
OUT_JSON=0

usage() { sed -n '2,24p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --json) OUT_JSON=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf '%s: unknown flag: %s\n' "$SELF" "$1" >&2; exit 64 ;;
    *) if [ -z "$SPEC_DIR" ]; then SPEC_DIR="$1"; else printf '%s: unexpected arg: %s\n' "$SELF" "$1" >&2; exit 64; fi ;;
  esac
  shift
done

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

json_escape() {
  local s="$1"
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

# Resolve <arg> (an NNN alias, or a spec dir) to a CONTAINED physical path.
resolve_spec() {
  local arg="$1" cand="" m _n=0
  if printf '%s' "$arg" | grep -qE '^[0-9]+$'; then
    for m in "$SPECS_ROOT/$arg"-*/; do
      [ -d "$m" ] || continue
      cand="${m%/}"; _n=$((_n + 1))
    done
    [ "$_n" -eq 1 ] || { printf '%s: %s for NNN '\''%s'\'' under docs/specs\n' "$SELF" "$([ "$_n" -eq 0 ] && printf 'no spec' || printf 'multiple specs')" "$arg" >&2; exit 64; }
  elif [ -d "$arg" ]; then cand="$arg"
  elif [ -d "$ROOT/$arg" ]; then cand="$ROOT/$arg"
  else printf '%s: spec dir not found: %s\n' "$SELF" "$arg" >&2; exit 64; fi
  local abs; abs="$(cd "$cand" 2>/dev/null && pwd -P)" || { printf '%s: cannot resolve: %s\n' "$SELF" "$arg" >&2; exit 64; }
  case "$abs/" in "$SPECS_ROOT"/*/) ;; *) printf '%s: refusing a target outside docs/specs: %s\n' "$SELF" "$arg" >&2; exit 64 ;; esac
  printf '%s' "$abs"
}

# Build the target list of spec dirs.
TARGETS=""
if [ -n "$SPEC_DIR" ]; then
  [ -n "$SPECS_ROOT" ] || { printf '%s: no docs/specs under the workspace root (%s)\n' "$SELF" "$ROOT" >&2; exit 64; }
  TARGETS="$(resolve_spec "$SPEC_DIR")" || exit 64
else
  [ -n "$SPECS_ROOT" ] || { [ "$OUT_JSON" -eq 1 ] && printf '{"specs":[],"total_findings":0,"specs_with_findings":0}\n'; exit 0; }
  for _d in "$SPECS_ROOT"/*/; do
    [ -d "$_d" ] || continue
    TARGETS="$TARGETS${TARGETS:+
}${_d%/}"
  done
fi

# --- finding helpers (read-only) -------------------------------------------

is_shipped() { grep -qiE '^\*\*Status:\*\*[[:space:]]*shipped(-partial)?\b' "$1" 2>/dev/null; }

count_unchecked() {
  [ -f "$1" ] || { printf '0'; return; }
  _n="$(grep -cE '^[[:space:]]*-[[:space:]]\[ \]' "$1" 2>/dev/null)"
  printf '%s' "${_n:-0}"
}

count_acceptance_unchecked() {
  [ -f "$1" ] || { printf '0'; return; }
  awk '
    /^##[[:space:]]+Acceptance criteria/ { insec=1; next }
    /^##[[:space:]]/ { if (insec) insec=0 }
    insec && /^[[:space:]]*-[[:space:]]\[ \]/ { n++ }
    END { printf "%d", n+0 }
  ' "$1"
}

# Strip inline `code` spans first so a spec that merely *discusses* `{{SLUG}}`
# in backticks is not a false positive — only a bare unfilled placeholder counts.
has_placeholders() {
  [ -f "$1" ] || return 1
  sed 's/`[^`]*`//g' "$1" 2>/dev/null | grep -qE '\{\{'
}

has_closure() { grep -qE '^\*\*Closure:\*\*' "$1" 2>/dev/null; }

has_dogfood_declared() {
  grep -qE '^\*\*Dogfood:\*\*[[:space:]]*`[^`]+`' "$TASKS_MD" "$SPEC_MD" 2>/dev/null
}

dogfood_opt_out_line() {
  grep -hE '^\*\*Dogfood-Opt-Out:\*\*' "$TASKS_MD" "$SPEC_MD" 2>/dev/null | head -n1
}

dogfood_opt_out_reason() {
  dogfood_opt_out_line | sed -E 's/^\*\*Dogfood-Opt-Out:\*\*[[:space:]]*//; s/[[:space:]]+$//'
}

has_passing_dogfood_log() {
  local notes="$1"
  [ -f "$notes" ] || return 1
  awk '
    /^##[[:space:]]+Dogfood log/ { inlog=1; next }
    /^##[[:space:]]/ { if (inlog) inlog=0 }
    inlog && /^###[[:space:]].*[[:space:]]—[[:space:]]pass([[:space:]]|\()/ { found=1 }
    inlog && /^[[:space:]]*-[[:space:]].*[[:space:]]—[[:space:]]pass[[:space:]]*$/ { found=1 }
    END { exit found ? 0 : 1 }
  ' "$notes"
}

looks_visual() {
  # Intentionally conservative: inspect spec.md only, not plan/tasks templates, so optional Visual QA
  # boilerplate does not make every shipped spec warn.
  [ -f "$SPEC_MD" ] || return 1
  sed 's/`[^`]*`//g' "$SPEC_MD" 2>/dev/null |
    grep -qiE '\b(UI|UX|visual|layout|menu|dropdown|button|icon|webview|sidebar|studio|activity panel|screen|screenshot|hover|focus|click|visible text|render|rendering|toolbar|modal|quickpick)\b'
}

visual_qa_opt_out_line() {
  grep -hE '^\*\*Visual QA Opt-Out:\*\*' "$TASKS_MD" "$SPEC_MD" "$NOTES_MD" 2>/dev/null | head -n1
}

visual_qa_opt_out_reason() {
  visual_qa_opt_out_line | sed -E 's/^\*\*Visual QA Opt-Out:\*\*[[:space:]]*//; s/[[:space:]]+$//'
}

has_visual_qa_evidence() {
  # Evidence is prose-based. A bare "## Visual QA" template heading is not enough.
  grep -hiqE '^(Evidence|Verdict):[[:space:]]*[^[:space:]]|^[[:space:]]*-[[:space:]]\[x\].*(Visual QA|visual proof|screenshot|preview|verdict|evidence)' "$TASKS_MD" "$SPEC_MD" "$NOTES_MD" 2>/dev/null
}

# --- scan -------------------------------------------------------------------

TOTAL_FINDINGS=0
SPECS_WITH_FINDINGS=0
TOTAL_WARNINGS=0
SPECS_WITH_WARNINGS=0
JSON_SPECS=""
JSON_WARNING_SPECS=""
HUMAN=""
WARNINGS_HUMAN=""

OLDIFS="$IFS"; IFS='
'
for SDIR in $TARGETS; do
  IFS="$OLDIFS"
  SPEC_MD="$SDIR/spec.md"
  TASKS_MD="$SDIR/tasks.md"
  NOTES_MD="$SDIR/notes.md"
  [ -f "$SPEC_MD" ] || { IFS='
'; continue; }
  if ! is_shipped "$SPEC_MD"; then IFS='
'; continue; fi

  REL="docs/specs/$(basename "$SDIR")"
  status_line="$(grep -iE '^\*\*Status:\*\*' "$SPEC_MD" | head -n1 | sed -E 's/^\*\*Status:\*\*[[:space:]]*//; s/[[:space:]].*$//')"

  findings=""
  json_findings=""
  warnings=""
  json_warnings=""

  t_un="$(count_unchecked "$TASKS_MD")"
  if [ "${t_un:-0}" -gt 0 ]; then
    findings="${findings}tasks-unchecked ($t_un)
"
    json_findings="${json_findings}${json_findings:+,}{\"type\":\"tasks-unchecked\",\"count\":$t_un}"
  fi

  a_un="$(count_acceptance_unchecked "$SPEC_MD")"
  if [ "${a_un:-0}" -gt 0 ]; then
    findings="${findings}acceptance-unchecked ($a_un)
"
    json_findings="${json_findings}${json_findings:+,}{\"type\":\"acceptance-unchecked\",\"count\":$a_un}"
  fi

  if has_placeholders "$SPEC_MD" || has_placeholders "$TASKS_MD"; then
    findings="${findings}placeholders
"
    json_findings="${json_findings}${json_findings:+,}{\"type\":\"placeholders\"}"
  fi

  if ! has_closure "$SPEC_MD"; then
    findings="${findings}missing-closure
"
    json_findings="${json_findings}${json_findings:+,}{\"type\":\"missing-closure\"}"
  fi

  opt_out_line="$(dogfood_opt_out_line)"
  opt_out_reason=""
  if [ -n "$opt_out_line" ]; then
    opt_out_reason="$(dogfood_opt_out_reason)"
    if [ -z "$opt_out_reason" ]; then
      findings="${findings}dogfood-opt-out-empty
"
      json_findings="${json_findings}${json_findings:+,}{\"type\":\"dogfood-opt-out-empty\"}"
    else
      warnings="${warnings}dogfood-opt-out: $opt_out_reason
"
      json_warnings="${json_warnings}${json_warnings:+,}{\"type\":\"dogfood-opt-out\",\"reason\":\"$(json_escape "$opt_out_reason")\"}"
    fi
  elif ! has_dogfood_declared; then
    findings="${findings}dogfood-missing
"
    json_findings="${json_findings}${json_findings:+,}{\"type\":\"dogfood-missing\"}"
  elif ! has_passing_dogfood_log "$NOTES_MD"; then
    findings="${findings}dogfood-unrun
"
    json_findings="${json_findings}${json_findings:+,}{\"type\":\"dogfood-unrun\"}"
  fi

  visual_opt_out_line="$(visual_qa_opt_out_line)"
  visual_opt_out_reason=""
  if looks_visual; then
    if [ -n "$visual_opt_out_line" ]; then
      visual_opt_out_reason="$(visual_qa_opt_out_reason)"
      if [ -z "$visual_opt_out_reason" ]; then
        warnings="${warnings}visual-qa-opt-out-empty
"
        json_warnings="${json_warnings}${json_warnings:+,}{\"type\":\"visual-qa-opt-out-empty\"}"
      else
        warnings="${warnings}visual-qa-opt-out: $visual_opt_out_reason
"
        json_warnings="${json_warnings}${json_warnings:+,}{\"type\":\"visual-qa-opt-out\",\"reason\":\"$(json_escape "$visual_opt_out_reason")\"}"
      fi
    elif ! has_visual_qa_evidence; then
      warnings="${warnings}visual-qa-missing
"
      json_warnings="${json_warnings}${json_warnings:+,}{\"type\":\"visual-qa-missing\"}"
    fi
  fi

  if [ -n "$findings" ]; then
    nf="$(printf '%s' "$findings" | grep -c .)"
    TOTAL_FINDINGS=$((TOTAL_FINDINGS + nf))
    SPECS_WITH_FINDINGS=$((SPECS_WITH_FINDINGS + 1))
    HUMAN="${HUMAN}  [${status_line}] $REL
$(printf '%s' "$findings" | sed 's/^/    - /')
"
    JSON_SPECS="${JSON_SPECS}${JSON_SPECS:+,}{\"spec\":\"$(json_escape "$REL")\",\"status\":\"$(json_escape "$status_line")\",\"findings\":[$json_findings],\"warnings\":[$json_warnings]}"
  fi

  if [ -n "$warnings" ]; then
    nw="$(printf '%s' "$warnings" | grep -c .)"
    TOTAL_WARNINGS=$((TOTAL_WARNINGS + nw))
    SPECS_WITH_WARNINGS=$((SPECS_WITH_WARNINGS + 1))
    WARNINGS_HUMAN="${WARNINGS_HUMAN}  [${status_line}] $REL
$(printf '%s' "$warnings" | sed 's/^/    - /')
"
    if [ -z "$findings" ]; then
      JSON_WARNING_SPECS="${JSON_WARNING_SPECS}${JSON_WARNING_SPECS:+,}{\"spec\":\"$(json_escape "$REL")\",\"status\":\"$(json_escape "$status_line")\",\"findings\":[],\"warnings\":[$json_warnings]}"
    fi
  fi
  IFS='
'
done
IFS="$OLDIFS"

# --- output -----------------------------------------------------------------

if [ "$OUT_JSON" -eq 1 ]; then
  _all_specs="$JSON_SPECS"
  [ -n "$JSON_WARNING_SPECS" ] && _all_specs="${_all_specs}${_all_specs:+,}$JSON_WARNING_SPECS"
  printf '{"specs":[%s],"total_findings":%d,"specs_with_findings":%d,"total_warnings":%d,"specs_with_warnings":%d}\n' \
    "$_all_specs" "$TOTAL_FINDINGS" "$SPECS_WITH_FINDINGS" "$TOTAL_WARNINGS" "$SPECS_WITH_WARNINGS"
else
  if [ "$SPECS_WITH_FINDINGS" -eq 0 ]; then
    printf '%s: clean — no closure inconsistencies in the targeted shipped spec(s)\n' "$SELF"
  else
    printf '%s: %d finding(s) across %d shipped spec(s):\n' "$SELF" "$TOTAL_FINDINGS" "$SPECS_WITH_FINDINGS"
    printf '%s' "$HUMAN"
  fi
  if [ "$SPECS_WITH_WARNINGS" -gt 0 ]; then
    printf '%s: %d warning(s) across %d shipped spec(s):\n' "$SELF" "$TOTAL_WARNINGS" "$SPECS_WITH_WARNINGS"
    printf '%s' "$WARNINGS_HUMAN"
  fi
fi

[ "$TOTAL_FINDINGS" -eq 0 ] || exit 1
exit 0

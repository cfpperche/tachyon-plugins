#!/usr/bin/env bash
# Focused regression for sdd-close visual-QA warnings.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tmp="$(mktemp -d /tmp/sdd-visual-close-XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p \
  "$tmp/docs/specs/001-ui-spec-a" \
  "$tmp/docs/specs/002-ui-proof-spec-b" \
  "$tmp/docs/specs/003-ui-optout-spec-c" \
  "$tmp/docs/specs/004-non-ui-spec-d" \
  "$tmp/docs/specs/005-real-finding-spec-e"
git -C "$tmp" init >/dev/null

cat > "$tmp/docs/specs/001-ui-spec-a/spec.md" <<'EOF'
# 001 — spec-a
**Status:** shipped
**Closure:** shipped
## Intent
Adds a button menu to the Activity UI.
## Acceptance criteria
- [x] ok
EOF
cat > "$tmp/docs/specs/001-ui-spec-a/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
EOF

cat > "$tmp/docs/specs/002-ui-proof-spec-b/spec.md" <<'EOF'
# 002 — spec-b
**Status:** shipped
**Closure:** shipped
## Intent
Changes a webview layout.
## Acceptance criteria
- [x] ok
EOF
cat > "$tmp/docs/specs/002-ui-proof-spec-b/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
## Visual QA
Evidence: screenshot reviewed.
Verdict: pass.
EOF

cat > "$tmp/docs/specs/003-ui-optout-spec-c/spec.md" <<'EOF'
# 003 — spec-c
**Status:** shipped
**Closure:** shipped
## Intent
Changes visible text in a generated CLI help snapshot.
## Acceptance criteria
- [x] ok
EOF
cat > "$tmp/docs/specs/003-ui-optout-spec-c/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
**Visual QA Opt-Out:** Text-only snapshot, covered by verify.
EOF

cat > "$tmp/docs/specs/004-non-ui-spec-d/spec.md" <<'EOF'
# 004 — spec-d
**Status:** shipped
**Closure:** shipped
## Intent
Refactors a parser.
## Acceptance criteria
- [x] ok
EOF
cat > "$tmp/docs/specs/004-non-ui-spec-d/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
EOF

cat > "$tmp/docs/specs/005-real-finding-spec-e/spec.md" <<'EOF'
# 005 — spec-e
**Status:** shipped
## Intent
Refactors another parser.
## Acceptance criteria
- [ ] missing
EOF
cat > "$tmp/docs/specs/005-real-finding-spec-e/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
EOF

for dir in "$tmp"/docs/specs/*; do
  touch "$dir/notes.md"
done

out="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/001-ui-spec-a)"
printf '%s\n' "$out"
printf '%s' "$out" | grep -q 'visual-qa-missing'
json="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/001-ui-spec-a --json)"
node -e 'const j=JSON.parse(process.argv[1]); if (j.total_findings !== 0 || j.total_warnings !== 2) process.exit(1); const s=j.specs[0]; if (!s || !s.warnings.some(w=>w.type==="visual-qa-missing")) process.exit(1);' "$json"

for spec in 002-ui-proof-spec-b 003-ui-optout-spec-c 004-non-ui-spec-d; do
  out="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" "docs/specs/$spec")"
  printf '%s\n' "$out"
  ! printf '%s' "$out" | grep -q 'visual-qa-missing'
done

if (cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/005-real-finding-spec-e >/tmp/sdd-visual-close-findings.txt 2>&1); then
  cat /tmp/sdd-visual-close-findings.txt
  printf 'expected real closure finding to fail\n' >&2
  exit 1
fi
grep -q 'acceptance-unchecked' /tmp/sdd-visual-close-findings.txt

#!/usr/bin/env bash
# Focused regression for opt-in, spec-owned artifact guidance and close warnings.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tmp="$(mktemp -d /tmp/sdd-artifact-close-XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p \
  "$tmp/docs/specs/001-local/evidence" \
  "$tmp/docs/specs/002-external" \
  "$tmp/docs/specs/003-missing" \
  "$tmp/docs/specs/004-external-optout" \
  "$tmp/docs/specs/005-non-file-evidence" \
  "$tmp/docs/specs/006-empty-optout" \
  "$tmp/docs/prototypes" \
  "$tmp/docs/published"
git -C "$tmp" init >/dev/null

make_spec() {
  local dir="$1"
  cat > "$dir/spec.md" <<'EOF'
# fixture
**Status:** shipped
**Closure:** shipped
## Intent
Exercises artifact ownership.
## Acceptance criteria
- [x] ok
EOF
  : > "$dir/plan.md"
  : > "$dir/notes.md"
}

for dir in "$tmp"/docs/specs/*; do make_spec "$dir"; done

printf 'proof\n' > "$tmp/docs/specs/001-local/evidence/result.png"
cat > "$tmp/docs/specs/001-local/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
Evidence: `docs/specs/001-local/evidence/result.png`
EOF

printf 'prototype\n' > "$tmp/docs/prototypes/demo.html"
cat > "$tmp/docs/specs/002-external/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
Prototype: `docs/prototypes/demo.html`
EOF

cat > "$tmp/docs/specs/003-missing/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
Evidence: `evidence/missing.png`
EOF

printf 'canonical\n' > "$tmp/docs/published/canonical.svg"
cat > "$tmp/docs/specs/004-external-optout/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
**Artifact-Location-Opt-Out:** canonical product documentation owns this asset
Evidence: `docs/published/canonical.svg`
EOF

cat > "$tmp/docs/specs/005-non-file-evidence/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
Evidence: https://example.test/review, preview route `sidebar/default`, manual pass.
EOF

cat > "$tmp/docs/specs/006-empty-optout/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
**Artifact-Location-Opt-Out:**
Prototype: `docs/prototypes/demo.html`
EOF

json="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/001-local --json)"
node -e 'const j=JSON.parse(process.argv[1]); const ws=j.specs.flatMap(s=>s.warnings); if (ws.some(w=>w.type.startsWith("artifact-"))) process.exit(1);' "$json"

json="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/002-external --json)"
node -e 'const j=JSON.parse(process.argv[1]); const ws=j.specs[0].warnings; if (!ws.some(w=>w.type==="artifact-outside-spec") || ws.some(w=>w.type==="artifact-missing")) process.exit(1);' "$json"
out="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/002-external)"
printf '%s' "$out" | grep -q 'artifact-outside-spec: docs/prototypes/demo.html'

json="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/003-missing --json)"
node -e 'const j=JSON.parse(process.argv[1]); const ws=j.specs[0].warnings; if (!ws.some(w=>w.type==="artifact-missing") || ws.some(w=>w.type==="artifact-outside-spec")) process.exit(1);' "$json"
out="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/003-missing)"
printf '%s' "$out" | grep -q 'artifact-missing: evidence/missing.png'

json="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/004-external-optout --json)"
node -e 'const j=JSON.parse(process.argv[1]); const ws=j.specs[0].warnings; if (!ws.some(w=>w.type==="artifact-location-opt-out") || ws.some(w=>w.type==="artifact-outside-spec")) process.exit(1);' "$json"

json="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/005-non-file-evidence --json)"
node -e 'const j=JSON.parse(process.argv[1]); const ws=j.specs.flatMap(s=>s.warnings); if (ws.some(w=>w.type.startsWith("artifact-"))) process.exit(1);' "$json"

json="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/006-empty-optout --json)"
node -e 'const j=JSON.parse(process.argv[1]); const ws=j.specs[0].warnings; if (!ws.some(w=>w.type==="artifact-location-opt-out-empty") || !ws.some(w=>w.type==="artifact-outside-spec")) process.exit(1);' "$json"

# `new` still scaffolds exactly four files and only reminds about optional artifacts.
new_output="$(cd "$tmp" && sh "$SCRIPT_DIR/new.sh" scaffold-contract)"
new_dir="$(printf '%s\n' "$new_output" | sed -n 's/^Scaffolded \(docs\/specs\/[^:]*\):$/\1/p')"
test -n "$new_dir"
test "$(find "$tmp/$new_dir" -type f | wc -l | tr -d ' ')" -eq 4
test "$(find "$tmp/$new_dir" -mindepth 1 -type d | wc -l | tr -d ' ')" -eq 0
printf '%s\n' "$new_output" | grep -q 'Optional artifacts: create them only when useful, inside'

printf 'test-artifact-locality-close: ok\n'

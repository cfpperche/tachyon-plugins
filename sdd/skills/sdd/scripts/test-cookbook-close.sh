#!/usr/bin/env bash
# Focused regression for sdd-close cookbook warnings + sdd-cookbook scaffold.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tmp="$(mktemp -d /tmp/sdd-cookbook-close-XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p \
  "$tmp/docs/specs/001-surface-no-book" \
  "$tmp/docs/specs/002-surface-with-book" \
  "$tmp/docs/specs/003-surface-optout" \
  "$tmp/docs/specs/004-internal-refactor" \
  "$tmp/docs/specs/005-explicit-flag-missing" \
  "$tmp/docs/specs/006-empty-optout"
git -C "$tmp" init >/dev/null

# 001: operator surface, no cookbook → warning cookbook-missing (+ dogfood opt-out warning)
cat > "$tmp/docs/specs/001-surface-no-book/spec.md" <<'EOF'
# 001 — surface-no-book
**Status:** shipped
**Closure:** shipped
## Intent
Adds a Bridge tool create_worktree for the managed worktree registry.
## Acceptance criteria
- [x] ok
EOF
cat > "$tmp/docs/specs/001-surface-no-book/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
EOF

# 002: same surface + cookbook.md present → no cookbook-missing
cat > "$tmp/docs/specs/002-surface-with-book/spec.md" <<'EOF'
# 002 — surface-with-book
**Status:** shipped
**Closure:** shipped
## Intent
Adds a Bridge tool list_worktrees for operators.
## Acceptance criteria
- [x] ok
EOF
cat > "$tmp/docs/specs/002-surface-with-book/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
**Cookbook:** yes
EOF
cat > "$tmp/docs/specs/002-surface-with-book/cookbook.md" <<'EOF'
# Cookbook
Happy path here.
EOF

# 003: surface + opt-out with reason → cookbook-opt-out warning only (not missing)
cat > "$tmp/docs/specs/003-surface-optout/spec.md" <<'EOF'
# 003 — surface-optout
**Status:** shipped
**Closure:** shipped
## Intent
Exposes create_worktree but documents via external guide.
## Acceptance criteria
- [x] ok
EOF
cat > "$tmp/docs/specs/003-surface-optout/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
**Cookbook-Opt-Out:** covered by product-foundation handbook
EOF

# 004: internal refactor, no surface language → no cookbook warning
cat > "$tmp/docs/specs/004-internal-refactor/spec.md" <<'EOF'
# 004 — internal-refactor
**Status:** shipped
**Closure:** shipped
## Intent
Refactors a pure parser helper.
## Acceptance criteria
- [x] ok
EOF
cat > "$tmp/docs/specs/004-internal-refactor/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
EOF

# 005: explicit **Cookbook:** without file → missing even without surface words
cat > "$tmp/docs/specs/005-explicit-flag-missing/spec.md" <<'EOF'
# 005 — explicit-flag
**Status:** shipped
**Closure:** shipped
## Intent
Internal change that still wants a cookbook.
## Acceptance criteria
- [x] ok
EOF
cat > "$tmp/docs/specs/005-explicit-flag-missing/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
**Cookbook:** yes
EOF

# 006: empty Cookbook-Opt-Out
cat > "$tmp/docs/specs/006-empty-optout/spec.md" <<'EOF'
# 006 — empty-optout
**Status:** shipped
**Closure:** shipped
## Intent
Adds a Bridge tool remove_worktree.
## Acceptance criteria
- [x] ok
EOF
cat > "$tmp/docs/specs/006-empty-optout/tasks.md" <<'EOF'
**Dogfood-Opt-Out:** fixture
**Cookbook-Opt-Out:**
EOF

for dir in "$tmp"/docs/specs/*; do
  touch "$dir/notes.md"
done

# --- close warnings ---
out="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/001-surface-no-book)"
printf '%s\n' "$out"
printf '%s' "$out" | grep -q 'cookbook-missing'
json="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/001-surface-no-book --json)"
node -e 'const j=JSON.parse(process.argv[1]); if (j.total_findings !== 0) process.exit(1); const s=j.specs[0]; if (!s || !s.warnings.some(w=>w.type==="cookbook-missing")) process.exit(1);' "$json"

for spec in 002-surface-with-book 004-internal-refactor; do
  out="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" "docs/specs/$spec")"
  printf '%s\n' "$out"
  ! printf '%s' "$out" | grep -q 'cookbook-missing'
done

out="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/003-surface-optout)"
printf '%s\n' "$out"
printf '%s' "$out" | grep -q 'cookbook-opt-out'
! printf '%s' "$out" | grep -q 'cookbook-missing'

out="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/005-explicit-flag-missing)"
printf '%s\n' "$out"
printf '%s' "$out" | grep -q 'cookbook-missing'

out="$(cd "$tmp" && bash "$SCRIPT_DIR/sdd-close.sh" docs/specs/006-empty-optout)"
printf '%s\n' "$out"
printf '%s' "$out" | grep -q 'cookbook-opt-out-empty'

# --- scaffold helper (must run with docs/specs workspace root) ---
(cd "$tmp" && bash "$SCRIPT_DIR/sdd-cookbook.sh" 004)
test -f "$tmp/docs/specs/004-internal-refactor/cookbook.md"
if (cd "$tmp" && bash "$SCRIPT_DIR/sdd-cookbook.sh" 004 2>/dev/null); then
  printf 'expected second scaffold to fail\n' >&2
  exit 1
fi

printf 'test-cookbook-close: ok\n'

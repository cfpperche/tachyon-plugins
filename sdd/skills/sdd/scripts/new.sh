#!/bin/sh
# sdd — scaffold a new spec: docs/specs/NNN-<slug>/{spec,plan,tasks,notes}.md
#
# Portable POSIX sh — runs identically under any runtime that has a shell
# (claude, codex). Resolves its own bundled templates relative to this script,
# so it works regardless of where the skill was materialized
# (.claude/skills/sdd or .agents/skills/sdd). Run from the WORKSPACE ROOT.
#
# Usage: new.sh <slug>
set -eu

# Resolve this script's dir → the templates live one level up, in ../templates.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMPLATES="$SCRIPT_DIR/../templates"
[ -d "$TEMPLATES" ] || { echo "sdd: templates not found at $TEMPLATES" >&2; exit 1; }

# 1. Sanitize the slug: lowercase, spaces/underscores → hyphens, drop anything
#    that is not [a-z0-9-], collapse repeats, trim leading/trailing hyphens.
raw=${1:-}
[ -n "$raw" ] || { echo "usage: new.sh <slug>" >&2; exit 2; }
slug=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' \
  | sed 's/[^a-z0-9-]//g; s/-\{2,\}/-/g; s/^-//; s/-$//')
[ -n "$slug" ] || { echo "sdd: slug is empty after sanitizing '$raw'" >&2; exit 2; }

ids_in_specs_dir() {
  _root=$1
  [ -d "$_root/docs/specs" ] || return 0
  ls -1 "$_root/docs/specs" 2>/dev/null | sed -n 's/^\([0-9][0-9][0-9]\)-.*/\1/p'
}

max_id_from_stdin() {
  sort -n | tail -1 | sed 's/^0*\([0-9]\)/\1/'
}

git_root=
git_common_dir=
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  git_common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git rev-parse --git-common-dir 2>/dev/null || true)
  case "$git_common_dir" in
    /*) ;;
    ?*) git_common_dir="$PWD/$git_common_dir" ;;
  esac
fi

# 2. Next NNN: strictly NNN-* dirs only (ignore non-numeric/malformed), default 001.
mkdir -p docs/specs

lock_dir=
ledger=
cleanup_lock() {
  if [ -n "$lock_dir" ] && [ -d "$lock_dir" ]; then
    rm -f "$lock_dir/created_at" "$lock_dir/meta" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}
trap cleanup_lock EXIT
trap 'cleanup_lock; exit 130' INT
trap 'cleanup_lock; exit 143' TERM

take_common_lock() {
  [ -n "$git_common_dir" ] || return 1
  state_dir="$git_common_dir/tachyon-sdd"
  mkdir -p "$state_dir" || return 1
  lock_dir="$state_dir/spec-alloc.lock.d"
  ledger="$state_dir/spec-allocations.tsv"
  wait_seconds=${SDD_LOCK_WAIT_SECONDS:-30}
  stale_seconds=${SDD_LOCK_STALE_SECONDS:-900}
  start=$(date +%s)
  while ! mkdir "$lock_dir" 2>/dev/null; do
    now=$(date +%s)
    stamp=
    [ -f "$lock_dir/created_at" ] && stamp=$(sed -n '1p' "$lock_dir/created_at" 2>/dev/null || true)
    case "$stamp" in ''|*[!0-9]*) stamp=0 ;; esac
    if [ "$stamp" -gt 0 ] && [ $(( now - stamp )) -ge "$stale_seconds" ]; then
      rm -rf "$lock_dir"
      continue
    fi
    [ $(( now - start )) -lt "$wait_seconds" ] || {
      echo "sdd: timed out waiting for spec allocation lock at $lock_dir" >&2
      exit 1
    }
    sleep 1
  done
  {
    date +%s
  } > "$lock_dir/created_at"
  {
    echo "pid=$$"
    echo "cwd=$PWD"
    echo "slug=$slug"
  } > "$lock_dir/meta"
  [ -f "$ledger" ] || : > "$ledger"
  return 0
}

allocated_with_common_lock=0
if take_common_lock; then
  allocated_with_common_lock=1
fi

next_start() {
  {
    ids_in_specs_dir "."
    if [ "$allocated_with_common_lock" -eq 1 ]; then
      awk -F '\t' 'NF >= 1 && $1 ~ /^[0-9][0-9][0-9]$/ { print $1 }' "$ledger" 2>/dev/null || true
      if [ -n "$git_root" ]; then
        git -C "$git_root" worktree list --porcelain 2>/dev/null | while IFS= read -r line; do
          case "$line" in
            worktree\ *) ids_in_specs_dir "${line#worktree }" ;;
          esac
        done
      fi
    fi
  } | max_id_from_stdin
}

max=$(next_start)
max=${max:-0}
n=$(( max + 1 ))

# 3. Allocate the dir ATOMICALLY (mkdir fails if it exists) so two agents racing
#    the same number don't collide. With a Git common dir, reserve the chosen NNN
#    in a local ledger so sibling worktrees do not reuse an in-flight number.
while :; do
  nnn=$(printf '%03d' "$n")
  dir="docs/specs/$nnn-$slug"
  if [ "$allocated_with_common_lock" -eq 1 ]; then
    if awk -F '\t' -v id="$nnn" 'NF >= 1 && $1 == id { found = 1 } END { exit found ? 0 : 1 }' "$ledger" 2>/dev/null; then
      n=$(( n + 1 ))
      continue
    fi
  fi
  if mkdir "$dir" 2>/dev/null; then
    if [ "$allocated_with_common_lock" -eq 1 ]; then
      branch=$(git -C "${git_root:-.}" symbolic-ref --quiet --short HEAD 2>/dev/null || git -C "${git_root:-.}" rev-parse --short HEAD 2>/dev/null || echo unknown)
      printf '%s\t%s\t%s\t%s\t%s\n' "$nnn" "$slug" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$branch" "$PWD" >> "$ledger"
    fi
    break
  fi
  [ -d "$dir" ] || { echo "sdd: cannot create $dir" >&2; exit 1; }
  n=$(( n + 1 ))
done

# 4. Copy each template, substituting ONLY the known values (NNN, slug, date).
#    Content placeholders like {{starting state}} are left intact for the author.
today=$(date +%Y-%m-%d)
for f in spec plan tasks notes; do
  sed -e "s/NNN/$nnn/g" -e "s/{{slug}}/$slug/g" -e "s/{{date}}/$today/g" \
    "$TEMPLATES/$f.md.tmpl" > "$dir/$f.md"
done

# 5. Report the four paths.
echo "Scaffolded $dir:"
for f in spec plan tasks notes; do echo "  $dir/$f.md"; done
echo "Next: fill spec.md (intent first) — do not auto-fill; the human owns intent."

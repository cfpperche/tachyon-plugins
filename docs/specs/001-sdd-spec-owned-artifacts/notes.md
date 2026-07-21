# 001 — sdd-spec-owned-artifacts — notes

_Created 2026-07-21._

_In-flight design memory — decisions, deviations, tradeoffs, and open questions surfaced **while building** that weren't pre-empted by `spec.md` or `plan.md`. Append-only by convention._

## Design decisions

_Choices made where the spec/plan was ambiguous. The decision + why this option over the others considered in the moment._

## Deviations

_Where implementation intentionally departed from `plan.md`, and why it was necessary or better._

- The generic Codex `quick_validate.py` rejects the pre-existing `compatibility` frontmatter key, while this Tachyon plugin intentionally targets both Claude and Codex. The implementation keeps that runtime metadata and uses shell syntax, focused regressions, JSON manifest, and diff validation instead of deleting a valid project-level contract to satisfy a narrower validator.

## Tradeoffs

_Alternatives weighed mid-build. The chosen path + what was given up + why it was worth it._

## Open questions

_Questions surfaced during the build with no answer yet. Owner or path to resolution if known._

## Verification log

### 2026-07-21T14:55:57Z — pass (1/1) — source: tasks.md
- `bash sdd/skills/sdd/scripts/test-artifact-locality-close.sh && bash sdd/skills/sdd/scripts/test-visual-close.sh && bash sdd/skills/sdd/scripts/test-cookbook-close.sh` — pass

## Dogfood log

### 2026-07-21T14:55:59Z — pass (1/1) — source: tasks.md — commit: 9f7b76e2a49e87e91fdc296d1f6cc255b1b7cd6f
- `tmp=$(mktemp -d /tmp/sdd-artifact-dogfood-XXXXXX) && trap 'rm -rf "$tmp"' EXIT && git -C "$tmp" init -q && cd "$tmp" && sh /home/goat/tachyon-plugins/sdd/skills/sdd/scripts/new.sh artifact-dogfood && test "$(find docs/specs -type f | wc -l)" -eq 4` — pass

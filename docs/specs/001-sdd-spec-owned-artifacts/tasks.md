# 001 — sdd-spec-owned-artifacts — tasks

_Generated from `plan.md` on 2026-07-21. Work top-to-bottom. Check boxes as tasks complete. If a task reveals the plan is wrong, update `plan.md` before continuing._

## Implementation

- [x] Add the opt-in spec-owned artifact contract to skill and README.
- [x] Update plan/tasks templates and `new.sh` output without scaffolding auxiliary files.
- [x] Add artifact declaration parsing, locality/existence warnings, opt-out handling, and JSON output to `sdd-close.sh`.
- [x] Add the focused artifact-locality regression script.
- [x] Bump plugin metadata and repository summary to 1.6.0 behavior.

## Verification

_Acceptance checks tied to `spec.md`. Each should map to a checklist item there._

- [x] `new.sh` still creates exactly four core files and prints the locality reminder.
- [x] Spec-local, external, missing, opt-out, URL/preview/manual cases pass the focused matrix.
- [x] Existing visual and cookbook close regressions remain green.
- [x] Every bundled shell script passes `bash -n`; plugin metadata parses and declares version 1.6.0 for both runtimes.
- [x] Source plugin recommends no global `docs/prototypes/` staging area; remaining occurrences are the explicit anti-example and regression fixtures.

**Headless check:** `bash sdd/skills/sdd/scripts/test-artifact-locality-close.sh && bash sdd/skills/sdd/scripts/test-visual-close.sh && bash sdd/skills/sdd/scripts/test-cookbook-close.sh`
**Verify:** `bash sdd/skills/sdd/scripts/test-artifact-locality-close.sh && bash sdd/skills/sdd/scripts/test-visual-close.sh && bash sdd/skills/sdd/scripts/test-cookbook-close.sh`
<!-- A mechanical command an agent can run to validate this spec's implementation
     without a human (tests / build / lint). Kept green = the spec stays delivered.
     To make `/sdd verify` re-run it, also declare it on a **Verify:** line, e.g.:
       **Verify:** `npm test`
     `/sdd verify` reads the FIRST backtick span per **Verify:** line, previews by
     default, and runs only with --run. Multiple **Verify:** lines run in order. -->

## Dogfood

**Dogfood:** `tmp=$(mktemp -d /tmp/sdd-artifact-dogfood-XXXXXX) && trap 'rm -rf "$tmp"' EXIT && git -C "$tmp" init -q && cd "$tmp" && sh /home/goat/tachyon-plugins/sdd/skills/sdd/scripts/new.sh artifact-dogfood && test "$(find docs/specs -type f | wc -l)" -eq 4`
<!-- A representative command that exercises the shipped behavior end-to-end.
     `/sdd dogfood` previews by default and runs only with --run, then logs under
     notes.md `## Dogfood log`. If no meaningful headless dogfood exists, replace
     the Dogfood line with: **Dogfood-Opt-Out:** <non-empty reason>. -->

**Human dogfood:** optional — after publishing and reinstalling, start a new agent thread, scaffold a disposable spec, and confirm the locality rule appears without any prototype being created.
<!-- Opt-in: a short walkthrough a human follows to approve the spec (demo steps,
     UI routes, things to eyeball). Name the steps here when human sign-off matters. -->

## Visual QA

**Visual QA Opt-Out:** terminal/text-only plugin contract; exact output is covered by shell tests.

## Cookbook

_Optional operator/agent how-to. Not scaffolded by `new`. When this ship adds a Bridge tool, CLI, registry lifecycle, or other usable surface, add `cookbook.md` (via `sdd-cookbook.sh <001>`) and declare **Cookbook:** yes — or **Cookbook-Opt-Out:** &lt;reason&gt;. `close` warns (does not hard-fail) if a likely operator surface ships without either._

**Cookbook-Opt-Out:** existing SDD commands remain unchanged; this adds policy and closure warnings, not a new operator workflow.

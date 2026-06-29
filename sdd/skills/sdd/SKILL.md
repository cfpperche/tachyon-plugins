---
name: sdd
description: Spec-driven development scaffolding. Use when starting non-trivial work (3+ files, a new module, an API/schema change, or a vague request that needs decomposition). Scaffolds and progresses docs/specs/NNN-<slug>/{spec,plan,tasks,notes}.md — intent before code, then re-verifies and audits closure at the end. Subcommands - new <slug>, plan, tasks, list, verify <spec> (re-run a spec's declared check; preview by default), close (audit shipped specs for closure debt). Skip for one-file fixes, typos, or mechanical edits where the diff IS the spec.
compatibility: Runtime-neutral. Works on any agent runtime that can read a bundled skill directory and run shell commands (claude, codex). Resolves its templates relative to this SKILL.md — no host-specific path assumptions.
license: MIT
---

# Spec-driven development

Non-trivial work is spec-first: capture **intent** before writing code, in a small set of living documents under `docs/specs/NNN-<slug>/`. The spec is the contract; the code is the implementation of a contract that already exists.

## When to use / when to skip

**Use** when the work is 3+ files, a new module, an API/schema change, or a vague request that needs decomposition.

**Skip** for a one-file fix, a typo, a rename, or a mechanical edit where the diff itself is self-evidently the whole change. Spec-driving a trivial change is overhead; match the rigor to the work.

## The four artifacts

Every spec is a directory `docs/specs/NNN-<slug>/` holding:

| File | Purpose | When it's written |
|------|---------|-------------------|
| `spec.md` | **Intent** — the problem, acceptance criteria (Given/When/Then), non-goals. The contract. | up front, by a human (or drafted from a conversation, then ratified) |
| `plan.md` | **Approach** — how the spec will be built; key decisions, files touched, risks. | after the spec is agreed |
| `tasks.md` | **Steps** — small ordered checkboxes derived from the plan. | after the plan |
| `notes.md` | **In-flight memory** — decisions, deviations, tradeoffs, open questions surfaced *during* the build. | populated while implementing (empty at scaffold time) |

## Subcommands

### `new <slug>`

Scaffold a fresh spec. **From the workspace root**, run the bundled script (it lives in this skill's `scripts/` directory):

```
sh scripts/new.sh <slug>
```

The script is the executable contract — it sanitizes the slug, picks the next free `NNN` (strictly `NNN-*` dirs, default `001`), allocates the directory **atomically** (two agents racing the same number won't collide), copies the four templates, and substitutes the known values (`NNN`, slug, date) while leaving content placeholders intact. It prints the four paths. Doing it by hand instead of via the script is error-prone (literal `NNN`/`{{slug}}` leak into the spec) — prefer the script.

After scaffolding: **do NOT auto-fill `spec.md`** — intent is the human's. Offer to draft it from a conversational description, but only after they describe the change. `notes.md` stays empty at scaffold time — its job is in-flight design memory during implementation.

### `plan`

Given an agreed `spec.md`, draft `plan.md`: the approach, the key decisions (and rejected alternatives, with reasons), the files touched, the risks. Read the repo first — configs, existing specs, the modules you'll change — and ground the plan in what's actually there. Cite the sources you consulted.

### `tasks`

Given an agreed `plan.md`, decompose it into `tasks.md`: small, ordered, unambiguous checkbox steps. Each task should be independently checkable. If a task reveals the plan is wrong, fix `plan.md` before continuing.

### `list`

List the specs under `docs/specs/` with their status (read the `**Status:**` line of each `spec.md`).

### `verify <spec>`

Re-run a spec's declared verification command(s) to prove its mechanical claim still holds. A spec opts in by declaring one or more `**Verify:** ` `` `<cmd>` `` lines in its `tasks.md` (canonical; `spec.md` is the fallback). The bundled script lives in **this skill's `scripts/` directory** and requires `bash`; invoke it by that path (resolve this skill's dir — `.claude/skills/sdd/` on Claude, `.agents/skills/sdd/` on Codex — and run from anywhere inside the workspace; it finds the repo root via git). The spec target may be the dir (`docs/specs/NNN-<slug>`) or just the `NNN`:

```
bash "<this-skill-dir>"/scripts/spec-verify.sh docs/specs/NNN-<slug>
```

**Preview by default — this runs NOTHING.** It prints the resolved spec + the extracted command(s) and exits. To actually execute, add `--run`:

```
bash "<this-skill-dir>"/scripts/spec-verify.sh docs/specs/NNN-<slug> --run
```

**Pass `--run` ONLY after the user has authorized the displayed command(s)** — or the current prompt clearly asks to run that spec's verification. The command is selected from a markdown file, so a `--run` supplied unprompted could execute something unintended: preview it, show the command, get the go-ahead, then `--run`. With `--run`, each command runs from the repo root and a timestamped pass/fail block is appended to the spec's `notes.md` under `## Verification log`. Exit: `0` (preview shown, or `--run` and all passed) · `1` (`--run` and a command failed) · `2` (no `**Verify:**` declared — `notes.md` untouched). Targets outside `docs/specs/` are refused.

### `close [<spec>]`

Audit a shipped spec's artifacts against its declared status — a **read-only** closure-hygiene check (writes nothing). Invoke the bundled script by its path in this skill's `scripts/` dir (requires `bash`; run from anywhere inside the workspace — it finds the repo root via git):

```
bash "<this-skill-dir>"/scripts/sdd-close.sh                        # sweep every shipped spec
bash "<this-skill-dir>"/scripts/sdd-close.sh docs/specs/NNN-<slug>  # just one (or just NNN)
```

For each spec whose `**Status:**` is `shipped` (or `shipped-partial`) it reports: `tasks-unchecked` (`- [ ]` left in `tasks.md`), `acceptance-unchecked` (`- [ ]` left in `spec.md` § Acceptance criteria), `placeholders` (surviving `{{...}}` in `spec.md`/`tasks.md`), `missing-closure` (no `**Closure:**` line in `spec.md`). Non-shipped specs are skipped. Exit `0` clean · `1` findings. `--json` emits a machine-readable report. A clean close = the boxes are checked, the placeholders are gone, and a `**Closure:**` line records what shipped.

## Verification & closure contract

These two subcommands read three opt-in markdown conventions on a spec — nothing else gates:

- **`**Verify:** ` `` `<cmd>` ``** in `tasks.md` (or `spec.md`) — declares the command(s) `verify` re-runs.
- **`**Status:** shipped` (or `shipped-partial`)** — makes a spec eligible for the `close` audit.
- **`**Closure:**`** in `spec.md` — the line that records what shipped; its absence is `close`'s `missing-closure` finding.

## Acceptance criteria shape

Write acceptance as **observable outcomes**, not implementation steps:

- **Behavior** → a `Scenario:` with Given / When / Then sub-bullets.
- **Static facts** → plain checkbox bullets.

If every box can be ticked, the spec is delivered. Each criterion should be verifiable without re-reading the plan.

```
- [ ] **Scenario: <name>**
  - **Given** <starting state>
  - **When** <action>
  - **Then** <observable outcome>
- [ ] <a static fact that is either true or false>
```

## Working discipline

- **Read before asking.** If the repo could answer a question (configs, existing specs, schemas, modules, recent `git log`), read it first. Asking is the fallback, not the default — and when you do ask, name the file you read so the grounding is visible.
- **Ask in plain prose.** When you need the human to decide between genuine forks, ask directly in the conversation. (Do not assume a structured-question UI exists — degrade to prose.)
- **One spec, one concern.** If a spec is sprawling, it's probably two specs.
- **Status is a bare enum** on the `**Status:**` line: `draft | in-progress | shipped | superseded | abandoned | deferred`.

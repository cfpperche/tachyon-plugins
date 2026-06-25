---
name: sdd
description: Spec-driven development scaffolding. Use when starting non-trivial work (3+ files, a new module, an API/schema change, or a vague request that needs decomposition). Scaffolds and progresses docs/specs/NNN-<slug>/{spec,plan,tasks,notes}.md — intent before code. Subcommands - new <slug>, plan, tasks, list. Skip for one-file fixes, typos, or mechanical edits where the diff IS the spec.
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

Scaffold a fresh spec.

1. Pick the next free `NNN` — list `docs/specs/` and take `max(NNN) + 1`, zero-padded to 3 digits.
2. Create `docs/specs/NNN-<slug>/`.
3. Copy the four templates bundled with this skill — they live in the **`templates/` directory alongside this `SKILL.md`** — into the new spec dir, renaming off the `.tmpl` suffix:
   - `spec.md.tmpl` → `spec.md`
   - `plan.md.tmpl` → `plan.md`
   - `tasks.md.tmpl` → `tasks.md`
   - `notes.md.tmpl` → `notes.md`
4. **Report the four paths.** Do NOT auto-fill `spec.md` — intent is the human's. Offer to draft it from a conversational description, but only after they describe the change. If the idea is still vague, suggest interviewing it out first (see `plan`/refine flow below).

`notes.md` stays empty at scaffold time — its job is in-flight design memory during implementation.

### `plan`

Given an agreed `spec.md`, draft `plan.md`: the approach, the key decisions (and rejected alternatives, with reasons), the files touched, the risks. Read the repo first — configs, existing specs, the modules you'll change — and ground the plan in what's actually there. Cite the sources you consulted.

### `tasks`

Given an agreed `plan.md`, decompose it into `tasks.md`: small, ordered, unambiguous checkbox steps. Each task should be independently checkable. If a task reveals the plan is wrong, fix `plan.md` before continuing.

### `list`

List the specs under `docs/specs/` with their status (read the `**Status:**` line of each `spec.md`).

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

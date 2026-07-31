---
name: sdd
description: "Spec-driven development scaffolding for work whose decisions need an explicit contract: meaningful ambiguity, new modules or interfaces, migrations or lifecycle changes, cross-cutting behavior, real alternatives, costly reversal, or coordination. Scaffolds and progresses repository-local spec, plan, task, and notes documents; then re-verifies, dogfoods, and audits closure plus optional artifact locality. Provides new, plan, tasks, list, verify, dogfood, cookbook, and close workflows. Skip bounded, reversible changes even when they touch several files."
license: MIT
---

# Spec-driven development

Decision-heavy work is spec-first: capture **intent** before writing code, in a small set of living documents under `docs/specs/NNN-<slug>/`. The spec is the contract; the code is the implementation of a contract that already exists.

## When to use / when to skip

Choose by the decisions the change requires, not by file count, diff size, or whether UI and tests happen to live in separate files.

**Use** when at least one of these is material:

- the desired behavior or acceptance boundary is meaningfully ambiguous;
- the change introduces or reshapes a module, API, schema, protocol, or other durable contract;
- migration, persistence, compatibility, rollout, recovery, or lifecycle behavior must be designed;
- behavior changes across multiple subsystems or ownership boundaries;
- there are real alternatives whose tradeoffs should be recorded before implementation;
- reversal would be expensive, risky, or destructive;
- multiple people or agents need a shared contract to coordinate independent work.

**Skip** when the outcome is bounded, understood, and cheaply reversible. A component change may legitimately include
its implementation, CSS, tests, localization, and documentation without needing a spec. The same applies to focused
fixes, renames, and mechanical edits whose behavior and boundary are already clear.

If signals conflict, ask one question: **would writing the intent and rejected alternatives prevent a plausible wrong
implementation or coordination failure?** If yes, use a spec. If it would only restate an already-obvious diff, skip it.

This skill is repository-local and orchestration-neutral. It uses only the repository and conversation context supplied
to it, and manages only its local spec artifacts. It does not discover or mutate external task boards, agent state,
handoff systems, or runtime-specific work queues.

It is runtime-neutral: any agent runtime that can read the bundled skill directory and run shell commands can use it.
Scripts and templates resolve relative to this `SKILL.md`; there are no host-specific path assumptions.

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

The script is the executable contract — it sanitizes the slug, picks the next free `NNN` (strictly `NNN-*` dirs, default `001`), allocates the directory **atomically** (two agents racing the same number won't collide), copies the four templates, and substitutes the known values (`NNN`, slug, date) while leaving content placeholders intact. In a Git repository, it also coordinates sibling worktrees from the same clone through a portable `mkdir` lock + local ledger under Git's common dir, so two local worktrees do not reuse an in-flight number. Doing it by hand instead of via the script is error-prone (literal `NNN`/`{{slug}}` leak into the spec) — prefer the script.

This is a local same-clone guarantee, not global distributed coordination. Separate clones, separate machines, or a branch merge can still introduce duplicate `NNN` prefixes. For that boundary, run the bundled duplicate checker:

```
sh scripts/check-ids.sh
```

It exits nonzero and lists the colliding `docs/specs/NNN-*` directories when duplicates exist.

After scaffolding: **do NOT auto-fill `spec.md`** — intent is the human's. Offer to draft it from a conversational description, but only after they describe the change. `notes.md` stays empty at scaffold time — its job is in-flight design memory during implementation. The scaffold always contains only the four core Markdown files. Prototypes, screenshots, diagrams, and other supporting files are opt-in; create them only when they materially help the spec.

### `plan`

Given an agreed `spec.md`, draft `plan.md`: the approach, the key decisions (and rejected alternatives, with reasons), the files touched, the risks. Read the repo first — configs, existing specs, the modules you'll change — and ground the plan in what's actually there. Cite the sources you consulted.

### `tasks`

Given an agreed `plan.md`, decompose it into `tasks.md`: small, ordered, unambiguous checkbox steps. Each task should be independently checkable. If a task reveals the plan is wrong, fix `plan.md` before continuing.

### `list`

List the specs under `docs/specs/` with their status (read the `**Status:**` line of each `spec.md`).

### `verify <spec>`

Re-run a spec's declared verification command(s) to prove its mechanical claim still holds. A spec opts in by declaring one or more `**Verify:** ` `` `<cmd>` `` lines in its `tasks.md` (canonical; `spec.md` is the fallback). The bundled script lives in **this skill's `scripts/` directory** and requires `bash`; invoke it by that path. `<this-skill-dir>` is the directory this SKILL.md was loaded from — your runtime tells you where it materialized it (Claude prints it as *Base directory for this skill*). Run from anywhere inside the workspace; the script finds the repo root via git. Do **not** hardcode `.claude/skills/…` or `.agents/skills/…`: an agent working in its own git worktree has neither, and the skill tree is delivered into the agent's private runtime home. The spec target may be the dir (`docs/specs/NNN-<slug>`) or just the `NNN`:

```
bash "<this-skill-dir>"/scripts/spec-verify.sh docs/specs/NNN-<slug>
```

**Preview by default — this runs NOTHING.** It prints the resolved spec + the extracted command(s) and exits. To actually execute, add `--run`:

```
bash "<this-skill-dir>"/scripts/spec-verify.sh docs/specs/NNN-<slug> --run
```

**Pass `--run` ONLY after the user has authorized the displayed command(s)** — or the current prompt clearly asks to run that spec's verification. The command is selected from a markdown file, so a `--run` supplied unprompted could execute something unintended: preview it, show the command, get the go-ahead, then `--run`. With `--run`, each command runs from the repo root and a timestamped pass/fail block is appended to the spec's `notes.md` under `## Verification log`. Exit: `0` (preview shown, or `--run` and all passed) · `1` (`--run` and a command failed) · `2` (no `**Verify:**` declared — `notes.md` untouched). Targets outside `docs/specs/` are refused.

### `dogfood <spec>`

Run a spec's declared headless dogfood command(s). A spec opts in by declaring one or more `**Dogfood:** ` `` `<cmd>` `` lines in its `tasks.md` (canonical; `spec.md` is the fallback). The bundled script lives in **this skill's `scripts/` directory** and requires `bash`; invoke it by that path:

```
bash "<this-skill-dir>"/scripts/sdd-dogfood.sh docs/specs/NNN-<slug>
bash "<this-skill-dir>"/scripts/sdd-dogfood.sh docs/specs/NNN-<slug> --run
```

**Preview by default — this runs NOTHING and writes NOTHING.** With `--run`, each command runs from the repo root and a timestamped pass/fail block is appended to `notes.md` under `## Dogfood log`. Exit: `0` (preview shown, or `--run` and all passed) · `1` (`--run` and a command failed) · `2` (no `**Dogfood:**` declared — `notes.md` untouched). Targets outside `docs/specs/` are refused.

Use `Dogfood` for a representative end-to-end exercise of the delivered behavior, not as a duplicate of `Verify`. If a shipped spec cannot have meaningful headless dogfood, declare `**Dogfood-Opt-Out:** <reason>` with a non-empty reason. Human dogfood remains opt-in and informational; use `**Human dogfood:**` for routes, UI checks, or manual approval steps.

## Visual QA for interface work

When a spec changes something a human sees, inspect the real surface before delivery. This includes browser pages, VS Code webviews, sidebars, Activity items, menus, buttons, terminal snapshots, screenshots, generated docs, and any rendered preview.

Keep this prose-based, not a fixed enum. In `plan.md`, describe the affected surface and the visual risk in plain language when it matters. In `tasks.md` or `notes.md`, record concrete proof after inspection:

- `Evidence:` with a screenshot path, preview route, browser/VS Code view, or manual visual pass.
- `Verdict:` with the short result, including any fixes made after looking.

If visual QA is intentionally not useful, write `**Visual QA Opt-Out:** <reason>`. A shipped visual-looking spec without evidence or opt-out gets a `visual-qa-missing` warning from `close`, but warnings do not block closure. The goal is to catch avoidable layout/placement mistakes without turning SDD into a rigid UI taxonomy.

## Supporting artifacts (opt-in, spec-owned)

Not every spec needs a prototype or a durable evidence file. Do not create either as ceremony. When one is useful specifically for a spec, its default owner is the same spec directory:

```text
docs/specs/NNN-<slug>/
  prototypes/   # optional HTML, SVG, or other exploratory prototype
  evidence/     # optional screenshots, diagrams, logs, or review output
```

These directory names are conventions, not required scaffolding. A file directly under the spec directory is also valid. Reference durable local files in backticks on a `Prototype:` or `Evidence:` line so `close` can audit them, for example:

```markdown
Prototype: `docs/specs/NNN-<slug>/prototypes/flow.html`
Evidence: `docs/specs/NNN-<slug>/evidence/sidebar.png`
```

Preview routes, URLs, and prose-only manual checks remain valid evidence and are not treated as local artifact declarations. If a declared artifact has a deliberate owner outside the spec — for example a canonical product asset — record `**Artifact-Location-Opt-Out:** <non-empty reason>` in `spec.md`, `plan.md`, `tasks.md`, or `notes.md`. `close` reports missing declared files and undeclared external placement as warning-only hygiene signals; it does not require an artifact to exist.

## Cookbook (opt-in operator how-to)

When a ship introduces a **usable surface** — tools, CLI, registry lifecycle, or product API another operator will invoke — capture a short **how-to** so the next operator does not reverse-engineer the code.

| File | Role |
|------|------|
| `cookbook.md` | Happy path, tools/payloads, fail-closed rules, cleanup. **Not** the contract. |
| `spec.md` | Intent + acceptance (Given/When/Then). |
| `notes.md` | In-flight design memory. |

**Not scaffolded by `new`.** Opt in at ship time:

```
bash "<this-skill-dir>"/scripts/sdd-cookbook.sh docs/specs/NNN-<slug>
# or: bash .../sdd-cookbook.sh NNN
```

Then declare in `tasks.md` (or `spec.md`):

- **`**Cookbook:** yes`** — this ship has (or will have) `cookbook.md`
- **`**Cookbook-Opt-Out:** <reason>`** — no operator surface / covered elsewhere (reason required)

`close` emits **warning-only** `cookbook-missing` when a shipped spec looks like an operator surface (or declares `**Cookbook:**`) but has neither `cookbook.md` nor a valid opt-out. Empty opt-out → `cookbook-opt-out-empty`. Warnings never flip exit code by themselves.

Keep cookbooks short (one page): when to use / when not / happy path / tools table / fail-closed / cleanup / link to `spec.md`.

### `close [<spec>]`

Audit a shipped spec's artifacts against its declared status — a **read-only** closure-hygiene check (writes nothing). Invoke the bundled script by its path in this skill's `scripts/` dir (requires `bash`; run from anywhere inside the workspace — it finds the repo root via git):

```
bash "<this-skill-dir>"/scripts/sdd-close.sh                        # sweep every shipped spec
bash "<this-skill-dir>"/scripts/sdd-close.sh docs/specs/NNN-<slug>  # just one (or just NNN)
```

For each spec whose `**Status:**` is `shipped` (or `shipped-partial`) it reports: `tasks-unchecked` (`- [ ]` left in `tasks.md`), `acceptance-unchecked` (`- [ ]` left in `spec.md` § Acceptance criteria), `placeholders` (surviving `{{...}}` in `spec.md`/`tasks.md`), `missing-closure` (no `**Closure:**` line in `spec.md`), `dogfood-missing` (no headless dogfood declaration and no valid opt-out), `dogfood-unrun` (dogfood declared but no passing `## Dogfood log` entry), and `dogfood-opt-out-empty` (opt-out without a reason). It also emits warning-only hygiene signals: `visual-qa-missing` for likely UI without proof/opt-out, `cookbook-missing` for likely operator surfaces (or explicit `**Cookbook:**`) without `cookbook.md`/opt-out, `artifact-missing` for a declared local file absent from disk, and `artifact-outside-spec` when a declared spec-specific file lives outside its owning spec without a location opt-out. A valid `**Dogfood-Opt-Out:**` / cookbook / visual / artifact-location opt-out does not fail close, but is printed as a warning and emitted in JSON. Non-shipped specs are skipped. Exit `0` clean or warnings-only · `1` findings. `--json` emits a machine-readable report. A clean close = the boxes are checked, the placeholders are gone, a `**Closure:**` line records what shipped, and dogfood proof or a justified opt-out exists.

## Verification & closure contract

These subcommands read markdown conventions on a spec — nothing else gates:

- **`**Verify:** ` `` `<cmd>` ``** in `tasks.md` (or `spec.md`) — declares the command(s) `verify` re-runs.
- **`**Dogfood:** ` `` `<cmd>` ``** in `tasks.md` (or `spec.md`) — declares the command(s) `dogfood` previews/runs and logs under `## Dogfood log`.
- **`**Dogfood-Opt-Out:** <reason>`** in `tasks.md` (or `spec.md`) — explicitly exempts a shipped spec from headless dogfood; the reason must be non-empty and `close` surfaces it as a warning.
- **`**Human dogfood:**`** in `tasks.md` — optional manual route/checklist for maintainer approval; `close` does not fail if it is absent or incomplete.
- **`Evidence:` / `Verdict:` under `## Visual QA`** — optional visual proof for UI/interface work; concrete proof suppresses the `visual-qa-missing` warning.
- **`**Visual QA Opt-Out:** <reason>`** — explicitly explains why visual QA is not useful for a visual-looking spec; warning-only.
- **`Prototype:` / `Evidence:` with a backticked local artifact path** — optional declaration of a durable supporting file; spec-owned paths are the default and `close` warns when the file is missing.
- **`**Artifact-Location-Opt-Out:** <reason>`** — non-empty reason for a declared artifact deliberately owned outside the spec; warning-only.
- **`cookbook.md`** — optional operator how-to; scaffold with `sdd-cookbook.sh` (not `new`).
- **`**Cookbook:** yes`** — declares cookbook intent; `close` warns if the file is still missing.
- **`**Cookbook-Opt-Out:** <reason>`** — non-empty reason when no cookbook is warranted; warning-only.
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
- **Status is a bare enum** on the `**Status:**` line: `draft | in-progress | shipped | shipped-partial | superseded | abandoned | deferred`.

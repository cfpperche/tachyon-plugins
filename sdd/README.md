# sdd - spec-driven development (Tachyon plugin)

A runtime-neutral Tachyon skill for spec-driven development: capture intent before code, break implementation into a
small plan and checklist, then verify, dogfood, and close the spec with evidence.

It installs the `sdd` skill into Claude, Codex, and Grok. It does not wire hooks, provision binaries, fetch data artifacts, or
call paid services.

SDD is optional and repository-local. Installing Tachyon does not require it, and Tachyon does not invoke it for
startup, operation, verification, or releases. The skill reads only repository/conversation context and manages its
own `docs/specs/` artifacts; it has no integration with task boards, agent state, handoff systems, or work queues.

## When to use it

Use a spec when the change carries meaningful decision complexity: ambiguous behavior, a new or changed module/API/
schema/protocol, migration or lifecycle design, cross-cutting behavior, real alternatives, costly reversal, or
coordination that needs a shared contract.

Do not use file count as a proxy. A bounded, reversible change can touch a component, CSS, tests, localization, and
documentation without needing a spec. If a spec would only restate an obvious diff, skip it.

## What it creates

`sdd new <slug>` scaffolds:

```text
docs/specs/NNN-<slug>/
  spec.md
  plan.md
  tasks.md
  notes.md
```

Number allocation is same-clone worktree-safe: the helper coordinates sibling worktrees from the same Git clone so two
local agents do not pick the same `NNN` while scaffolding concurrently.

**Opt-in later (not part of `new`):**

```text
docs/specs/NNN-<slug>/cookbook.md   # operator/agent how-to — sdd-cookbook.sh
docs/specs/NNN-<slug>/prototypes/   # prototype files, only when useful
docs/specs/NNN-<slug>/evidence/     # durable evidence, only when useful
```

Prototypes and evidence are not required for every spec. When created for one spec, their default owner is that spec
directory rather than a shared top-level `docs/prototypes/`. An artifact with a deliberate different owner can declare
`**Artifact-Location-Opt-Out:** <reason>`.

## Commands

| Command | Purpose |
|---|---|
| `new <slug>` | Scaffold the four core spec files from templates. |
| `plan` | Draft implementation approach after the intent is agreed. |
| `tasks` | Convert the plan into ordered checkbox work. |
| `list` | List local specs and their `Status`. |
| `verify <spec>` | Preview or re-run a spec's declared `**Verify:**` command. |
| `dogfood <spec>` | Preview or run a spec's declared headless `**Dogfood:**` command. |
| `cookbook <spec>` | Opt-in: scaffold `cookbook.md` from the template (`sdd-cookbook.sh`). |
| `close [<spec>]` | Read-only closure audit for shipped specs. |

`verify` and `dogfood` are preview-by-default. They only execute declared commands when run with `--run`, and then
append dated logs to `notes.md`.

## Cookbook (opt-in)

When a ship adds a usable surface (tools, registry lifecycle, CLI), write a short `cookbook.md` so the next
operator does not reverse-engineer the code. Scaffold with:

```sh
bash "<skill>/scripts/sdd-cookbook.sh" docs/specs/NNN-<slug>
# or NNN only
```

Declare `**Cookbook:** yes` in `tasks.md`, or `**Cookbook-Opt-Out:** <reason>`. `close` warns (does not hard-fail) when
a likely operator surface ships without either.

## Closure contract

A clean shipped spec has:

- no unchecked acceptance or task boxes;
- no template placeholders;
- a `**Closure:**` line in `spec.md`;
- either passing headless dogfood evidence or a non-empty `**Dogfood-Opt-Out:**` reason.

Warning-only (exit still 0 if no hard findings):

- visual QA missing/opt-out for UI-looking contracts;
- cookbook missing/opt-out for operator-surface contracts or explicit `**Cookbook:**`.
- a declared local artifact missing from disk or stored outside its owning spec without a location opt-out.

## Install

Install through Tachyon's Plugins View with a pinned source:

```sh
github:cfpperche/tachyon-plugins@<ref>#path=sdd
```

Or install from a local checkout of this package (directory that contains `tachyon-plugin.json`).

The plugin is pure skill payload: no additional OS tools are required beyond a POSIX shell for the bundled helper
scripts.

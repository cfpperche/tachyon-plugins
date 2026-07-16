# sdd - spec-driven development (Tachyon plugin)

A runtime-neutral Tachyon skill for spec-driven development: capture intent before code, break implementation into a
small plan and checklist, then verify, dogfood, and close the spec with evidence.

It installs the `sdd` skill into Claude and Codex. It does not wire hooks, provision binaries, fetch data artifacts, or
call paid services.

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
```

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

When a ship adds a usable surface (Bridge tools, registry lifecycle, CLI), write a short `cookbook.md` so the next
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

## Install

Install through Tachyon's Plugins View with a pinned source:

```sh
github:cfpperche/tachyon-plugins@<ref>#path=sdd
```

Or install from a local checkout of this package (directory that contains `tachyon-plugin.json`).

The plugin is pure skill payload: no additional OS tools are required beyond a POSIX shell for the bundled helper
scripts.

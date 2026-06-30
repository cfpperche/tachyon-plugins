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

## Commands

| Command | Purpose |
|---|---|
| `new <slug>` | Scaffold the four spec files from templates. |
| `plan` | Draft implementation approach after the intent is agreed. |
| `tasks` | Convert the plan into ordered checkbox work. |
| `list` | List local specs and their `Status`. |
| `verify <spec>` | Preview or re-run a spec's declared `**Verify:**` command. |
| `dogfood <spec>` | Preview or run a spec's declared headless `**Dogfood:**` command. |
| `close [<spec>]` | Read-only closure audit for shipped specs. |

`verify` and `dogfood` are preview-by-default. They only execute declared commands when run with `--run`, and then
append dated logs to `notes.md`.

## Closure contract

A clean shipped spec has:

- no unchecked acceptance or task boxes;
- no template placeholders;
- a `**Closure:**` line in `spec.md`;
- either passing headless dogfood evidence or a non-empty `**Dogfood-Opt-Out:**` reason.

## Install

Install through Tachyon's Plugins View with a pinned source:

```sh
github:cfpperche/tachyon-plugins@<ref>#path=sdd
```

The plugin is pure skill payload: no additional OS tools are required beyond a POSIX shell for the bundled helper
scripts.

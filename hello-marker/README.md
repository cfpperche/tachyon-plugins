# hello-marker (Tachyon plugin)

A benign round-trip proof plugin for Tachyon's plugin lifecycle. It wires a harmless `PreToolUse` hook into both
Claude and Codex, prints a marker line, exits `0`, and never mutates project state.

Use it when you need to prove install -> materialize -> hook execution -> update -> remove without involving a
security scanner, browser driver, paid API, external binary, or data artifact.

## What it ships

- `tachyon-plugin.json` with `blocks` for `claude/` and `codex/`.
- Native hook configs for both runtimes.
- A tiny `marker.sh` per runtime block. The scripts only print:
  - `[hello-marker] tachyon plugin round-trip OK (claude)`
  - `[hello-marker] tachyon plugin round-trip OK (codex)`

## Install

Install through Tachyon's Plugins View with a pinned source:

```sh
github:cfpperche/tachyon-plugins@<ref>#path=hello-marker
```

The consent drawer should show only runtime hook materialization. There are no provisioned tools, data artifacts,
external tools, config files, git hooks, or dependencies.

## Safety

The hook is intentionally a no-op. It does not inspect tool input, block commands, write files, read secrets, call the
network, or touch Git state. Its only purpose is to make the runtime hook path observable.

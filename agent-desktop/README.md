# agent-desktop

`agent-desktop` gives agents explicit, bounded "hands" on the user's desktop: open an app or URL, wait for a window,
restore it, and bring it to the foreground before another tool such as `agent-screen` captures visual evidence.

V1 targets the current dogfood environment: WSL controlling the Windows host desktop through PowerShell and Win32 APIs.
It does not take screenshots, run background loops, type arbitrary text, click the mouse, or perform privacy redaction.
The user consent model is explicit: if you run this plugin, you accept that it can launch, restore, and focus real
desktop windows and that visible titles/URLs may expose private context.

## Usage

From a Tachyon workspace with the plugin installed:

```bash
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" doctor
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" list-windows --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" launch --app chrome --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" open-url --browser chrome --new-window https://github.com --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" wait-window --process chrome --title GitHub --timeout 10 --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" focus --window-id 123456 --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" restore --window-id 123456 --json
```

All commands write compact JSON to stdout. `--json` is accepted for readability but JSON is the only v1 output format.

## Contract

- Desktop mutation is explicit. The plugin only acts when a command is invoked.
- `doctor` reports whether the Windows-host backend is available from WSL.
- `list-windows` reports visible top-level Windows host windows with bounded titles by default. Use `--verbose` only when
  full window titles are acceptable.
- Commands that require a single target accept `--window-id`, or `--process <name>` plus optional `--title <substring>`.
- Ambiguous process/title matches fail closed and return bounded candidate metadata.
- `open-url` is restricted to `http://` and `https://` URLs and supports Chrome only in v1. It opens a new Chrome window.
- `focus` restores the target, then tries direct foregrounding, ALT foreground unlock, and an attach-thread fallback.
  It only reports success after verifying that the foreground root window matches the target.
- `restore` calls Windows restore on the selected target and reports whether it had to change minimized state.
- Window bounds use physical pixels and DWM extended frame bounds where available, matching `agent-screen`.
- Pair with `agent-screen screenshot --window-id <id>` for visual evidence. `agent-desktop` never captures pixels.

## Exit Codes

| Code | Error |
|---:|---|
| 0 | ok |
| 1 | failed |
| 64 | invalid-argument |
| 70 | backend-unavailable |
| 71 | not-found |
| 72 | ambiguous |
| 73 | timeout |
| 74 | focus-denied |

Every non-zero exit emits JSON with `ok=false`, `error`, `exit_code`, and a short `message`.

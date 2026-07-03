---
name: agent-desktop
description: Explicit desktop control primitives for non-web dogfood. Use when an agent needs to launch an app, open a URL, wait for a native window, restore/focus it, audit owned desktop sessions, or clean up plugin-opened windows before inspecting with agent-screen. V1 targets WSL controlling the Windows host desktop and deliberately excludes screenshots, arbitrary keyboard input, mouse input, privacy redaction, or background automation.
---

# agent-desktop

Use `agent-desktop` when the user has consented to desktop control and the agent needs bounded "hands" before using
`agent-screen` as "eyes". Prefer passing `--session <id>` to any command that opens windows, then run
`cleanup --session <id>` when the dogfood step is complete.

## Invocation

```bash
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" doctor
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" list-windows --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" launch --app <name-or-path> --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" open-url --browser chrome --new-window [--session <id>] <http-or-https-url> --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" wait-window --process <name> [--title <substring>] --timeout <seconds> --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" focus --window-id <id> --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" focus --process <name> [--title <substring>] --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" restore --window-id <id> --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" sessions show --session <id> --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" cleanup --session <id> --dry-run --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" cleanup --session <id> --json
```

## Use this when

- A native or installed app must be opened before visual inspection.
- A minimized or covered target window must be restored/focused before `agent-screen` captures it.
- A browser URL needs to be opened in a deterministic Chrome window before screenshot dogfood.
- You need structured window ids and bounds to chain into `agent-screen screenshot --window-id <id>`.
- You opened windows through `agent-desktop` and need to clean up only those plugin-owned windows.

## Do not use this when

- The target is a web page that `agent-browser` can inspect directly.
- The user has not consented to desktop mutation.
- You need screenshots; use `agent-screen`.
- You need arbitrary typing, hotkeys, clicking, or mouse movement; those are future versions.
- You need privacy filtering or redaction; v1 does not provide it.

## Safety and failure behavior

- Treat `list-windows --json` as consented desktop inspection because window titles can reveal private context.
- Prefer `--window-id` after listing windows when a target can be isolated.
- If using `--process`/`--title`, expect ambiguous matches to fail closed and retry with a returned id.
- `focus` may steal focus from the user. Run it only when that state change is intended.
- A successful `focus` means foreground verification passed; otherwise the command fails with `focus-denied`.
- `open-url` only accepts `http://` and `https://` URLs and supports Chrome in v1. It uses a dedicated session Chrome
  profile and records owned windows in `.tachyon/agent-desktop/sessions/`.
- Always prefer `cleanup --session <id> --dry-run` before destructive cleanup when a session has multiple windows.
- `cleanup --session <id>` only closes ledger-owned windows whose live identity still matches the recorded HWND, pid,
  process start time, window class, and session profile.
- Do not close windows by process/title when cleanup is available; use the session ledger.
- Keep dogfood screenshots under a worktree evidence path such as `.tachyon/evidence/<name>.png`.

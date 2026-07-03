---
name: agent-desktop
description: Explicit desktop control primitives for non-web dogfood. Use when an agent needs to launch an app, open a URL, wait for a native window, restore/focus it, send a bounded text/key/click input action, audit owned desktop sessions, or clean up plugin-opened windows before inspecting with agent-screen. V1 targets WSL controlling the Windows host desktop and deliberately excludes screenshots, OCR, privacy redaction, background automation, and free-form macros.
---

# agent-desktop

Use `agent-desktop` when the user has consented to desktop control and the agent needs bounded "hands" before using
`agent-screen` as "eyes". Prefer passing `--session <id>` to any command that opens windows, then run
`cleanup --session <id>` when the dogfood step is complete.

## Invocation

```bash
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" doctor
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" list-windows --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" apps find <name-or-path> --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" launch --app <name-or-path> --dry-run --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" launch --app <name-or-path> --wait-window --session <id> --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" open-url --browser chrome --new-window [--session <id>] <http-or-https-url> --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" wait-window --process <name> [--title <substring>] --timeout <seconds> --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" focus --window-id <id> --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" focus --process <name> [--title <substring>] --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" restore --window-id <id> --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" type --window-id <id> --text <text> --session <id> [--dry-run] --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" key --window-id <id> --key <allowed-key> --session <id> [--dry-run] --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" click --window-id <id> --x <px> --y <px> --session <id> [--expected-bounds <json>] [--dry-run] --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" sessions show --session <id> --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" cleanup --session <id> --dry-run --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" cleanup --session <id> --json
```

## Use this when

- A native or installed app must be opened before visual inspection.
- You need to discover how an app name resolves before launching it.
- A minimized or covered target window must be restored/focused before `agent-screen` captures it.
- A browser URL needs to be opened in a deterministic Chrome window before screenshot dogfood.
- You need structured window ids and bounds to chain into `agent-screen screenshot --window-id <id>`.
- After inspecting a screenshot, you need to type one line, press one allowed key/chord, or left-click one safe point
  inside a known window.
- You opened windows through `agent-desktop` and need to clean up only those plugin-owned windows.

## Do not use this when

- The target is a web page that `agent-browser` can inspect directly.
- The user has not consented to desktop mutation.
- You need screenshots; use `agent-screen`.
- You need arbitrary typing, unsupported hotkeys, right/double click, drag, scroll, mouse movement without click, OCR, or a
  background automation loop.
- You need privacy filtering or redaction; v1 does not provide it.

## Safety and failure behavior

- Treat `list-windows --json` as consented desktop inspection because window titles can reveal private context.
- Prefer `--window-id` after listing windows when a target can be isolated.
- If using `--process`/`--title`, expect ambiguous matches to fail closed and retry with a returned id.
- `focus` may steal focus from the user. Run it only when that state change is intended.
- A successful `focus` means foreground verification passed; otherwise the command fails with `focus-denied`.
- Use input only in the screenshot loop: focus/open -> `agent-screen screenshot --window-id <id>` -> one input command ->
  `agent-screen screenshot --window-id <id>` -> cleanup.
- `type`, `key`, and `click` require explicit `--window-id` and `--session`; process/title targeting is refused for
  mutation.
- `type` is single-line only, no control characters, and max 1024 characters. Use `key --key enter` for Enter.
- `key` allow-list: `enter`, `escape`, `tab`, `backspace`, `delete`, `up`, `down`, `left`, `right`, `ctrl+a`, `ctrl+f`,
  `ctrl+s`, `ctrl+z`. `ctrl+s` can save user data.
- `click` coordinates are screenshot/DWM-bounds-relative. Avoid title bars and borders; nonclient and obscured clicks are
  refused. The physical cursor may move and is not restored.
- Use `apps find <query>` before launch when the app name is not an explicit executable path.
- Use `launch --app <query> --dry-run` to inspect the selected executable, source, confidence, and denied reason.
- Use `launch --app <query> --wait-window --session <id>` when cleanup is expected. Without `--wait-window`, generic
  launches are reported as `owned=false` because no window identity has been proven.
- Native apps may restore recent files/projects. Treat that as part of the consented desktop mutation.
- Packaged Windows apps are owned only when direct pid/start/exe/HWND/class identity is proven; indirect host/frame
  handoffs are launched-not-owned.
- Generic browser launches are refused; use `open-url --browser chrome` for URLs.
- `open-url` only accepts `http://` and `https://` URLs and supports Chrome in v1. It uses a dedicated session Chrome
  profile and records owned windows in `.tachyon/agent-desktop/sessions/`.
- Always prefer `cleanup --session <id> --dry-run` before destructive cleanup when a session has multiple windows.
- `cleanup --session <id>` only closes ledger-owned windows whose live identity still matches the recorded HWND, pid,
  process start time, executable path, window class, and session profile.
- For non-owned touched windows, `cleanup --session <id>` restores the recorded minimized state and never closes them.
- Do not close windows by process/title when cleanup is available; use the session ledger.
- Keep dogfood screenshots under a worktree evidence path such as `.tachyon/evidence/<name>.png`.

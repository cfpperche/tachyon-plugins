# agent-desktop

`agent-desktop` gives agents explicit, bounded "hands" on the user's desktop: open an app or URL, wait for a window,
restore it, bring it to the foreground, send one scoped input action, and clean up windows the plugin opened before
another tool such as `agent-screen` captures visual evidence.

V1 targets the current dogfood environment: WSL controlling the Windows host desktop through PowerShell and Win32 APIs.
It does not take screenshots, run background loops, perform OCR, run a planner, or perform privacy redaction. The user
consent model is explicit: if you run this plugin, you accept that it can launch, restore, focus, type, press safe keys,
left-click inside a target window, and close plugin-owned desktop windows and that visible titles/URLs may expose private
context.

## Usage

From a Tachyon workspace with the plugin installed:

```bash
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" doctor
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" list-windows --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" apps find notepad --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" launch --app notepad --dry-run --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" launch --app notepad --wait-window --session dogfood-1 --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" open-url --browser chrome --new-window --session dogfood-1 https://github.com --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" wait-window --process chrome --title GitHub --timeout 10 --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" focus --window-id 123456 --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" restore --window-id 123456 --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" type --window-id 123456 --text "hello" --session dogfood-1 --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" key --window-id 123456 --key ctrl+a --session dogfood-1 --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" click --window-id 123456 --x 40 --y 80 --session dogfood-1 --dry-run --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" sessions show --session dogfood-1 --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" cleanup --session dogfood-1 --dry-run --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-desktop/skills/agent-desktop/scripts/agent-desktop.sh" cleanup --session dogfood-1 --json
```

All commands write compact JSON to stdout. `--json` is accepted for readability but JSON is the only v1 output format.

## Contract

- Desktop mutation is explicit. The plugin only acts when a command is invoked.
- `doctor` reports whether the Windows-host backend is available from WSL and checks non-installable requirements:
  PowerShell, WSL interop/`wslpath`, and Chrome for `open-url --browser chrome`.
- `list-windows` reports visible top-level Windows host windows with bounded titles by default. Use `--verbose` only when
  full window titles are acceptable.
- Commands that require a single target accept `--window-id`, or `--process <name>` plus optional `--title <substring>`.
- Ambiguous process/title matches fail closed and return bounded candidate metadata.
- `apps find <query>` explains how an app name/path resolves across literal paths, built-in aliases, Windows App Paths,
  `%PATH%`, Start Menu shortcuts, and conservative common install directories.
- `launch --app <query> --dry-run` reports the selected candidate without starting it.
- `launch --app <query> --wait-window --session <id>` starts the resolved app, snapshots windows before launch, and only
  records `owned=true` when a new top-level window can be tied to the launched process tree. If no new owned window is
  identified, the app may still be launched but cleanup will not claim it.
- Native apps may restore recent files/projects according to their own settings. User consent for `launch` covers that
  visible desktop mutation.
- Packaged Windows apps are owned only when they expose a direct process/window identity that passes the same checks.
  Indirect frame/host handoffs are launched-not-owned.
- Generic browser app launches are refused; use `open-url --browser chrome` so the plugin can create a dedicated owned
  session profile.
- `open-url` is restricted to `http://` and `https://` URLs and supports Chrome only in v1. It opens a new Chrome window
  in a dedicated session profile and records `owned=true` in the workspace ledger.
- `focus` restores the target, then tries direct foregrounding, ALT foreground unlock, and an attach-thread fallback.
  It only reports success after verifying that the foreground root window matches the target.
- `restore` calls Windows restore on the selected target and reports whether it had to change minimized state.
- Input commands (`type`, `key`, `click`) require both `--window-id` and `--session`. They never target by process/title.
- `type` transports text as base64 UTF-8 into PowerShell and injects it with Win32 `SendInput`: printable ASCII uses
  `VkKeyScanW` virtual-key events for reliability in modern Windows controls, with Unicode events as fallback. Text is
  limited to one line, no control characters, and 1024 characters. Use `key --key enter` for Enter.
- `key` only accepts: `enter`, `escape`, `tab`, `backspace`, `delete`, `up`, `down`, `left`, `right`, `ctrl+a`,
  `ctrl+f`, `ctrl+s`, `ctrl+z`. `ctrl+s` can persist user data in non-owned apps; this is covered by user consent.
- `click` sends one left button down/up pair. Coordinates are relative to the `agent-screen screenshot --window-id`
  image/DWM extended frame bounds, not Win32 client coordinates. The command refuses out-of-bounds points, nonclient
  title-bar/border points, and points where another root window is topmost immediately before the click.
- Input commands append session ledger events. If a non-owned window is touched by input, cleanup restores its prior
  minimized state and never closes it.
- `sessions list` and `sessions show --session <id>` inspect the workspace ledger and live identity verification state.
- `cleanup --session <id> --dry-run` reports which owned windows would be closed without closing anything.
- `cleanup --session <id>` sends `WM_CLOSE` only to windows owned by that session after revalidating HWND, pid, process
  start time, process name, executable path, window class, and Chrome profile path. It does not kill processes by default.
  For non-owned touched windows, cleanup restores the recorded minimized state instead of closing the window.
- `close --window-id <id>` refuses unknown or non-owned windows.
- Window bounds use physical pixels and DWM extended frame bounds where available, matching `agent-screen`.
- Pair with `agent-screen screenshot --window-id <id>` for visual evidence. The intended loop is:
  focus/open with `agent-desktop`, inspect with `agent-screen`, send one `agent-desktop` input action, inspect again, then
  cleanup. `agent-desktop` never captures pixels.

## Runtime Requirements

`agent-desktop` intentionally declares no Tachyon-managed `externalTools`: it uses WSL and Windows host primitives that
Tachyon cannot install safely for the user.

- WSL with Windows interop enabled
- `wslpath` in the WSL environment
- Windows host `powershell.exe`
- Chrome installed on the Windows host for `open-url --browser chrome`

Chrome session profiles are created under the Windows temp directory (`%TEMP%\agent-desktop-profiles\<session>`). The
workspace ledger is written under `.tachyon/agent-desktop/sessions/`.

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

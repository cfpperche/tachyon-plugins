# agent-screen

`agent-screen` gives agents explicit, bounded eyes on non-web surfaces: installed VS Code/Tachyon dogfood, native
windows, terminal windows, and UI states that do not have a browser route.

V1 is screenshot-only. On WSL it prefers a Windows host screenshot for the active desktop window, because X11/WSLg
capture can miss Windows-native apps such as VS Code. Screen recording is intentionally deferred until screenshot
capture has proven useful and the recording backend, cancel-safe output format, and frame-sampling story are designed.

## Usage

From a Tachyon workspace with the plugin installed:

```bash
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-screen/skills/agent-screen/scripts/agent-screen.sh" doctor
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-screen/skills/agent-screen/scripts/agent-screen.sh" list-windows --json
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-screen/skills/agent-screen/scripts/agent-screen.sh" screenshot --active --out .tachyon/evidence/sidebar.png
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-screen/skills/agent-screen/scripts/agent-screen.sh" screenshot --screen --out .tachyon/evidence/desktop.png
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-screen/skills/agent-screen/scripts/agent-screen.sh" screenshot --window-id 123456 --out .tachyon/evidence/window.png
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-screen/skills/agent-screen/scripts/agent-screen.sh" screenshot --window "Visual Studio Code" --out .tachyon/evidence/vscode.png
```

## Contract

- Capture is explicit. The plugin never records or screenshots in the background.
- `doctor` explains the selected backend or the missing display/tool.
- `screenshot` writes a real PNG or fails before leaving a misleading artifact.
- On WSL, `--active`, `--screen`, `--window-id`, and `--window <query>` prefer the Windows host backend.
- `list-windows --json` reports visible Windows-host windows with bounded titles by default. Use `--verbose` only when
  the user explicitly accepts that full window titles may contain private data.
- `--window <query>` matches title or process name and fails closed on zero or ambiguous matches. Ambiguous errors report
  ids/processes/bounds by default, not window titles.
- `--window-id <id>` captures a specific id selected from `list-windows`.
- `--active` resolves the foreground window and uses `PrintWindow` first. If that returns a blank frame, it falls back to
  visible rectangle capture and reports `mode=active-window-screen-fallback`.
- X11 fallback captures the active/selected X11 window when available; on WSLg/X11 sessions that expose no active window,
  it captures the full display and reports `mode=screen-fallback`.
- `mode=screen-fallback` proves the backend captured the X11 display, not that the target app was visible. If the image
  is empty/black, bring the target window onto that display or use a future host-side backend.
- Windows-host `--window-id` and `--window <query>` use `PrintWindow` so covered windows can still be captured. Minimized
  windows still fail closed; restore them before capture.
- `warning=blank-frame-suspected` means the PNG is valid but visually suspicious, usually because a GPU-backed app
  returned an empty frame to `PrintWindow`.

## Backends

The v1 backends are:

- Windows host capture from WSL via PowerShell/.NET `PrintWindow` and `CopyFromScreen`
- Windows host window inventory and targeting via `EnumWindows`, process metadata, and window bounds
- The Windows host helper declares DPI awareness and uses DWM extended frame bounds where available, so screenshots use
  physical pixels with tighter visible-window bounds.
- Windows host operations are timeout-guarded; a hung target should fail instead of blocking the agent indefinitely.
- Linux/WSLg X11 capture via `ffmpeg` with `x11grab`

- `ffmpeg` with `x11grab`
- `$DISPLAY`
- `xdpyinfo` for display dimensions
- `xdotool` + `xwininfo` for optional window targeting

Other platforms should fail closed until a platform-specific backend is implemented.

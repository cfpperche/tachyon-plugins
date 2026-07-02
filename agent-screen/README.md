# agent-screen

`agent-screen` gives agents explicit, bounded eyes on non-web surfaces: installed VS Code/Tachyon dogfood, native
windows, terminal windows, and UI states that do not have a browser route.

V1 is screenshot-only. Screen recording is intentionally deferred until screenshot capture has proven useful and the
recording backend, cancel-safe output format, and frame-sampling story are designed.

## Usage

From a Tachyon workspace with the plugin installed:

```bash
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-screen/skills/agent-screen/scripts/agent-screen.sh" doctor
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-screen/skills/agent-screen/scripts/agent-screen.sh" list-windows
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-screen/skills/agent-screen/scripts/agent-screen.sh" screenshot --active --out .tachyon/evidence/sidebar.png
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/agent-screen/skills/agent-screen/scripts/agent-screen.sh" screenshot --window "Visual Studio Code" --out .tachyon/evidence/vscode.png
```

## Contract

- Capture is explicit. The plugin never records or screenshots in the background.
- `doctor` explains the selected backend or the missing display/tool.
- `screenshot` writes a real PNG or fails before leaving a misleading artifact.
- `--active` captures the active X11 window when available; on WSLg/X11 sessions that expose no active window, it
  captures the full display and reports `mode=screen-fallback`.
- `--window <query>` requires a unique visible X11 window match; ambiguous or missing matches fail closed.
- `mode=screen-fallback` proves the backend captured the X11 display, not that the target app was visible. If the image
  is empty/black, bring the target window onto that display or use a future host-side backend.

## Backend

The v1 backend is Linux/WSLg X11 capture:

- `ffmpeg` with `x11grab`
- `$DISPLAY`
- `xdpyinfo` for display dimensions
- `xdotool` + `xwininfo` for optional window targeting

Other platforms should fail closed until a platform-specific backend is implemented.

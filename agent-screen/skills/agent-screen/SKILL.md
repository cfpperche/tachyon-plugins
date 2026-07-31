---
name: agent-screen
description: OS-level screenshot primitive for non-web Visual QA and installed-app dogfood. Use when an agent needs to inspect a real desktop/native/VS Code/TUI surface that has no browser route. Captures explicit PNG screenshots via a local display backend and fails closed when no screen/backend is available. V1 is screenshots only; NOT background recording, OCR, pixel-diff baselines, or web pages covered by agent-browser.
---

# agent-screen

Capture a real desktop screenshot for non-web Visual QA and installed-app dogfood. On WSL, prefer the Windows host
backend for VS Code/desktop validation; X11 fallback can capture only the WSLg/X display and may miss Windows-native
windows.

## Invocation

```bash
bash "<this-skill-dir>"/scripts/agent-screen.sh doctor
bash "<this-skill-dir>"/scripts/agent-screen.sh list-windows --json
bash "<this-skill-dir>"/scripts/agent-screen.sh screenshot --active --out <png>
bash "<this-skill-dir>"/scripts/agent-screen.sh screenshot --screen --out <png>
bash "<this-skill-dir>"/scripts/agent-screen.sh screenshot --window-id <id> --out <png>
bash "<this-skill-dir>"/scripts/agent-screen.sh screenshot --window-id <id> --restore-minimized --out <png>
bash "<this-skill-dir>"/scripts/agent-screen.sh screenshot --window "<title-query>" --out <png>
```

> `<this-skill-dir>` is the directory this SKILL.md was loaded from — your runtime tells you where it
> materialized it (Claude prints it as *Base directory for this skill*; Codex uses the bundled skill path).
> Resolve it and run from anywhere in the workspace. Do **not** hardcode `.claude/skills/…`, `.agents/skills/…`
> or `.tachyon/plugins/…` — an agent working in its own git worktree has none of those directories.

## Use this when

- You need visual proof of installed VS Code/Tachyon UI after a VSIX install or reload.
- The surface is native, desktop, terminal, or otherwise has no browser route.
- Bridge/API data can prove state but not what the human actually sees.

## Do not use this when

- A page can be inspected with `agent-browser`.
- The user asked for video. Recording is a future v2 and is not part of this plugin version.
- You need OCR or semantic accessibility inspection.

## Safety and failure behavior

- Capture is always explicit. Do not run it speculatively on unrelated tasks.
- Treat `list-windows --json` and `--screen` as consented desktop inspection. The user must have asked for/accepted the
  screen-inspection risk before you run them.
- Prefer `list-windows --json` followed by `--window-id` when a specific target can be isolated.
- Use `--restore-minimized` only when the user explicitly wants the target window restored for capture. It changes the
  desktop state and may bring that window to the foreground.
- Use `--screen` when the user has arranged multiple windows side by side.
- If the display/backend is unavailable, report the error; do not fabricate visual evidence.
- Keep screenshots in a worktree evidence path when possible, such as `.tachyon/evidence/<name>.png`.
- On Windows-host, `--active` resolves the foreground window. If `PrintWindow` returns a blank frame, it may report
  `mode=active-window-screen-fallback`; this is a visible-rectangle capture of the active window, not covered-window
  evidence.
- `--active` may report `mode=screen-fallback` when no active window can be resolved; this is still a real screenshot,
  but it is full-display evidence rather than window-targeted evidence.
- If `mode=screen-fallback` produces an empty/black screenshot, report that as backend proof only, not visual validation
  of the target app.
- If stdout includes `warning=blank-frame-suspected`, treat the PNG as suspicious and prefer `--screen` or a visible
  active-window fallback for validation.

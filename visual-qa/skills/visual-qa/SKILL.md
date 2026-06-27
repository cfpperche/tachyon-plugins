---
name: visual-qa
description: Advisory Visual QA on a web UI a worktree changed — judge "does this page LOOK right vs the design intent" (visual fidelity), not whether it works. Use when reviewing a UI/front-end change for appearance, layout, spacing, or design-system fidelity, or when asked "does this page look right / look good / match the design". Drives the page with the agent-browser plugin, screenshots the project's declared routes, judges them against the project's declared design-intent anchor, and attaches a verdict + durable screenshots to the worktree evidence channel (attach_evidence). It NEVER gates a merge — it informs the parent. NOT functional/e2e correctness (that's the verify gate), NOT an accessibility audit, NOT for non-web/native/desktop UIs. Requires the agent-browser plugin installed alongside + a host Chrome; web-only.
license: MIT
---

# visual-qa — advisory Visual QA on a web UI

The first **producer** for the worktree evidence channel: look at a UI change, judge it against the project's
**design intent**, attach an advisory verdict + screenshots. It decides nothing — the verify gate stays the gate.

## Preflight (any "no" → return `unable_to_judge`, with the reason — never guess)

1. **Config present?** Read this plugin's `config/visual-qa.json` (materialized at install). It must declare an
   `anchor` (≥1 of `text` / `path` / `url`) and a bounded `routes` list. Missing anchor → `unable_to_judge` ("no
   design-intent anchor — a verdict would be taste"). Missing routes → ask the human which URL(s) to judge (v1 does
   NOT infer routes from the project).
2. **agent-browser available?** This skill delegates browser-driving to the **agent-browser** plugin. If it isn't
   installed / its CLI is unavailable → `unable_to_judge` ("install the agent-browser plugin to capture the UI").
3. **Run `config.setup` (if present), then check reachability.** `setup` is the project's own "how to make my UI
   reachable" (human/agent-authored — same trust as a project CLAUDE.md): if `setup.command` is set, run it in the
   background and poll `setup.readyUrl` until it responds; follow `setup.notes`. This is how a UI with NO URL (e.g.
   a VS Code extension webview) gets one — serve a preview harness and point `routes` at it. Then confirm the route
   URLs respond; if not → ask the human to start the app; don't fabricate.

## Flow

1. **Capture.** For each declared route × viewport (default desktop `1440x900`; mobile `390x844` only if
   configured), use the **agent-browser** skill to navigate the **direct URL** and screenshot, saving to a
   worktree-relative path `.vqa/visual-qa/<route>-<viewport>.png`. Prefer direct URLs + pre-authenticated saved
   state. If reaching a route needs a state-mutating action (agent-browser holds those at its write-gate), return
   `unable_to_judge` for that route or ask the human — do not build an auto-click flow. Wait for network-idle / a
   known selector before shooting; note any volatile/animated regions as a limitation.

2. **Judge against the ANCHOR — written intent, not a pixel oracle.** Read the anchor (`text`, the `path` doc,
   and/or the `url`). Compare each screenshot to the intent and cite **concrete observations per dimension** —
   layout, spacing, alignment, typography, color/contrast vs the design tokens, responsive behavior. Examples:
   "the settings card respects the 8px grid"; "primary button contrast is below the design token at the disabled
   state"; "header overlaps the content below 360px". A prior screenshot is CONTEXT, never canonical truth.

3. **Pick a verdict** (advisory model judgment — context, not truth):
   - `pass` — matches the intent on the dimensions judged.
   - `concern` — works but a noted issue → `severity: warn`.
   - `fail` — a real visual defect → `severity: error`.
   - `unable_to_judge` — couldn't capture, or no anchor.

4. **Attach** to the worktree agent via the `attach_evidence` bridge tool:
   ```
   attach_evidence(
     targetAgent: "<the worktree agent>",
     producer:    "<your agent name>",
     kind:        "judgment",
     severity:    "info" | "warn" | "error",
     summary:     "Visual QA: <verdict> — <one line>",
     detail:      "<the dimensions judged + concrete observations + what anchor you compared against>",
     artifacts:   [".vqa/visual-qa/home-desktop.png", ...],   // worktree-relative; Tachyon copies them durably
   )
   ```
   The parent reads it via `list_evidence` / the `verify_agent` summary — alongside, never instead of, the verify
   badge.

## Discipline

- **Anchor or nothing.** No anchor → `unable_to_judge`. Always cite the dimensions you judged.
- **Advisory only.** Never block a merge on a Visual QA verdict.
- **Concrete or nothing.** "Looks good" is not a verdict.
- **Web-only.** Browser-routable UIs only; native/desktop/mobile-app/TUI are out of scope.

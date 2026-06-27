# visual-qa

**Advisory Visual QA on a web UI a worktree changed.** An agent drives the page, screenshots the routes you
declare, judges them against the design intent you declare, and attaches a verdict + durable screenshots to the
worktree's **evidence channel** — so a parent agent (or you) reads "does this look right?" alongside the verify
gate. It **never gates a merge**; it informs.

This is the first **producer** for Tachyon's worktree evidence channel — and a worked example of the layering:
Tachyon ships the channel (`attach_evidence`); this plugin is one producer built on top.

## How it fits together

| Piece | Role |
|---|---|
| **agent-browser** plugin | drives the browser + screenshots (install it alongside — this plugin delegates capture to it) |
| **visual-qa** (this) | the recipe: capture declared routes → judge vs the anchor → `attach_evidence` |
| Tachyon core | the evidence channel + the durable screenshot copy |

## Install

Via the Tachyon **Plugins View** → *Add by source*:

```
github:cfpperche/tachyon-plugins@<ref>#path=visual-qa
github:cfpperche/tachyon-plugins@<ref>#path=agent-browser   # required for capture
```

Then **edit the config** (Plugins View → Config) — the two things an agent must NOT guess:

```jsonc
{
  "anchor": { "text": "How this UI should look / the invariants that matter", "path": "docs/design.md" },
  "routes": [{ "name": "settings", "url": "http://localhost:3000/settings" }],
  "viewports": [{ "name": "desktop", "width": 1440, "height": 900 }]
}
```

- **`anchor`** (≥1 of `text`/`path`/`url`) — REQUIRED. No anchor → the verdict is `unable_to_judge` (a verdict
  without intent is just taste). A prior screenshot is *context*, never a canonical baseline.
- **`routes`** — REQUIRED, a bounded list of direct URLs (not "the UI"). v1 does not infer them.
- **`viewports`** — optional (default desktop).

## Use

Ask an agent to "visual-QA this UI change" / "does this page look right?" — the skill's description matches the
task. It (1) preflights (anchor? agent-browser? app reachable?), (2) screenshots each route×viewport to
`.vqa/visual-qa/*.png`, (3) judges vs the anchor with concrete per-dimension observations, (4) attaches a
`judgment` verdict (`pass|concern|fail|unable_to_judge`) + the screenshots via `attach_evidence`.

## Scope

- **Web-only** (a real URL). Native/desktop/mobile/TUI is out of scope (a future OS-capture primitive).
- **Advisory.** Never a merge gate, never a pixel-diff regression gate.
- Auth: prefer direct URLs + pre-authenticated saved state; a route that needs state-mutating navigation returns
  `unable_to_judge` rather than auto-clicking.

---
name: visual-qa
description: Advisory Visual QA on a web UI — judge "does this page LOOK right vs the design intent" (visual fidelity), not whether it works. Use when reviewing a UI/front-end change for appearance, layout, spacing, or design-system fidelity, or when asked "does this page look right / look good / match the design", OR when invoked ad-hoc as `/visual-qa <surface-or-url> --anchor "<intent>"` to judge a specific surface NOW. Takes the target + the design-intent anchor at INVOCATION (inline), falling back to the project's declared config baseline; drives the page with the agent-browser plugin, screenshots the route(s), judges them against the anchor, and attaches a verdict + durable screenshots to the worktree evidence channel (attach_evidence). It NEVER gates a merge — it informs the parent. NOT functional/e2e correctness (that's the verify gate), NOT an accessibility audit, NOT for non-web/native/desktop UIs. Requires the agent-browser plugin installed alongside + a host Chrome; web-only.
license: MIT
argument-hint: '[<surface-or-url>] [--anchor "<intent>" | --anchor-path <doc> | --anchor-url <url>] [--viewport WxH]'
---

# visual-qa — advisory Visual QA on a web UI

The first **producer** for the worktree evidence channel: look at a UI change, judge it against the **design intent**,
attach an advisory verdict + screenshots. It decides nothing — the verify gate stays the gate.

**Two ways to run, same discipline:**
- **Interactive (preferred in a live session):** `/visual-qa <surface-or-url> --anchor "<intent>"` — you supply the
  target + the design intent inline, no file edit. The skill also reads the surrounding conversation, so
  *"visual-qa the Agent Studio tabs — the codicons should align with their labels"* works as a natural-language ask.
- **Baseline (persistent / CI):** no args → run against the project's declared `config/visual-qa.json` (the spec-275
  baseline: a fixed anchor + route set judged every time).

The invocation always WINS; the config is the fallback. The anchor discipline never relaxes — you just declare the
anchor by TYPING it instead of editing a file.

## Resolution Algorithm (run this, in order — do NOT improvise)

Resolve each input by precedence, then record where it came from. **invocation → config baseline → fallback.**

| input | from invocation | else config | else (fallback) |
|---|---|---|---|
| **anchor** | `--anchor "<text>"`, `--anchor-path <doc>`, or `--anchor-url <url>` (or stated in the ask) | `config.anchor` | — |
| **target** | a direct URL, or a named surface | `config.routes` | — |
| **viewports** | `--viewport WxH` | `config.viewports` | desktop `1440x900` |
| **setup** | — | `config.setup` | none (assume reachable) |

Fill a provenance table for the run — you attach it later:

```
anchor_source   = invocation | config | human_followup | missing
target_source   = invocation | config | human_followup
viewports_source = invocation | config | default
setup_source    = config | none
mixed_provenance = (anchor_source != target_source AND both ∈ {invocation,config})
```

Then apply the **runtime-readiness branches** (these are NOT schema errors — an empty config is valid):

1. **No target** (no invocation target AND no `config.routes`) → ASK the human for a URL. This ask is the first-class
   path — do NOT tell them to go edit the config (that recreates the pain). `target_source = human_followup`.
2. **No anchor** (no invocation anchor AND no `config.anchor`) → return **`unable_to_judge`** with the reason:
   `"no design-intent anchor — a verdict without one is just taste. Re-run with --anchor \"<intent>\"."` Never guess.
3. **Mixed provenance — the one footgun.** If the target is an **inline ad-hoc** one (a direct URL or a named surface
   from the invocation) but the anchor would come from `config.anchor`: do NOT silently borrow it (that anchor may
   describe a DIFFERENT surface). Either ask the human for the intent (`anchor_source = human_followup`), OR proceed
   against `config.anchor` ONLY with an explicit run note in the verdict `detail` ("anchor borrowed from config
   baseline; written for the baseline surfaces, may not fit this target") and `mixed_provenance = true`.
4. **`setup` is for harness/config targets only.** Run `config.setup` only when the target is a `config.routes` entry
   or its harness. NEVER run it for an arbitrary inline URL (a baseline `npm run preview:webview` is meaningless for
   `https://example.com`). An inline direct URL is assumed reachable; if it isn't, ask the human to start the app.

### Named surface → URL: catalog resolution (spec 281)

When the target is a NAMED surface (not a direct URL), resolve it in this ORDER — run the steps, don't improvise:

1. **`config.routes` named entry** — if the name matches one, use its URL (the spec-277 path).
2. **`config.catalog` resolution** — if a catalog is declared (`config.catalog = {path, base}`) and no routes entry
   matched, run this checklist:
   a. **Run `config.setup` FIRST** so `base` is reachable. If setup fails or `base` doesn't respond →
      **`unable_to_capture`** (a capture/setup failure — NOT a visual `fail`, NOT `unable_to_judge`), recording the
      candidate you were resolving. Never judge against an unreachable base.
   b. **Match the view — DETERMINISTIC FIRST:** read the catalog JSON at `config.catalog.path`. Parse a `view:fixture`
      syntax if present. Match the surface name to an entry by **exact `view` id → exact `title` → an `aliases` entry**,
      case-insensitive. ONLY if nothing matches deterministically, pick the best entry by a semantic/`tags` read — but
      if **>1 plausible view** exists (e.g. "pin" → pin-studio AND pin-preview), STATE the candidates and ASK; tags
      alone never decide.
   c. **Pick the fixture:** the named fixture (`view:fixture`), else the view's `default`. If the phrase names a STATE,
      LIST that view's fixtures and pick/ask for the matching one (the defect may live in a non-default fixture).
   d. **Join the URL (relative-only):** `resolved_url = base` (drop a trailing `/`) `+ entry.url` (keep its leading `/`,
      preserve the query). The catalog `url` MUST be relative — REJECT an absolute catalog url (absolute targets belong
      in `config.routes`, not catalog data).
   e. **Open + VERIFY (anti-stale):** open `resolved_url`, then confirm the page rendered the resolved surface via the
      harness marker — `document.body.dataset.previewView` / `…previewFixture` must equal the resolved `view`/`fixture`.
      On a mismatch → **`unable_to_capture`** + ask (a stale catalog rendering a DIFFERENT surface must never be judged
      as the named one).
   f. **Record provenance** in the verdict `data`: `resolution_source: "config.routes" | "catalog" | "human"`, `view`,
      `fixture`, `catalog_path`, `catalog_base`, `resolved_url`, and `catalog_hash` (a short hash of the catalog file),
      so a reviewer sees exactly what was QA'd.
3. **Otherwise ASK the human for the direct URL** (first-class) — never fabricate one.

Resolution is ADDITIVE and TRANSPARENT: always state the surface you resolved to. The anchor stays mandatory — no
anchor → `unable_to_judge`, never "resolution failed".

**Inline target overrides the ENTIRE config route set** for that run — ad-hoc means "judge THIS now", not "append to
the baseline suite".

## Preflight (after resolution)

- **agent-browser available?** This skill delegates browser-driving to the **agent-browser** plugin. If it isn't
  installed / its CLI is unavailable → `unable_to_judge` ("install the agent-browser plugin to capture the UI").
- **Setup (if `setup_source = config`):** run `setup.command` in the background, poll `setup.readyUrl` until it
  responds, follow `setup.notes`. This is how a UI with NO URL (e.g. a VS Code extension webview) gets one — serve a
  preview harness and point routes at it. Then confirm the route URLs respond; if not → ask the human to start the
  app; don't fabricate.

## Flow

1. **Capture.** For each resolved route × viewport, use the **agent-browser** skill to navigate the **direct URL** and
   screenshot, saving to a worktree-relative path `.vqa/visual-qa/<route>-<viewport>.png`. Prefer direct URLs +
   pre-authenticated saved state. If reaching a route needs a state-mutating action (agent-browser holds those at its
   write-gate), return `unable_to_judge` for that route or ask the human — do not build an auto-click flow. Wait for
   network-idle / a known selector before shooting; note any volatile/animated regions as a limitation.

2. **Judge against the ANCHOR — written intent, not a pixel oracle.** Read the anchor (`text`, the `path` doc, and/or
   the `url`). Compare each screenshot to the intent and cite **concrete observations per dimension** — layout,
   spacing, alignment, typography, color/contrast vs the design tokens, responsive behavior. Examples: "the settings
   card respects the 8px grid"; "primary button contrast is below the design token at the disabled state"; "header
   overlaps the content below 360px". A prior screenshot is CONTEXT, never canonical truth.

3. **Pick a verdict** (advisory model judgment — context, not truth):
   - `pass` — matches the intent on the dimensions judged.
   - `concern` — works but a noted issue → `severity: warn`.
   - `fail` — a real visual defect → `severity: error`.
   - `unable_to_judge` — couldn't capture, or no anchor.

4. **Attach** to the worktree agent via the `attach_evidence` bridge tool — RECORD the provenance in `data`:
   ```
   attach_evidence(
     targetAgent: "<the worktree agent>",
     producer:    "<your agent name>",
     kind:        "judgment",
     severity:    "info" | "warn" | "error",
     summary:     "Visual QA: <verdict> — <one line>",
     detail:      "<the dimensions judged + concrete observations + what anchor you compared against;
                   include the mixed-provenance note if mixed_provenance>",
     data:        { "anchor_source": "...", "target_source": "...", "viewports_source": "...",
                    "setup_source": "...", "mixed_provenance": false },
     artifacts:   [".vqa/visual-qa/home-desktop.png", ...],   // worktree-relative; Tachyon copies them durably
   )
   ```
   The parent reads it via `list_evidence` / the `verify_agent` summary — alongside, never instead of, the verify
   badge.

## Discipline

- **Anchor or nothing.** No anchor from EITHER channel → `unable_to_judge`. Always cite the dimensions you judged.
- **Never silently borrow an anchor** for an ad-hoc target — ask, or note it + flag `mixed_provenance`.
- **Ask, don't send to a file.** A missing target → ask for the URL inline; never "go edit the config".
- **Advisory only.** Never block a merge on a Visual QA verdict.
- **Concrete or nothing.** "Looks good" is not a verdict.
- **Web-only.** Browser-routable UIs only; native/desktop/mobile-app/TUI are out of scope.

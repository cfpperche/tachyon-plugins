---
name: diagram
description: Deterministic technical diagrams from a Mermaid source. Use when the user wants an architecture, flowchart, sequence, ER, class, or state diagram rendered to a real, tracked SVG/PNG/PDF asset — for a design doc, spec, README, or slide. Renders locally + free via the Mermaid CLI (mmdc) in a system headless Chrome; the browser is detected and (if missing) offered as a consent-gated assisted install. Degrades to structural validation (the .mmd source is always kept) when no browser is present. NOT organic/photo imagery, NOT motion/video, NOT custom visual-design craft.
---

# diagram — deterministic technical diagrams

Compile a Mermaid source (a `.mmd` file or inline text) into a tracked **SVG/PNG/PDF** asset, locally and free. The
browser is resolved through Tachyon's shim — the skill never runs a tool off the bare PATH.

## Invocation

```
bash "<this-skill-dir>"/scripts/diagram.sh "<source.mmd | mermaid text>" [--format svg|png|pdf] [--out <dir>] [--theme default|dark|forest|neutral]
```

> `<this-skill-dir>` is the directory this SKILL.md was loaded from — your runtime tells you where it
> materialized it (Claude prints it as *Base directory for this skill*; Codex uses the bundled skill path).
> Resolve it and run from anywhere in the workspace. Do **not** hardcode `.claude/skills/…`, `.agents/skills/…`
> or `.tachyon/plugins/…` — an agent working in its own git worktree has none of those directories.

- **`<source>`** — a path to a `.mmd` file, or inline Mermaid text (e.g. `"flowchart TD\n A-->B"`).
- **`--format`** — `svg` (default), `png`, or `pdf`.
- **`--out <dir>`** — output dir (default `assets/diagrams/`). The `.mmd` source is always written next to the render.
- **`--theme`** — a Mermaid built-in theme only (`default` / `dark` / `forest` / `neutral`).

## What it does (and the contract it upholds)

1. Resolves a system **browser** via `.tachyon/bin/_tachyon-external diagram chrome` (a trusted absolute path; tries
   google-chrome / google-chrome-stable / chromium / chromium-browser; never the bare PATH).
2. Acquires **mmdc** at a pinned version via `npx -p @mermaid-js/mermaid-cli@<pinned> mmdc`
   (`PUPPETEER_SKIP_DOWNLOAD=1` — no bundled Chromium; reuses the system browser). **First run fetches it from npm**
   (a lower-trust, non-engine-checksummed acquisition — see the README); subsequent runs reuse the npx cache.
3. Renders the source into the requested format and writes the asset + the tracked `.mmd` source.

## Fail-closed behavior (the source is never lost)

- No system browser → **`status=unavailable`**: the source is structurally validated and **kept**; relay the
  install hint (the plugin's card/drawer offers a consent-gated assisted install where your OS prompts for your
  password — Tachyon never sees it).
- No `npx` (Node not installed) → **`status=unavailable`**: source kept; install Node and re-run.
- Source is not valid Mermaid, or mmdc errors (syntax) → **`status=error`**: the source is kept for you to fix.
- It never emits an empty asset.

## Output + provenance

- The render goes to `--out` (default `assets/diagrams/`); the `.mmd` source is written alongside (the durable
  artifact). The skill **never** `git add`s anything, and **warns** if the output path is git-ignored.
- A one-line run record (status, source sha, format, the mmdc package+version, `acquisition:npx`,
  `engine_checksummed:false`) is appended under `.tachyon/`.

## When NOT to use

- Organic/photo imagery (that's an image generator). Motion/video. Custom visual-design craft. Non-Mermaid diagram
  languages (Graphviz/PlantUML/D2) — Mermaid-only.

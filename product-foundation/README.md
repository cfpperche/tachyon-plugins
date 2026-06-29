# product-foundation — idea → a complete docs-first product foundation (Tachyon plugin)

A foundation generator + design partner for the product lifecycle (idea → v1 → vN). A **15-step pipeline** turns a
one-line idea into a complete, **docs-first** product foundation plus a **visual contract**, then scaffolds the SDD
umbrella + foundation spec the engineering build runs as.

**It produces planning artifacts and a visual contract — NOT a runnable app.** The app build is the SDD workflow working
the scaffolded specs.

## What it produces (at `--out=<path>/docs/`)

- **Discovery** — concept brief (with a binding product-form declaration + market sizing as an explicit hypothesis),
  lo-fi mood + killer flow, functional spec (with an assumption register — the bets, never fabricated interviews),
  UX audit.
- **Specification** — PRD, OST (Opportunity Solution Tree), sitemap/IA, system design (RACI + risk + data-flow), legal
  posture (DPIA-triggered), roadmap / cost / GTM (all labeled **pre-validation projections**, presented as ranges).
- **Identity** — brand book, design system (tokens + components).
- **Visual contract** — navigable screen-atlas + hi-fi killer-flow mood (static HTML) + fixture-spec.
- **SDD handoff** — scaffolds `docs/specs/001-<slug>/` (umbrella) + `002-foundation/` (the research-driven foundation
  child) the build runs as.

5 phases, 4 user gates (a concept kill-gate after step 1 + 3 phase gates with distilled review agendas). A per-phase
quality judge grades scope/completeness/coherence. Product-form aware: `screen-app | headless-service | cli | bot |
embedded` adapt the relevant steps.

## Runtimes

**Claude only in v1.** The pipeline's spine is a delegated, stateful orchestration (parallel producer waves, per-phase
judge batches, schema-validation + re-dispatch, the gated state machine) that relies on enforced sub-agent dispatch. A
codex port is a deliberate fast-follow once a codex orchestration adapter is built + dogfooded — never a hollow port.

## Optional dependency — the agent-browser plugin

The best-effort Phase-4 **visual check** (screenshot the hi-fi mood screens over `file://`, check overflow) is delegated
to the **[agent-browser](../agent-browser) plugin** (declared `dependencies: ["agent-browser@^2.1.0"]`). Per Tachyon's
plugin-dependency model this is **surfaced at install, non-blocking, never auto-installed** — if the agent-browser
plugin (or host Chrome) isn't present, the visual check records a skip and the pipeline proceeds. The plugin bundles no
browser of its own.

## Usage

```
/product-foundation "<one-line idea>" --out=<path> [--stack=<next|expo>] [--from-step=NN] [--skip-prd] [--skip-brand]
```

`--out` is required (a docs-first tree is written under `<out>/docs/`). Resume a partial run with `--from-step=NN`.

## Bundled scripts (Bun required)

The pipeline ships TS helper scripts run with **Bun** (`bun scripts/...`):

- `validate-step.ts` — the **Layer-1 schema-floor validator** (a HARD gate: the orchestrator runs it after each step
  and does NOT advance on a `schema-incomplete` result). **Bun is required for the pipeline** to enforce the floors.
- `craft-floor-check.ts` (anti-slop) + `staleness-check.ts` (post-run drift) — **advisory**, non-blocking; if Bun is
  missing these checks are skipped, the run is unaffected.

## Bundled design systems

Step 14 (design system) draws from a bundled catalogue of ~150 vendored **Open-Design** design systems
(`skills/product-foundation/design-systems/`, ~6 MB) — only 1–2 are read per run (via the catalogue index), but the
breadth is the point. The Open-Design content is **Apache-2.0**; attribution is preserved in
`skills/product-foundation/vendor/open-design/{LICENSE,NOTICE}` — see [`CREDITS`](./CREDITS).

## Not

A runnable app (docs-first; the app build is the SDD workflow on the scaffolded specs). A diagram tool, an image/video
generator, or a browser primitive (that is the agent-browser plugin).

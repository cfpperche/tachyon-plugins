# tachyon-plugins

Installable capability plugins for [Tachyon](https://marketplace.visualstudio.com/) — the multi-runtime agent orchestrator.

Each plugin is a self-contained directory with a `tachyon-plugin.json` manifest and one native config block per supported runtime (`claude/`, `codex/`). Tachyon's plugin engine owns the install / update / remove lifecycle and wires each plugin's declared blocks into the runtime's own config (`.claude/settings.json`, `.codex/hooks.json`, …). Plugins are **content**; the engine + format live in the Tachyon repo and ship with no bundled plugins.

## Install

Via the Tachyon **Plugins View** → *Add by source*, with a pinned git ref:

```
github:<owner>/tachyon-plugins@<ref>#path=<plugin-dir>
```

## Plugins

| Plugin | What it does | Runtimes |
|---|---|---|
| [`sdd`](./sdd) | Spec-driven development — scaffolds + progresses `docs/specs/NNN-<slug>/{spec,plan,tasks,notes}.md` (`new`/`plan`/`tasks`/`list`), then closes the loop: `verify` re-runs a spec's declared check (preview-by-default, `--run` to execute) and `close` audits shipped specs for closure debt. | claude · codex |
| [`hello-marker`](./hello-marker) | Benign round-trip proof: wires a harmless no-op `PreToolUse` marker hook. Exercises the full install→wire→update→remove lifecycle without touching security or project state. | claude · codex |
| [`secrets-guard`](./secrets-guard) | A **two-layer git secrets gate** powered by gitleaks. Layer 1: a `pre-commit` git-hook scans staged changes (Tachyon fetches the pinned, checksum-verified gitleaks binary). Layer 2: a per-runtime `PreToolUse` shape-gate stops an agent from silently bypassing layer 1 via `--no-verify`/compound/`-a`. Combines **hooks + git-hooks + tools**. | claude · codex (+ git hook) |
| [`transcribe`](./transcribe) | **Local-first speech-to-text** — an audio or video file → transcript via whisper.cpp (content never leaves the machine). The model ships as a checksummed data artifact; whisper-cli + ffmpeg as external tools. | claude · codex |
| [`diagram`](./diagram) | **Deterministic technical diagrams** (architecture / flowchart / sequence / ER / class / state) from Mermaid → tracked SVG/PNG/PDF, local + free (npx `mmdc` + system Chrome). | claude · codex |
| [`audio`](./audio) | **Text-to-speech** — text → spoken audio/voiceover, local-first + free (Kokoro / Piper via uvx). | claude · codex |
| [`image`](./image) | **Paid AI image generation** via fal.ai (needs `FAL_KEY`) — draft mockups, brand text/photo, hero art; a cost gate prints the spend before each call. | claude · codex |
| [`sound`](./sound) | **Paid music + sound effects** via fal.ai (`--kind music\|sfx`, needs `FAL_KEY`); cost-gated. | claude · codex |
| [`hyperframes`](./hyperframes) | **Deterministic local video from code** — HTML → MP4 via ffmpeg, free, git-tracked source. The local/free half of the split video capability. | claude · codex |
| [`video`](./video) | **Paid generative AI video** via the fal.ai queue (Wan / Kling / Veo class, needs `FAL_KEY`) — async fire-and-forget `submit`→`poll`, hard `--confirm-cost-usd` gate on every submit. The generative/paid half (sibling of `hyperframes`). | claude · codex |
| [`product-foundation`](./product-foundation) | **Idea → a complete docs-first product foundation.** A 15-step pipeline produces every planning artifact (concept brief, spec with an assumption register, UX audit, PRD, OST, sitemap/IA, system design, legal, roadmap/cost/GTM, brand, design system) + a visual contract, then scaffolds the SDD umbrella + foundation child. NOT a runnable app. Optionally depends on the `agent-browser` plugin for the visual check. | claude |

## Manifest format

```jsonc
{
  "name": "hello-marker",            // lowercase kebab, marketplace-safe
  "version": "1.0.0",                // semver
  "description": "…",
  "runtimes": ["claude", "codex"],   // v1 supported runtimes
  "blocks": { "claude": "claude/", "codex": "codex/" }  // runtime → native block dir (optional per runtime)
}
```

Inside a hook command, the token `${PLUGIN_ROOT}` resolves to that runtime's materialized block directory (so `"${PLUGIN_ROOT}"/marker.sh` points at the script shipped beside the block's `hooks.json`).

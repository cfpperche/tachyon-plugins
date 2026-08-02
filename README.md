# tachyon-plugins

Installable capability plugins for [Tachyon](https://marketplace.visualstudio.com/) — the multi-runtime agent orchestrator.

Each plugin is a self-contained directory with a `tachyon-plugin.json` manifest and, when needed, one native config block per supported runtime (`claude/`, `codex/`, `grok/`). Tachyon's plugin engine owns the install / update / remove lifecycle and wires each plugin's declared blocks into the runtime's own config (`.claude/settings.json`, `.codex/hooks.json`, `.grok/hooks.json`, …). Plugins are **content**; the engine + format live in the Tachyon repo and ship with no bundled plugins.

## Install

Via the Tachyon **Plugins View** → *Add by source*, with a pinned git ref:

```
github:<owner>/tachyon-plugins@<ref>#path=<plugin-dir>
```

Every first-party plugin directory now carries a local `README.md`, and every manifest exposes a `docsUrl` that the
Plugins View can surface after install.

## Plugins

| Plugin | What it does | Runtimes |
|---|---|---|
| [`sdd`](./sdd) | Spec-driven development — scaffolds + progresses `docs/specs/NNN-<slug>/{spec,plan,tasks,notes}.md` (`new`/`plan`/`tasks`/`list`) with same-clone worktree-safe numbering and opt-in spec-owned artifacts, then closes the loop: `verify` re-runs a spec's declared check, `dogfood` runs declared headless dogfood (both preview-by-default), and `close` audits closure debt, dogfood proof, and declared artifact locality. | claude · codex · grok |
| [`hello-marker`](./hello-marker) | Benign round-trip proof: wires a harmless no-op `PreToolUse` marker hook. Exercises the full install→wire→update→remove lifecycle without touching security or project state. | claude · codex |
| [`secrets-guard`](./secrets-guard) | A **two-layer git secrets gate** powered by gitleaks. Layer 1: a `pre-commit` git-hook scans staged changes (Tachyon fetches the pinned, checksum-verified gitleaks binary). Layer 2: a per-runtime `PreToolUse` shape-gate stops an agent from silently bypassing layer 1 via `--no-verify`/compound/`-a`. Combines **hooks + git-hooks + tools**. | claude · codex · grok (+ git hook) |
| [`dep-audit`](./dep-audit) | **On-demand OSV vulnerability audit** for dependency lockfiles via pinned osv-scanner. Scans INSTALLED deps (npm/pnpm/yarn/bun, PyPI, Go, crates, …), **reports + proposes upgrades** — never auto-fixes, never edits a manifest/lockfile, never gates install or commit. Skill-primary + provisioned tool. | claude · codex · grok |
| [`verify-gate`](./verify-gate) | A **landing gate for your trunk**: a `pre-push` git-hook runs the project's verification and refuses the push when it fails. Scoped by git's pre-push stdin, so pushes to feature branches cost nothing and branch deletions are skipped. Branches and command come from the environment (falling back to `verify:full`/`verify`/`test` in `package.json`), so nothing is project-specific. Fails closed — a gate that cannot resolve a command refuses rather than waving the push through. | any (+ git hook) |
| [`transcribe`](./transcribe) | **Local-first speech-to-text** — an audio or video file → transcript via whisper.cpp (content never leaves the machine). The model ships as a checksummed data artifact; whisper-cli + ffmpeg as external tools. | claude · codex · grok |
| [`diagram`](./diagram) | **Deterministic technical diagrams** (architecture / flowchart / sequence / ER / class / state) from Mermaid → tracked SVG/PNG/PDF, local + free (npx `mmdc` + system Chrome). | claude · codex · grok |
| [`agent-browser`](./agent-browser) | **Eyes + hands on the web** — pinned, checksum-verified Chrome-over-CDP CLI + skill: open → accessibility snapshot with `@eN` refs → act / screenshot / extract (including auth-gated pages via CLI saved-session state the LLM never sees). Human-owned `allowedDomains` restraint; writes are unreviewed (v3 withdrew the write-gate claim). Needs host Chrome/Chromium. | claude · codex · grok |
| [`agent-screen`](./agent-screen) | **OS-level screenshots** for non-web Visual QA and installed-app dogfood. Captures explicit PNG evidence from the real desktop via a Windows-host backend on WSL, with X11 fallback, window targeting, opt-in minimized-window restore, blank-frame warnings, and fail-closed errors. V1 is screenshot-only; screen recording is deferred. | claude · codex · grok |
| [`agent-desktop`](./agent-desktop) | **OS-level desktop control** for non-web dogfood. Launches apps, opens Chrome URLs in owned sessions, waits for windows, restores/focuses selected windows, audits sessions, and cleans up plugin-opened windows from WSL against the Windows host. Pair with `agent-screen` for pixels; v1 excludes arbitrary keyboard/mouse automation. | claude · codex · grok |
| [`visual-qa`](./visual-qa) | **Advisory Visual QA** for a web UI a worktree changed. Drives the page via `agent-browser`, screenshots declared routes, judges against YOUR design-intent anchor (not a pixel baseline), and attaches verdict + screenshots to the worktree evidence channel. Never gates a merge; requires the `agent-browser` plugin alongside. | claude · codex · grok |
| [`audio`](./audio) | **Text-to-speech** — text → spoken audio/voiceover, local-first + free (Kokoro / Piper via uvx). | claude · codex · grok |
| [`image`](./image) | **Paid AI image generation** via fal.ai (needs `FAL_KEY`) — draft mockups, brand text/photo, hero art; a cost gate prints the spend before each call. | claude · codex · grok |
| [`sound`](./sound) | **Paid music + sound effects** via fal.ai (`--kind music\|sfx`, needs `FAL_KEY`); cost-gated. | claude · codex · grok |
| [`hyperframes`](./hyperframes) | **Deterministic local video from code** — HTML → MP4 via ffmpeg, free, git-tracked source. The local/free half of the split video capability. | claude · codex · grok |
| [`video`](./video) | **Paid generative AI video** via the fal.ai queue (Wan / Kling / Veo class, needs `FAL_KEY`) — async fire-and-forget `submit`→`poll`, hard `--confirm-cost-usd` gate on every submit. The generative/paid half (sibling of `hyperframes`). | claude · codex · grok |
| [`product-foundation`](./product-foundation) | **Idea → a complete docs-first product foundation.** A 15-step pipeline produces every planning artifact (concept brief, spec with an assumption register, UX audit, PRD, OST, sitemap/IA, system design, legal, roadmap/cost/GTM, brand, design system) + a visual contract, then scaffolds the SDD umbrella + foundation child. NOT a runnable app. Optionally depends on the `agent-browser` plugin for the visual check. | claude |

## Manifest format

```jsonc
{
  "name": "hello-marker",            // lowercase kebab, marketplace-safe
  "version": "1.0.0",                // semver
  "description": "…",
  "runtimes": ["claude", "codex", "grok"],   // supported runtimes
  "docsUrl": "https://github.com/cfpperche/tachyon-plugins/tree/main/hello-marker",
  "blocks": { "claude": "claude/", "codex": "codex/", "grok": "grok/" }  // runtime → native block dir (optional per runtime)
}
```

Inside a hook command, the token `${PLUGIN_ROOT}` resolves to that runtime's materialized block directory (so `"${PLUGIN_ROOT}"/marker.sh` points at the script shipped beside the block's `hooks.json`).

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
| [`sdd`](./sdd) | Spec-driven development scaffolding — a portable skill that scaffolds and progresses `docs/specs/NNN-<slug>/{spec,plan,tasks,notes}.md`. Materializes into `.claude/skills/` and `.agents/skills/`. | claude · codex |
| [`hello-marker`](./hello-marker) | Benign round-trip proof: wires a harmless no-op `PreToolUse` marker hook. Exercises the full install→wire→update→remove lifecycle without touching security or project state. | claude · codex |
| [`secrets-guard`](./secrets-guard) | A git **pre-commit secrets gate** powered by gitleaks. Tachyon fetches the pinned, checksum-verified gitleaks binary (tool provisioning) and wires a `pre-commit` hook that blocks any commit whose staged changes contain a detected secret. | any (git hook) |

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

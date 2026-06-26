# secrets-guard

A **two-layer git secrets gate** powered by [gitleaks](https://github.com/gitleaks/gitleaks). It makes the
secrets gate genuinely hard to slip — for you, the agent, and your IDE.

| Layer | What | Capability | Bypassable by `--no-verify`? |
|---|---|---|---|
| **1 — scan** | a `pre-commit` git-hook runs gitleaks over the staged diff; a detected secret **blocks the commit** | `gitHooks` + `tools` (the pinned gitleaks binary) | **Yes** — by git's design |
| **2 — shape-gate** | a per-runtime `PreToolUse(Bash)` hook stops an **agent** from *silently* bypassing layer 1 via `--no-verify` / compound `&&` / `git commit -a` | `blocks` (claude + codex native hooks) | **No** — it runs before git |

Layer 1 is the scan. Layer 2 closes the obvious escape hatch: a git pre-commit hook is bypassable with
`git commit --no-verify` (or a compound `git add … && git commit`, or `git commit -a`), so an agent could
commit a secret without the scan ever running. The shape-gate intercepts the agent's `git commit` *command*
**before git runs** and refuses those bypass shapes (a clean commit falls through to layer 1 unchanged).

This is the first plugin to combine three capabilities for one purpose — **hooks + git-hooks + tools**.

## Install

Via the Tachyon **Plugins View** → *Add by source*, with a pinned git ref:

```
github:cfpperche/tachyon-plugins@<ref>#path=secrets-guard
```

The consent drawer shows all of it: the **runtimes** the shape-gate wires into (claude/codex), the **git-hook**
command, and the **tool** (gitleaks: resolved platform + URL + checksum + publisher) — each behind its own
acknowledgement. On confirm, Tachyon downloads gitleaks for your platform, verifies it, installs it read-only +
content-addressed under `.tachyon/bin/`, wires the pre-commit gate, and registers the per-runtime shape-gate.

## How each layer behaves

**Layer 1 (every commit, everyone):**

```
gitleaks protect --staged --no-banner --redact
```

A staged secret → gitleaks exits non-zero → the commit is rejected (location shown, secret value `--redact`ed).

**Layer 2 (the agent's commits):** intercepts a `git commit` Bash call and **blocks** these bypass shapes:

- `git commit --no-verify` — disables the git-hook
- `git add … && git commit` / `; git commit` — a compound that can smuggle `--no-verify`
- `git commit -a` / `-am` — auto-stage that slips changes past the gate

A deliberate, human-authorized bypass: put an inline `# OVERRIDE: <reason ≥10 chars>` line in the command.

> Layer 2 protects against the **agent / tool-driven** commit. A **human** typing `--no-verify` in their own
> terminal is not gated by the runtime hook — that is by design (it's your repo; `--no-verify` is your escape
> hatch). The point is that an agent can't *silently* slip the gate.

## Supported platforms

gitleaks 8.18.4 is pinned for: `linux-x64` (glibc + musl), `linux-arm64` (glibc + musl), `darwin-x64`,
`darwin-arm64`. An unsupported platform surfaces a clear "no pinned artifact" message. (Windows is not supported
in this Tachyon version.) The shape-gate (layer 2) needs `jq` on PATH; if it is missing the gate fails **open**
(layer 1 still scans).

## Removing / clone-rehydrate

- Removing the plugin un-registers both layers, deletes the provisioned gitleaks binary when no other plugin
  references it, and restores your prior hook setup.
- A fresh clone (where `.tachyon/bin` is gitignored) rehydrates the tool explicitly from the lockfile — never a
  silent fetch.

## Updating gitleaks

The version + checksums are pinned in `tachyon-plugin.json`. To move to a newer gitleaks, bump `version`, the
per-platform `url`/`sha256`, and the archive `binSha256`, then publish a new plugin version — Tachyon never
fetches "latest", a mirror, or an unpinned artifact.

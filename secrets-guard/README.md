# secrets-guard

A **two-layer git secrets gate** powered by [gitleaks](https://github.com/gitleaks/gitleaks). Both layers
exist in the package; **only layer 1 is on by default after install.** Layer 2 reaches managed agent
sessions only when the workspace classifies the plugin (see [Install](#install)).

| Layer | What | Capability | On after install alone? | Bypassable by `--no-verify`? |
|---|---|---|---|---|
| **1 — scan** | a `pre-commit` git-hook runs gitleaks over the staged diff; a detected secret **blocks the commit** | `gitHooks` + `tools` (the pinned gitleaks binary) | **Yes** | **Yes** — by git's design |
| **2 — shape-gate** | a per-runtime `PreToolUse(Bash)` hook stops an **agent** from *silently* bypassing layer 1 via `--no-verify` / compound `&&` / `git commit -a` | `blocks` (claude + codex + grok native hooks) | **No** — needs workspace classification | **No** — it runs before git |

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

The consent drawer shows the **runtimes** the shape-gate can wire into (claude/codex/grok), the **git-hook**
command, and the **tool** (gitleaks: resolved platform + URL + checksum + publisher) — each behind its own
acknowledgement. On confirm, Tachyon downloads gitleaks for your platform, verifies it, installs it read-only +
content-addressed under `.tachyon/bin/`, wires the pre-commit gate (**layer 1 is live**), and **registers** the
per-runtime shape-gate settings-hooks in the plugin lockfile.

**Registering is not projecting.** Layer 2 does **not** enter an agent's session until the workspace classifies
this plugin under `settings.agentHookProjection`. Without that line, a fresh install has **one** layer (the
scan), and an agent can still use `--no-verify` / compound stage+commit / `git commit -a` to skip it. Add:

```yaml
settings:
  agentHookProjection:
    secrets-guard: enforcement
```

Only `enforcement` projects. Unclassified installs project nothing for this plugin (Tachyon withholds with an
explicit reason rather than failing open into a fake gate). Classification is a **workspace-wide** decision
about a gate — not a per-agent capability grant — so it is not toggled from Agent Studio authorize buttons.

## How each layer behaves

**Layer 1 (every commit, everyone — on after install):**

```
gitleaks protect --staged --no-banner --redact
```

A staged secret → gitleaks exits non-zero → the commit is rejected (location shown, secret value `--redact`ed).

**Layer 2 (the agent's commits — only after `secrets-guard: enforcement`):** intercepts a `git commit` Bash
call and **blocks** these bypass shapes:

- `git commit --no-verify` — disables the git-hook
- `git add … && git commit` / `git stage … && git commit` / `git rm --cached … && git commit` / `git mv … && git commit` (same, chained with `;`) — a staging step folded directly into the commit, with nothing reviewable in between
- `git commit -a` / `-am` — auto-stage that slips changes past the gate

An unrelated command chained the same way (`cd <worktree> && git commit`, `npm test && git commit`, …)
never touches the index and is not a bypass — layer 2 only flags a **staging** verb chained into the
commit, not any `&&`/`;` in front of one (as of v2.1.0).

A **clean** commit (`git add <files>` as its own step, then a plain `git commit`, no `-a`, no
`--no-verify`) never needs anything extra — it passes silently, every time. `# OVERRIDE: <reason ≥10 chars>`
is ONLY for a commit that just got blocked above and you're intentionally keeping the bypass shape anyway;
put it as its own line, never inside the `-m` message body (a `-m "..."` doesn't strip a leading `#` line
the way an interactive editor commit does, so an override inside the message text becomes the commit's
permanent subject). As of v2.0.3 the override marker is only even inspected once a bypass shape is
actually detected, so pasting a stale one onto an already-clean commit is simply ignored, not "harmlessly
accepted into the message" — but the discipline above still saves you from writing it there by habit.

> Layer 2 protects against the **agent / tool-driven** commit. A **human** typing `--no-verify` in their own
> terminal is not gated by the runtime hook — that is by design (it's your repo; `--no-verify` is your escape
> hatch). The point is that an agent can't *silently* slip the gate.

## Supported platforms

gitleaks 8.18.4 is pinned for: `linux-x64` (glibc + musl), `linux-arm64` (glibc + musl), `darwin-x64`,
`darwin-arm64`. An unsupported platform surfaces a clear "no pinned artifact" message. (Windows is not supported
in this Tachyon version.) The shape-gate (layer 2) needs `jq` on PATH; if it is missing the gate fails **open**
(layer 1 still scans).

## Removing / clone-rehydrate

- Removing the plugin un-registers both layers (git-hook + lockfile settings-hooks), deletes the provisioned
  gitleaks binary when no other plugin references it, and restores your prior hook setup. You can also drop
  the `agentHookProjection` line if you added one.
- A fresh clone (where `.tachyon/bin` is gitignored) rehydrates the tool explicitly from the lockfile — never a
  silent fetch. Re-classify `secrets-guard: enforcement` in the new workspace if you want layer 2 again.

## Updating gitleaks

The version + checksums are pinned in `tachyon-plugin.json`. To move to a newer gitleaks, bump `version`, the
per-platform `url`/`sha256`, and the archive `binSha256`, then publish a new plugin version — Tachyon never
fetches "latest", a mirror, or an unpinned artifact.

# secrets-guard

A git **pre-commit secrets gate** powered by [gitleaks](https://github.com/gitleaks/gitleaks). Tachyon fetches the
pinned `gitleaks` binary — checksum-verified, content-addressed, human-consented — and wires a `pre-commit` hook
that **blocks any commit whose staged changes contain a detected secret**. Runtime-agnostic: the gate runs for
you, the agent, and your IDE, on every commit.

This is the first plugin to use Tachyon's **tool provisioning** (the plugin declares a per-platform pinned tool;
the engine downloads + verifies it; a `${tool:…}` reference in the git-hook resolves to a launcher that
re-validates the binary's hash before every run).

## Install

Via the Tachyon **Plugins View** → *Add by source*, with a pinned git ref:

```
github:cfpperche/tachyon-plugins@<ref>#path=secrets-guard
```

The consent drawer shows the git-hook command **and** the tool: gitleaks 8.18.4, the resolved platform, the
download URL, the checksum, and the publisher — behind a dedicated acknowledgement (the `sha256` proves the bytes
match this manifest, **not** that the publisher is trustworthy). On confirm, Tachyon downloads gitleaks for your
platform, verifies it, installs it read-only + content-addressed under `.tachyon/bin/`, and activates the hook.

## What it does

On every `git commit`, the hook runs:

```
gitleaks protect --staged --no-banner --redact
```

- **No secret detected** → the commit proceeds.
- **A secret is detected** in the staged diff → gitleaks exits non-zero and the commit is **rejected** (the
  finding's location is shown; the secret value is `--redact`ed from the output).

The binary is invoked through Tachyon's launcher, which re-validates its content hash (and ownership/mode) against
the lockfile before every exec — so a swapped binary never runs.

## Supported platforms

gitleaks 8.18.4 is pinned for: `linux-x64` (glibc + musl), `linux-arm64` (glibc + musl), `darwin-x64`,
`darwin-arm64`. On an unsupported platform the install surfaces a clear "no pinned artifact" message rather than
failing silently. (Windows is not supported in this Tachyon version.)

## Bypassing / removing

- A one-off bypass: `git commit --no-verify` (standard git; the gate is a normal pre-commit hook).
- Removing the plugin un-registers the hook and deletes the provisioned gitleaks binary when no other plugin
  references it; your prior hook setup is restored.

## Updating gitleaks

The version + checksums are pinned in `tachyon-plugin.json`. To move to a newer gitleaks, bump `version`, the
per-platform `url`/`sha256`, and the archive `binSha256`, then publish a new plugin version — Tachyon never
fetches "latest", a mirror, or an unpinned artifact.

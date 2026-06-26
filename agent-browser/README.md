# agent-browser (Tachyon plugin)

Give a Tachyon agent **eyes + hands on the web**. The plugin provisions the pinned, checksum-verified
[`agent-browser`](https://github.com/vercel-labs/agent-browser) CLI (a native Chrome-over-CDP binary) and ships a
runtime-neutral skill that teaches the open → snapshot → act loop. An agent acts **by intent** against an
accessibility snapshot with `@eN` element refs — not brittle CSS selectors.

## What it ships

- **A pinned tool** — the `agent-browser` v0.31.0 binary, per platform (linux x64/arm64 glibc+musl, macOS
  x64/arm64), fetched over HTTPS, sha256-verified, content-addressed, and re-validated by the plugin launcher
  before every run. Invoke it only through `.tachyon/bin/_tachyon-tool agent-browser agent-browser …`.
- **A thin skill** (`claude` + `codex`) — the read loop, per-agent session naming, the auth-state workflow, the
  v1 confirmation policy, and a preflight `doctor`. The full, version-matched command surface loads on demand via
  `agent-browser skills get core`.

## v1 — read-first

Navigation, inspection (`snapshot`), screenshots, and content extraction are the headline — **including from
auth-gated pages** via the CLI's saved-session state (the LLM never sees a credential). Any **state-mutating**
action (form submit, a write-click, or acting on a sensitive site) is **confirmation-gated** in v1. Full
form-driving is **v2**.

## Requirements

- A host **Chrome/Chromium** (the plugin does NOT provision the browser). The bundled `doctor` fails loud with
  `BROWSER_RUNTIME_MISSING` + remediation when it is absent. `agent-browser install` can fetch a pinned
  Chrome-for-Testing if you prefer.

## Security

Higher-trust than a scanner plugin: this binary controls a browser, reaches the network, can replay
authenticated sessions from local state, and writes credential-class files. Saved sessions live **only** under
`.tachyon/browser-state/` (gitignored); encrypt them at rest with `AGENT_BROWSER_ENCRYPTION_KEY`. The default
profile is isolated — never the human's real Chrome profile.

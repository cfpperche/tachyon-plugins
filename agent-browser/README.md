# agent-browser (Tachyon plugin)

Give a Tachyon agent **eyes + hands on the web**. The plugin provisions the pinned, checksum-verified
[`agent-browser`](https://github.com/vercel-labs/agent-browser) CLI (a native Chrome-over-CDP binary) and ships a
runtime-neutral skill that teaches the open → snapshot → act loop. An agent acts **by intent** against an
accessibility snapshot with `@eN` element refs — not brittle CSS selectors.

## What it ships

- **A pinned tool** — the `agent-browser` v0.31.0 binary, per platform (linux x64/arm64 glibc+musl, macOS
  x64/arm64), fetched over HTTPS, sha256-verified, content-addressed, and re-validated by the plugin launcher
  before every run. Invoke it only through `.tachyon/bin/_tachyon-tool agent-browser agent-browser …`.
- **A thin skill** (`claude` + `codex`) — the read loop, form-driving with the held-write contract, per-agent
  session naming, the auth-state workflow, and a preflight `doctor`. The authoritative, version-matched command
  reference is the binary's own `--help` / `<command> --help` (the standalone binary ships no `skills` dir).

## v2 — form-driving with a mechanical write gate

Navigation, inspection (`snapshot`), screenshots, and content extraction — **including from auth-gated pages** via
the CLI's saved-session state (the LLM never sees a credential). v2 adds **form-driving**: every state-mutating
action (`click`/`fill`/`type`/submit/`upload`/`eval`/`download`) is **mechanically held for confirmation** — the
Tachyon launcher force-enables agent-browser's action confirmation (spec 269 `launchPolicy`), so a write returns
`confirmation_required` + an id instead of running silently, and the override flags (`--confirm-actions`,
`--action-policy`) are refused. Reads stay frictionless. A human approves a held write with `agent-browser confirm
<id>` (auto-denies after 60s).

> A **mechanical hold + cooperative approval**, not an airtight sandbox: the held-category list is best-effort (a
> rare/renamed mutator could slip), on-disk config files aren't blocked, and a same-user shell agent could
> self-`confirm` — the same residual Tachyon documents for any provisioned tool. The skill's contract makes the
> human the approver.

## Requirements

- A host **Chrome/Chromium** (the plugin does NOT provision the browser). The bundled `doctor` fails loud with
  `BROWSER_RUNTIME_MISSING` + remediation when it is absent. `agent-browser install` can fetch a pinned
  Chrome-for-Testing if you prefer.

## Security

Higher-trust than a scanner plugin: this binary controls a browser, reaches the network, can replay
authenticated sessions from local state, and writes credential-class files. Saved sessions live **only** under
`.tachyon/browser-state/` (gitignored); encrypt them at rest with `AGENT_BROWSER_ENCRYPTION_KEY`. The default
profile is isolated — never the human's real Chrome profile.

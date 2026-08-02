# agent-browser (Tachyon plugin)

Give a Tachyon agent **eyes + hands on the web**. The plugin provisions the pinned, checksum-verified
[`agent-browser`](https://github.com/vercel-labs/agent-browser) CLI (a native Chrome-over-CDP binary) and ships a
runtime-neutral skill that teaches the open → snapshot → act loop. An agent acts **by intent** against an
accessibility snapshot with `@eN` element refs — not brittle CSS selectors.

## What it ships

- **A pinned tool** — the `agent-browser` v0.31.0 binary, per platform (linux x64/arm64 glibc+musl, macOS
  x64/arm64), fetched over HTTPS, sha256-verified, content-addressed, and re-validated by the plugin launcher
  before every run. Invoke it only through `.tachyon/bin/_tachyon-tool agent-browser agent-browser …`.
- **A thin skill** (`claude` + `codex` + `grok`) — the read loop, form-driving, per-agent session naming, the auth-state
  workflow, and a preflight `doctor`. The authoritative, version-matched command reference is the binary's own
  `--help` / `<command> --help` (the standalone binary ships no `skills` dir).

## v3 — the write gate was withdrawn (breaking)

Navigation, inspection (`snapshot`), screenshots, and content extraction — **including from auth-gated pages** via
the CLI's saved-session state (the LLM never sees a credential) — are unchanged and frictionless.

**v2 claimed that every state-mutating action was mechanically held for human confirmation. That claim was
false**, and v3 removes it. The CLI's `confirmActions` feature is accepted and then ignored on the CLI surface of
the pinned v0.31.0 binary. Measured, on a fresh daemon in an isolated namespace:

| invocation | result |
| --- | --- |
| `confirmActions: "eval,upload,download"` in the config (v2 default) | `eval "1+1"` → `2` |
| `--confirm-actions eval,upload,download` forced on the command line | `eval "1+1"` → `2` |
| `--confirm-actions all` | `eval "1+1"` → `2`; `click` clicks |
| `--confirm-actions all --confirm-interactive` with no TTY | `eval "1+1"` → `2` |

No `confirmation_required` is ever returned. So there is nothing for a human to approve, and no Tachyon-side
`launchPolicy` change can create one — this is upstream behaviour. **Treat every write as unreviewed.** The skill
now makes the agent responsible for asking a human *before* it writes, rather than promising a hold that will not
come.

`confirmActions` stays in the shipped config so the hold begins working the day upstream honours it, and
`--confirm-actions` / `--action-policy` stay in `denyArgs` so the agent still cannot override the human's value.

### What IS mechanical — `allowedDomains`

`allowedDomains` in the human-owned config **is** honoured by 0.31.0: a navigation outside the list fails with
`Domain '<host>' is not in the allowed domains list`. Tachyon feeds the config with a forced `--config` and, as of
v3, also blocks the agent from widening the scope — `--allowed-domains` is in `denyArgs` and
`AGENT_BROWSER_ALLOWED_DOMAINS` is in `scrubEnv`. Only a human sets it, via **Plugins → Config**:

```json
{ "confirmActions": "eval,upload,download", "allowedDomains": ["staging.example.com", "localhost"] }
```

> Upgrading from 2.x: the skill previously told the agent to `export AGENT_BROWSER_ALLOWED_DOMAINS=…` itself. That
> env var is now stripped — an agent-settable restraint is not a restraint. Move the scope into the config.

## Requirements

- A host **Chrome/Chromium** (the plugin does NOT provision the browser). The bundled `doctor` fails loud with
  `BROWSER_RUNTIME_MISSING` + remediation when it is absent. `agent-browser install` can fetch a pinned
  Chrome-for-Testing if you prefer.

## Security

Higher-trust than a scanner plugin: this binary controls a browser, reaches the network, can replay
authenticated sessions from local state, and writes credential-class files. Saved sessions live **only** under
`.tachyon/browser-state/` (gitignored); encrypt them at rest with `AGENT_BROWSER_ENCRYPTION_KEY`. The default
profile is isolated — never the human's real Chrome profile.

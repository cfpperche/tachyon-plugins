# agent-browser (Tachyon plugin)

Give a Tachyon agent **eyes + hands on the web**. The plugin ships a runtime-neutral skill that teaches the
open → snapshot → act loop for the [`agent-browser`](https://github.com/vercel-labs/agent-browser) CLI (a native
Chrome-over-CDP binary), which **you** install. An agent acts **by intent** against an
accessibility snapshot with `@eN` element refs — not brittle CSS selectors.

## What it ships

- **A thin skill** (`claude` + `codex` + `grok`) — the read loop, form-driving, per-agent session naming, the auth-state
  workflow, and a preflight `doctor`. The authoritative, version-matched command reference is the binary's own
  `--help` / `<command> --help` (the standalone binary ships no `skills` dir).

## Requirements

Tachyon does not install these — the manifest names the CLI in `requires` and you provide both.

### `agent-browser` — the CLI

- **npm** — `npm i -g agent-browser` (also the only install that ships `agent-browser skills`)
- **release binary** — https://github.com/vercel-labs/agent-browser/releases
- `AGENT_BROWSER_BIN` overrides the resolved binary.

This skill was written against **v0.34.0**; newer versions are expected to work, and `agent-browser doctor` is
the check that matters. Tachyon used to fetch a pinned, sha256-verified build and re-validate it before every
run — it no longer downloads third-party binaries, so the version you get is the version you installed.

### Chrome or Chromium — the browser runtime

Not shipped (a multi-file browser runtime is not a single verifiable executable). `AB doctor` fails loud with
`BROWSER_RUNTIME_MISSING` when it is absent; `agent-browser install --with-deps` can fetch a Chrome-for-Testing.

## Configuration is yours

The CLI reads a config file (`--config <file>`, or `AGENT_BROWSER_CONFIG`) that can set `confirmActions`,
`allowedDomains`, an action policy, and more. An example ships at `config/agent-browser.json`.

Tachyon used to force one config onto every invocation and strip the flags an agent could use to widen it. **It
no longer does.** The tool is fully usable, and the restraints are the project's to choose — put a config where
your project wants it, point the agent at it, and write the rule in your own project instructions. The skill is
written to honour a config it is given and never to loosen one.

## v3 — the write gate was withdrawn (breaking)

Navigation, inspection (`snapshot`), screenshots, and content extraction remain available. Auth-gated access via
saved state now requires the global workspace-mode choice documented below; the LLM never sees a credential.

**v2 claimed that every state-mutating action was mechanically held for human confirmation. That claim was
false**, and v3 removes it. `confirmActions` matches exact protocol action names. The shipped
`upload` and `download` tokens hold those actions, while `eval` does not hold JavaScript evaluation because its
protocol name is `evaluate`. Keeping `eval` instead of enabling that gate is an explicit owner decision dated
2026-08-21. Most writes therefore still run immediately; get human approval before every write.

The original measurements explain the mismatch:

| invocation | result |
| --- | --- |
| `confirmActions: "eval,upload,download"` in the config (v2 default) | `eval "1+1"` → `2` |
| `--confirm-actions eval,upload,download` forced on the command line | `eval "1+1"` → `2` |
| `--confirm-actions all` | `eval "1+1"` → `2`; `click` clicks |
| `--confirm-actions all --confirm-interactive` with no TTY | `eval "1+1"` → `2` |

The category token `eval` and `all` do not produce a general hold. Exact `upload` and `download` do. The skill
makes the agent responsible for asking a human *before* every write rather than promising a comprehensive hold.

`confirmActions` stays in the shipped config with the owner's chosen tokens, and
`--confirm-actions` / `--action-policy` stay in `denyArgs` so the agent still cannot override the human's value.

### What IS mechanical — `allowedDomains`

`allowedDomains` in the human-owned config **is** honoured by 0.34.0: a navigation outside the list fails with
`Domain '<host>' is not in the allowed domains list`. Tachyon feeds the config with a forced `--config` and, as of
v3, also blocks the agent from widening the scope — `--allowed-domains` is in `denyArgs` and
`AGENT_BROWSER_ALLOWED_DOMAINS` is in `scrubEnv`. Only a human sets it, via **Plugins → Config**:

```json
{ "confirmActions": "eval,upload,download", "allowedDomains": ["staging.example.com", "localhost"] }
```

> Upgrading from 2.x: the skill previously told the agent to `export AGENT_BROWSER_ALLOWED_DOMAINS=…` itself. That
> env var is now stripped — an agent-settable restraint is not a restraint. Move the scope into the config.

### 0.34 workspace-mode choice: allowlist OR saved-state auth

Version 0.34 refuses `state load`, `--state`, and `--restore` while `allowedDomains` is configured because saved
state can replay origins before the allowlist verifies them. Tachyon force-feeds the same human-owned config to
every invocation, so this is a global workspace mode, not a per-session choice.

Default to `allowedDomains`. To use saved-state auth, the human must remove it in **Plugins → Config**, accepting
that every invocation using that config loses the mechanical host boundary. If a task needs both, stop: 0.34
cannot provide both, and agents cannot bypass or narrow the global choice.

## Requirements

- A host **Chrome/Chromium** (not shipped). The bundled `doctor` fails loud with
  `BROWSER_RUNTIME_MISSING` + remediation when it is absent. `agent-browser install` can fetch a
  Chrome-for-Testing if you prefer.

## Security

Higher-trust than a scanner plugin: this binary controls a browser, reaches the network, can replay
authenticated sessions from local state, and writes credential-class files. Saved sessions live **only** under
`.tachyon/browser-state/` (gitignored); encrypt them at rest with `AGENT_BROWSER_ENCRYPTION_KEY`. The default
profile is isolated — never the human's real Chrome profile.

---
name: agent-browser
description: Drive a real Chrome browser to inspect pages, take screenshots, and extract web content — including from pages behind a login — using the pinned, checksum-verified agent-browser CLI. Use when a task needs to see or read a web page (visual inspection, scraping rendered content, reading auth-gated content, checking how a deployed UI renders). v1 is read-first — navigation, inspection, and extraction are free, while any state-mutating action (submitting a form, a click that writes, or acting on a sensitive site) requires explicit human confirmation. Needs a host Chrome/Chromium.
compatibility: Runtime-neutral. Works on any runtime that can run a bundled skill's shell scripts (claude, codex). Invokes the browser only through the plugin-scoped launcher; resolves it relative to the workspace root — no host-specific path assumptions.
license: MIT
---

# agent-browser — eyes + hands on the web

This skill drives the **agent-browser** CLI (a native Chrome-over-CDP binary that Tachyon provisioned and
checksum-verifies on every run). You act on pages **by intent** against an accessibility snapshot with stable
`@eN` element refs — not brittle CSS selectors.

## Invocation — always through the launcher

Never call a raw `agent-browser` from `PATH`. Invoke the **provisioned, hash-validated** binary through the
plugin-scoped launcher at the workspace root:

```sh
.tachyon/bin/_tachyon-tool agent-browser agent-browser <args...>
```

For brevity below, treat `AB` as that prefix (e.g. `AB open https://example.com` ≡
`.tachyon/bin/_tachyon-tool agent-browser agent-browser open https://example.com`). Run from the workspace root.

## Step 0 — doctor first (every session)

Before the first browse in a session, run the preflight (the bundled script lives in this skill's `scripts/`
directory):

```sh
sh scripts/doctor.sh
```

It proves the binary runs and a usable Chrome is present. If it prints `BROWSER_RUNTIME_MISSING`, **stop** and
surface the remediation it gives (install Chrome, or `AB install` to fetch a pinned Chrome-for-Testing). Do not
attempt to browse until doctor passes — a missing browser must never look like a successful empty read.

## Step 1 — the read loop (the v1 core)

```sh
AB --session "$SESSION" open https://example.com     # navigate
AB --session "$SESSION" snapshot -i                   # accessibility tree + @eN refs (what's on the page)
AB --session "$SESSION" screenshot out.png            # visual capture
AB --session "$SESSION" get text @e5                  # extract a specific element's text
```

`snapshot -i` is your primary "what is on this page" call. Read, screenshot, and extract freely on ordinary
pages — that is the read-first contract. For the **full**, version-matched command surface (network capture,
React inspection, diffing, PDF, tabs, …) load it on demand:

```sh
AB skills get core
```

## Sessions — one isolated browser per agent

Always pass a stable, agent-scoped session so concurrent agents never share a browser:

```sh
SESSION="tachyon-$(basename "$(pwd)")-${TACHYON_AGENT_ID:-$$}"
```

Each `--session` gets its own daemon + Chrome. Set an idle timeout so abandoned daemons self-close, and clean up
explicitly when done:

```sh
export AGENT_BROWSER_IDLE_TIMEOUT_MS=300000   # 5 min
AB --session "$SESSION" close                 # or: AB --session "$SESSION" quit
```

## Reading auth-gated content (the headline capability)

The agent **never handles credentials**. A human logs in once; the agent reuses the saved session headlessly.

1. **Human headed login (once per host).** A human opens a headed browser, logs in, and saves the session state
   into the per-workspace, gitignored, credential-class store:

   ```sh
   AB --profile "$PWD/.tachyon/browser-state/<host>-profile" open https://<host>/login   # human logs in here
   AB state save "$PWD/.tachyon/browser-state/<host>.json"
   ```

2. **Agent reuses it headlessly:**

   ```sh
   AB --session "$SESSION" state load "$PWD/.tachyon/browser-state/<host>.json"
   AB --session "$SESSION" open https://<host>/protected
   ```

   Prefer `--session <name> --restore` with `--restore-check-url`/`--restore-check-text` so a stale session is
   detected before you trust it.

- State files live **only** under `.tachyon/browser-state/` — gitignored, credential-class (cookies + tokens =
  a password). Encrypt at rest by exporting `AGENT_BROWSER_ENCRYPTION_KEY` (a 64-hex key) before save/load.
- **Never** point `--profile` at the human's real Chrome profile; use an isolated path under
  `.tachyon/browser-state/` only.
- **Expiry:** if a previously-working authenticated nav now returns 401/403 or redirects to a login page, the
  session expired. Do **not** silently retry — remove the stale state file and ask the human to log in again.

## v1 read-first — what needs human confirmation

Free (no confirmation): navigate, `snapshot`, `screenshot`, `get text/html`, read-only inspection of ordinary
pages.

**Ask for explicit human confirmation first** before:
- submitting a form, or any `click`/`fill`/`press` that **writes** or triggers an action;
- extracting content from an **authenticated** page (you may be reading private data);
- acting on a **sensitive** domain (admin consoles, banking, anything destructive).

Full form-driving (clicks/fills/uploads as a first-class flow) is **v2** — until then, treat write-actions as
confirmation-gated exceptions, not the default.

## Cross-references

- The browser binary is provisioned + hash-validated per Tachyon's tool-provisioning model; you only ever reach
  it through `.tachyon/bin/_tachyon-tool`.
- `AB skills get core` is the authoritative, version-matched command reference for the installed binary.

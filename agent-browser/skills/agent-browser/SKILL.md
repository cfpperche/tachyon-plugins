---
name: agent-browser
description: Drive a real Chrome browser to inspect pages, take screenshots, extract web content (including from pages behind a login), AND drive forms — using the pinned, checksum-verified agent-browser CLI. Use when a task needs to see, read, or interact with a web page (visual inspection, scraping rendered content, reading auth-gated content, filling/submitting a form, checking a deployed UI). Reads are free; every state-mutating action (click/fill/type/submit/upload/eval/download) is mechanically HELD for human confirmation by the Tachyon launcher — it does not run silently and the gate cannot be turned off. Needs a host Chrome/Chromium.
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

Before the first browse in a session, run the preflight. The bundled script lives in the materialized skill dir,
so use the path for your runtime (run from the workspace root):

```sh
sh .claude/skills/agent-browser/scripts/doctor.sh     # claude
sh .agents/skills/agent-browser/scripts/doctor.sh     # codex
```

It delegates to the CLI's own `AB doctor` — a real check of the binary, Chrome detection, AND a headless launch
test (you can also just run `AB doctor` directly). If it prints `BROWSER_RUNTIME_MISSING`, **stop** and surface
the remediation it gives (install Chrome, or `AB install --with-deps` to fetch a pinned Chrome-for-Testing). Do
not attempt to browse until doctor passes — a missing browser must never look like a successful empty read.

## Step 1 — the read loop (the core)

```sh
AB --session "$SESSION" open https://example.com     # navigate
AB --session "$SESSION" snapshot -i                   # accessibility tree + @eN refs (what's on the page)
AB --session "$SESSION" screenshot out.png            # visual capture
AB --session "$SESSION" get text @e5                  # extract a specific element's text
```

`snapshot -i` is your primary "what is on this page" call. Read, screenshot, and extract freely on ordinary
pages — that is the read-first contract. For the **full** command surface (network capture, React inspection,
diffing, PDF, tabs, …), the binary's built-in help is the authoritative, version-matched reference:

```sh
AB --help            # all commands
AB snapshot --help   # one command's flags
```

(`AB skills get core` is NOT available for this provisioned binary — the skill content ships only with an npm
install, not the standalone binary. Use `--help`.)

## Sessions — pick ONE name and reuse it for the whole task

Each `--session` gets its own daemon + Chrome. **Critical:** every Tachyon shell call is a separate process, so a
per-process value like `$$` would give `open` and `snapshot` *different* sessions — the snapshot would not see the
page you opened. Choose **one fixed session string at the start of the task** and pass that exact literal to every
command. Use the Tachyon agent id when available, else a fixed task label:

```sh
SESSION="tachyon-${TACHYON_AGENT_ID:-myTaskLabel}"   # decide once; reuse verbatim every call
AB --session "$SESSION" open https://example.com
AB --session "$SESSION" snapshot -i                   # same SESSION → same browser
```

Set an idle timeout so abandoned daemons self-close, and clean up explicitly when done:

```sh
export AGENT_BROWSER_IDLE_TIMEOUT_MS=300000   # 5 min
AB --session "$SESSION" close                 # or: AB --session "$SESSION" quit
```

## Reading auth-gated content (the headline capability)

The agent **never handles credentials**. A human logs in once; the agent reuses the saved session headlessly.

0. **Prepare the store (once).** Create the credential-class dir with tight perms and confirm it is git-ignored —
   these files are equivalent to a saved password and must never be committed:

   ```sh
   mkdir -p .tachyon/browser-state && chmod 700 .tachyon/browser-state
   git check-ignore -q .tachyon/browser-state || echo "WARNING: .tachyon/browser-state is NOT gitignored — add it before saving any session."
   ```

1. **Human headed login (once per host).** A human opens a **headed** browser in a **dedicated login session**,
   logs in, and saves the state:

   ```sh
   AB --session login-<host> --headed --profile "$PWD/.tachyon/browser-state/<host>-profile" open https://<host>/login
   # ↑ human logs in in the window that opens, then:
   AB --session login-<host> state save "$PWD/.tachyon/browser-state/<host>.json"
   ```

2. **Agent reuses it headlessly:**

   ```sh
   AB --session "$SESSION" state load "$PWD/.tachyon/browser-state/<host>.json"
   AB --session "$SESSION" open https://<host>/protected
   ```

   Prefer `--session <name> --restore` with `--restore-check-url`/`--restore-check-text` so a stale session is
   detected before you trust it.

- State files live **only** under `.tachyon/browser-state/` — credential-class (cookies + tokens = a password).
  Encrypt at rest by exporting `AGENT_BROWSER_ENCRYPTION_KEY` (a 64-hex key) before save/load.
- **Never** point `--profile` at the human's real Chrome profile; use an isolated path under
  `.tachyon/browser-state/` only.
- **Expiry:** if a previously-working authenticated nav now returns 401/403 or redirects to a login page, the
  session expired. Do **not** silently retry — remove the stale state file and ask the human to log in again.

## Form-driving — writes are MECHANICALLY held for confirmation (v2)

Reads (navigate, `snapshot`, `screenshot`, `get text/html`) are free. The **common state-mutating** actions —
`click`, `fill`, `type`, `press`, `select`, `check`, `upload`, `drag`, `eval`, `download`, and more — are **held**
for confirmation: Tachyon's launcher force-enables agent-browser's action confirmation (you do **not** set it, and
you **cannot** turn it off — the `--confirm-actions`/`--action-policy`/`--config` flags and the `mcp`/`batch`
subcommands are refused, and the action-policy/config env vars are scrubbed). A held write does NOT run
immediately; it returns:

```json
{ "success": true, "data": { "action": "click", "confirmation_required": true, "confirmation_id": "r580423" } }
```

**The contract (do this exactly):**
1. Issue the write (e.g. `AB --session "$SESSION" --json click @e7`).
2. If the result is `confirmation_required`, the action is **pending, not done**. **Surface the pending action +
   its `confirmation_id` to the human and STOP** — describe what it will do ("submit the login form on
   staging.example.com").
3. **Do NOT confirm it yourself.** A human approves out of band with `AB confirm <id>` (or rejects with
   `AB deny <id>`); a pending confirmation **auto-denies after 60s**. Only after a human confirm does the write
   run — then re-`snapshot` to verify the effect.

> Honesty (read this): this is a **mechanical hold + a cooperative human-approval protocol**, NOT an airtight
> sandbox. Two limits: (a) the held categories are a best-effort list — a rare/renamed mutator could run ungated
> (treat ANY write as needing the confirm protocol, not just the listed ones); (b) a same-user agent with a shell
> could self-`confirm`, the same residual Tachyon documents for any provisioned tool. The contract above is what
> makes the human the approver — follow it, and never self-confirm.

**Prefer staging, and restrict where you can write.** Before a form-driving task, scope navigation to the target
host so a write can't wander onto a sensitive domain:

```sh
export AGENT_BROWSER_ALLOWED_DOMAINS="staging.example.com,localhost"
```

**Keep an action trail.** Append each write's `--json` result (action, target, url, outcome) to a gitignored log
so what the agent did on the web is auditable:

```sh
AB --session "$SESSION" --json click @e7 | tee -a .tachyon/browser-actions.log
```

**Still get explicit human go-ahead** before extracting from an **authenticated** page or acting on a
**sensitive** domain (admin/banking/destructive) — the held-write gate covers the click, not your judgment about
where to point it.

## Cross-references

- The browser binary is provisioned + hash-validated per Tachyon's tool-provisioning model; you only ever reach
  it through `.tachyon/bin/_tachyon-tool`.
- `AB --help` (and `AB <command> --help`) is the authoritative, version-matched command reference for the
  installed binary. `AB doctor` is the full environment + launch self-check.

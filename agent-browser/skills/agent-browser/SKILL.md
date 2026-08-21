---
name: agent-browser
description: Drive a real Chrome browser to inspect pages, take screenshots, extract web content (including from pages behind a login), and drive forms with the pinned, checksum-verified agent-browser CLI. Use for visual inspection, rendered-page extraction, auth-gated content, form filling, or deployed-UI checks. Reads are free. Most writes run immediately; the shipped exact upload/download tokens hold only those actions. Get human approval before every write. allowedDomains is a human-owned global workspace mode that agents cannot widen; on pinned 0.34 it cannot be combined with saved-state replay. Needs host Chrome/Chromium.
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

Before the first browse in a session, run the preflight:

```sh
AB doctor
```

That is the full check — binary, Chrome detection, AND a headless launch test. (A thin wrapper ships at
`<this-skill-dir>/scripts/doctor.sh` if you want the same thing with a friendlier failure message; it just
delegates to `AB doctor`. `<this-skill-dir>` is the directory this SKILL.md was loaded from — your runtime tells
you where it materialized it. Do **not** hardcode `.claude/skills/…`, `.agents/skills/…` or `.tachyon/plugins/…`:
an agent working in its own git worktree has none of those directories.)

If it prints `BROWSER_RUNTIME_MISSING`, **stop** and surface
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

The agent **never handles credentials**. A human logs in once; the agent can reuse saved state headlessly — but
on 0.34 this is a **workspace-mode choice**, not a per-session option.

**Before using `state load`, `--state`, or `--restore`, ask the human to check Tachyon's Plugins → Config.** If
`allowedDomains` is present, stop: 0.34 refuses saved-state replay because restored state can replay origins
before the allowlist verifies them. Tachyon force-feeds that one human-owned config to every invocation and
blocks agents from overriding it, so changing the mode affects the whole workspace.

Default to keeping `allowedDomains`. Use saved-state replay only after the human explicitly removes
`allowedDomains` in Plugins → Config and accepts that every invocation using this plugin config loses the
mechanical host boundary. If the task requires both persisted authentication and an allowlist, stop and report
that 0.34 cannot provide both; do not bypass the refusal or silently discard either restraint.

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

## Form-driving — get approval before every write

Reads (navigate, `snapshot`, `screenshot`, `get text/html`) are free. Most writes — `click`, `fill`, `type`,
`press`, `select`, `check`, `drag`, and `eval` — execute when issued against the real page. The shipped exact
`upload` and `download` tokens hold those two protocol actions for confirmation. Do not treat that narrow hold
as a general write gate: get the human's go-ahead before every write.

> Why this section changed (plugin v3): the CLI has a `confirmActions` feature and Tachyon does force-feed the
> human-owned config to it. On pinned CLI **0.34.0**, matching uses exact protocol action names. The shipped
> `upload` and `download` tokens hold; the shipped `eval` token does not hold JavaScript evaluation because that
> protocol action is named `evaluate`. Keeping `eval` rather than enabling that gate is an explicit owner
> decision dated 2026-08-21. `all` and documentation-category names are not a general gate.

**The contract (do this exactly):**

1. **Before the first write of a task, ask the human.** Name the host, the page, and what the write will do
   ("fill the login form on staging.example.com and submit it"). Wait for an explicit go-ahead. A write is
   irreversible from your side unless the exact action is one of the two held tokens; never assume a hold will
   appear.
2. **Read before you write.** `snapshot -i` first, so the `@eN` ref you act on is the element you think it is.
3. **Keep an action trail.** Append each write's `--json` result (action, target, url, outcome) to a gitignored
   log so what the agent did on the web is auditable:

   ```sh
   AB --session "$SESSION" --json click @e7 | tee -a .tachyon/browser-actions.log
   ```
4. **Re-`snapshot` after every write** and report the actual effect — never assume the write did what you meant.

### The restraint that IS mechanical — `allowedDomains`

The human-owned config can pin the set of hosts the browser may reach. That one **is honoured** by 0.34.0 — a
navigation outside it fails with `Domain '<host>' is not in the allowed domains list`. Tachyon feeds that config
with a forced `--config` and blocks your ability to widen it: `--allowed-domains` is refused and
`AGENT_BROWSER_ALLOWED_DOMAINS` is stripped from your environment. So this is a real boundary, not a suggestion.

You cannot set it. **Ask the human to** — before a form-driving task, ask them to add the scope to the plugin
config via Tachyon's **Plugins → Config** editor:

```json
{ "confirmActions": "eval,upload,download", "allowedDomains": ["staging.example.com", "localhost"] }
```

(`confirmActions` is kept with the owner's chosen tokens. It holds only exact `upload` and `download`; do not
read its presence as a general write gate.)

This setting is the **global workspace mode**. While `allowedDomains` is present, 0.34 refuses `state load`,
`--state`, and `--restore` for every session. Only the human can switch modes in Plugins → Config, and removing
the setting removes the host boundary from every invocation using that config. Never ask for a session-local
exception: Tachyon deliberately prevents one.

**Prefer staging.** And still get explicit human go-ahead before extracting from an **authenticated** page or
acting on a **sensitive** domain (admin/banking/destructive) — `allowedDomains` bounds *where* you can act, never
*what* the action does once you are there.

## Cross-references

- The browser binary is provisioned + hash-validated per Tachyon's tool-provisioning model; you only ever reach
  it through `.tachyon/bin/_tachyon-tool`.
- `AB --help` (and `AB <command> --help`) is the authoritative, version-matched command reference for the
  installed binary. `AB doctor` is the full environment + launch self-check.

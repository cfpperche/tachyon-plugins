---
name: agent-browser
description: Drive a real Chrome browser to inspect pages, take screenshots, extract web content (including from pages behind a login), and drive forms with the agent-browser CLI. Use for visual inspection, rendered-page extraction, auth-gated content, form filling, or deployed-UI checks. Reads are free. Most writes run immediately; the shipped exact upload/download tokens hold only those actions. Get human approval before every write. Honour whatever config the project sets — never widen it. Needs agent-browser and host Chrome/Chromium.
license: MIT
---

# agent-browser — eyes + hands on the web

This skill drives the **agent-browser** CLI (a native Chrome-over-CDP binary the operator installs — see the
plugin README). You act on pages **by intent** against an accessibility snapshot with stable `@eN` element refs —
not brittle CSS selectors.

## Invocation

Call the CLI from `PATH`:

```sh
agent-browser <args...>
```

For brevity below, `AB` means `agent-browser` (e.g. `AB open https://example.com`). Run from the workspace root.

**If the project ships a browser config, use it and do not override it.** Pass `--config <file>` (or set
`AGENT_BROWSER_CONFIG`) when the project has one — this plugin ships an example at
`config/agent-browser.json`. Tachyon used to force one config onto every invocation and strip the flags that
could widen it; it no longer does. The restraint is now the project's to set and yours to respect: never pass
`--allowed-domains`, `--action-policy` or `--confirm-actions` to loosen what the human configured, and say so
plainly if a task seems to need that.

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
the remediation it gives (install Chrome, or `AB install --with-deps` to fetch a Chrome-for-Testing). Do
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

(`AB skills get core` exists only on the npm install, not on a standalone release binary. Use `--help`.)

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

The agent **never handles credentials**. A human logs in once; the agent can reuse saved state headlessly.

**Before using `state load`, `--state`, or `--restore`, check the config the project is using.** If it sets
`allowedDomains`, stop and ask: the CLI refuses saved-state replay under an allowlist, because restored state can
replay origins before the allowlist verifies them. That refusal is the CLI's, and it is a good one — report it
rather than working around it.

If the task needs both persisted authentication and an allowlist, say that the CLI cannot give both and let the
human choose. Dropping `allowedDomains` to get replay is **the human's call, never yours** — and it is a real
loss, so name it when you report.

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

> Why this section reads the way it does: the CLI has a `confirmActions` feature, and matching uses exact
> protocol action names. `upload` and `download` hold those two actions; `eval` does **not** hold JavaScript
> evaluation, because that protocol action is named `evaluate`. `all` and documentation-category names are not a
> general gate. Tachyon no longer forces a config onto the CLI — whether any of this is switched on is the
> project's choice, which makes it more important, not less, that you never assume a gate is there.

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

- The CLI comes from `PATH` (`AGENT_BROWSER_BIN` overrides). Tachyon names it in the manifest's `requires`; the
  operator installs it.
- `AB --help` (and `AB <command> --help`) is the authoritative, version-matched command reference for the
  installed binary. `AB doctor` is the full environment + launch self-check.

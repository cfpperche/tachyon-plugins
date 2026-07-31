---
name: dep-audit
description: On-demand detector for known-vulnerable INSTALLED dependencies, across whatever ecosystems a repo has (npm/pnpm/yarn/bun, PyPI, Go, crates, Packagist, RubyGems, Maven/Gradle, NuGet). Use when the user wants to check whether locked dependencies have published CVEs/advisories ("scan for vulnerable deps", "audit dependencies", "any known CVEs in our packages?", "vuln check before release"). Wraps osv-scanner, which Tachyon provisions as a pinned, checksum-verified binary and the skill invokes through the plugin-scoped launcher. Reports + proposes upgrades; never auto-fixes, never gates install or commit. Flags - [path] --json --exit-code --severity <low|moderate|high|critical>.
argument-hint: "[path] [--json] [--exit-code] [--severity <low|moderate|high|critical>]"
license: MIT
---

# dep-audit — known-vulnerability detector

Thin wrapper over `scripts/audit.sh`, which runs the provisioned `osv-scanner` through the Tachyon launcher and
shapes its output. The script is the engine; this skill decides when to run it and how to surface the result.

## When to run

Run on demand when the user asks to check dependency vulnerabilities, or proactively before a release / when
reviewing a PR that bumps dependencies. **Do not** wire this into a commit or install gate — it is detection +
proposal only. CVEs appear independently of your commits, so gating every commit is noise.

## What to do

1. **Parse `$ARGUMENTS`** — pass them straight through to the script. All are optional:
   - `[path]` — directory to scan (default: repo root `.`).
   - `--json` — structured output (for wrappers/tests; shape-only, not a wire contract).
   - `--exit-code` — map result status to a non-zero exit (`findings`=1, `unavailable`=2, `failed`=3) for
     consumer-owned CI. Omit for the default advisory behavior (always exit 0).
   - `--severity <low|moderate|high|critical>` — report only findings at or above this floor.

2. **Invoke the script.** It ships inside this skill, so run it from **this skill's own directory**:
   ```bash
   bash "<this-skill-dir>"/scripts/audit.sh $ARGUMENTS
   ```
   > `<this-skill-dir>` is the directory this SKILL.md was loaded from — your runtime tells you where it
   > materialized it (Claude prints it as *Base directory for this skill*; Codex uses the bundled skill path).
   > Do **not** hardcode `.claude/skills/…`, `.agents/skills/…` or `.tachyon/plugins/…` — an agent working in
   > its own git worktree has none of those directories.

   The script itself is runtime-neutral; it resolves osv-scanner via the launcher regardless of which runtime it
   was materialized into.

3. **Surface the result** — relay the script's report. The first line is `dep-audit: status=<clean|findings|unavailable|failed>`:
   - **`clean`** — say so plainly, naming the ecosystems scanned.
   - **`findings`** — summarise per finding: package@version, severity, advisory id/CVE, fixed version, and whether
     it's a direct or transitive dependency. For fixable direct deps, **propose** the upgrade target — do NOT edit
     any manifest/lockfile yourself.
   - **`unavailable`** — osv-scanner is not provisioned (the launcher is absent). Relay the hint to sync/reinstall
     the plugin so Tachyon fetches the pinned binary; a fresh clone rehydrates it. Do not treat this as "clean".
   - **`failed`** — the engine errored. Relay the diagnostic; suggest re-running the raw command.
   - **`skipped/unsupported` lockfiles** — always relay these (e.g. a legacy binary `bun.lockb` that needs
     migrating to text `bun.lock`); a partially-covered scan is not a clean one.

4. **Source-completeness caveat** — when reporting `clean`, frame it honestly: "no known-vulnerable dependencies
   found *by osv-scanner*", not "no vulnerabilities exist". Independent scanners overlap only ~60–65%.

## Remediation discipline

The capacity proposes; the human disposes. Never run `osv-scanner fix --apply`, `npm audit fix`, `bun audit fix`,
or edit a manifest/lockfile as part of this skill. If the user wants the upgrade applied, that is a separate,
explicit action they confirm.

## Notes

- `jq` is required on the host (the script parses osv-scanner's JSON with it). It is not provisioned; install it
  via your package manager if absent.
- A recurring cadence is out of scope — to run this periodically, wire it into your CI or a scheduled job that
  invokes the script.

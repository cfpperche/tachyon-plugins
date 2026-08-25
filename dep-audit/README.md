# dep-audit

**On-demand OSV vulnerability audit for dependency lockfiles**, powered by
[osv-scanner](https://github.com/google/osv-scanner). It scans a repo's INSTALLED dependencies for known
CVEs/advisories and **reports + proposes upgrades** — it never auto-fixes, never edits a manifest/lockfile, and
**never gates install or commit**.

This is the first **skill-primary** plugin that combines two capabilities: a `skills` payload (the `/dep-audit`
command + its engine script). The engine, `osv-scanner`, is NOT shipped and NOT downloaded by Tachyon:
the manifest names it in `requires` and the operator installs it.

## Install

Via the Tachyon **Plugins View** → *Add by source*, with a pinned git ref:

```
github:cfpperche/tachyon-plugins@<ref>#path=dep-audit
```

Installing the plugin materializes the skill. It does **not** install the engine.

## Requirements

Two tools must be on your `PATH`. Tachyon names them in the manifest's `requires` and installs neither.

### `osv-scanner` — the engine

- **brew** — `brew install osv-scanner`
- **go** — `go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest`
- **release binary** — https://github.com/google/osv-scanner/releases (no distro packages it)

### `jq` — the script parses the engine's JSON with it

- **apt** — `sudo apt-get install -y jq` · **dnf** — `sudo dnf install -y jq` · **pacman** — `sudo pacman -S --noconfirm jq` · **brew** — `brew install jq`

> Without `osv-scanner` the skill reports `unavailable`, never `clean`. That distinction is deliberate: a scanner
> that did not run has found nothing, and "found nothing" must never read as "there is nothing".

## Use

Run the skill on demand:

```
/dep-audit [path] [--json] [--exit-code] [--severity <low|moderate|high|critical>]
```

- `[path]` — directory to scan (default: repo root).
- `--json` — structured output (shape-only; not a versioned wire contract).
- `--exit-code` — map status → process exit (`clean=0 findings=1 unavailable=2 failed=3`) for CI. **Without it the
  process always exits 0** (advisory family — never a gate).
- `--severity` — report only findings at or above the floor.

### Result statuses

| status | meaning |
|---|---|
| `clean` | osv-scanner ran; no known-vulnerable deps in its corpus |
| `findings` | osv-scanner ran; ≥1 known-vulnerable dep (with proposed fixes for fixable direct deps) |
| `unavailable` | osv-scanner is **not on PATH** — install it; **not** "clean", nothing was scanned |
| `failed` | the engine ran but errored / produced unparseable output |

## Ecosystem / lockfile coverage

Detection is osv-scanner's; the table below is what this plugin expects to be scanned. **An unsupported or
unrecognised lockfile is surfaced as "not scanned", never folded into `clean`.**

| Ecosystem | Lockfiles |
|---|---|
| npm | `package-lock.json`, `npm-shrinkwrap.json` |
| pnpm | `pnpm-lock.yaml` |
| Yarn | `yarn.lock` |
| Bun | `bun.lock` (text). A legacy binary `bun.lockb` is **not** parsed → "migrate to text lockfile" |
| Python | `requirements.txt`, `poetry.lock`, `Pipfile.lock` |
| Go | `go.mod`, `go.sum` |
| Rust | `Cargo.lock` |
| PHP | `composer.lock` |
| Ruby | `Gemfile.lock` |
| Maven/Gradle | `gradle.lockfile` |
| NuGet | `packages.lock.json` |

Coverage is "what the pinned osv-scanner version detects", **not** "all vulnerabilities known anywhere" —
independent scanners overlap only ~60–65%.

## Advisory-only, by design

dep-audit deliberately ships **no gate**. CVEs are published independently of your commits, so blocking every
commit on a vuln scan is noise — that is why this is on-demand. If your team wants a release/CI gate, wire it
yourself; the engine already speaks exit codes:

```sh
# in CI — fail the job on a high+ finding. In a plain CHECKOUT the installer wrote the
# skill per-runtime (.claude/skills, .agents/skills, or .grok/skills), so resolve it runtime-agnostically.
# (An AGENT does not use this form — it runs the script from its own skill dir; see SKILL.md.)
ROOT="$(git rev-parse --show-toplevel)"
for d in .agents/skills .claude/skills .grok/skills; do
  S="$ROOT/$d/dep-audit/scripts/audit.sh"; [ -f "$S" ] && break
done
bash "$S" --exit-code --severity high || exit 1
```

…or call the engine directly in your own git-hook:

```sh
osv-scanner scan --recursive .
```

## Remediation discipline

The plugin **proposes**; the human disposes. It never runs `osv-scanner fix --apply`, `npm/bun audit fix`, or edits
a manifest/lockfile. Applying an upgrade is always a separate, explicit action you confirm.

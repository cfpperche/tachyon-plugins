# diagram — deterministic technical diagrams (Tachyon plugin)

A Tachyon marketplace plugin that compiles a **Mermaid** source into a tracked **SVG/PNG/PDF** asset, **locally and
free**. It renders via the [Mermaid CLI](https://github.com/mermaid-js/mermaid-cli) (`mmdc`) in a **system headless
Chrome** — no bundled browser, no paid lane, no API key.

The diagram counterpart of a local utility: a real, reproducible asset file from a text spec. Not organic/photo
imagery, not motion, not custom visual-design craft.

## Dependencies

- **A system browser** — declared as an **external tool** with candidate names `google-chrome` /
  `google-chrome-stable` / `chromium` / `chromium-browser` (Tachyon spec 289 multi-name detection). Detected
  on PATH. A missing browser is reported as `unavailable` with the install line for your platform (see Requirements).
- **Node / `npx`** — assumed present (Tachyon already runs on Node). `mmdc` is acquired at a **pinned exact version**
  via `npx -p @mermaid-js/mermaid-cli@<pinned> mmdc` with `PUPPETEER_SKIP_DOWNLOAD=1` (reuse the system browser) and
  `npm_config_ignore_scripts=true` (block npm lifecycle scripts).

### A note on trust (honest about the npx lane)

Unlike Tachyon's pinned+checksummed tools/data, `mmdc` is fetched from **npm at first run** — a **lower-trust,
non-engine-checksummed** acquisition. The only integrity anchor is the **exact pinned version**. This is a deliberate
recorded tradeoff (a correct npm-package provisioner — full transitive-lockfile integrity, lifecycle policy, native
modules, offline cache — is a separate engine product, disproportionate for one plugin). Each run records the package,
version, `acquisition:npx`, and `engine_checksummed:false` to `.tachyon/diagram-runs.jsonl`. First run needs network;
later runs reuse the npx cache (offline is best-effort, not guaranteed).

## Install

Install through the Tachyon Plugins view. On install you'll see the **browser** external tool as present/missing
(with the candidate set disclosed). A missing browser gets an **Install in terminal** button. The plugin installs
regardless — a render with no browser degrades to **validation-only** (the source is kept), never a dead artifact.

## Usage

```
bash "<this-skill-dir>"/scripts/diagram.sh \
  "flowchart TD
   A[Start] --> B{Decision}
   B -->|yes| C[Do it]
   B -->|no| D[Skip]" --format svg --out assets/diagrams
```

- **`<source>`** — a `.mmd` file path or inline Mermaid text.
- **`--format`** — `svg` (default) / `png` / `pdf`.
- **`--out <dir>`** — output dir (default `assets/diagrams/`); the `.mmd` source is written alongside.
- **`--theme`** — a Mermaid built-in theme (`default` / `dark` / `forest` / `neutral`).

## Fail-closed behavior

- No browser → `status=unavailable` (source validated + kept; assisted-install offered on the card).
- No `npx` → `status=unavailable` (install Node, re-run).
- Bad Mermaid / mmdc syntax error → `status=error` (source kept).
- The asset is never empty; the `.mmd` source is never lost; the skill never `git add`s and **warns** if the output
  path is git-ignored.

## License / attribution

mermaid-cli + Mermaid are MIT-licensed. The renderer is fetched from npm at the pinned version; nothing is bundled in
git.

## Requirements

Tachyon no longer installs external tools; the manifest only **names** them in `requires`.
Install these before using the plugin:

### `chrome`

- **apt** — `sudo apt-get install -y chromium`
- **dnf** — `sudo dnf install -y chromium`
- **pacman** — `sudo pacman -S --noconfirm chromium`
- **brew** — `brew install --cask google-chrome`
- Install a Chromium-based browser so mmdc can render headlessly — Debian `sudo apt install chromium`; Ubuntu ships it as a snap (`sudo snap install chromium`); Fedora `sudo dnf install chromium`; Arch `sudo pacman -S chromium`; macOS `brew install --cask google-chrome`. Any of google-chrome / google-chrome-stable / chromium / chromium-browser on a system PATH works.

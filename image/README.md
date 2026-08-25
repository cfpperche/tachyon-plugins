# image — paid AI image generation (Tachyon plugin)

A Tachyon marketplace plugin that generates images via the **fal.ai** REST API. **PAID** — each call costs money and
**prints the estimated cost before it fires**. The first **API-plugin** (env-key + paid REST; no provisioned
binary/data).

## Requirements

- **`FAL_KEY`** (from https://fal.ai) — a SECRET, read first from the process env and then from
  `.tachyon/secrets.env`; Tachyon never stores/echoes it. Missing → `unavailable`.
- **curl** + **jq** — declared external tools (detected + assist-installed via the card); the fal client uses the
  TRUSTED resolved paths, never bare names.

## Tiers

| `--tier` | model | ~cost | output |
|---|---|---|---|
| `draft` | fal-ai/flux/schnell | ~$0.003 | jpg → gitignored `assets/generated/mockups/` |
| `brand-text` | fal-ai/gpt-image-2 | ~$0.04+ | png → tracked `assets/brand/` |
| `brand-photo` | fal-ai/imagen4/ultra | ~$0.06 | png → tracked `assets/brand/` |

## Usage

```
bash "<this-skill-dir>"/scripts/image.sh \
  --tier draft --aspect landscape --name hero "a calm mountain lake at dawn"
```

`--aspect square|landscape|portrait`; `--name <slug>`.

To avoid exporting the key in every shell, create a local workspace file:

```
mkdir -p .tachyon
printf 'FAL_KEY=your_fal_key_here\n' > .tachyon/secrets.env
chmod 600 .tachyon/secrets.env
```

An already-exported `FAL_KEY` wins over the file. The file is parsed as data; it is never sourced.

## Cost / paid posture

Every call prints `estimated: $X.XXX …` BEFORE the paid request. Run it ONLY when the user wants image generation /
has authorized the spend. Each run records `{tier,model,cost_estimate_usd,output,paid:true}` to
`.tachyon/image-runs.jsonl`.

## Not

Free/local imagery (paid only); music/SFX (the sound plugin); technical diagrams (the diagram plugin).

## Requirements

Tachyon no longer installs external tools; the manifest only **names** them in `requires`.
Install these before using the plugin:

### `curl`

- **apt** — `sudo apt-get install -y curl`
- **dnf** — `sudo dnf install -y curl`
- **pacman** — `sudo pacman -S --noconfirm curl`
- **brew** — `brew install curl`
- Install curl (the HTTP client for the fal.ai REST API) — Debian/Ubuntu `sudo apt install curl`; Fedora `sudo dnf install curl`; Arch `sudo pacman -S curl`; macOS ships it (or `brew install curl`).

### `jq`

- **apt** — `sudo apt-get install -y jq`
- **dnf** — `sudo dnf install -y jq`
- **pacman** — `sudo pacman -S --noconfirm jq`
- **brew** — `brew install jq`
- Install jq (builds the request body + extracts the image URL) — Debian/Ubuntu `sudo apt install jq`; Fedora `sudo dnf install jq`; Arch `sudo pacman -S jq`; macOS `brew install jq`.

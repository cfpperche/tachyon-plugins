# video — paid generative AI video (Tachyon plugin)

A Tachyon marketplace plugin that generates organic/photoreal **video** via the **fal.ai** queue REST API. **PAID +
ASYNC** — a clip costs **$0.50–$3** and takes ~5 min, so it is **fire-and-forget** (submit → poll). The generative
half of the split video capability; its deterministic/free sibling is the `hyperframes` plugin.

## Requirements

- **`FAL_KEY`** (https://fal.ai) — a SECRET; read first from env and then from `.tachyon/secrets.env`, never
  stored/echoed (passed via a 0600 `curl --config`).
- **curl** + **jq** — named in `requires`, resolved from PATH (`VIDEO_CURL` / `VIDEO_JQ` override).
- A source **image** (https URL) for the image→video tiers (`draft`/`standard`) — e.g. an `image`-plugin output you
  host publicly. `premium` (Veo) can be text-only.

## Tiers (the bundled oracle `references/video-tiers.json`)

| `--tier` | model | ~price | max | input |
|---|---|---|---|---|
| draft | fal-ai/wan/v2.2-a14b/image-to-video | ~$0.10/s | 5s | image→video |
| standard | fal-ai/kling-video/v3/pro/image-to-video | ~$0.112/s | 15s | image→video |
| premium | fal-ai/veo/3.1 | ≤$0.60/s | 8s | text or image (audio) — endpoint UNVERIFIED |

## Usage

```
V="<this-skill-dir>"/scripts/video.sh
bash "$V" submit "a slow drone shot over a misty forest at dawn" --tier draft --image-url https://example.com/still.jpg --duration 4 --confirm-cost-usd 0.40
bash "$V" poll --all
```

To avoid exporting the key in every shell, create a local workspace file:

```
mkdir -p .tachyon
printf 'FAL_KEY=your_fal_key_here\n' > .tachyon/secrets.env
chmod 600 .tachyon/secrets.env
```

An already-exported `FAL_KEY` wins over the file. The file is parsed as data; it is never sourced.

## Cost / paid posture

`submit` prints the estimate and **refuses without `--confirm-cost-usd ≥ estimate`** (every submit; before any
network). Duration is bounded by the tier max. An ambiguous submit is never auto-retried (run `poll --all` first).
A real overrun is recorded-and-warned (the job is already billed). Each event lands in the gitignored ledger.

## Not

Deterministic/free code video (the `hyperframes` plugin); music/SFX (`sound`); still images (`image`).

## Verify before relying

Tier endpoints/prices are representative + dated; the `premium` (Veo) endpoint/body is UNVERIFIED. Confirm via fal
docs before a real premium call — the oracle is the single edit point.

## Requirements

Tachyon no longer installs external tools; the manifest only **names** them in `requires`.
Install these before using the plugin:

### `curl`

- **apt** — `sudo apt-get install -y curl`
- **dnf** — `sudo dnf install -y curl`
- **pacman** — `sudo pacman -S --noconfirm curl`
- **brew** — `brew install curl`
- Install curl (the HTTP client for the fal.ai queue REST API) — apt/dnf/pacman `curl`; macOS ships it.

### `jq`

- **apt** — `sudo apt-get install -y jq`
- **dnf** — `sudo dnf install -y jq`
- **pacman** — `sudo pacman -S --noconfirm jq`
- **brew** — `brew install jq`
- Install jq (reads the tier oracle + builds the body + parses the queue responses) — apt/dnf/pacman `jq`; macOS `brew install jq`.

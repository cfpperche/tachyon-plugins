# sound — paid music + SFX generation (Tachyon plugin)

A Tachyon marketplace plugin that generates **music + sound effects** via the **fal.ai** REST API. **PAID** — cost =
price × duration, **printed before the call**, with a **hard `--confirm-cost-usd` gate above $0.25**. An API-plugin
(env-key + paid REST; no provisioned binary/data). The sibling of the image plugin; NOT the local-first audio plugin.

## Requirements

- **`FAL_KEY`** (https://fal.ai) — a SECRET; read first from the env and then from `.tachyon/secrets.env`, never
  stored/echoed. Missing → `unavailable`.
- **curl** + **jq** — declared external tools (the fal client uses the TRUSTED resolved paths). **ffmpeg** optional
  (mp3; wav works without).

## Tiers (the bundled oracle `references/sound-tiers.json` — the single edit point)

| `--kind` | `--tier` | model | ~price |
|---|---|---|---|
| music | standard | cassetteai/music-generator | ~$0.02/min |
| music | premium | fal-ai/elevenlabs/music | ~$0.80/min (endpoint UNVERIFIED) |
| sfx | sfx | fal-ai/elevenlabs/sound-effects/v2 | ~$0.002/sec |

## Usage

```
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/sound/skills/sound/scripts/sound.sh" \
  "warm lo-fi loop, mellow" --kind music --duration 20 --out assets/sound
# above $0.25 → re-run with --confirm-cost-usd <amount> (only if the spend was authorized)
```

To avoid exporting the key in every shell, create a local workspace file:

```
mkdir -p .tachyon
printf 'FAL_KEY=your_fal_key_here\n' > .tachyon/secrets.env
chmod 600 .tachyon/secrets.env
```

An already-exported `FAL_KEY` wins over the file. The file is parsed as data; it is never sourced.

## Cost / paid posture

Cost is printed before any network call; above the oracle threshold ($0.25) the run is **refused** until
`--confirm-cost-usd` is passed (never auto-supply it). Each run records
`{kind,tier,model,cost_estimate_usd,duration_s,output,paid:true}` to `.tachyon/sound-runs.jsonl`.

## Not

Spoken voice/narration (the audio plugin); free/local audio (paid only).

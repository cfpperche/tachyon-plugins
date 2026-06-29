---
name: sound
description: PAID creative-audio generation (music + sound effects) via the fal.ai REST API (needs a FAL_KEY env var). Use when the user wants generated music or SFX from a text prompt — UI sounds, a soundtrack, a sting, an ambient bed. Music (--kind music) at standard ~$0.02/min or premium ~$0.80/min, or SFX (--kind sfx) ~$0.002/sec. Cost = price x duration; prints the estimate before it fires and HARD-refuses above $0.25 without --confirm-cost-usd. PAID — only run when the user authorized the spend. NOT speech or voiceover (the audio plugin), NOT free or local.
---

# sound — paid music + SFX generation (fal.ai)

Generate music or sound effects from a prompt via the fal.ai REST API. **PAID** — cost = price × duration, **printed
before the call**, with a **hard `--confirm-cost-usd` gate above $0.25**. Model/body/price come from a bundled tier
oracle; curl + jq are resolved through Tachyon's shims; `FAL_KEY` is read from the env and never stored.

## Invocation

```
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/sound/skills/sound/scripts/sound.sh" "<prompt>" --kind music|sfx [--tier <name>] [--duration <sec>] [--format mp3|wav] [--out <dir>] [--confirm-cost-usd <n>]
```

- **`--kind`** (REQUIRED) — `music` (tiers `standard`/`premium`) or `sfx`.
- **`--duration`** — seconds (defaults per tier). **`--confirm-cost-usd`** — required when the estimate exceeds $0.25.
- **`--format`** mp3 (default; needs ffmpeg) / wav. **`--out`** (default `assets/sound/`).

## Cost discipline (PAID — read this)

Each call **spends money**. The skill prints `estimated: $X …`; above $0.25 it **refuses without `--confirm-cost-usd`
and makes NO network call**. Pass `--confirm-cost-usd <amount>` **only when the user explicitly authorized that
spend** — never auto-supply it.

## Fail-closed

- `FAL_KEY` unset → `unavailable`. curl/jq missing → `unavailable` (card offers an assisted install).
- Over-threshold without confirm → refused before any call. Non-200 fal / no audio URL → `error`.

## When NOT to use

- Spoken voice / narration → the audio plugin. Free/local audio doesn't exist here (paid only).

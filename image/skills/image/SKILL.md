---
name: image
description: PAID AI image generation via the fal.ai REST API (needs a FAL_KEY env var). Use when the user wants a generated image — a mockup, brand asset, hero, or illustration from a prompt. Three tiers: draft (FLUX schnell, ~$0.003, throwaway), brand-text (gpt-image-2, ~$0.04+, crisp typography), brand-photo (Imagen 4 Ultra, ~$0.06, photo-real). Every call PRINTS the estimated cost before it fires. PAID — only run when the user wants to spend on image generation. NOT free/local, NOT music/SFX (sound plugin), NOT technical diagrams (diagram plugin).
---

# image — paid AI image generation (fal.ai)

Generate an image from a prompt via the fal.ai REST API. **PAID** — each call costs money and **prints the estimated
cost before it fires**. curl + jq are resolved through Tachyon's shims (trusted paths); `FAL_KEY` is read from the
env and never stored.

## Invocation

```
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/image/skills/image/scripts/image.sh" --tier draft|brand-text|brand-photo [--aspect square|landscape|portrait] [--name <slug>] "<prompt>"
```

- **`--tier`** (REQUIRED) — `draft` (~$0.003, jpg, gitignored mockup) · `brand-text` (~$0.04+, png, tracked) ·
  `brand-photo` (~$0.06, png, tracked).
- **`--aspect`** — `square` (default) / `landscape` / `portrait`.
- **`--name`** — output slug (allowlisted); auto-derived from the prompt otherwise.

## Cost discipline (PAID — read this)

This capability **spends money**. The skill prints `estimated: $X.XXX for <model> …` and then fires a paid call.
**Only run it when the user has asked for image generation / authorized the spend** — do not generate speculatively.
The output path is mechanical: `draft` → gitignored `assets/generated/mockups/`, `brand-*` → tracked `assets/brand/`.

## Fail-closed

- `FAL_KEY` unset → `unavailable` (set it; Tachyon never stores it).
- curl/jq missing → `unavailable` (the card offers an assisted install).
- `--tier` omitted → the 3-option error. A non-200 fal response / no image URL → `error`.

## When NOT to use

- Free/local imagery doesn't exist here (this is paid). Music/SFX → the sound plugin. Technical diagrams → diagram.

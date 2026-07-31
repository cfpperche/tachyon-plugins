---
name: image
description: PAID AI image generation via the fal.ai REST API (needs FAL_KEY in env or .tachyon/secrets.env). Use when the user wants a generated image — a mockup, brand asset, hero, or illustration from a prompt. Three tiers — draft (FLUX schnell, ~$0.003, throwaway), brand-text (gpt-image-2, ~$0.04+, crisp typography), brand-photo (Imagen 4 Ultra, ~$0.06, photo-real). Every call PRINTS the estimated cost before it fires. PAID — only run when the user wants to spend on image generation. NOT free or local, NOT music or SFX (the sound plugin), NOT technical diagrams (the diagram plugin).
---

# image — paid AI image generation (fal.ai)

Generate an image from a prompt via the fal.ai REST API. **PAID** — each call costs money and **prints the estimated
cost before it fires**. curl + jq are resolved through Tachyon's shims (trusted paths); `FAL_KEY` is read from the
env or `.tachyon/secrets.env` and never stored or echoed.

## Invocation

```
bash "<this-skill-dir>"/scripts/image.sh --tier draft|brand-text|brand-photo [--aspect square|landscape|portrait] [--name <slug>] "<prompt>"
```

> `<this-skill-dir>` is the directory this SKILL.md was loaded from — your runtime tells you where it
> materialized it (Claude prints it as *Base directory for this skill*; Codex uses the bundled skill path).
> Resolve it and run from anywhere in the workspace. Do **not** hardcode `.claude/skills/…`, `.agents/skills/…`
> or `.tachyon/plugins/…` — an agent working in its own git worktree has none of those directories.

- **`--tier`** (REQUIRED) — `draft` (~$0.003, jpg, gitignored mockup) · `brand-text` (~$0.04+, png, tracked) ·
  `brand-photo` (~$0.06, png, tracked).
- **`--aspect`** — `square` (default) / `landscape` / `portrait`.
- **`--name`** — output slug (allowlisted); auto-derived from the prompt otherwise.

## Cost discipline (PAID — read this)

This capability **spends money**. The skill prints `estimated: $X.XXX for <model> …` and then fires a paid call.
**Only run it when the user has asked for image generation / authorized the spend** — do not generate speculatively.
The output path is mechanical: `draft` → gitignored `assets/generated/mockups/`, `brand-*` → tracked `assets/brand/`.

## FAL_KEY

Preferred persistent setup:

```
mkdir -p .tachyon
printf 'FAL_KEY=your_fal_key_here\n' > .tachyon/secrets.env
chmod 600 .tachyon/secrets.env
```

An exported `FAL_KEY` wins over the file. The file is parsed as data and is never sourced.

## Fail-closed

- `FAL_KEY` missing from env and `.tachyon/secrets.env` → `unavailable` (set it; Tachyon never stores it).
- curl/jq missing → `unavailable` (the card offers an assisted install).
- `--tier` omitted → the 3-option error. A non-200 fal response / no image URL → `error`.

## When NOT to use

- Free/local imagery doesn't exist here (this is paid). Music/SFX → the sound plugin. Technical diagrams → diagram.

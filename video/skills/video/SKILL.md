---
name: video
description: PAID generative AI video via the fal.ai queue REST API (needs a FAL_KEY env var). Use when the user wants organic/photoreal motion (Wan/Kling/Veo class) generated from a prompt — plus a source image for the image-to-video tiers (draft/standard). ASYNC and fire-and-forget — submit queues a ~5-min paid job, poll reaps it. A clip costs $0.50 to $3, so a HARD --confirm-cost-usd gate is required on every submit. PAID — only run when the user authorized the spend. NOT deterministic free code video (the hyperframes plugin), NOT music or SFX (the sound plugin) or still images (the image plugin).
---

# video — paid generative AI video (fal.ai, async)

Generate organic/photoreal motion via fal.ai video models through the **queue** REST API. **PAID + ASYNC** — a clip
costs **$0.50–$3** and takes ~5 min, so it is **fire-and-forget**: `submit` queues the job and returns a `request_id`;
`poll` reaps it later. curl + jq are resolved trusted through the shims; `FAL_KEY` is read from env and never stored.

## Invocation

```
V="$(git rev-parse --show-toplevel)/.tachyon/plugins/video/skills/video/scripts/video.sh"
bash "$V" submit "<prompt>" --tier draft|standard|premium [--duration <sec>] [--image-url <https-url>] [--name <slug>] --confirm-cost-usd <max>
bash "$V" poll --all          # reap finished jobs (status → download)
bash "$V" poll --id <request_id>
```

- **`--tier`** — `draft` (Wan ~$0.10/s, ≤5s, image→video) · `standard` (Kling ~$0.112/s, ≤15s, image→video) ·
  `premium` (Veo ≤$0.60/s worst-case, ≤8s, text or image, audio).
- **`--image-url`** — REQUIRED https URL for the image→video tiers (draft/standard); the source image (e.g. an
  `image`-plugin output you hosted publicly). premium can be text-only.
- **`--duration`** — seconds, bounded by the tier max. **`--confirm-cost-usd`** — REQUIRED, must cover the estimate.

## Cost discipline (PAID — read this)

Every `submit` **spends money**. The skill prints `estimated: $X …` and **refuses without `--confirm-cost-usd ≥ the
estimate`**, before any network call. Pass `--confirm-cost-usd <amount>` **only when the user explicitly authorized
that spend** — never auto-supply it. An ambiguous submit failure is **never auto-retried** (it could double-bill) —
run `poll --all` to check before re-submitting.

## Async / the ledger

`submit` records the job to a gitignored ledger (`.tachyon/video-jobs/ledger.jsonl`) and returns immediately — it
does NOT block. Run `poll` (a separate call) to reap: a completed job downloads to `assets/generated/videos/` (gitignore
`assets/generated/`); in-progress jobs stay pending; `poll` is locked against concurrent runs.

## Fail-closed

- `FAL_KEY` unset → `unavailable`. curl/jq missing → `unavailable`. Below the cost ceiling / over the duration max →
  refused before any call. A missing/non-https `--image-url` on an image→video tier → refused.

## When NOT to use

- Deterministic/free code video → the `hyperframes` plugin. Music/SFX → `sound`. Still images → `image`.

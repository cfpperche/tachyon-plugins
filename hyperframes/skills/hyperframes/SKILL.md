---
name: hyperframes
description: Deterministic LOCAL video from code — render an HTML/CSS/JS composition to MP4 via the HyperFrames CLI (npx, pinned, Apache-2.0), free with no inference cost. Use when the user wants a structured motion-graphics video (a product demo, changelog/release clip, animated explainer, killer-flow walkthrough) defined as code — git-tracked source, regenerable MP4. Needs Node 22+ and ffmpeg; HyperFrames manages its own headless Chromium. NOT generative/paid AI video (the separate video plugin), NOT a still image (the diagram or image plugins).
---

# hyperframes — deterministic video from code

Render an HTML/CSS/JS composition to an **MP4**, locally and free, via the HeyGen **HyperFrames** CLI (run pinned via
`npx`, never installed globally). Zero inference cost — the composition source is git-tracked and the MP4 is
regenerable. ffmpeg is resolved trusted through Tachyon's shim; HyperFrames manages its own headless Chromium.

## Invocation

```
HF="$(git rev-parse --show-toplevel)/.tachyon/plugins/hyperframes/skills/hyperframes/scripts/hyperframes.sh"
bash "$HF" doctor                      # check Node 22+/ffmpeg/browser
bash "$HF" scaffold my-clip            # copy the minimal composition → assets/video/compositions/my-clip/
# edit assets/video/compositions/my-clip/index.html (see references/authoring.md)
bash "$HF" render my-clip [--quality draft|high] [--name <out-slug>]
```

- **scaffold `<slug>`** — copies the owned minimal template (we never run `hyperframes init`).
- **render `<slug>`** — renders the composition → `assets/generated/videos/<date>-<slug>.mp4` (draft by default).

## What it does (and the contract it upholds)

1. Verifies **Node 22+** + **npx**; resolves **ffmpeg** via `_tachyon-external hyperframes ffmpeg` (trusted path).
2. Renders from inside the composition dir via `npx hyperframes@<pin> render` (its bundled Chromium + your ffmpeg).
3. Writes the MP4 to a contained, gitignored generated dir; the `.mmd`-equivalent (your `index.html` + project) stays
   tracked. Never `git add`s.

## Authoring

The scaffolded `index.html` is a minimal composition (a title + subtitle with a GSAP entrance). For real authoring
(animations, components, captions, media), see `references/authoring.md` and HeyGen's official HyperFrames skills/docs
(`heygen-com/hyperframes`, Apache-2.0) — this plugin is a thin Tachyon-native wrapper, not a re-implementation of
their authoring system.

## Fail-closed behavior

- No npx / Node < 22 → `unavailable` (install Node 22+). No ffmpeg → `unavailable` (the card offers an assisted install).
- On Linux ARM with no browser, HyperFrames would try a system package install → the wrapper **refuses** (install a
  browser yourself). A render error → `error` with the log tail; never an empty MP4.

## Trust note

The engine is fetched from npm at the pinned version via `npx` (a lower-trust, non-engine-checksummed lane); the
first render also downloads a headless Chromium into HyperFrames' own cache. Provenance records the version + lane in
`.tachyon/hyperframes-runs.jsonl`.

## When NOT to use

- Generative/organic AI video → the separate `video` plugin (paid). A still image → `diagram` (technical) / `image`
  (organic, paid). Recorded-footage editing — out of scope.

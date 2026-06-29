# Authoring HyperFrames compositions (thin reference)

This plugin ships a **minimal** composition template and depends on the HyperFrames CLI engine. It is deliberately
NOT a full authoring system — for depth, use HeyGen's official HyperFrames skills + docs
(`github.com/heygen-com/hyperframes`, Apache-2.0; also distributed as a Claude/Codex/Cursor plugin).

## The composition shape (what `scaffold` gives you)

A composition is a small project dir (`assets/video/compositions/<slug>/`):

- **`index.html`** — the composition. The root carries the timeline contract:
  `<div id="root" data-composition-id="main" data-start="0" data-duration="5" data-width="1920" data-height="1080">`.
  Each animated element is a `.clip` with `data-start` / `data-duration` / `data-track-index`. Animate with GSAP
  (CDN-loaded in the template; vendor it locally for hermetic renders).
- **`hyperframes.json`** — engine config (schema + registry + paths).
- **`package.json`** — pins the engine (`hyperframes@<pin>`); the plugin runs the CLI via `npx`, not these scripts.

## Editing tips

- Keep the canvas at the declared `data-width`/`data-height` (default 1920×1080).
- Prefer an auto-resolved font family (e.g. `"Roboto"`) over a system stack — HyperFrames injects it at render; a
  system stack triggers a lint warning.
- `data-duration` on the root sets the clip length (seconds).
- Iterate with `--quality draft`; deliver with `--quality high`.

## Validate before you render

HyperFrames has `lint` / `validate` / `inspect` (run via `npx hyperframes@<pin> <cmd>` from the composition dir):
`lint` catches missing `data-composition-id` / overlapping tracks; `validate` loads it in headless Chrome and reports
runtime/contrast issues; `inspect` checks text overflow + motion intent.

## Go deeper (official)

Animations, reusable components, embedded captions, media (images/audio/video), TTS, background removal, and the
Studio timeline editor (`npx hyperframes@<pin> preview`) are all in HeyGen's official skills — install their plugin or
read `heygen-com/hyperframes/skills/` for the full authoring surface.

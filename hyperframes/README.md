# hyperframes — deterministic video from code (Tachyon plugin)

A Tachyon marketplace plugin that renders an **HTML/CSS/JS composition → MP4**, **locally and free**, via the HeyGen
**HyperFrames** CLI (run pinned through `npx`, never installed globally). Zero inference cost; the composition source
is git-tracked and the MP4 is regenerable. The deterministic half of "video" — its paid/generative sibling is the
separate `video` plugin.

## Requirements

- **Node 22+** + **npx** — the ambient runner (`hyperframes@<pin>` via `npx`, a lower-trust pinned lane).
- **ffmpeg** — a declared external tool (detected + assist-installed via the card); HyperFrames needs it for MP4 encode.
- **headless Chromium** — **managed by HyperFrames itself** (Puppeteer; downloaded into its own cache on first
  render, with a system-Chrome fallback). NOT a Tachyon-declared dependency.

## Usage

```
HF="$(git rev-parse --show-toplevel)/.tachyon/plugins/hyperframes/skills/hyperframes/scripts/hyperframes.sh"
bash "$HF" doctor
bash "$HF" scaffold my-clip
# edit assets/video/compositions/my-clip/index.html
bash "$HF" render my-clip --quality draft
```

Output → `assets/generated/videos/<date>-<slug>.mp4` (regenerable; gitignore `assets/generated/`). Source stays
tracked. The script never `git add`s and never runs `hyperframes init`.

## Authoring

A minimal template ships here; for depth use HeyGen's official HyperFrames skills/docs (see `CREDITS.md`). This plugin
is a thin Tachyon-native wrapper, not a re-implementation of their authoring system.

## Fail-closed

- No npx / Node < 22 / no ffmpeg → `unavailable`. On Linux ARM with no browser, the wrapper refuses (it will not let
  HyperFrames run a system package install). A render failure → `error`; never an empty MP4.

## License / attribution

HyperFrames (`heygen-com/hyperframes`) is **Apache-2.0**. The minimal composition template here is adapted from the
HyperFrames composition shape; see `CREDITS.md`. The engine is fetched from npm at the pinned version via `npx` —
nothing is bundled in git.

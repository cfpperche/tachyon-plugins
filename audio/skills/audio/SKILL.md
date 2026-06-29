---
name: audio
description: Local-first text-to-speech. Use when the user wants to turn text into spoken audio ("read this aloud", "make an mp3 of this", "narrate this", "voiceover", "TTS this"). Runs fully on-device via piper (default, self-contained, a pinned checksummed voice) or kokoro (--engine kokoro; higher quality + multilingual incl pt-BR, needs espeak-ng). Both run through uv's tool runner (uvx); the plugin detects + assist-installs the system tools it needs. NOT music/SFX, NOT voice cloning, NOT remote/paid TTS.
---

# audio — local-first text-to-speech

Turn text into a spoken `wav`/`mp3`, fully on-device. System tools (espeak-ng, ffmpeg) + the pinned voice are resolved
through Tachyon's shims (never off the bare PATH); the `uvx` RUNNER is resolved on the ambient PATH (like `npx` — uv
installs to a user dir). The skill never downloads the pinned voice itself.

## Invocation

```
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/audio/skills/audio/scripts/audio.sh" "<text>" [--engine piper|kokoro] [--voice <name>] [--lang <code>] [--format wav|mp3] [--out <dir>]
```

- **`<text>`** — the text to speak (quote it).
- **`--engine`** — `piper` (default; self-contained, the pinned voice) or `kokoro` (higher quality + multilingual; needs espeak-ng).
- **`--voice`** — a voice name (allowlisted). Defaults per engine+lang. The pinned default is piper `en_US-lessac-medium`.
- **`--lang`** — a language code (kokoro maps it, e.g. `pt` → Brazilian; piper picks a locale default).
- **`--format`** — `wav` (default) or `mp3` (needs ffmpeg; falls back to wav if absent).
- **`--out <dir>`** — output dir (default `assets/audio/`), contained to the workspace.

## What it does (and the contract it upholds)

1. Resolves **uvx** (uv's runner) on the ambient PATH (like a runner — uv installs to a user dir; missing → `unavailable`).
2. **piper:** for the default voice, resolves the pinned `.onnx` + `.onnx.json` via `_tachyon-data audio voice-onnx`
   / `voice-config` (hash-verified, read-only) and materializes them as the sibling pair piper expects; a non-default
   voice is fetched on-demand from HF (unpinned, allowlisted name). Acquires piper via pinned `uvx --from piper-tts==X`.
3. **kokoro:** presence-gates **espeak-ng** via `_tachyon-external audio espeak-ng`, then runs the shipped
   `audio-kokoro.py` via pinned `uvx --with kokoro==X --with soundfile==X python …`.
4. Encodes to `wav`/`mp3` (mp3 via ffmpeg resolved through the shim; falls back to wav).

## Fail-closed behavior (never a fake audio file)

- Missing **uvx** → `unavailable` (assisted install on the card, or the official uv installer).
- kokoro without **espeak-ng** → `unavailable` (distinct hint; suggests `--engine piper`).
- Missing shim / unprovisioned voice → `unavailable` (reinstall / Rehydrate).
- A present engine erroring → `error` with the underlying log. Never writes an empty file.

## Trust note (honest about the uvx lane)

The Python engines (piper-tts / kokoro / soundfile) are fetched from PyPI via **pinned-version `uvx`** — a
lower-trust, NOT engine-checksummed lane (the pinned version is the only anchor; first run needs network). The
DEFAULT piper voice IS engine-checksummed (a 284 data artifact, offline after install). Run provenance under
`.tachyon/audio-runs.jsonl` records `acquisition:uvx` + `engine_checksummed:false`.

## When NOT to use

- Speech-to-text (that's transcribe — the reverse). Music/SFX (that's sound). Voice cloning. Remote/paid TTS
  (a separate integration plugin).

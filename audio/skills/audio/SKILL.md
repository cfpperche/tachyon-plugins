---
name: audio
description: Local-first text-to-speech. Use when the user wants to turn text into spoken audio ("read this aloud", "make an mp3 of this", "narrate this", "voiceover", "TTS this"). Runs fully on-device via piper (default, self-contained, a pinned checksummed voice) or kokoro (--engine kokoro; higher quality + multilingual incl pt-BR, needs espeak-ng). Both run through uv's tool runner (uvx); the plugin detects + assist-installs the system tools it needs. NOT music/SFX, NOT voice cloning, NOT remote/paid TTS.
---

# audio — local-first text-to-speech

Turn text into a spoken `wav`/`mp3`, fully on-device. `espeak-ng`, `ffmpeg` and the `uvx` runner come from PATH; the
default voice is fetched once from a pinned revision, checksum-verified, and cached under the repo. Nothing is ever
used unverified, and a missing piece is always `unavailable` with the command that fixes it.

## Invocation

```
bash "<this-skill-dir>"/scripts/audio.sh "<text>" [--engine piper|kokoro] [--voice <name>] [--lang <code>] [--format wav|mp3] [--out <dir>]
```

> `<this-skill-dir>` is the directory this SKILL.md was loaded from — your runtime tells you where it
> materialized it (Claude prints it as *Base directory for this skill*; Codex uses the bundled skill path).
> Resolve it and run from anywhere in the workspace. Do **not** hardcode `.claude/skills/…`, `.agents/skills/…`
> or `.tachyon/plugins/…` — an agent working in its own git worktree has none of those directories.

- **`<text>`** — the text to speak (quote it).
- **`--engine`** — `piper` (default; self-contained, the pinned voice) or `kokoro` (higher quality + multilingual; needs espeak-ng).
- **`--voice`** — a voice name (allowlisted). Defaults per engine+lang. The pinned default is piper `en_US-lessac-medium`.
- **`--lang`** — a language code (kokoro maps it, e.g. `pt` → Brazilian; piper picks a locale default).
- **`--format`** — `wav` (default) or `mp3` (needs ffmpeg; falls back to wav if absent).
- **`--out <dir>`** — output dir (default `assets/audio/`), contained to the workspace.

## What it does (and the contract it upholds)

1. Resolves **uvx** (uv's runner) on the ambient PATH (like a runner — uv installs to a user dir; missing → `unavailable`).
2. **piper:** the default voice's `.onnx` + `.onnx.json` are fetched once from a PINNED HF revision, each verified
   against its sha256 before use, and cached at `<repo>/.tachyon/models/audio/` (resolved via
   `git rev-parse --git-common-dir`, so a linked worktree shares the authority's cache). A non-default voice is
   fetched on-demand, unpinned, as it always was. Acquires piper via pinned `uvx --from piper-tts==X`.
3. **kokoro:** presence-gates **espeak-ng** on PATH (`AUDIO_ESPEAK` overrides), then runs the shipped
   `audio-kokoro.py` via pinned `uvx --with kokoro==X --with soundfile==X python …`.
4. Encodes to `wav`/`mp3` (mp3 via `ffmpeg` from PATH; falls back to wav).

## Fail-closed behavior (never a fake audio file)

- Missing **uvx** → `unavailable` (install uv: https://docs.astral.sh/uv/getting-started/installation/).
- kokoro without **espeak-ng** → `unavailable` (distinct hint; suggests `--engine piper`).
- A voice download that fails, or whose sha256 does not match the pin → `unavailable`, naming the mismatch. A
  partial download is written to a `.part` file and never moved into the cache.
- A present engine erroring → `error` with the underlying log. Never writes an empty file.

## Trust note (honest about the uvx lane)

The Python engines (piper-tts / kokoro / soundfile) are fetched from PyPI via **pinned-version `uvx`** — a
lower-trust, NOT engine-checksummed lane (the pinned version is the only anchor; first run needs network). The
DEFAULT piper voice IS engine-checksummed (a 284 data artifact, offline after install). Run provenance under
`.tachyon/audio-runs.jsonl` records `acquisition:uvx` + `engine_checksummed:false`.

## When NOT to use

- Speech-to-text (that's transcribe — the reverse). Music/SFX (that's sound). Voice cloning. Remote/paid TTS
  (a separate integration plugin).

---
name: transcribe
description: Local-first speech-to-text. Use when the user wants to turn an audio OR video file into a transcript ("transcribe this call", "get the text from this recording", "subtitles for this screencast", "what was said in this mp3/wav/m4a/mp4"). Runs fully on-device via whisper.cpp — the audio never leaves the machine. Needs whisper-cli + ffmpeg on PATH and a ggml model file the operator downloads once (the README carries the URL and its sha256). NOT text-to-speech, NOT remote/paid transcription, NOT live/streaming.
---

# transcribe — local speech-to-text

Turn an audio or video file into a transcript, fully on-device. The skill NEVER downloads anything: the tools come
from PATH and the model is a file the operator placed. When either is missing it says `unavailable` and names the
exact command to fix it — it never guesses and never produces a transcript it did not earn.

## Invocation

```
bash "<this-skill-dir>"/scripts/transcribe.sh <audio-or-video-file> [--format txt|srt|vtt|json] [--language <code|auto>]
```

> `<this-skill-dir>` is the directory this SKILL.md was loaded from — your runtime tells you where it
> materialized it (Claude prints it as *Base directory for this skill*; Codex uses the bundled skill path).
> Resolve it and run from anywhere in the workspace. Do **not** hardcode `.claude/skills/…`, `.agents/skills/…`
> or `.tachyon/plugins/…` — an agent working in its own git worktree has none of those directories.

- **`<file>`** — any audio/video ffmpeg can decode (mp3, m4a, wav, mp4, mov, …).
- **`--format`** — `txt` (default), `srt`, `vtt`, or `json`.
- **`--language`** — a language code, or `auto` (default; the model is multilingual).

The transcript is printed to stdout.

## What it does (and the contract it upholds)

1. Resolves the **ggml model** at `<repo>/.tachyon/models/transcribe/ggml-base.bin`, or wherever `TRANSCRIBE_MODEL`
   points. The repo root comes from `git rev-parse --git-common-dir`, so a linked worktree finds the model in the
   authority checkout instead of needing its own copy.
2. Resolves **whisper-cli** and **ffmpeg** from PATH (`TRANSCRIBE_WHISPER` / `TRANSCRIBE_FFMPEG` override), checked
   with `command -v` before use.
3. Transcodes the input to 16 kHz mono PCM wav with ffmpeg (whisper.cpp's required format), in a private temp dir.
4. Runs `whisper-cli` on the model + wav, writing the requested format.

## Fail-closed behavior (never a fake transcript)

- A missing model / missing whisper-cli / missing ffmpeg → **`unavailable`**, printing the exact command to fix it
  (the model's download URL plus the sha256 to verify it against; or the package-manager line for the tool).
- ffmpeg decode failure or a whisper-cli non-zero exit → **`failed`** with the underlying error.
- It never writes an empty transcript.

## When NOT to use

- Text-to-speech (this is the reverse). Remote/paid transcription. Live/streaming transcription. Speaker diarization.

---
name: transcribe
description: Local-first speech-to-text. Use when the user wants to turn an audio OR video file into a transcript ("transcribe this call", "get the text from this recording", "subtitles for this screencast", "what was said in this mp3/wav/m4a/mp4"). Runs fully on-device via whisper.cpp — the audio never leaves the machine. Needs the whisper-cli + ffmpeg system tools (the plugin detects them and offers an assisted install) and the pinned ggml model (Tachyon provisions it, checksum-verified, read-only). NOT text-to-speech, NOT remote/paid transcription, NOT live/streaming.
---

# transcribe — local speech-to-text

Turn an audio or video file into a transcript, fully on-device. Everything is resolved through Tachyon's shims — the
skill NEVER downloads the model itself and NEVER runs a tool off the bare PATH.

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

1. Resolves the **pinned ggml model** via `.tachyon/bin/_tachyon-data transcribe model` (hash-verified at resolve;
   read-only; never re-downloaded by the skill).
2. Resolves **whisper-cli** and **ffmpeg** via `.tachyon/bin/_tachyon-external transcribe <name>` (trusted absolute
   paths; never the bare PATH — spoof-resistant).
3. Transcodes the input to 16 kHz mono PCM wav with ffmpeg (whisper.cpp's required format), in a private temp dir.
4. Runs `whisper-cli` on the model + wav, writing the requested format.

## Fail-closed behavior (never a fake transcript)

- A missing shim / unprovisioned model / missing whisper-cli / missing ffmpeg → **`unavailable`** with how to fix
  (reinstall/Rehydrate, or install the tool — the plugin's install drawer offers an assisted install where your OS
  prompts for your password; Tachyon never sees it).
- ffmpeg decode failure or a whisper-cli non-zero exit → **`failed`** with the underlying error.
- It never writes an empty transcript.

## When NOT to use

- Text-to-speech (this is the reverse). Remote/paid transcription. Live/streaming transcription. Speaker diarization.

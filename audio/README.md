# audio — local-first text-to-speech (Tachyon plugin)

A Tachyon marketplace plugin that turns text into spoken **wav/mp3**, **fully on-device**. Two engines:

- **piper** (default) — a pinned, checksummed voice model the plugin fetches once (63 MB) and caches at
  `<repo>/.tachyon/models/audio/`; offline afterwards.
- **kokoro** (`--engine kokoro`) — higher quality + multilingual (incl pt-BR); needs **espeak-ng** on PATH plus a
  shipped Python helper; the kokoro weights are fetched by the package on first run.

## Requirements

Tachyon installs none of these — the manifest names them in `requires` and the operator provides them.

- **`ffmpeg`** (mp3 output; wav works without it) — `sudo apt-get install -y ffmpeg` · `brew install ffmpeg`
- **`espeak-ng`** (kokoro only) — `sudo apt-get install -y espeak-ng` · `brew install espeak-ng` · `AUDIO_ESPEAK` overrides
- **`uvx`** (uv's tool runner) — https://docs.astral.sh/uv/getting-started/installation/

The default voice is **not** a requirement: the plugin downloads it on first run from a pinned Hugging Face revision
and refuses to use it unless the sha256 matches. Tachyon used to do that verification; the plugin does it now, and
prints the mismatch rather than continuing.

Both engines run through **`uvx`** (uv's tool runner — the Python analog of `npx`); the Python packages (piper-tts,
kokoro, soundfile) are acquired at **pinned exact versions**. **Local-only** — there is no paid/remote lane (an
ElevenLabs integration is a separate plugin).

## Dependencies

- **uvx (uv)** — the Python tool RUNNER, resolved on the ambient PATH (like `npx`; uv installs to a user dir such as
  `~/.local/bin`, so it is NOT a trust-gated external tool). Install: `curl -LsSf https://astral.sh/uv/install.sh | sh`
  or `brew install uv`. Missing → a clear `unavailable`.
- **espeak-ng** — external tool (detected + assist-installed via the card); only for `--engine kokoro`; apt/dnf/pacman/brew.
- **ffmpeg** — external tool; only for `mp3` output (wav needs none); apt/dnf/pacman/brew.

### Trust note (the uvx lane)

The Python engines are fetched from PyPI via pinned-version `uvx` — a **lower-trust, non-engine-checksummed** lane
(the pinned version is the only anchor; first run needs network). The **default piper voice IS** engine-checksummed
(a pinned `{url,sha256}` 284 data artifact, immutable HF revision). Each run records
`acquisition:uvx` + `engine_checksummed:false` to `.tachyon/audio-runs.jsonl`.

## Usage

```
bash "<this-skill-dir>"/scripts/audio.sh \
  "Hello from a local voice." --engine piper --format wav --out assets/audio
```

- `--engine piper|kokoro`, `--voice <name>` (allowlisted), `--lang <code>`, `--format wav|mp3`, `--out <dir>`.

## Fail-closed

- Missing uvx → `unavailable`; kokoro w/o espeak-ng → `unavailable` (suggests piper); a present engine erroring →
  `error`. Never an empty audio file. The output is contained to the workspace, never auto-staged, and warns on a
  git-ignored path.

## License / attribution

piper (rhasspy/piper-tts), kokoro, soundfile are their authors' (MIT/Apache as upstream). The default piper voice is
from rhasspy/piper-voices, pinned to an immutable revision. Engines are fetched from PyPI at the pinned versions;
nothing is bundled in git.

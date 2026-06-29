# audio — local-first text-to-speech (Tachyon plugin)

A Tachyon marketplace plugin that turns text into spoken **wav/mp3**, **fully on-device**. Two engines:

- **piper** (default) — self-contained; a pinned, checksummed voice model (a 284 data artifact, offline after install).
- **kokoro** (`--engine kokoro`) — higher quality + multilingual (incl pt-BR); needs **espeak-ng** + a shipped Python
  shim; the kokoro weights are fetched by the package on first run.

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
bash "$(git rev-parse --show-toplevel)/.tachyon/plugins/audio/skills/audio/scripts/audio.sh" \
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

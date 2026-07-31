# transcribe — local speech-to-text (Tachyon plugin)

A Tachyon marketplace plugin that turns an audio/video file into a transcript, **fully on-device** via
[whisper.cpp](https://github.com/ggerganov/whisper.cpp). The audio content never leaves the machine; only the model
weights are fetched once (pinned + checksum-verified).

It is the first plugin to use **both** of Tachyon's newest engine capabilities together:

- a **data artifact** — the `ggml` model file, pinned by `{url, sha256}`, installed read-only + content-addressed,
  resolved via the `_tachyon-data` shim;
- **external tools** — `whisper-cli` + `ffmpeg`, detected spoof-resistantly, assist-installable (your OS prompts for
  the password in a visible terminal — Tachyon never handles it), resolved via the `_tachyon-external` shim.

## Install

Install through the Tachyon Plugins view. On install you'll see:

- the **model** (a ~148 MB download + store acknowledgement — read-only, never executed);
- **whisper-cli** and **ffmpeg** as present/missing. For a missing tool, an **Install in terminal** button runs your
  system package manager in a visible terminal where your OS prompts for your password.

### Getting whisper-cli

- **macOS:** `brew install whisper-cpp` (installs `whisper-cli`) — offered as an assisted install.
- **Debian sid:** `sudo apt install whisper.cpp-tools` (ships `/usr/bin/whisper-cli`) — manual (package naming is
  distro-specific).
- **Otherwise:** build from [whisper.cpp](https://github.com/ggerganov/whisper.cpp); the binary must be named
  `whisper-cli`.

`ffmpeg` is offered as an assisted install on apt/dnf/pacman/brew.

## Usage

```
bash "<this-skill-dir>"/scripts/transcribe.sh recording.mp3 --format srt --language auto
```

## Model provenance + attribution

- Model: `ggml-base.bin` (multilingual, ~148 MB), the whisper.cpp GGML conversion of OpenAI's Whisper `base` model.
- Pinned to an **immutable HuggingFace revision**:
  `ggerganov/whisper.cpp` @ `5359861c739e955e79d9a303bcbc70fb988958b1` →
  `resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin`,
  sha256 `60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe`.
- whisper.cpp is MIT-licensed (Georgi Gerganov); the Whisper models are from OpenAI. The model is **downloaded
  locally + pinned**, never bundled in git.

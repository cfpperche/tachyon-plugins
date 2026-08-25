# transcribe — local speech-to-text (Tachyon plugin)

A Tachyon marketplace plugin that turns an audio/video file into a transcript, **fully on-device** via
[whisper.cpp](https://github.com/ggerganov/whisper.cpp). The audio content never leaves the machine; only the model
weights are fetched once (pinned + checksum-verified).

It needs two things Tachyon does not provide, and says so plainly when either is absent.

## Requirements

### `whisper-cli` and `ffmpeg` — on PATH

- **apt** — `sudo apt install whisper.cpp` (ships `/usr/bin/whisper-cli`) and `sudo apt-get install -y ffmpeg`
- **brew** — `brew install whisper-cpp ffmpeg`
- Override with `TRANSCRIBE_WHISPER` / `TRANSCRIBE_FFMPEG` to point at a specific binary.

### The ggml model — a file you download once (147 MB)

```sh
mkdir -p .tachyon/models/transcribe
curl -L -o .tachyon/models/transcribe/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin

sha256sum .tachyon/models/transcribe/ggml-base.bin
# expected: 60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe
```

The revision in that URL is pinned and the checksum is the one this plugin was built against — **verify it**.
Tachyon used to do that verification for you; now the check is yours, which is why the expected digest is printed
here and by the script itself. Point `TRANSCRIBE_MODEL` at a ggml model you already have to use that instead.

The script resolves the repo root with `git rev-parse --git-common-dir`, so a linked worktree reads the model from
the authority checkout — one download, every worktree.

## Install

Install through the Tachyon Plugins view. On install you'll see:

- the **model** (a ~148 MB download + store acknowledgement — read-only, never executed);
- **whisper-cli** and **ffmpeg** as present/missing. For a missing tool, an **Install in terminal** button runs your
  system package manager in a visible terminal where your OS prompts for your password.

### Getting whisper-cli

- **macOS:** `brew install whisper-cpp` (installs `whisper-cli`).
- **Debian sid:** `sudo apt install whisper.cpp-tools` (ships `/usr/bin/whisper-cli`) — manual (package naming is
  distro-specific).
- **Otherwise:** build from [whisper.cpp](https://github.com/ggerganov/whisper.cpp); the binary must be named
  `whisper-cli`.

`ffmpeg` comes from your package manager: apt/dnf/pacman/brew.

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

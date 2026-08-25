#!/usr/bin/env bash
# transcribe — local speech-to-text via whisper.cpp. Transcodes the input to 16 kHz mono wav with ffmpeg, then
# runs whisper-cli. Fail-closed: distinct `unavailable` (a dependency is missing/incompatible) vs `failed` (a
# present tool errored); never writes an empty transcript.
#
# Dependencies, and who provides them: `whisper-cli` and `ffmpeg` come from PATH, and the ggml model is a file the
# OPERATOR places (see the plugin README, which carries the URL and the sha256 to verify it against). Tachyon no
# longer downloads binaries or artifacts, so this script never curls anything either — it checks, and when
# something is missing it says exactly what and how to get it.
set -euo pipefail

PLUGIN="transcribe"
FORMAT="txt"          # txt (default) | srt | vtt | json
LANG_CODE="auto"      # the model is multilingual; auto-detect by default
INPUT=""

usage() { echo "usage: transcribe <audio-or-video-file> [--format txt|srt|vtt|json] [--language <code|auto>]" >&2; }

# ── parse args (each value-flag REQUIRES a value; only one input file) ──
while [ $# -gt 0 ]; do
  case "$1" in
    --format)   [ $# -ge 2 ] || { echo "transcribe: --format requires a value" >&2; exit 64; }; FORMAT="$2"; shift 2 ;;
    --format=*) FORMAT="${1#*=}"; shift ;;
    --language)   [ $# -ge 2 ] || { echo "transcribe: --language requires a value" >&2; exit 64; }; LANG_CODE="$2"; shift 2 ;;
    --language=*) LANG_CODE="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "transcribe: unknown flag '$1'" >&2; usage; exit 64 ;;
    *) [ -z "$INPUT" ] || { echo "transcribe: only one input file is allowed" >&2; exit 64; }; INPUT="$1"; shift ;;
  esac
done

# ── validate the request BEFORE touching the filesystem ──
case "$FORMAT" in txt|srt|vtt|json) ;; *) echo "transcribe: unknown --format '$FORMAT' (txt|srt|vtt|json)" >&2; exit 64 ;; esac
[ -n "$INPUT" ] || { usage; exit 64; }
[ -f "$INPUT" ] || { echo "transcribe: failed: input file not found: $INPUT" >&2; exit 1; }

# ── the model lives under the AUTHORITY checkout, not the current one. `--git-common-dir` points into the primary
#    checkout's .git even from a linked worktree, so its parent is the authority root: one model, shared by every
#    worktree, and no copy to drift. ──
COMMON="$(git rev-parse --git-common-dir 2>/dev/null || true)"
[ -n "$COMMON" ] || { echo "transcribe: unavailable: not inside a git work tree (the model lives at <repo>/.tachyon/models/$PLUGIN)" >&2; exit 1; }
ROOT="$(cd "$(dirname "$COMMON")" && pwd -P)"
MODEL_DIR="$ROOT/.tachyon/models/$PLUGIN"
MODEL="${TRANSCRIBE_MODEL:-$MODEL_DIR/ggml-base.bin}"

# The model is the plugin's OWN asset, so the plugin fetches it — pinned revision, checksum verified before first
# use. Tachyon stopped downloading third-party artifacts; that is a statement about Tachyon, not about what a plugin
# the operator chose to install may do for itself. The pin and the digest are what the old provisioning gave, and
# they are kept here rather than traded away.
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin"
MODEL_SHA="60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"

verify_model() {
  # A partial download must never be used as a model. Verify BEFORE moving into place, and treat a missing
  # sha256 tool as a refusal rather than a pass — "could not check" is not "checked".
  local file="$1" got=""
  if command -v sha256sum >/dev/null 2>&1; then got="$(sha256sum "$file" | cut -d' ' -f1)"
  elif command -v shasum >/dev/null 2>&1;   then got="$(shasum -a 256 "$file" | cut -d' ' -f1)"
  else echo "transcribe: unavailable: no sha256sum/shasum to verify the model against its pin" >&2; return 1; fi
  [ "$got" = "$MODEL_SHA" ] || { echo "transcribe: unavailable: the downloaded model does not match its pin (got $got)" >&2; return 1; }
}

if [ ! -f "$MODEL" ]; then
  if [ -n "${TRANSCRIBE_MODEL:-}" ]; then
    echo "transcribe: unavailable: TRANSCRIBE_MODEL points at $MODEL, which does not exist" >&2
    exit 1
  fi
  command -v curl >/dev/null 2>&1 || { echo "transcribe: unavailable: curl is needed to fetch the ggml model on first run" >&2; exit 1; }
  mkdir -p -- "$MODEL_DIR" || { echo "transcribe: unavailable: cannot create $MODEL_DIR" >&2; exit 1; }
  echo "transcribe: first-run setup — fetching the pinned ggml model (147 MB, once)…" >&2
  PART="$MODEL.part.$$"
  trap 'rm -f "$PART" 2>/dev/null' EXIT
  if ! curl -fsSL -o "$PART" "$MODEL_URL"; then
    rm -f "$PART"
    echo "transcribe: unavailable: could not download the model. Fetch it by hand and re-run:" >&2
    echo "    curl -L -o \"$MODEL\" $MODEL_URL" >&2
    echo "  Or point TRANSCRIBE_MODEL at a ggml model you already have." >&2
    exit 1
  fi
  verify_model "$PART" || { rm -f "$PART"; exit 1; }
  mv -- "$PART" "$MODEL" || { rm -f "$PART"; echo "transcribe: unavailable: could not install the model at $MODEL" >&2; exit 1; }
  trap - EXIT
  echo "transcribe: model ready at $MODEL" >&2
fi

WHISPER="${TRANSCRIBE_WHISPER:-whisper-cli}"
FFMPEG="${TRANSCRIBE_FFMPEG:-ffmpeg}"
command -v "$WHISPER" >/dev/null 2>&1 || { echo "transcribe: unavailable: whisper-cli is not on PATH — Debian/Ubuntu: sudo apt install whisper.cpp; macOS: brew install whisper-cpp" >&2; exit 1; }
command -v "$FFMPEG"  >/dev/null 2>&1 || { echo "transcribe: unavailable: ffmpeg is not on PATH — apt/dnf/pacman/brew install ffmpeg" >&2; exit 1; }

# ── compatibility preflight: a stale/forked whisper-cli that exits 0 on --help but lacks the flags we use must be
#    rejected as `unavailable`, not silently `failed` at run time (codex HIGH). ──
WHISPER_HELP="$("$WHISPER" --help 2>&1 || true)"
for flag in --model --file --language "--output-${FORMAT}" --output-file; do
  case "$WHISPER_HELP" in
    *"$flag"*) ;;
    *) echo "transcribe: unavailable: this whisper-cli does not support '$flag' — install a recent whisper.cpp whisper-cli (e.g. brew install whisper-cpp)" >&2; exit 1 ;;
  esac
done

# ── private temp dir (mapped to fail-closed vocab; cleaned on exit). Always transcode → 16 kHz mono PCM wav. ──
umask 077
if ! TMPDIR_RUN="$(mktemp -d)"; then echo "transcribe: failed: could not create a temp directory" >&2; exit 1; fi
trap 'rm -rf "$TMPDIR_RUN"' EXIT
WAV="$TMPDIR_RUN/audio.wav"
if ! "$FFMPEG" -nostdin -y -i "$INPUT" -ar 16000 -ac 1 -c:a pcm_s16le "$WAV" >/dev/null 2>"$TMPDIR_RUN/ffmpeg.err"; then
  echo "transcribe: failed: ffmpeg could not decode '$INPUT':" >&2; tail -3 "$TMPDIR_RUN/ffmpeg.err" >&2; exit 1
fi

# ── run whisper-cli on the resolved model + wav. --output-<fmt> + --output-file writes <base>.<ext>. ──
OUTBASE="$TMPDIR_RUN/out"
if ! "$WHISPER" --model "$MODEL" --file "$WAV" --language "$LANG_CODE" "--output-${FORMAT}" --output-file "$OUTBASE" >/dev/null 2>"$TMPDIR_RUN/whisper.err"; then
  echo "transcribe: failed: whisper-cli errored:" >&2; tail -3 "$TMPDIR_RUN/whisper.err" >&2; exit 1
fi

OUTFILE="$OUTBASE.$FORMAT"
[ -s "$OUTFILE" ] || { echo "transcribe: failed: whisper-cli produced no transcript" >&2; exit 1; }
cat "$OUTFILE"

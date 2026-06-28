#!/usr/bin/env bash
# transcribe (spec 286) — local speech-to-text via whisper.cpp. Resolves the pinned model + the whisper-cli/ffmpeg
# system tools through Tachyon's shims (NEVER curls the model, NEVER runs an unresolved binary), transcodes the
# input to 16 kHz mono wav with ffmpeg, then runs whisper-cli. Fail-closed: distinct `unavailable` (a dependency is
# missing) vs `failed` (a present tool errored); never writes an empty transcript.
set -euo pipefail

PLUGIN="transcribe"
FORMAT="txt"          # txt (default) | srt | vtt | json
LANG_CODE="auto"      # the model is multilingual; auto-detect by default
INPUT=""

usage() { echo "usage: transcribe <audio-or-video-file> [--format txt|srt|vtt|json] [--language <code|auto>]" >&2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --format) shift; FORMAT="${1:-txt}" ;;
    --format=*) FORMAT="${1#*=}" ;;
    --language) shift; LANG_CODE="${1:-auto}" ;;
    --language=*) LANG_CODE="${1#*=}" ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "transcribe: unknown flag '$1'" >&2; usage; exit 64 ;;
    *) INPUT="$1" ;;
  esac
  shift
done

[ -n "$INPUT" ] || { usage; exit 64; }
[ -f "$INPUT" ] || { echo "transcribe: failed: input file not found: $INPUT" >&2; exit 1; }
case "$FORMAT" in txt|srt|vtt|json) ;; *) echo "transcribe: failed: unknown --format '$FORMAT' (txt|srt|vtt|json)" >&2; exit 64 ;; esac

# repo root (the shims are workspace-relative; cwd-independent — spec 272 contract).
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] || { echo "transcribe: unavailable: not inside a git work tree (the Tachyon shims live at <repo>/.tachyon/bin)" >&2; exit 1; }

DATA_SHIM="$ROOT/.tachyon/bin/_tachyon-data"
EXT_SHIM="$ROOT/.tachyon/bin/_tachyon-external"
[ -x "$DATA_SHIM" ] || { echo "transcribe: unavailable: the _tachyon-data shim is missing — reinstall the transcribe plugin (or run Rehydrate after a fresh clone)" >&2; exit 1; }
[ -x "$EXT_SHIM" ]  || { echo "transcribe: unavailable: the _tachyon-external shim is missing — reinstall the transcribe plugin (or run Rehydrate after a fresh clone)" >&2; exit 1; }

# resolve the pinned model (read-only, hash-verified at resolve time) + the system tools (trusted absolute paths).
MODEL="$("$DATA_SHIM" "$PLUGIN" model)"   || { echo "transcribe: unavailable: the ggml model is not provisioned — reinstall the transcribe plugin (or Rehydrate)" >&2; exit 1; }
WHISPER="$("$EXT_SHIM" "$PLUGIN" whisper-cli)" || { echo "transcribe: unavailable: whisper-cli is not installed — install it (the plugin's drawer offers an assisted install; or: brew install whisper-cpp)" >&2; exit 1; }
FFMPEG="$("$EXT_SHIM" "$PLUGIN" ffmpeg)"       || { echo "transcribe: unavailable: ffmpeg is not installed — install it (the plugin's drawer offers an assisted install; or: apt/dnf/brew install ffmpeg)" >&2; exit 1; }

# work in a private temp dir (cleaned on exit). Always transcode → 16 kHz mono PCM wav (avoids whisper build-variance).
TMPDIR_RUN="$(mktemp -d)"; trap 'rm -rf "$TMPDIR_RUN"' EXIT
WAV="$TMPDIR_RUN/audio.wav"
if ! "$FFMPEG" -nostdin -y -i "$INPUT" -ar 16000 -ac 1 -c:a pcm_s16le "$WAV" >/dev/null 2>"$TMPDIR_RUN/ffmpeg.err"; then
  echo "transcribe: failed: ffmpeg could not decode '$INPUT':" >&2; tail -3 "$TMPDIR_RUN/ffmpeg.err" >&2; exit 1
fi

# run whisper-cli on the resolved model + wav. --output-<fmt> + --output-file writes <base>.<ext>.
OUTBASE="$TMPDIR_RUN/out"
OUTFLAG="--output-${FORMAT}"
if ! "$WHISPER" --model "$MODEL" --file "$WAV" --language "$LANG_CODE" "$OUTFLAG" --output-file "$OUTBASE" >/dev/null 2>"$TMPDIR_RUN/whisper.err"; then
  echo "transcribe: failed: whisper-cli errored:" >&2; tail -3 "$TMPDIR_RUN/whisper.err" >&2; exit 1
fi

OUTFILE="$OUTBASE.$FORMAT"
[ -s "$OUTFILE" ] || { echo "transcribe: failed: whisper-cli produced no transcript" >&2; exit 1; }
cat "$OUTFILE"

#!/usr/bin/env bash
# audio (spec 290) — LOCAL-first text-to-speech. Two on-device engines: piper (DEFAULT, self-contained, a pinned
# checksummed voice) and kokoro (opt-in, higher quality + multilingual, needs espeak-ng). Both run through uv's tool
# runner `uvx` (acquired at PINNED package versions — a lower-trust, NON-engine-checksummed lane, the diagram-npx
# analog). espeak-ng/ffmpeg come from PATH; the pinned default voice is fetched once and checksum-verified (data
# for the default voice); the uvx RUNNER is resolved on the ambient PATH (like npx — uv installs to a user dir).
# Fail-closed: `unavailable` (a dep is missing) vs `error` (a present engine failed); never an
# empty/fake audio file. NO paid/remote lane (ElevenLabs lives in a separate integration plugin).
set -euo pipefail

PLUGIN="audio"
HERE="$(cd "$(dirname "$0")" && pwd)"

# pinned uvx package versions (spec 290 D5 — exact, never floating)
PIPER_PKG="piper-tts==1.4.2"
KOKORO_PKG="kokoro==0.9.4"
SOUNDFILE_PKG="soundfile==0.14.0"

PINNED_VOICE="en_US-lessac-medium"   # the one piper voice provisioned as a 284 data artifact (offline + checksummed)

ENGINE="piper"; VOICE=""; LANG_CODE="en"; FORMAT="wav"; OUT_DIR=""; TEXT=""

# test/override hooks (never needed in normal use)
: "${AUDIO_UVX:=}"          # force a uvx command
: "${AUDIO_FFMPEG_BIN:=}"   # force an ffmpeg path

usage() { echo "usage: audio \"<text>\" [--engine piper|kokoro] [--voice <name>] [--lang <code>] [--format wav|mp3] [--out <dir>]" >&2; }

# ── parse args (each value-flag REQUIRES a value; first positional is the text) ──
while [ $# -gt 0 ]; do
  case "$1" in
    --engine)   [ $# -ge 2 ] || { echo "audio: --engine requires a value" >&2; exit 64; }; ENGINE="$2"; shift 2 ;;
    --engine=*) ENGINE="${1#*=}"; shift ;;
    --voice)    [ $# -ge 2 ] || { echo "audio: --voice requires a value" >&2; exit 64; }; VOICE="$2"; shift 2 ;;
    --voice=*)  VOICE="${1#*=}"; shift ;;
    --lang)     [ $# -ge 2 ] || { echo "audio: --lang requires a value" >&2; exit 64; }; LANG_CODE="$2"; shift 2 ;;
    --lang=*)   LANG_CODE="${1#*=}"; shift ;;
    --format)   [ $# -ge 2 ] || { echo "audio: --format requires a value" >&2; exit 64; }; FORMAT="$2"; shift 2 ;;
    --format=*) FORMAT="${1#*=}"; shift ;;
    --out)      [ $# -ge 2 ] || { echo "audio: --out requires a value" >&2; exit 64; }; OUT_DIR="$2"; shift 2 ;;
    --out=*)    OUT_DIR="${1#*=}"; shift ;;
    -h|--help)  usage; exit 0 ;;
    -*) echo "audio: unknown flag '$1'" >&2; usage; exit 64 ;;
    *) [ -z "$TEXT" ] || { echo "audio: only one text argument is allowed (quote it)" >&2; exit 64; }; TEXT="$1"; shift ;;
  esac
done

case "$ENGINE" in piper|kokoro) ;; *) echo "audio: unknown --engine '$ENGINE' (piper|kokoro)" >&2; exit 64 ;; esac
case "$FORMAT" in wav|mp3) ;; *) echo "audio: unknown --format '$FORMAT' (wav|mp3)" >&2; exit 64 ;; esac
[ -n "$TEXT" ] || { usage; exit 64; }
# lang: a short token only (kokoro maps it; piper ignores it) — bounded, charset-safe
echo "$LANG_CODE" | grep -Eq '^[A-Za-z][A-Za-z-]{0,15}$' || { echo "audio: invalid --lang '$LANG_CODE'" >&2; exit 64; }

# ── default voice per engine + language ──
if [ -z "$VOICE" ]; then
  case "$ENGINE" in
    piper)  VOICE="$PINNED_VOICE"; case "$LANG_CODE" in pt*|br) VOICE="pt_BR-faber-medium";; esac ;;
    kokoro) VOICE="af_heart";      case "$LANG_CODE" in pt*|br) VOICE="pf_dora";; esac ;;
  esac
fi
# D4 — STRICT allowlist BEFORE any path/URL construction (no traversal via the voice name)
echo "$VOICE" | grep -Eq '^[A-Za-z0-9_-]{1,64}$' || { echo "audio: invalid --voice '$VOICE' (allowed: letters/digits/_/-, ≤64)" >&2; exit 64; }

# ── repo root. `--git-common-dir` points into the PRIMARY checkout's .git even from a linked worktree, so its
#    parent is the authority root: one voice cache, shared by every worktree, no copy to drift. ──
COMMON="$(git rev-parse --git-common-dir 2>/dev/null || true)"
[ -n "$COMMON" ] || { echo "audio: unavailable: not inside a git work tree (the voice cache lives at <repo>/.tachyon/models/$PLUGIN)" >&2; exit 1; }
ROOT="$(cd "$(dirname "$COMMON")" && pwd -P)"
VOICE_DIR="$ROOT/.tachyon/models/$PLUGIN"

# ── output dir: default assets/audio/, CONTAINED to the workspace ──
OUT_DIR="${OUT_DIR:-assets/audio}"
case "$OUT_DIR" in /*) ;; *) OUT_DIR="$ROOT/$OUT_DIR" ;; esac
mkdir -p -- "$OUT_DIR" || { echo "audio: error: cannot create output dir: $OUT_DIR" >&2; exit 1; }
OUT_REAL="$(cd "$OUT_DIR" && pwd -P)" || { echo "audio: error: bad output dir: $OUT_DIR" >&2; exit 1; }
ROOT_REAL="$(cd "$ROOT" && pwd -P)"
case "$OUT_REAL/" in "$ROOT_REAL"/*) ;; *) echo "audio: error: --out must stay inside the workspace ($ROOT_REAL); refusing '$OUT_REAL'" >&2; exit 64 ;; esac
OUT_DIR="$OUT_REAL"

sha_of() { { sha256sum 2>/dev/null || shasum -a 256 2>/dev/null; } | awk '{print $1}'; }
TEXT_SHA="$(printf '%s' "$TEXT" | sha_of)"
STEM="audio-${TEXT_SHA:0:8}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# ── provenance: one JSONL line under .tachyon/ (honest about the uvx lane) ──
PROV_DIR="$ROOT/.tachyon"; PROV="$PROV_DIR/audio-runs.jsonl"
record() {  # $1=status $2=output
  [ -d "$PROV_DIR" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -cn --arg st "$1" --arg sha "$TEXT_SHA" --arg eng "$ENGINE" --arg voice "$VOICE" --arg lang "$LANG_CODE" \
    --arg fmt "$FORMAT" --arg out "${2:-}" \
    '{status:$st, text_sha256:$sha, engine:$eng, voice:$voice, language:$lang, format:$fmt, output:$out, stayed_local:true, acquisition:"uvx", engine_checksummed:false}' >> "$PROV" 2>/dev/null || true
}

# ── resolve uvx — the AMBIENT runner (like diagram's npx), NOT a trust-gated external tool. uv almost always installs
#    to a USER dir (~/.local/bin) that the system-PATH trust model rightly rejects, so gating it there would make the
#    plugin unusable; the runner is resolved on the ambient PATH (override for tests). Missing → unavailable. ──
if [ -n "$AUDIO_UVX" ]; then UVX="$AUDIO_UVX"
elif command -v uvx >/dev/null 2>&1; then UVX="$(command -v uvx)"
else record unavailable ""; echo "audio: unavailable: uv (uvx) is not installed — install uv: 'curl -LsSf https://astral.sh/uv/install.sh | sh' (then restart your shell) or 'brew install uv'. https://docs.astral.sh/uv/" >&2; exit 1; fi

WAV="$WORK/out.wav"

if [ "$ENGINE" = "piper" ]; then
  # ── piper: a pinned default voice (284 data) copied to sibling names, or an on-demand HF fetch for other voices ──
  if [ "$VOICE" = "$PINNED_VOICE" ]; then
    # The DEFAULT voice keeps its pin: a fixed HF revision plus a sha256 for each of the two files, verified before
    # first use and cached under the authority root. That is what the old provisioning gave, kept here rather than
    # traded away — the non-default branch below is, and always was, unpinned.
    PIN_REV="e21c7de8d4eab79b902f0d61e662b3f21664b8d2"
    PIN_BASE="https://huggingface.co/rhasspy/piper-voices/resolve/$PIN_REV/en/en_US/lessac/medium/$PINNED_VOICE"
    PIN_SHA_ONNX="5efe09e69902187827af646e1a6e9d269dee769f9877d17b16b1b46eeaaf019f"
    PIN_SHA_CFG="efe19c417bed055f2d69908248c6ba650fa135bc868b0e6abb3da181dab690a0"

    sha_of() {
      if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
      elif command -v shasum >/dev/null 2>&1;   then shasum -a 256 "$1" | cut -d' ' -f1
      else echo ""; fi
    }
    fetch_pinned() {   # $1=url $2=dest $3=expected-sha $4=label
      local part="$2.part.$$" got
      command -v curl >/dev/null 2>&1 || { record unavailable ""; echo "audio: unavailable: curl is needed to fetch the default voice on first run" >&2; exit 1; }
      curl -fsSL -o "$part" "$1" || { rm -f "$part"; record unavailable ""; echo "audio: unavailable: could not download the $4 ($1)" >&2; exit 1; }
      got="$(sha_of "$part")"
      [ -n "$got" ] || { rm -f "$part"; record unavailable ""; echo "audio: unavailable: no sha256sum/shasum to verify the $4 against its pin" >&2; exit 1; }
      [ "$got" = "$3" ] || { rm -f "$part"; record unavailable ""; echo "audio: unavailable: the downloaded $4 does not match its pin (got $got)" >&2; exit 1; }
      mv -- "$part" "$2" || { rm -f "$part"; record unavailable ""; echo "audio: unavailable: could not install the $4 at $2" >&2; exit 1; }
    }

    mkdir -p -- "$VOICE_DIR" || { record unavailable ""; echo "audio: unavailable: cannot create $VOICE_DIR" >&2; exit 1; }
    ONNX="$VOICE_DIR/$PINNED_VOICE.onnx"
    CFG="$VOICE_DIR/$PINNED_VOICE.onnx.json"
    if [ ! -f "$ONNX" ] || [ ! -f "$CFG" ]; then
      echo "audio: first-run setup — fetching the pinned voice '$PINNED_VOICE' (63 MB, once)…" >&2
      [ -f "$ONNX" ] || fetch_pinned "$PIN_BASE.onnx"      "$ONNX" "$PIN_SHA_ONNX" "voice model"
      [ -f "$CFG"  ] || fetch_pinned "$PIN_BASE.onnx.json" "$CFG"  "$PIN_SHA_CFG"  "voice config"
    fi
    # piper wants the pair as on-disk siblings next to the model it is given.
    cp -- "$ONNX" "$WORK/$VOICE.onnx"      2>/dev/null || { record unavailable ""; echo "audio: unavailable: could not stage the voice model" >&2; exit 1; }
    cp -- "$CFG"  "$WORK/$VOICE.onnx.json" 2>/dev/null || { record unavailable ""; echo "audio: unavailable: could not stage the voice config" >&2; exit 1; }
  else
    # on-demand, UNPINNED HF fetch for a non-default voice (the voice name is allowlist-validated above → safe to
    # build the nested rhasspy/piper-voices path). VOICE = <locale>-<name>-<quality>, e.g. en_US-lessac-medium.
    command -v curl >/dev/null 2>&1 || { record unavailable ""; echo "audio: unavailable: curl needed to fetch the non-default piper voice '$VOICE'" >&2; exit 1; }
    locale="${VOICE%%-*}"; rest="${VOICE#*-}"; vname="${rest%%-*}"; quality="${rest##*-}"; fam="${locale%%_*}"
    base="https://huggingface.co/rhasspy/piper-voices/resolve/main/$fam/$locale/$vname/$quality/$VOICE"
    echo "audio: first-run setup — fetching piper voice '$VOICE' (on-demand, unpinned)…" >&2
    curl -fsSL -o "$WORK/$VOICE.onnx"      "$base.onnx"      2>/dev/null || { record unavailable ""; echo "audio: unavailable: could not fetch piper voice '$VOICE' (check the name + connectivity)" >&2; exit 1; }
    curl -fsSL -o "$WORK/$VOICE.onnx.json" "$base.onnx.json" 2>/dev/null || { record unavailable ""; echo "audio: unavailable: could not fetch the config for piper voice '$VOICE'" >&2; exit 1; }
  fi
  if ! printf '%s' "$TEXT" | "$UVX" --from "$PIPER_PKG" piper --model "$WORK/$VOICE.onnx" --output_file "$WAV" >"$WORK/piper.log" 2>&1; then
    record error ""; echo "audio: error: piper synthesis failed (voice=$VOICE). Log: $(tail -3 "$WORK/piper.log" 2>/dev/null | tr '\n' ' ')" >&2; exit 1
  fi
else
  # ── kokoro: needs espeak-ng (presence-gated via the shim) + the shipped python helper, run via uvx ──
  ESPEAK="$(command -v "${AUDIO_ESPEAK:-espeak-ng}" 2>/dev/null)" || { record unavailable ""; echo "audio: unavailable: kokoro needs espeak-ng on PATH — apt/dnf/pacman/brew install espeak-ng. Or use --engine piper." >&2; exit 1; }
  [ -f "$HERE/audio-kokoro.py" ] || { record error ""; echo "audio: error: kokoro helper missing from the plugin payload ($HERE/audio-kokoro.py)" >&2; exit 1; }
  # bind kokoro's phonemizer to the TRUSTED espeak-ng (codex HIGH): run with a sanitized PATH that puts the resolved
  # espeak's dir first + only system dirs after — never the workspace/cwd, so a planted espeak-ng can't be picked up.
  if ! env PATH="$(dirname "$ESPEAK"):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$UVX" --with "$KOKORO_PKG" --with "$SOUNDFILE_PKG" python "$HERE/audio-kokoro.py" --text "$TEXT" --voice "$VOICE" --lang "$LANG_CODE" --out "$WAV" >"$WORK/kokoro.log" 2>&1; then
    record error ""; echo "audio: error: kokoro synthesis failed (voice=$VOICE lang=$LANG_CODE). Log: $(tail -3 "$WORK/kokoro.log" 2>/dev/null | tr '\n' ' ')" >&2; exit 1
  fi
fi

[ -s "$WAV" ] || { record error ""; echo "audio: error: the engine produced no audio" >&2; exit 1; }

# ── encode (wav = copy; mp3 = ffmpeg, falls back to wav). Produce into a FRESH temp file inside the out dir, then
#    `mv -f` over the final path — a pre-existing symlink at the destination is REPLACED, not followed (codex HIGH:
#    symlink containment bypass; also prevents a stale/partial file on a failed mp3 encode — codex MEDIUM). ──
OUTPUT="$OUT_DIR/$STEM.$FORMAT"
TMP_OUT="$(mktemp -- "$OUT_DIR/.audio-XXXXXX")"
if [ "$FORMAT" = "wav" ]; then
  cp -- "$WAV" "$TMP_OUT"
else
  FFMPEG="${AUDIO_FFMPEG_BIN:-}"; [ -n "$FFMPEG" ] || FFMPEG="$(command -v ffmpeg 2>/dev/null || true)"
  if [ -n "$FFMPEG" ] && "$FFMPEG" -nostdin -y -i "$WAV" -f mp3 "$TMP_OUT" >/dev/null 2>&1 && [ -s "$TMP_OUT" ]; then :; else
    cp -- "$WAV" "$TMP_OUT"; OUTPUT="$OUT_DIR/$STEM.wav"; FORMAT="wav"
    echo "audio: note: ffmpeg unavailable/failed for mp3 — wrote wav instead ($OUTPUT)" >&2
  fi
fi
[ -s "$TMP_OUT" ] || { rm -f -- "$TMP_OUT" 2>/dev/null || true; record error ""; echo "audio: error: no output written" >&2; exit 1; }
mv -f -- "$TMP_OUT" "$OUTPUT"

# warn (not fail) if the asset lands on a git-ignored path
if git -C "$ROOT" check-ignore -q -- "$OUTPUT" 2>/dev/null; then
  echo "audio: warning: '$OUTPUT' is git-ignored — the asset won't be tracked. Pass --out <tracked dir> or adjust .gitignore." >&2
fi

record ok "$OUTPUT"
echo "audio: status=ok"
echo "  engine=$ENGINE  voice=$VOICE  lang=$LANG_CODE  format=$FORMAT"
echo "  wrote=$OUTPUT (stayed_local=true)  uvx packages pinned (not engine-checksummed)"

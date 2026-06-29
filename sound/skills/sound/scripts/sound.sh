#!/usr/bin/env bash
# sound (spec 291) — PAID creative audio (music + SFX) via the fal.ai REST API. Model/body/price come from a bundled
# tier ORACLE (references/sound-tiers.json — D5). curl + jq (+ optional ffmpeg) resolved via _tachyon-external (TRUSTED
# paths, never bare — D1). Needs FAL_KEY (env; never stored/echoed — D4). Cost = price x duration, PRINTED before the
# call; a HARD --confirm-cost-usd gate is REQUIRED above the oracle threshold (D3) — checked BEFORE any network call.
set -euo pipefail
# sanitize PATH to trusted system dirs before any ambient tool (git/awk/jq-helpers…) runs (codex MEDIUM).
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

PLUGIN="sound"
HERE="$(cd "$(dirname "$0")" && pwd)"
ORACLE="$HERE/../references/sound-tiers.json"

KIND=""; TIER=""; DURATION=""; CONFIRM=""; FORMAT="mp3"; OUT_DIR=""; PROMPT=""
: "${SOUND_CURL:=}"; : "${SOUND_JQ:=}"; : "${SOUND_FFMPEG_BIN:=}"   # test overrides (mock for the headless dogfood)

usage() { echo "usage: sound \"<prompt>\" --kind music|sfx [--tier <name>] [--duration <sec>] [--format mp3|wav] [--out <dir>] [--confirm-cost-usd <n>]" >&2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --kind)     [ $# -ge 2 ] || { echo "sound: --kind requires a value" >&2; exit 64; }; KIND="$2"; shift 2 ;;
    --kind=*)   KIND="${1#*=}"; shift ;;
    --tier)     [ $# -ge 2 ] || { echo "sound: --tier requires a value" >&2; exit 64; }; TIER="$2"; shift 2 ;;
    --tier=*)   TIER="${1#*=}"; shift ;;
    --duration)   [ $# -ge 2 ] || { echo "sound: --duration requires a value" >&2; exit 64; }; DURATION="$2"; shift 2 ;;
    --duration=*) DURATION="${1#*=}"; shift ;;
    --format)   [ $# -ge 2 ] || { echo "sound: --format requires a value" >&2; exit 64; }; FORMAT="$2"; shift 2 ;;
    --format=*) FORMAT="${1#*=}"; shift ;;
    --out)      [ $# -ge 2 ] || { echo "sound: --out requires a value" >&2; exit 64; }; OUT_DIR="$2"; shift 2 ;;
    --out=*)    OUT_DIR="${1#*=}"; shift ;;
    --confirm-cost-usd)   [ $# -ge 2 ] || { echo "sound: --confirm-cost-usd requires a value" >&2; exit 64; }; CONFIRM="$2"; shift 2 ;;
    --confirm-cost-usd=*) CONFIRM="${1#*=}"; shift ;;
    -h|--help)  usage; exit 0 ;;
    -*) echo "sound: unknown flag '$1'" >&2; usage; exit 64 ;;
    *) [ -z "$PROMPT" ] || { echo "sound: only one prompt is allowed (quote it)" >&2; exit 64; }; PROMPT="$1"; shift ;;
  esac
done

case "$KIND" in music|sfx) ;; *) echo "sound: --kind music|sfx is required" >&2; exit 64 ;; esac
case "$FORMAT" in mp3|wav) ;; *) echo "sound: unknown --format '$FORMAT' (mp3|wav)" >&2; exit 64 ;; esac
[ -n "$PROMPT" ] || { usage; exit 64; }
[ -z "$DURATION" ] || echo "$DURATION" | grep -Eq '^[0-9]{1,4}$' || { echo "sound: --duration must be whole seconds (1–9999)" >&2; exit 64; }
[ -z "$CONFIRM" ] || echo "$CONFIRM" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || { echo "sound: --confirm-cost-usd must be a number" >&2; exit 64; }

# ── repo root + resolve curl/jq via the shim (TRUSTED; never bare — D1) ──
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] || { echo "sound: unavailable: not inside a git work tree (the Tachyon shims live at <repo>/.tachyon/bin)" >&2; exit 1; }
EXT_SHIM="$ROOT/.tachyon/bin/_tachyon-external"
CURL="${SOUND_CURL:-}"; [ -n "$CURL" ] || CURL="$("$EXT_SHIM" "$PLUGIN" curl 2>/dev/null || true)"
JQ="${SOUND_JQ:-}";     [ -n "$JQ" ]   || JQ="$("$EXT_SHIM" "$PLUGIN" jq 2>/dev/null || true)"
[ -n "$CURL" ] || { echo "sound: unavailable: curl not installed/trusted — the card offers an assisted install" >&2; exit 1; }
[ -n "$JQ" ]   || { echo "sound: unavailable: jq not installed/trusted — the card offers an assisted install" >&2; exit 1; }
[ -f "$ORACLE" ] || { echo "sound: error: tier oracle missing ($ORACLE) — reinstall the sound plugin" >&2; exit 1; }

# ── resolve the tier from the oracle (default per --kind) ──
[ -n "$TIER" ] || TIER="$("$JQ" -r --arg k "$KIND" 'if $k=="music" then .default_tier_music else .default_tier_sfx end' "$ORACLE")"
ROW="$("$JQ" -c --arg t "$TIER" '.tiers[$t] // empty' "$ORACLE")"
[ -n "$ROW" ] || { echo "sound: error: unknown --tier '$TIER' (see references/sound-tiers.json)" >&2; exit 1; }
field() { printf '%s' "$ROW" | "$JQ" -r --arg f "$1" '.[$f] // empty'; }
MODEL="$(field model)"; PROMPT_FIELD="$(field prompt_field)"; DUR_FIELD="$(field duration_field)"; DUR_UNIT="$(field duration_unit)"
URL_PATH="$(field output_url_path)"; PRICE="$(field price)"; PRICE_UNIT="$(field price_unit)"; DEF_DUR="$(field default_duration)"
THRESH="$("$JQ" -r '.confirm_threshold_usd // 0.25' "$ORACLE")"
[ -n "$DURATION" ] || DURATION="$DEF_DUR"
# duration MUST be >= 1s — a zero duration yields a $0.00 estimate that would BYPASS the confirm gate (codex HIGH).
[ "${DURATION:-0}" -ge 1 ] 2>/dev/null || { echo "sound: --duration must be at least 1 second (got '$DURATION')" >&2; exit 64; }
# the oracle's output_url_path is interpolated into a jq filter → enforce a STRICT dotted-field shape so a tampered
# oracle can't smuggle jq code (data-must-not-become-code; codex MEDIUM).
echo "$URL_PATH" | grep -Eq '^\.[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$' || { echo "sound: error: oracle output_url_path '$URL_PATH' is not a plain dotted field — refusing (tampered oracle?)" >&2; exit 1; }

# ── cost = price x duration-in-unit (awk float) ──
COST="$(awk -v p="$PRICE" -v d="$DURATION" -v u="$PRICE_UNIT" 'BEGIN{
  if (u=="per_minute") c=p*(d/60); else if (u=="per_second") c=p*d; else c=p; printf "%.4f", c }')"

# ── COST PRINT — BEFORE any network call (D3) ──
echo "estimated: \$$COST for $MODEL ($KIND/$TIER, ${DURATION}s) — PAID call"

# ── HARD confirm gate ABOVE the threshold, checked BEFORE the call (D3) ──
OVER="$(awk -v c="$COST" -v t="$THRESH" 'BEGIN{print (c>t)?1:0}')"
if [ "$OVER" = "1" ]; then
  if [ -z "$CONFIRM" ] || [ "$(awk -v c="$COST" -v k="$CONFIRM" 'BEGIN{print (k>=c)?1:0}')" != "1" ]; then
    echo "sound: refused: estimated \$$COST exceeds the \$$THRESH confirm threshold. Re-run with --confirm-cost-usd $COST (only if the user authorized this spend). NO paid call was made." >&2
    exit 1
  fi
fi

# ── FAL_KEY (env; never echoed — D4). Copy to a NON-exported var + unset so no spawned tool inherits it (codex MEDIUM). ──
[ -n "${FAL_KEY:-}" ] || { echo "sound: unavailable: FAL_KEY is not set — this is a PAID capability. Set FAL_KEY (https://fal.ai) and re-run. Tachyon never stores the key." >&2; exit 1; }
_FAL="$FAL_KEY"; unset FAL_KEY

# ── output dir (contained) — D6 ──
OUT_DIR="${OUT_DIR:-assets/sound}"
case "$OUT_DIR" in /*) ;; *) OUT_DIR="$ROOT/$OUT_DIR" ;; esac
mkdir -p -- "$OUT_DIR"
OUT_REAL="$(cd "$OUT_DIR" && pwd -P)"; ROOT_REAL="$(cd "$ROOT" && pwd -P)"
case "$OUT_REAL/" in "$ROOT_REAL"/*) ;; *) echo "sound: error: --out escaped the workspace" >&2; exit 1 ;; esac
STEM="sound-$(printf '%s' "$PROMPT" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"

# ── build the body (prompt + duration in the oracle's unit) + POST sync ──
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
DUR_BODY="$DURATION"; [ "$DUR_UNIT" = "ms" ] && DUR_BODY="$((DURATION * 1000))"
if [ -n "$DUR_FIELD" ] && [ "$DUR_FIELD" != "null" ]; then
  BODY="$("$JQ" -nc --arg p "$PROMPT" --arg pf "$PROMPT_FIELD" --arg df "$DUR_FIELD" --argjson dv "$DUR_BODY" '{($pf):$p, ($df):$dv}')"
else
  BODY="$("$JQ" -nc --arg p "$PROMPT" --arg pf "$PROMPT_FIELD" '{($pf):$p}')"
fi
# pass the auth header via a 0600 curl config (NOT argv → not ps-visible; NOT env → not inherited) — codex MEDIUM.
CFG="$WORK/curl.cfg"; ( umask 077; printf 'header = "Authorization: Key %s"\n' "$_FAL" > "$CFG" )
HTTP="$("$CURL" -sS --config "$CFG" -o "$WORK/resp.json" -w '%{http_code}' -X POST "https://fal.run/$MODEL" \
  -H "Content-Type: application/json" --data-raw "$BODY" --max-time 300 2>/dev/null || printf '000')"
if [ "$HTTP" != "200" ]; then
  # NEVER print the raw authenticated response body (codex HIGH) — only a safe parsed field.
  EC="$("$JQ" -r '(.error.type // .error // .detail // .message // "no detail") | tostring' "$WORK/resp.json" 2>/dev/null | head -c 160)"
  echo "sound: error: fal HTTP $HTTP for $MODEL (${EC:-no detail})" >&2; exit 1
fi
URL="$("$JQ" -r "($URL_PATH) // empty" "$WORK/resp.json" 2>/dev/null)"
[ -n "$URL" ] || { echo "sound: error: fal response carried no audio url (oracle output_url_path=$URL_PATH)" >&2; exit 1; }
"$CURL" -fsSL -o "$WORK/audio.src" "$URL" 2>/dev/null && [ -s "$WORK/audio.src" ] || { echo "sound: error: failed to download the generated audio" >&2; exit 1; }

# ── encode to the requested format (temp inside out dir → mv -f; mp3 via ffmpeg, falls back to wav) ──
OUTPUT="$OUT_REAL/$STEM.$FORMAT"
TMP_OUT="$(mktemp -- "$OUT_REAL/.sound-XXXXXX")"
if [ "$FORMAT" = "wav" ]; then
  cp -- "$WORK/audio.src" "$TMP_OUT" || { rm -f -- "$TMP_OUT"; echo "sound: error: could not write the output file" >&2; exit 1; }
else
  FFMPEG="${SOUND_FFMPEG_BIN:-}"; [ -n "$FFMPEG" ] || FFMPEG="$("$EXT_SHIM" "$PLUGIN" ffmpeg 2>/dev/null || true)"
  if [ -n "$FFMPEG" ] && "$FFMPEG" -nostdin -y -i "$WORK/audio.src" -f mp3 "$TMP_OUT" >/dev/null 2>&1 && [ -s "$TMP_OUT" ]; then :; else
    cp -- "$WORK/audio.src" "$TMP_OUT" || { rm -f -- "$TMP_OUT"; echo "sound: error: could not write the output file" >&2; exit 1; }
    OUTPUT="$OUT_REAL/$STEM.wav"; FORMAT="wav"
    echo "sound: note: ffmpeg unavailable/failed for mp3 — wrote the raw asset as wav ($OUTPUT)" >&2
  fi
fi
[ -s "$TMP_OUT" ] || { rm -f -- "$TMP_OUT"; echo "sound: error: no output written" >&2; exit 1; }
mv -f -- "$TMP_OUT" "$OUTPUT"   # replace a pre-existing symlink, never follow it

PROV_DIR="$ROOT/.tachyon"
if [ -d "$PROV_DIR" ]; then
  "$JQ" -nc --arg kind "$KIND" --arg tier "$TIER" --arg model "$MODEL" --arg cost "$COST" --arg out "$OUTPUT" --argjson dur "$DURATION" \
    '{capability:"sound", kind:$kind, tier:$tier, model:$model, cost_estimate_usd:($cost|tonumber), duration_s:$dur, output:$out, paid:true}' >> "$PROV_DIR/sound-runs.jsonl" 2>/dev/null || true
fi
echo "sound: status=ok"
echo "  kind=$KIND  tier=$TIER  model=$MODEL  ${DURATION}s  cost~\$$COST  wrote=$OUTPUT"

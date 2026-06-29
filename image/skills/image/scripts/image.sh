#!/usr/bin/env bash
# image (spec 291) — PAID AI image generation via the fal.ai REST API. Resolves curl + jq through Tachyon's
# _tachyon-external shim (TRUSTED paths, never bare names — spec 291 D1). Needs FAL_KEY (env; never stored/echoed —
# D4). PRINTS the estimated cost BEFORE any paid request fires (D3). Fail-closed: `unavailable` (no key / missing
# tool) vs `error` (a present call failed); never a silent paid call.
set -euo pipefail
# sanitize PATH to trusted system dirs BEFORE any ambient tool (git/awk/sha…) runs — a poisoned PATH could otherwise
# return a fake repo root → a fake shim, or inherit the key (codex MEDIUM). Test overrides are absolute, unaffected.
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

PLUGIN="image"
TIER=""; ASPECT="square"; NAME=""; PROMPT=""

# test/override hooks (a mocked curl/jq for the headless dogfood; never used in normal runs)
: "${IMAGE_CURL:=}"; : "${IMAGE_JQ:=}"

usage() { echo "usage: image --tier draft|brand-text|brand-photo [--aspect square|landscape|portrait] [--name <slug>] \"<prompt>\"" >&2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --tier)     [ $# -ge 2 ] || { echo "image: --tier requires a value" >&2; exit 64; }; TIER="$2"; shift 2 ;;
    --tier=*)   TIER="${1#*=}"; shift ;;
    --aspect)   [ $# -ge 2 ] || { echo "image: --aspect requires a value" >&2; exit 64; }; ASPECT="$2"; shift 2 ;;
    --aspect=*) ASPECT="${1#*=}"; shift ;;
    --name)     [ $# -ge 2 ] || { echo "image: --name requires a value" >&2; exit 64; }; NAME="$2"; shift 2 ;;
    --name=*)   NAME="${1#*=}"; shift ;;
    -h|--help)  usage; exit 0 ;;
    -*) echo "image: unknown flag '$1'" >&2; usage; exit 64 ;;
    *) [ -z "$PROMPT" ] || { echo "image: only one prompt is allowed (quote it)" >&2; exit 64; }; PROMPT="$1"; shift ;;
  esac
done

# --tier is REQUIRED — the 3-option error
if [ -z "$TIER" ]; then
  { echo "image error: --tier is required. Pick one:";
    echo "  --tier draft        cheap mockup      (~\$0.003/img, FLUX schnell)";
    echo "  --tier brand-text   premium w/ text   (~\$0.04+/img, gpt-image-2)";
    echo "  --tier brand-photo  premium photo     (~\$0.06/img, Imagen 4 Ultra)"; } >&2
  exit 64
fi
[ -n "$PROMPT" ] || { usage; exit 64; }
case "$ASPECT" in square|landscape|portrait) ;; *) echo "image: unknown --aspect '$ASPECT'" >&2; exit 64 ;; esac
[ -z "$NAME" ] || echo "$NAME" | grep -Eq '^[A-Za-z0-9_-]{1,64}$' || { echo "image: invalid --name '$NAME' (letters/digits/_/-, ≤64)" >&2; exit 64; }

# tier → model | approx cost (USD) | extension | tracked? (draft=gitignored mockup, brand=tracked asset)
case "$TIER" in
  draft)       MODEL="fal-ai/flux/schnell"; COST="0.003"; EXT="jpg"; DEST="mockups" ;;
  brand-text)  MODEL="fal-ai/gpt-image-2";  COST="0.04";  EXT="png"; DEST="brand" ;;
  brand-photo) MODEL="fal-ai/imagen4/ultra"; COST="0.06"; EXT="png"; DEST="brand" ;;
  *) echo "image: unknown --tier '$TIER' (draft|brand-text|brand-photo)" >&2; exit 64 ;;
esac
case "$ASPECT" in
  square)    IMAGE_SIZE="square_hd";     DIMS="1024x1024" ;;
  landscape) IMAGE_SIZE="landscape_16_9"; DIMS="1024x576" ;;
  portrait)  IMAGE_SIZE="portrait_16_9";  DIMS="576x1024" ;;
esac

# ── repo root + resolve curl/jq via the shim (TRUSTED; never bare — D1) ──
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] || { echo "image: unavailable: not inside a git work tree (the Tachyon shims live at <repo>/.tachyon/bin)" >&2; exit 1; }
EXT_SHIM="$ROOT/.tachyon/bin/_tachyon-external"
CURL="${IMAGE_CURL:-}"; [ -n "$CURL" ] || CURL="$("$EXT_SHIM" "$PLUGIN" curl 2>/dev/null || true)"
JQ="${IMAGE_JQ:-}";     [ -n "$JQ" ]   || JQ="$("$EXT_SHIM" "$PLUGIN" jq 2>/dev/null || true)"
[ -n "$CURL" ] || { echo "image: unavailable: curl not installed/trusted — the plugin's card offers an assisted install (apt/dnf/pacman/brew)" >&2; exit 1; }
[ -n "$JQ" ]   || { echo "image: unavailable: jq not installed/trusted — the plugin's card offers an assisted install (apt/dnf/pacman/brew)" >&2; exit 1; }

# ── FAL_KEY (env; never echoed — D4). Copy to a NON-exported var + unset, so no spawned tool inherits it (codex MEDIUM). ──
[ -n "${FAL_KEY:-}" ] || { echo "image: unavailable: FAL_KEY is not set — this is a PAID capability. Set FAL_KEY in your env (https://fal.ai) and re-run. Tachyon never stores the key." >&2; exit 1; }
_FAL="$FAL_KEY"; unset FAL_KEY

# ── output path (contained; draft → gitignored mockups, brand → tracked) — D6 ──
[ -n "$NAME" ] || NAME="$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//' | cut -c1-40)"
[ -n "$NAME" ] || NAME="image"
if [ "$DEST" = "mockups" ]; then OUT_DIR="$ROOT/assets/generated/mockups"; else OUT_DIR="$ROOT/assets/brand"; fi
mkdir -p -- "$OUT_DIR"
OUT_REAL="$(cd "$OUT_DIR" && pwd -P)"; ROOT_REAL="$(cd "$ROOT" && pwd -P)"
case "$OUT_REAL/" in "$ROOT_REAL"/*) ;; *) echo "image: error: output dir escaped the workspace" >&2; exit 1 ;; esac
OUTPUT="$OUT_REAL/$NAME.$EXT"

# ── COST PRINT — BEFORE any paid request (D3) ──
echo "estimated: \$$COST for $MODEL at $DIMS ($ASPECT) — PAID call about to fire"

# ── generate: POST to fal.run (sync), extract the image URL, download — all via the TRUSTED curl/jq ──
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BODY="$("$JQ" -nc --arg p "$PROMPT" --arg s "$IMAGE_SIZE" '{prompt:$p, image_size:$s, num_images:1}')"
# pass the auth header via a 0600 curl config (NOT argv → not ps-visible; NOT env → not inherited) — codex MEDIUM.
CFG="$WORK/curl.cfg"; ( umask 077; printf 'header = "Authorization: Key %s"\n' "$_FAL" > "$CFG" )
HTTP="$("$CURL" -sS --config "$CFG" -o "$WORK/resp.json" -w '%{http_code}' -X POST "https://fal.run/$MODEL" \
  -H "Content-Type: application/json" --data-raw "$BODY" --max-time 180 2>/dev/null || printf '000')"
if [ "$HTTP" != "200" ]; then
  # NEVER print the raw authenticated response body (codex HIGH) — extract only a safe parsed field.
  EC="$("$JQ" -r '(.error.type // .error // .detail // .message // "no detail") | tostring' "$WORK/resp.json" 2>/dev/null | head -c 160)"
  echo "image: error: fal HTTP $HTTP for $MODEL (${EC:-no detail})" >&2; exit 1
fi
URL="$("$JQ" -r '(.images[0].url // .image.url // .url // empty)' "$WORK/resp.json" 2>/dev/null)"
[ -n "$URL" ] || { echo "image: error: fal response carried no image url" >&2; exit 1; }
TMP_OUT="$(mktemp -- "$OUT_REAL/.image-XXXXXX")"
"$CURL" -fsSL -o "$TMP_OUT" "$URL" 2>/dev/null && [ -s "$TMP_OUT" ] || { rm -f -- "$TMP_OUT"; echo "image: error: failed to download the generated image" >&2; exit 1; }
mv -f -- "$TMP_OUT" "$OUTPUT"   # replace a pre-existing symlink, never follow it

# provenance (gitignored generated manifest for draft; tracked side keeps the asset only)
PROV_DIR="$ROOT/.tachyon"
if [ -d "$PROV_DIR" ] && command -v "$JQ" >/dev/null 2>&1; then
  "$JQ" -nc --arg tier "$TIER" --arg model "$MODEL" --arg cost "$COST" --arg out "$OUTPUT" --arg dims "$DIMS" \
    '{capability:"image", tier:$tier, model:$model, cost_estimate_usd:($cost|tonumber), output:$out, dimensions:$dims, paid:true}' >> "$PROV_DIR/image-runs.jsonl" 2>/dev/null || true
fi

if git -C "$ROOT" check-ignore -q -- "$OUTPUT" 2>/dev/null; then
  [ "$DEST" = "mockups" ] || echo "image: warning: '$OUTPUT' is git-ignored — a brand asset is expected to be tracked." >&2
fi
echo "image: status=ok"
echo "  tier=$TIER  model=$MODEL  dims=$DIMS  cost~\$$COST  wrote=$OUTPUT"

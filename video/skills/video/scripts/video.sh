#!/usr/bin/env bash
# video (spec 293) — PAID generative AI video via the fal.ai QUEUE REST API. ASYNC + fire-and-forget: `submit` queues
# a job (a ~5-min, $0.50–$3 paid render), persists the request_id to a gitignored ledger, and returns immediately;
# `poll` (a separate invocation) reaps terminal jobs (status → result → download). curl + jq resolved TRUSTED via the
# shim (never bare). FAL_KEY = env or .tachyon/secrets.env (never stored/echoed; passed via a 0600 curl --config).
# HARD --confirm-cost-usd gate on EVERY submit. NO auto-retry on an ambiguous submit (it could double-bill).
# Model/body/price from a bundled oracle.
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"   # sanitize before any ambient tool runs

PLUGIN="video"
HERE="$(cd "$(dirname "$0")" && pwd)"
ORACLE="$HERE/../references/video-tiers.json"
QUEUE_BASE="https://queue.fal.run"
: "${VIDEO_CURL:=}"; : "${VIDEO_JQ:=}"   # test overrides (mock fal for the headless dogfood)

usage() { echo "usage: video <submit \"<prompt>\" --tier draft|standard|premium [--duration <sec>] [--image-url <https-url>] [--name <slug>] --confirm-cost-usd <max>  |  poll [--all | --id <request_id>]>" >&2; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] || { echo "video: unavailable: not inside a git work tree (Tachyon shims live at <repo>/.tachyon/bin)" >&2; exit 1; }
# Ferramentas externas vêm do PATH: o Tachyon não provisiona mais, e o manifesto só as NOMEIA em `requires`.
JOBS_DIR="$ROOT/.tachyon/video-jobs"; LEDGER="$JOBS_DIR/ledger.jsonl"; LOCK="$JOBS_DIR/lock"
OUT_DIR="$ROOT/assets/generated/videos"

resolve_tools() {
  CURL="${VIDEO_CURL:-}"; [ -n "$CURL" ] || CURL="$(command -v curl 2>/dev/null || true)"
  JQ="${VIDEO_JQ:-}";     [ -n "$JQ" ]   || JQ="$(command -v jq 2>/dev/null || true)"
  [ -n "$CURL" ] && [ -x "$CURL" ] || { echo "video: unavailable: curl not on PATH — install it (see the plugin README)" >&2; exit 1; }
  [ -n "$JQ" ] && [ -x "$JQ" ] || { echo "video: unavailable: jq not on PATH — install it (see the plugin README)" >&2; exit 1; }
}
load_fal_key_from_secrets() {
  [ -n "${FAL_KEY:-}" ] && return 0
  secrets="$ROOT/.tachyon/secrets.env"
  [ -f "$secrets" ] || return 0
  line="$(awk '
    /^[[:space:]]*(#|$)/ { next }
    /^[[:space:]]*(export[[:space:]]+)?FAL_KEY[[:space:]]*=/ { found=$0 }
    END { if (found) print found }
  ' "$secrets" 2>/dev/null || true)"
  [ -n "$line" ] || return 0
  value="${line#*=}"
  value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$value" in
    \"*\") value="${value#\"}"; value="${value%\"}" ;;
    \'*\') value="${value#\'}"; value="${value%\'}" ;;
  esac
  [ -n "$value" ] || return 0
  FAL_KEY="$value"
}
need_key() { load_fal_key_from_secrets; [ -n "${FAL_KEY:-}" ] || { echo "video: unavailable: FAL_KEY is not set — this is a PAID capability. Set FAL_KEY in your env or $ROOT/.tachyon/secrets.env (https://fal.ai) and re-run. Tachyon never stores the key." >&2; exit 1; }; _FAL="$FAL_KEY"; unset FAL_KEY; }
auth_cfg() { ( umask 077; printf 'header = "Authorization: Key %s"\n' "$_FAL" > "$1" ); }   # 0600 curl --config (not argv/env)
b64d() { base64 -d 2>/dev/null || base64 -D; }   # portable base64 decode (GNU -d / BSD -D)

SUB="${1:-}"; [ $# -gt 0 ] && shift || true
[ -n "$SUB" ] || { usage; exit 64; }

case "$SUB" in
  submit)
    TIER=""; DURATION=""; IMG=""; CONFIRM=""; NAME=""; PROMPT=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --tier)     [ $# -ge 2 ] || { echo "video: --tier requires a value" >&2; exit 64; }; TIER="$2"; shift 2 ;;
        --tier=*)   TIER="${1#*=}"; shift ;;
        --duration) [ $# -ge 2 ] || { echo "video: --duration requires a value" >&2; exit 64; }; DURATION="$2"; shift 2 ;;
        --duration=*) DURATION="${1#*=}"; shift ;;
        --image-url) [ $# -ge 2 ] || { echo "video: --image-url requires a value" >&2; exit 64; }; IMG="$2"; shift 2 ;;
        --image-url=*) IMG="${1#*=}"; shift ;;
        --name)     [ $# -ge 2 ] || { echo "video: --name requires a value" >&2; exit 64; }; NAME="$2"; shift 2 ;;
        --name=*)   NAME="${1#*=}"; shift ;;
        --confirm-cost-usd) [ $# -ge 2 ] || { echo "video: --confirm-cost-usd requires a value" >&2; exit 64; }; CONFIRM="$2"; shift 2 ;;
        --confirm-cost-usd=*) CONFIRM="${1#*=}"; shift ;;
        -*) echo "video: submit: unknown flag '$1'" >&2; exit 64 ;;
        *) [ -z "$PROMPT" ] || { echo "video: one prompt only (quote it)" >&2; exit 64; }; PROMPT="$1"; shift ;;
      esac
    done
    [ -n "$PROMPT" ] || { usage; exit 64; }
    [ -f "$ORACLE" ] || { echo "video: error: tier oracle missing ($ORACLE) — reinstall the plugin" >&2; exit 1; }
    [ -z "$NAME" ] || echo "$NAME" | grep -Eq '^[a-z0-9][a-z0-9-]{0,63}$' || { echo "video: invalid --name" >&2; exit 64; }
    resolve_tools
    ROW="$("$JQ" -c --arg t "$TIER" '.tiers[$t] // empty' "$ORACLE")"
    [ -n "$ROW" ] || { echo "video: error: --tier must be one of draft|standard|premium" >&2; exit 64; }
    f() { printf '%s' "$ROW" | "$JQ" -r --arg k "$1" '.[$k] // empty'; }
    MODEL="$(f model)"; PRICE="$(f price_usd_per_second)"; MAXD="$(f max_duration_seconds)"; DEFD="$(f default_duration)"
    REQ_IMG="$(f requires_image_url)"; PROMPT_FIELD="$(f prompt_field)"; DUR_FIELD="$(f duration_field)"; IMG_FIELD="$(f image_field)"; URL_PATH="$(f output_url_path)"
    echo "$URL_PATH" | grep -Eq '^\.[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$' || { echo "video: error: oracle output_url_path '$URL_PATH' is not a plain dotted field — refusing (tampered oracle?)" >&2; exit 1; }
    [ -n "$DURATION" ] || DURATION="$DEFD"
    echo "$DURATION" | grep -Eq '^[0-9]{1,4}$' || { echo "video: --duration must be whole seconds" >&2; exit 64; }
    # D6 — HARD duration bounds (1 .. tier max), BEFORE any network
    [ "$DURATION" -ge 1 ] 2>/dev/null || { echo "video: --duration must be >= 1" >&2; exit 64; }
    [ "$DURATION" -le "$MAXD" ] 2>/dev/null || { echo "video: --duration $DURATION exceeds the $TIER tier max of ${MAXD}s" >&2; exit 64; }
    # D7 — image-to-video tiers require a validated https image URL (never local-fetched)
    if [ "$REQ_IMG" = "true" ]; then
      [ -n "$IMG" ] || { echo "video: the '$TIER' tier is image-to-video — pass --image-url <https url> (e.g. an image-plugin output uploaded somewhere public)" >&2; exit 64; }
    fi
    if [ -n "$IMG" ]; then case "$IMG" in https://*) ;; *) echo "video: --image-url must be an https:// URL" >&2; exit 64 ;; esac; echo "$IMG" | grep -Eq '[[:space:]]' && { echo "video: --image-url must not contain whitespace" >&2; exit 64; }; fi
    # estimate + HARD cost gate on EVERY submit (D5) — BEFORE the key/network
    EST="$(awk -v p="$PRICE" -v d="$DURATION" 'BEGIN{printf "%.2f", p*d}')"
    echo "estimated: \$$EST for $MODEL ($TIER, ${DURATION}s @ \$$PRICE/s) — PAID generation"
    [ -n "$CONFIRM" ] || { echo "video: refused: --confirm-cost-usd is REQUIRED for a paid generation. Re-run with --confirm-cost-usd $EST (only if the user authorized this spend). NO call was made." >&2; exit 1; }
    echo "$CONFIRM" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || { echo "video: --confirm-cost-usd must be a number" >&2; exit 64; }
    [ "$(awk -v c="$CONFIRM" -v e="$EST" 'BEGIN{print (c>=e)?1:0}')" = "1" ] || { echo "video: refused: --confirm-cost-usd $CONFIRM is below the estimate \$$EST. NO call was made." >&2; exit 1; }
    need_key
    mkdir -p -- "$JOBS_DIR"
    # preflight ledger writability BEFORE the paid network call (codex MEDIUM — don't bill then lose the request_id)
    [ -w "$JOBS_DIR" ] && { : >> "$LEDGER"; } 2>/dev/null || { echo "video: unavailable: the job ledger ($LEDGER) is not writable — fix that before a paid submit" >&2; exit 1; }
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT; CFG="$WORK/cfg"; auth_cfg "$CFG"
    # build the body (prompt + duration + image_url when applicable)
    if [ -n "$IMG" ]; then
      BODY="$("$JQ" -nc --arg p "$PROMPT" --arg pf "$PROMPT_FIELD" --arg df "$DUR_FIELD" --argjson dv "$DURATION" --arg if "$IMG_FIELD" --arg iv "$IMG" '{($pf):$p, ($df):$dv, ($if):$iv}')"
    else
      BODY="$("$JQ" -nc --arg p "$PROMPT" --arg pf "$PROMPT_FIELD" --arg df "$DUR_FIELD" --argjson dv "$DURATION" '{($pf):$p, ($df):$dv}')"
    fi
    # POST to the QUEUE. NO auto-retry (D4): an ambiguous failure may already be a billed job.
    HTTP="$("$CURL" -sS --config "$CFG" -o "$WORK/resp.json" -w '%{http_code}' -X POST "$QUEUE_BASE/$MODEL" -H "Content-Type: application/json" --data-raw "$BODY" --max-time 90 2>/dev/null || printf '000')"
    if [ "$HTTP" != "200" ]; then
      EC="$("$JQ" -r '(.error.type // .error // .detail // .message // "no detail") | tostring' "$WORK/resp.json" 2>/dev/null | head -c 160)"
      echo "video: error: submit HTTP $HTTP for $MODEL (${EC:-no detail}). NOT retried — if the request may have queued, run 'video poll --all' before re-submitting (avoid a double charge)." >&2; exit 1
    fi
    REQ_ID="$("$JQ" -r '.request_id // empty' "$WORK/resp.json")"
    [ -n "$REQ_ID" ] || { echo "video: error: submit response carried no request_id — run 'video poll --all' to check before re-submitting." >&2; exit 1; }
    # validate the fal request_id BEFORE it ever reaches a path/URL (codex HIGH — fal/mock-controlled)
    echo "$REQ_ID" | grep -Eq '^[A-Za-z0-9_-]{1,128}$' || { echo "video: error: fal returned an unexpected request_id shape '$REQ_ID' — check your fal dashboard for a queued job before re-submitting (avoid a double charge)." >&2; exit 1; }
    OUT_NAME="${NAME:-$REQ_ID}"
    # APPEND the `submitted` event IMMEDIATELY (D4 anti-orphan). status/result URLs are CONSTRUCTED from model+id at
    # poll time (not stored from the response) so the FAL_KEY auth only ever goes to queue.fal.run (codex BLOCKER).
    if ! "$JQ" -nc --arg id "$REQ_ID" --arg model "$MODEL" --arg tier "$TIER" --arg est "$EST" --arg up "$URL_PATH" --arg name "$OUT_NAME" --argjson dur "$DURATION" \
      '{event:"submitted", request_id:$id, model:$model, tier:$tier, estimate_usd:($est|tonumber), duration_s:$dur, output_url_path:$up, name:$name}' >> "$LEDGER"; then
      echo "video: error: a job was SUBMITTED but the ledger write failed — RECORD THIS to poll it (do not re-submit): request_id=$REQ_ID model=$MODEL" >&2; exit 1
    fi
    echo "video: status=submitted"
    echo "  request_id=$REQ_ID  tier=$TIER  est~\$$EST  — a paid render is queued (~5 min)."
    echo "  reap it later with:  video poll --all   (or  video poll --id $REQ_ID)"
    ;;

  poll)
    MODE="all"; ONLY_ID=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --all) MODE="all"; shift ;;
        --id)  [ $# -ge 2 ] || { echo "video: --id requires a value" >&2; exit 64; }; ONLY_ID="$2"; MODE="id"; shift 2 ;;
        --id=*) ONLY_ID="${1#*=}"; MODE="id"; shift ;;
        -*) echo "video: poll: unknown flag '$1'" >&2; exit 64 ;;
        *) echo "video: poll: unexpected arg '$1'" >&2; exit 64 ;;
      esac
    done
    [ -f "$LEDGER" ] || { echo "video: no jobs in the ledger (nothing to poll)"; exit 0; }
    resolve_tools; need_key
    mkdir -p -- "$JOBS_DIR"
    # D3 — lock against concurrent polls (atomic mkdir; released on exit)
    if ! mkdir "$LOCK" 2>/dev/null; then echo "video: another poll is in progress (lock held) — try again shortly" >&2; exit 1; fi
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"; rmdir "$LOCK" 2>/dev/null || true' EXIT; CFG="$WORK/cfg"; auth_cfg "$CFG"
    mkdir -p -- "$OUT_DIR"; OUT_REAL="$(cd "$OUT_DIR" && pwd -P)"; ROOT_REAL="$(cd "$ROOT" && pwd -P)"
    case "$OUT_REAL/" in "$ROOT_REAL"/*) ;; *) echo "video: error: output dir escaped the workspace" >&2; exit 1 ;; esac
    # latest event per request_id; pending = latest event is "submitted"
    PENDING="$("$JQ" -s -r 'group_by(.request_id) | map(.[-1]) | map(select(.event=="submitted")) | .[] | @base64' "$LEDGER" 2>/dev/null || true)"
    [ -n "$PENDING" ] || { echo "video: poll: no pending jobs"; exit 0; }
    reaped=0
    for row in $PENDING; do
      J="$(printf '%s' "$row" | b64d)"
      ID="$(printf '%s' "$J" | "$JQ" -r '.request_id')"
      [ "$MODE" = "all" ] || [ "$ID" = "$ONLY_ID" ] || continue
      MODEL="$(printf '%s' "$J" | "$JQ" -r '.model')"; URL_PATH="$(printf '%s' "$J" | "$JQ" -r '.output_url_path')"; NAME="$(printf '%s' "$J" | "$JQ" -r '.name')"
      # RE-VALIDATE every ledger field on read — a hand-edited ledger must not reach a path/URL/jq filter (codex HIGH/MEDIUM)
      echo "$ID"       | grep -Eq '^[A-Za-z0-9_-]{1,128}$' || { echo "video: skip: invalid request_id in ledger" >&2; continue; }
      echo "$MODEL"    | grep -Eq '^[A-Za-z0-9._/-]{1,200}$' || { echo "video: skip $ID: invalid model in ledger" >&2; continue; }
      echo "$NAME"     | grep -Eq '^[A-Za-z0-9_-]{1,128}$' || { echo "video: skip $ID: invalid name in ledger" >&2; continue; }
      echo "$URL_PATH" | grep -Eq '^\.[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$' || { echo "video: skip $ID: invalid output_url_path in ledger" >&2; continue; }
      # status/result URLs CONSTRUCTED from validated model+id → the FAL_KEY auth ONLY ever hits queue.fal.run (codex BLOCKER)
      SU="$QUEUE_BASE/$MODEL/requests/$ID/status"; RU="$QUEUE_BASE/$MODEL/requests/$ID"
      ST="$("$CURL" -sS --config "$CFG" "$SU" --max-time 30 2>/dev/null | "$JQ" -r '.status // empty' 2>/dev/null || true)"
      case "$ST" in
        COMPLETED)
          if "$CURL" -sS --config "$CFG" -o "$WORK/res.json" "$RU" --max-time 30 2>/dev/null; then
            URL="$("$JQ" -r "($URL_PATH) // empty" "$WORK/res.json" 2>/dev/null)"
            # the clip url is an arbitrary CDN host → download WITHOUT the auth config (never send FAL_KEY off fal); https-only.
            case "$URL" in https://*) ;; *) echo "video: $ID: result carried no https clip url — re-poll" >&2; continue ;; esac
            if "$CURL" -fsSL -o "$WORK/clip" "$URL" --max-time 600 2>/dev/null && [ -s "$WORK/clip" ]; then
              OUT="$OUT_REAL/$(date -u +%Y-%m-%d)-$NAME.mp4"; mv -f -- "$WORK/clip" "$OUT"
              "$JQ" -nc --arg id "$ID" --arg out "${OUT#"$ROOT/"}" '{event:"completed", request_id:$id, output:$out}' >> "$LEDGER"
              echo "video: reaped $ID → ${OUT#"$ROOT/"}"; reaped=$((reaped+1))
            else
              # transient download failure → DON'T append a terminal event (the job STAYS pending → re-pollable; codex HIGH)
              echo "video: $ID completed but the clip download failed — re-poll to retry the download (the paid job is NOT re-run)" >&2
            fi
          else
            echo "video: $ID completed but the result fetch failed — re-poll" >&2
          fi
          ;;
        IN_QUEUE|IN_PROGRESS|"") echo "video: $ID still ${ST:-pending} — re-poll later" ;;
        *) "$JQ" -nc --arg id "$ID" --arg s "$ST" '{event:"failed", request_id:$id, status:$s}' >> "$LEDGER"; echo "video: $ID terminal status '$ST' — marked failed" >&2 ;;
      esac
    done
    echo "video: poll done (reaped $reaped)"
    ;;

  -h|--help) usage; exit 0 ;;
  *) echo "video: unknown subcommand '$SUB' (submit | poll)" >&2; usage; exit 64 ;;
esac

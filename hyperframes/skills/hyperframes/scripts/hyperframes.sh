#!/usr/bin/env bash
# hyperframes (spec 292) — deterministic LOCAL video: an HTML/CSS/JS composition → MP4 via the HyperFrames CLI
# (npx hyperframes@<pin>, HeyGen, Apache-2.0) in its bundled headless Chromium + system ffmpeg. FREE (no inference).
# The composition source is git-tracked; the MP4 is regenerable. We ship our OWN minimal template and NEVER run
# `hyperframes init` (it couples to upstream scaffolding + remote/global-skills pulls). npx is the ambient runner
# (like diagram's npx); ffmpeg is resolved TRUSTED via the shim; HyperFrames manages its own browser. Fail-closed:
# `unavailable` (a dep missing) vs `error` (a present render failed).
set -euo pipefail

PLUGIN="hyperframes"
HF_PIN="0.7.18"   # spec 292 — EXACT pin (pre-1.0; a minor bump can change render output)
HERE="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$HERE/../references/composition-template"

usage() { echo "usage: hyperframes <doctor | scaffold <slug> | render <slug> [--name <out-slug>] [--quality draft|high]>" >&2; }

SUB="${1:-}"; [ $# -gt 0 ] && shift || true
[ -n "$SUB" ] || { usage; exit 64; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] || { echo "hyperframes: unavailable: not inside a git work tree (Tachyon shims live at <repo>/.tachyon/bin)" >&2; exit 1; }
EXT_SHIM="$ROOT/.tachyon/bin/_tachyon-external"

# ── shared dependency checks ──
need_npx() { command -v npx >/dev/null 2>&1 || { echo "hyperframes: unavailable: npx not found — install Node 22+ (https://nodejs.org). HyperFrames runs via 'npx hyperframes@$HF_PIN'." >&2; exit 1; }; }
need_node22() {
  command -v node >/dev/null 2>&1 || { echo "hyperframes: unavailable: node not found — HyperFrames requires Node 22+." >&2; exit 1; }
  local maj; maj="$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
  [ -n "$maj" ] && [ "$maj" -ge 22 ] 2>/dev/null || { echo "hyperframes: unavailable: Node $(node -v 2>/dev/null) is too old — HyperFrames requires Node 22+." >&2; exit 1; }
}
resolve_ffmpeg() {  # TRUSTED ffmpeg via the shim (override AUDIO-style for tests), or unavailable
  if [ -n "${HYPERFRAMES_FFMPEG_BIN:-}" ]; then FFMPEG="$HYPERFRAMES_FFMPEG_BIN"; return 0; fi
  [ -x "$EXT_SHIM" ] || { echo "hyperframes: unavailable: the _tachyon-external shim is missing — reinstall the plugin (or Rehydrate)" >&2; exit 1; }
  FFMPEG="$("$EXT_SHIM" "$PLUGIN" ffmpeg 2>/dev/null)" || { echo "hyperframes: unavailable: ffmpeg not installed/trusted — the plugin's card offers an assisted install (apt/dnf/pacman/brew)" >&2; exit 1; }
}
# D2 — on Linux ARM with NO browser, upstream may attempt an apt-get install. Fail CLOSED rather than let it mutate
# packages: require a resolvable browser first (system Chrome OR a HyperFrames/puppeteer cache).
guard_arm_browser() {
  case "$(uname -s 2>/dev/null)" in Linux) ;; *) return 0 ;; esac
  case "$(uname -m 2>/dev/null)" in aarch64|arm*) ;; *) return 0 ;; esac
  for b in google-chrome google-chrome-stable chromium chromium-browser; do command -v "$b" >/dev/null 2>&1 && return 0; done
  for d in "$HOME/.cache/puppeteer" "$HOME/.cache/hyperframes" "$HOME/.cache/ms-playwright"; do [ -d "$d" ] && [ -n "$(ls -A "$d" 2>/dev/null)" ] && return 0; done
  echo "hyperframes: unavailable: on Linux ARM with no detected browser, HyperFrames would try to install one via the system package manager — refusing. Install a browser yourself (e.g. 'sudo apt install chromium') and re-run." >&2
  exit 1
}

slug_ok() { echo "$1" | grep -Eq '^[a-z][a-z0-9-]{0,63}$'; }
COMP_ROOT="$ROOT/assets/video/compositions"
OUT_DIR="$ROOT/assets/generated/videos"

case "$SUB" in
  doctor)
    need_node22; need_npx
    echo "hyperframes — capability check"
    echo "  [ ok ] node: $(node -v 2>/dev/null)  | npx: present"
    if [ -n "${HYPERFRAMES_FFMPEG_BIN:-}" ] || { [ -x "$EXT_SHIM" ] && "$EXT_SHIM" "$PLUGIN" ffmpeg >/dev/null 2>&1; }; then echo "  [ ok ] ffmpeg: trusted (via shim)"; else echo "  [warn] ffmpeg: not installed/trusted — the card offers an assisted install"; fi
    echo "  [info] running 'npx hyperframes@$HF_PIN doctor --json' (relevant checks only; Docker checks ignored)…"
    npx --yes "hyperframes@$HF_PIN" doctor --json 2>/dev/null | { command -v jq >/dev/null 2>&1 && jq -r '(.checks // .results // .) | tostring' 2>/dev/null || cat; } | head -c 1200 || echo "  (hyperframes doctor unavailable — first run fetches the engine)"
    echo
    ;;

  scaffold)
    SLUG="${1:-}"; [ -n "$SLUG" ] || { echo "hyperframes: scaffold: <slug> required (kebab-case)" >&2; exit 64; }
    slug_ok "$SLUG" || { echo "hyperframes: scaffold: slug must be kebab-case (^[a-z][a-z0-9-]*$, ≤64)" >&2; exit 64; }
    [ -d "$TEMPLATE_DIR" ] || { echo "hyperframes: error: owned template missing at $TEMPLATE_DIR — reinstall the plugin" >&2; exit 1; }
    DEST="$COMP_ROOT/$SLUG"
    [ -e "$DEST" ] && { echo "hyperframes: scaffold: $DEST already exists (pick another slug or edit it)" >&2; exit 1; }
    mkdir -p -- "$DEST"
    DEST_REAL="$(cd "$DEST" && pwd -P)"; ROOT_REAL="$(cd "$ROOT" && pwd -P)"
    case "$DEST_REAL/" in "$ROOT_REAL"/*) ;; *) echo "hyperframes: error: composition dir escaped the workspace" >&2; exit 1 ;; esac
    cp -- "$TEMPLATE_DIR/index.html" "$TEMPLATE_DIR/hyperframes.json" "$TEMPLATE_DIR/package.json" "$DEST/"
    echo "hyperframes: scaffolded ${DEST#"$ROOT/"}"
    echo "  edit ${DEST#"$ROOT/"}/index.html (see references/authoring.md + HeyGen's docs), then:"
    echo "  hyperframes render $SLUG"
    ;;

  render)
    SLUG=""; OUT_SLUG=""; QUALITY="draft"
    while [ $# -gt 0 ]; do
      case "$1" in
        --name)    [ $# -ge 2 ] || { echo "hyperframes: --name requires a value" >&2; exit 64; }; OUT_SLUG="$2"; shift 2 ;;
        --name=*)  OUT_SLUG="${1#*=}"; shift ;;
        --quality) [ $# -ge 2 ] || { echo "hyperframes: --quality requires a value" >&2; exit 64; }; QUALITY="$2"; shift 2 ;;
        --quality=*) QUALITY="${1#*=}"; shift ;;
        -*) echo "hyperframes: render: unknown flag '$1'" >&2; exit 64 ;;
        *) [ -z "$SLUG" ] || { echo "hyperframes: render: one composition slug only" >&2; exit 64; }; SLUG="$1"; shift ;;
      esac
    done
    [ -n "$SLUG" ] || { echo "hyperframes: render: <slug> required" >&2; exit 64; }
    slug_ok "$SLUG" || { echo "hyperframes: render: invalid slug" >&2; exit 64; }
    case "$QUALITY" in draft|high) ;; *) echo "hyperframes: render: --quality must be draft|high" >&2; exit 64 ;; esac
    [ -z "$OUT_SLUG" ] || slug_ok "$OUT_SLUG" || { echo "hyperframes: render: invalid --name" >&2; exit 64; }
    need_node22; need_npx; resolve_ffmpeg; guard_arm_browser
    COMP_DIR="$COMP_ROOT/$SLUG"; SRC="$COMP_DIR/index.html"
    [ -f "$SRC" ] || { echo "hyperframes: error: composition not found at ${SRC#"$ROOT/"} — scaffold it first" >&2; exit 1; }
    OUT_SLUG="${OUT_SLUG:-$SLUG}"
    mkdir -p -- "$OUT_DIR"; OUT_REAL="$(cd "$OUT_DIR" && pwd -P)"; ROOT_REAL="$(cd "$ROOT" && pwd -P)"
    case "$OUT_REAL/" in "$ROOT_REAL"/*) ;; *) echo "hyperframes: error: output dir escaped the workspace" >&2; exit 1 ;; esac
    OUTPUT="$OUT_REAL/$(date -u +%Y-%m-%d)-$OUT_SLUG.mp4"
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
    # render to a temp, then mv -f over the final path (never follow a pre-existing symlink). HyperFrames finds ffmpeg
    # on PATH → put the TRUSTED ffmpeg's dir first so a workspace-planted ffmpeg can't be used.
    if ! ( cd "$COMP_DIR" && PATH="$(dirname "$FFMPEG"):$PATH" npx --yes "hyperframes@$HF_PIN" render --quality "$QUALITY" --workers 1 -o "$WORK/out.mp4" ) >"$WORK/render.log" 2>&1; then
      echo "hyperframes: error: render failed (rc). Log: $(tail -3 "$WORK/render.log" 2>/dev/null | tr '\n' ' ')" >&2; exit 1
    fi
    [ -s "$WORK/out.mp4" ] || { echo "hyperframes: error: render produced no MP4. Log: $(tail -3 "$WORK/render.log" 2>/dev/null | tr '\n' ' ')" >&2; exit 1; }
    mv -f -- "$WORK/out.mp4" "$OUTPUT"
    # provenance (gitignored) — honest about the npx/browser lane
    PROV_DIR="$ROOT/.tachyon"
    if [ -d "$PROV_DIR" ] && command -v jq >/dev/null 2>&1; then
      jq -nc --arg slug "$SLUG" --arg src "${SRC#"$ROOT/"}" --arg out "${OUTPUT#"$ROOT/"}" --arg ver "$HF_PIN" --arg q "$QUALITY" \
        '{capability:"hyperframes", slug:$slug, source:$src, output:$out, hyperframes_version:$ver, quality:$q, browser_source:"hyperframes-managed", acquisition:"npx", engine_checksummed:false, stayed_local:true}' >> "$PROV_DIR/hyperframes-runs.jsonl" 2>/dev/null || true
    fi
    if git -C "$ROOT" check-ignore -q -- "$OUTPUT" 2>/dev/null; then : ; else echo "hyperframes: note: '$OUTPUT' is NOT git-ignored — MP4s are large + regenerable; consider gitignoring assets/generated/." >&2; fi
    echo "hyperframes: status=ok"
    echo "  rendered ${OUTPUT#"$ROOT/"}  (quality=$QUALITY, hyperframes@$HF_PIN — npx, not engine-checksummed)"
    echo "  source (tracked): ${SRC#"$ROOT/"}"
    ;;

  -h|--help) usage; exit 0 ;;
  *) echo "hyperframes: unknown subcommand '$SUB'" >&2; usage; exit 64 ;;
esac

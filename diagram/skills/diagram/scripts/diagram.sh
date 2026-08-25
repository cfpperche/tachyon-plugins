#!/usr/bin/env bash
# diagram (spec 288) — deterministic Mermaid → SVG/PNG/PDF, local + free. Resolves a system browser through Tachyon's
# PATH (multi-candidate google-chrome/chromium/…; DIAGRAM_CHROME overrides), acquires mmdc at a
# PINNED version via npx (PUPPETEER_SKIP_DOWNLOAD=1 so it reuses the system browser, + ignore-scripts to block npm
# lifecycle scripts). First run fetches mmdc from npm — a lower-trust, NON-engine-checksummed acquisition lane (the
# pinned version is the only integrity anchor). Degrades to structural validation (the .mmd source is always kept)
# when no browser / no npx. Fail-closed: `unavailable` (a dep is missing) vs `error` (the source/render is bad).
set -euo pipefail

PLUGIN="diagram"
MMDC_PKG="@mermaid-js/mermaid-cli"
MMDC_VERSION="11.15.0"          # PINNED (spec 288 D1) — exact version, never floating
FORMAT="svg"; OUT_DIR=""; THEME=""; SOURCE=""

# test/override hooks (never needed in normal use)
: "${DIAGRAM_CHROME_BIN:=}"     # force a browser path (skip the shim)
: "${DIAGRAM_MMDC:=}"           # force an mmdc command (skip npx)

usage() { echo "usage: diagram \"<source.mmd | mermaid text>\" [--format svg|png|pdf] [--out <dir>] [--theme default|dark|forest|neutral]" >&2; }

# ── parse args (each value-flag REQUIRES a value; only one source) ──
while [ $# -gt 0 ]; do
  case "$1" in
    --format)   [ $# -ge 2 ] || { echo "diagram: --format requires a value" >&2; exit 64; }; FORMAT="$2"; shift 2 ;;
    --format=*) FORMAT="${1#*=}"; shift ;;
    --out)      [ $# -ge 2 ] || { echo "diagram: --out requires a value" >&2; exit 64; }; OUT_DIR="$2"; shift 2 ;;
    --out=*)    OUT_DIR="${1#*=}"; shift ;;
    --theme)    [ $# -ge 2 ] || { echo "diagram: --theme requires a value" >&2; exit 64; }; THEME="$2"; shift 2 ;;
    --theme=*)  THEME="${1#*=}"; shift ;;
    -h|--help)  usage; exit 0 ;;
    -*) echo "diagram: unknown flag '$1'" >&2; usage; exit 64 ;;
    *) [ -z "$SOURCE" ] || { echo "diagram: only one source is allowed" >&2; exit 64; }; SOURCE="$1"; shift ;;
  esac
done

case "$FORMAT" in svg|png|pdf) ;; *) echo "diagram: unknown --format '$FORMAT' (svg|png|pdf)" >&2; exit 64 ;; esac
[ -z "$THEME" ] || case "$THEME" in default|dark|forest|neutral) ;; *) echo "diagram: unknown --theme '$THEME' (default|dark|forest|neutral)" >&2; exit 64 ;; esac
[ -n "$SOURCE" ] || { usage; exit 64; }

# ── repo root (the shims + provenance are workspace-relative; cwd-independent) ──
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] || { echo "diagram: unavailable: not inside a git work tree (the Tachyon shims live at <repo>/.tachyon/bin)" >&2; exit 1; }

# ── output dir: default assets/diagrams/, CONTAINED to the workspace (codex MEDIUM — no `--out ../../escape`) ──
OUT_DIR="${OUT_DIR:-assets/diagrams}"
case "$OUT_DIR" in /*) ;; *) OUT_DIR="$ROOT/$OUT_DIR" ;; esac
mkdir -p -- "$OUT_DIR" || { echo "diagram: error: cannot create output dir: $OUT_DIR" >&2; exit 1; }
OUT_REAL="$(cd "$OUT_DIR" && pwd -P)" || { echo "diagram: error: bad output dir: $OUT_DIR" >&2; exit 1; }
ROOT_REAL="$(cd "$ROOT" && pwd -P)"
case "$OUT_REAL/" in "$ROOT_REAL"/*) ;; *) echo "diagram: error: --out must stay inside the workspace ($ROOT_REAL); refusing '$OUT_REAL'" >&2; exit 64 ;; esac
OUT_DIR="$OUT_REAL"

sha_of() { { sha256sum 2>/dev/null || shasum -a 256 2>/dev/null; } | awk '{print $1}'; }

# ── resolve source: an existing .mmd file, or inline text → ALWAYS materialize a canonical tracked .mmd next to the
#    render (the source is the durable artifact — codex MEDIUM D3: never an asset without its adjacent source) ──
if [ -f "$SOURCE" ]; then
  STEM="$(basename -- "$SOURCE")"; STEM="${STEM%.*}"
  SRC="$OUT_DIR/$STEM.mmd"
  SRC_IN_REAL="$(cd "$(dirname -- "$SOURCE")" && pwd -P)/$(basename -- "$SOURCE")"
  [ "$SRC_IN_REAL" = "$OUT_DIR/$STEM.mmd" ] || cp -- "$SOURCE" "$SRC" # skip the copy if the input already IS the canonical file
else
  SSHA="$(printf '%s' "$SOURCE" | sha_of)"
  STEM="diagram-${SSHA:0:8}"
  SRC="$OUT_DIR/$STEM.mmd"
  printf '%s\n' "$SOURCE" > "$SRC"
fi
SRC_SHA="$(sha_of < "$SRC")"

# ── structural validation (browser-less, deterministic): first non-comment line names a Mermaid diagram type ──
KW='^(graph|flowchart|sequenceDiagram|classDiagram|erDiagram|stateDiagram(-v2)?|gantt|pie|journey|gitGraph|mindmap|timeline|quadrantChart|requirementDiagram|C4Context|C4Container|C4Component|architecture(-beta)?)\b'
LINE="$(grep -vE '^[[:space:]]*$|^[[:space:]]*%%' "$SRC" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' || true)"
printf '%s' "$LINE" | grep -Eq "$KW" || { echo "diagram: error: source does not look like a Mermaid diagram (the first non-comment line must name a diagram type, e.g. flowchart/sequenceDiagram/erDiagram). Source kept at: $SRC" >&2; exit 1; }

OUTPUT="$OUT_DIR/$STEM.$FORMAT"

# ── provenance: one JSONL line per run under .tachyon/ (honest about the npx, non-checksummed mmdc lane) ──
PROV_DIR="$ROOT/.tachyon"; PROV="$PROV_DIR/diagram-runs.jsonl"
record() {  # $1 = status, $2 = output path (or "")
  [ -d "$PROV_DIR" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -cn --arg st "$1" --arg sha "$SRC_SHA" --arg fmt "$FORMAT" --arg src "$SRC" --arg out "${2:-}" \
    --arg pkg "$MMDC_PKG" --arg ver "$MMDC_VERSION" \
    '{status:$st, source_sha256:$sha, format:$fmt, source:$src, output:$out, mmdc_package:$pkg, mmdc_version:$ver, acquisition:"npx", engine_checksummed:false}' >> "$PROV" 2>/dev/null || true
}

# ── resolve a TRUSTED system browser via the shim (unless overridden for tests) ──
if [ -n "$DIAGRAM_CHROME_BIN" ]; then
  CHROME="$DIAGRAM_CHROME_BIN"
else
  # Ferramentas externas vêm do PATH: o Tachyon não provisiona mais, e o manifesto só as NOMEIA em `requires`.
  CHROME="${DIAGRAM_CHROME:-}"
  if [ -z "$CHROME" ]; then for c in google-chrome google-chrome-stable chromium chromium-browser; do CHROME="$(command -v "$c" 2>/dev/null || true)"; [ -n "$CHROME" ] && break; done; fi
  [ -n "$CHROME" ] || { record unavailable ""; echo "diagram: unavailable: no Chromium-based browser on PATH (google-chrome/chromium) — apt/dnf/pacman install chromium, or brew install --cask google-chrome. Source VALIDATED + kept at $SRC" >&2; exit 1; }
fi

# ── resolve mmdc: test-only override → pinned npx. NO unpinned host-global fast path (codex HIGH/D1 — running a host
#    `mmdc` of unknown version while recording provenance as the pinned npx version is both unpinned + false). ──
declare -a MMDC
if [ -n "$DIAGRAM_MMDC" ]; then read -r -a MMDC <<< "$DIAGRAM_MMDC"   # TEST-ONLY override
elif command -v npx >/dev/null 2>&1; then MMDC=(npx -y -p "${MMDC_PKG}@${MMDC_VERSION}" mmdc)
else record unavailable ""; echo "diagram: unavailable: no npx (Node) to acquire mmdc — source VALIDATED + kept at $SRC. Install Node, then re-run." >&2; exit 1; fi

# ── puppeteer config reusing the resolved system browser (no Chromium download) ──
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PCFG="$WORK/puppeteer.json"
CHROME_J="${CHROME//\\/\\\\}"; CHROME_J="${CHROME_J//\"/\\\"}"  # JSON-escape \ and " (defense-in-depth; CHROME is shim-trusted)
printf '{"executablePath":"%s","args":["--no-sandbox","--disable-gpu"]}\n' "$CHROME_J" > "$PCFG"

declare -a RENDER=("${MMDC[@]}" -i "$SRC" -o "$OUTPUT" --puppeteerConfigFile "$PCFG")
[ -n "$THEME" ] && RENDER+=(-t "$THEME")

# PUPPETEER_SKIP_DOWNLOAD=1 → reuse the system browser; npm_config_ignore_scripts=true → block npm lifecycle scripts.
if ! PUPPETEER_SKIP_DOWNLOAD=1 npm_config_ignore_scripts=true "${RENDER[@]}" >"$WORK/mmdc.log" 2>&1; then
  rm -f -- "$OUTPUT" 2>/dev/null || true
  record error ""
  echo "diagram: error: mmdc render failed (likely a Mermaid syntax error). Source kept at $SRC. Log: $(tail -3 "$WORK/mmdc.log" 2>/dev/null | tr '\n' ' ')" >&2
  exit 1
fi
[ -s "$OUTPUT" ] || { rm -f -- "$OUTPUT" 2>/dev/null || true; record error ""; echo "diagram: error: mmdc produced no output at $OUTPUT" >&2; exit 1; }

# warn (not fail) if the asset lands on a git-ignored path
if git -C "$ROOT" check-ignore -q -- "$OUTPUT" 2>/dev/null; then
  echo "diagram: warning: '$OUTPUT' is git-ignored — the asset won't be tracked. Pass --out <tracked dir> or adjust .gitignore." >&2
fi

record ok "$OUTPUT"
echo "diagram: status=ok"
echo "  format=$FORMAT  source=$SRC (tracked)  wrote=$OUTPUT"
echo "  engine=mermaid/mmdc  mmdc=${MMDC_PKG}@${MMDC_VERSION} (npx — not engine-checksummed)"

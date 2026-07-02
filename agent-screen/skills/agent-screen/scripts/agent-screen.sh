#!/usr/bin/env bash
# agent-screen (spec 283) — explicit OS-level screenshots for non-web Visual QA.
# V1 is Linux/WSLg X11 only: ffmpeg x11grab for pixels, xdotool/xwininfo for optional window targeting.
set -euo pipefail

PLUGIN="agent-screen"

usage() {
  cat >&2 <<'EOF'
usage:
  agent-screen doctor
  agent-screen list-windows
  agent-screen screenshot --active --out <png>
  agent-screen screenshot --window <query> --out <png>
EOF
}

die_usage() { echo "agent-screen: $*" >&2; usage; exit 64; }
die_unavailable() { echo "agent-screen: unavailable: $*" >&2; exit 1; }
die_failed() { echo "agent-screen: failed: $*" >&2; exit 1; }

resolve_root() {
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$ROOT" ] || die_unavailable "not inside a git work tree (the Tachyon shims live at <repo>/.tachyon/bin)"
}

resolve_external() {
  local name="$1" shim resolved
  shim="$ROOT/.tachyon/bin/_tachyon-external"
  if [ -x "$shim" ]; then
    resolved="$("$shim" "$PLUGIN" "$name" 2>/dev/null || true)"
    if [ -n "$resolved" ] && [ -x "$resolved" ]; then
      printf '%s\n' "$resolved"
      return 0
    fi
  fi

  # Development fallback for running from the plugin repo before install. Installed Tachyon runs should resolve via shim.
  resolved="$(command -v "$name" 2>/dev/null || true)"
  [ -n "$resolved" ] && [ -x "$resolved" ] || return 1
  printf '%s\n' "$resolved"
}

require_base_backend() {
  resolve_root
  [ -n "${DISPLAY:-}" ] || die_unavailable "\$DISPLAY is not set; no X11 display to capture"
  FFMPEG="$(resolve_external ffmpeg)" || die_unavailable "ffmpeg is not installed or not trusted by Tachyon"
  command -v xdpyinfo >/dev/null 2>&1 || die_unavailable "xdpyinfo is missing; install x11-utils"
  SCREEN_SIZE="$(xdpyinfo 2>/dev/null | awk '/dimensions:/ {value=$2} END {print value}')"
  case "$SCREEN_SIZE" in
    *x*) ;;
    *) die_unavailable "could not read X11 display dimensions from xdpyinfo" ;;
  esac
}

require_window_tools() {
  XDO="$(resolve_external xdotool)" || die_unavailable "xdotool is not installed or not trusted by Tachyon"
  command -v xwininfo >/dev/null 2>&1 || die_unavailable "xwininfo is missing; install x11-utils"
}

json_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g'
}

window_name() {
  "$XDO" getwindowname "$1" 2>/dev/null || true
}

window_geometry() {
  local wid="$1"
  xwininfo -id "$wid" 2>/dev/null | awk '
    /Absolute upper-left X:/ { x=$NF }
    /Absolute upper-left Y:/ { y=$NF }
    /Width:/ { w=$NF }
    /Height:/ { h=$NF }
    END {
      if (x != "" && y != "" && w > 0 && h > 0) {
        printf "%s %s %s %s\n", x, y, w, h
      }
    }'
}

resolve_active_geometry() {
  require_window_tools
  local wid geom
  wid="$("$XDO" getactivewindow 2>/dev/null || true)"
  [ -n "$wid" ] || return 1
  geom="$(window_geometry "$wid")"
  [ -n "$geom" ] || return 1
  printf '%s %s\n' "$wid" "$geom"
}

resolve_window_query() {
  require_window_tools
  local query="$1"
  mapfile -t ids < <("$XDO" search --onlyvisible --name "$query" 2>/dev/null || true)
  [ "${#ids[@]}" -gt 0 ] || die_failed "no visible window matched query '$query'"
  [ "${#ids[@]}" -eq 1 ] || {
    echo "agent-screen: failed: query '$query' matched multiple visible windows:" >&2
    local id
    for id in "${ids[@]}"; do
      printf '  %s  %s\n' "$id" "$(window_name "$id")" >&2
    done
    exit 1
  }
  local geom
  geom="$(window_geometry "${ids[0]}")"
  [ -n "$geom" ] || die_failed "matched window '${ids[0]}' but could not read its geometry"
  printf '%s %s\n' "${ids[0]}" "$geom"
}

prepare_out() {
  local out="$1" dir
  [ -n "$out" ] || die_usage "screenshot requires --out <png>"
  case "$out" in
    *.png|*.PNG) ;;
    *) die_usage "--out must end in .png" ;;
  esac
  dir="$(dirname -- "$out")"
  mkdir -p -- "$dir" || die_failed "could not create output directory: $dir"
  OUT="$out"
  TMP_OUT="${OUT}.tmp.$$.png"
  rm -f -- "$TMP_OUT"
}

capture_png() {
  local input="$1" size="$2"
  if ! "$FFMPEG" -hide_banner -loglevel error -nostdin -y -f x11grab -video_size "$size" -i "$input" -frames:v 1 "$TMP_OUT"; then
    rm -f -- "$TMP_OUT"
    die_failed "ffmpeg x11grab capture failed for input '$input' size '$size'"
  fi
  [ -s "$TMP_OUT" ] || { rm -f -- "$TMP_OUT"; die_failed "capture produced an empty file"; }
  if command -v file >/dev/null 2>&1 && ! file "$TMP_OUT" | grep -q 'PNG image data'; then
    rm -f -- "$TMP_OUT"
    die_failed "capture did not produce a PNG"
  fi
  mv -f -- "$TMP_OUT" "$OUT"
}

cmd_doctor() {
  resolve_root
  local status="ok"
  echo "agent-screen: doctor"
  echo "  backend=x11grab"
  echo "  display=${DISPLAY:-}"
  if [ -z "${DISPLAY:-}" ]; then
    echo "  status=unavailable reason=no-display"
    exit 1
  fi
  if FFMPEG="$(resolve_external ffmpeg)"; then echo "  ffmpeg=$FFMPEG"; else echo "  ffmpeg=missing"; status="unavailable"; fi
  if XDO="$(resolve_external xdotool)"; then echo "  xdotool=$XDO"; else echo "  xdotool=missing"; fi
  if command -v xdpyinfo >/dev/null 2>&1; then
    SCREEN_SIZE="$(xdpyinfo 2>/dev/null | awk '/dimensions:/ {value=$2} END {print value}' || true)"
    echo "  screen_size=${SCREEN_SIZE:-unknown}"
  else
    echo "  xdpyinfo=missing"
    status="unavailable"
  fi
  if command -v xwininfo >/dev/null 2>&1; then echo "  xwininfo=$(command -v xwininfo)"; else echo "  xwininfo=missing"; fi
  [ "$status" = "ok" ] || exit 1
}

cmd_list_windows() {
  require_base_backend
  require_window_tools
  mapfile -t ids < <("$XDO" search --onlyvisible --name '.' 2>/dev/null || true)
  if [ "${#ids[@]}" -eq 0 ]; then
    echo "agent-screen: no visible X11 windows found"
    return 0
  fi
  local id geom name escaped
  for id in "${ids[@]}"; do
    geom="$(window_geometry "$id" || true)"
    name="$(window_name "$id")"
    escaped="$(printf '%s' "$name" | json_escape)"
    printf '{"id":"%s","name":"%s","geometry":"%s"}\n' "$id" "$escaped" "$geom"
  done
}

cmd_screenshot() {
  local mode="" query="" out="" wid="" x="" y="" w="" h="" geom_record
  while [ $# -gt 0 ]; do
    case "$1" in
      --active) mode="active"; shift ;;
      --window) [ $# -ge 2 ] || die_usage "--window requires a value"; mode="window"; query="$2"; shift 2 ;;
      --window=*) mode="window"; query="${1#*=}"; shift ;;
      --out) [ $# -ge 2 ] || die_usage "--out requires a value"; out="$2"; shift 2 ;;
      --out=*) out="${1#*=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      -*) die_usage "unknown flag '$1'" ;;
      *) die_usage "unexpected argument '$1'" ;;
    esac
  done
  [ -n "$mode" ] || die_usage "screenshot requires --active or --window <query>"
  [ "$mode" != "window" ] || [ -n "$query" ] || die_usage "--window requires a non-empty query"

  require_base_backend
  prepare_out "$out"

  if [ "$mode" = "window" ]; then
    read -r wid x y w h < <(resolve_window_query "$query")
    capture_png "${DISPLAY}+${x},${y}" "${w}x${h}"
    geom_record="window_id=$wid x=$x y=$y width=$w height=$h"
    echo "agent-screen: status=ok mode=window $geom_record wrote=$OUT"
    return 0
  fi

  if active_record="$(resolve_active_geometry 2>/dev/null || true)" && [ -n "$active_record" ]; then
    read -r wid x y w h <<< "$active_record"
    capture_png "${DISPLAY}+${x},${y}" "${w}x${h}"
    geom_record="window_id=$wid x=$x y=$y width=$w height=$h"
    echo "agent-screen: status=ok mode=active-window $geom_record wrote=$OUT"
    return 0
  fi

  capture_png "$DISPLAY" "$SCREEN_SIZE"
  echo "agent-screen: status=ok mode=screen-fallback size=$SCREEN_SIZE wrote=$OUT"
}

[ $# -gt 0 ] || { usage; exit 64; }
cmd="$1"; shift
case "$cmd" in
  doctor) [ $# -eq 0 ] || die_usage "doctor takes no arguments"; cmd_doctor ;;
  list-windows) [ $# -eq 0 ] || die_usage "list-windows takes no arguments"; cmd_list_windows ;;
  screenshot) cmd_screenshot "$@" ;;
  -h|--help|help) usage ;;
  *) die_usage "unknown command '$cmd'" ;;
esac

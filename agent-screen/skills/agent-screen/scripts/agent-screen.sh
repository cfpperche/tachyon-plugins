#!/usr/bin/env bash
# agent-screen (spec 283) — explicit OS-level screenshots for non-web Visual QA.
# V1 prefers a Windows host screenshot when running under WSL, then falls back to Linux/WSLg X11:
# PowerShell/.NET for the foreground Windows window; ffmpeg x11grab for X11 pixels; xdotool/xwininfo for X11 window targeting.
set -euo pipefail

PLUGIN="agent-screen"

usage() {
  cat >&2 <<'EOF'
usage:
  agent-screen doctor
  agent-screen list-windows [--json] [--verbose]
  agent-screen screenshot --active --out <png>
  agent-screen screenshot --screen --out <png>
  agent-screen screenshot --window-id <id> --out <png>
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

resolve_powershell() {
  local ps
  ps="$(command -v powershell.exe 2>/dev/null || true)"
  if [ -n "$ps" ] && [ -x "$ps" ]; then printf '%s\n' "$ps"; return 0; fi
  ps="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  if [ -x "$ps" ]; then printf '%s\n' "$ps"; return 0; fi
  ps="$(command -v pwsh.exe 2>/dev/null || true)"
  if [ -n "$ps" ] && [ -x "$ps" ]; then printf '%s\n' "$ps"; return 0; fi
  return 1
}

is_wsl() {
  grep -qi microsoft /proc/version 2>/dev/null
}

json_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g'
}

windows_host_ps1() {
  local ps1="$1"
  cat > "$ps1" <<'PS1'
param(
  [Parameter(Mandatory=$true)][string]$Command,
  [string]$Out = "",
  [string]$WindowId = "",
  [string]$Query = "",
  [switch]$VerboseTitles
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class AgentScreenNative {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")]
  public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }
}
"@

function Get-WindowTitle([IntPtr]$hwnd) {
  $len = [AgentScreenNative]::GetWindowTextLength($hwnd)
  if ($len -le 0) { return "" }
  $sb = New-Object System.Text.StringBuilder ($len + 1)
  [void][AgentScreenNative]::GetWindowText($hwnd, $sb, $sb.Capacity)
  return $sb.ToString()
}

function Short-Title([string]$title) {
  if ($VerboseTitles -or $title.Length -le 80) { return $title }
  return $title.Substring(0, 77) + "..."
}

function Get-Windows {
  $foreground = [AgentScreenNative]::GetForegroundWindow()
  $items = New-Object System.Collections.Generic.List[object]
  $callback = [AgentScreenNative+EnumWindowsProc]{
    param([IntPtr]$hwnd, [IntPtr]$lparam)
    if (-not [AgentScreenNative]::IsWindowVisible($hwnd)) { return $true }
    $title = Get-WindowTitle $hwnd
    if ([string]::IsNullOrWhiteSpace($title)) { return $true }
    $rect = New-Object AgentScreenNative+RECT
    if (-not [AgentScreenNative]::GetWindowRect($hwnd, [ref]$rect)) { return $true }
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -le 0 -or $height -le 0) { return $true }
    $bounds = New-Object System.Drawing.Rectangle $rect.Left, $rect.Top, $width, $height
    $monitor = ""
    foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
      if ([System.Drawing.Rectangle]::Intersect($screen.Bounds, $bounds).Width -gt 0 -and [System.Drawing.Rectangle]::Intersect($screen.Bounds, $bounds).Height -gt 0) {
        $monitor = $screen.DeviceName
        break
      }
    }
    [uint32]$pidValue = 0
    [void][AgentScreenNative]::GetWindowThreadProcessId($hwnd, [ref]$pidValue)
    $processName = ""
    try { $processName = (Get-Process -Id ([int]$pidValue) -ErrorAction Stop).ProcessName } catch {}
    $items.Add([pscustomobject]@{
      id = $hwnd.ToInt64().ToString()
      title = (Short-Title $title)
      fullTitle = $title
      process = $processName
      pid = [int64]$pidValue
      x = $rect.Left
      y = $rect.Top
      width = $width
      height = $height
      monitor = $monitor
      minimized = [AgentScreenNative]::IsIconic($hwnd)
      foreground = ($hwnd -eq $foreground)
    })
    return $true
  }
  [void][AgentScreenNative]::EnumWindows($callback, [IntPtr]::Zero)
  return @($items | Sort-Object -Property foreground -Descending)
}

function Write-Json($obj) {
  $obj | ConvertTo-Json -Compress -Depth 4
}

function Capture-Rect([System.Drawing.Rectangle]$bounds, [string]$out) {
  if ($bounds.Width -le 0 -or $bounds.Height -le 0) {
    [Console]::Error.WriteLine("agent-screen: failed: invalid capture bounds")
    exit 1
  }
  $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
  $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose()
  $bmp.Dispose()
}

function Capture-Window([IntPtr]$hwnd, [System.Drawing.Rectangle]$bounds, [string]$out) {
  if ($hwnd -eq [IntPtr]::Zero) {
    [Console]::Error.WriteLine("agent-screen: failed: invalid window handle")
    exit 1
  }
  if ($bounds.Width -le 0 -or $bounds.Height -le 0) {
    [Console]::Error.WriteLine("agent-screen: failed: invalid window bounds")
    exit 1
  }
  $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  $ok = [AgentScreenNative]::PrintWindow($hwnd, $hdc, 2)
  $g.ReleaseHdc($hdc)
  $g.Dispose()
  if (-not $ok) {
    $bmp.Dispose()
    [Console]::Error.WriteLine("agent-screen: failed: PrintWindow could not capture the requested window")
    exit 1
  }
  $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

function Bounds-For-Hwnd([IntPtr]$hwnd) {
  if ($hwnd -eq [IntPtr]::Zero) { return $null }
  $rect = New-Object AgentScreenNative+RECT
  if (-not [AgentScreenNative]::GetWindowRect($hwnd, [ref]$rect)) { return $null }
  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  if ($width -le 0 -or $height -le 0) { return $null }
  return New-Object System.Drawing.Rectangle $rect.Left, $rect.Top, $width, $height
}

function Emit-Capture([string]$mode, [System.Drawing.Rectangle]$bounds, [string]$out) {
  Capture-Rect $bounds $out
  Write-Output ("out=" + $out)
  Write-Output ("mode=" + $mode)
  Write-Output ("x=" + $bounds.X)
  Write-Output ("y=" + $bounds.Y)
  Write-Output ("width=" + $bounds.Width)
  Write-Output ("height=" + $bounds.Height)
}

function Emit-WindowCapture([string]$mode, [IntPtr]$hwnd, [System.Drawing.Rectangle]$bounds, [string]$out) {
  Capture-Window $hwnd $bounds $out
  Write-Output ("out=" + $out)
  Write-Output ("mode=" + $mode)
  Write-Output ("x=" + $bounds.X)
  Write-Output ("y=" + $bounds.Y)
  Write-Output ("width=" + $bounds.Width)
  Write-Output ("height=" + $bounds.Height)
}

if ($Command -eq "list") {
  $windows = Get-Windows | ForEach-Object {
    [pscustomobject]@{
      id = $_.id
      title = $_.title
      process = $_.process
      pid = $_.pid
      x = $_.x
      y = $_.y
      width = $_.width
      height = $_.height
      monitor = $_.monitor
      minimized = $_.minimized
      foreground = $_.foreground
    }
  }
  Write-Json @($windows)
  exit 0
}

if ($Command -eq "screen") {
  if ([string]::IsNullOrWhiteSpace($Out)) { [Console]::Error.WriteLine("agent-screen: failed: missing output path"); exit 1 }
  $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
  Emit-Capture "screen" $bounds $Out
  exit 0
}

if ($Command -eq "active") {
  if ([string]::IsNullOrWhiteSpace($Out)) { [Console]::Error.WriteLine("agent-screen: failed: missing output path"); exit 1 }
  $hwnd = [AgentScreenNative]::GetForegroundWindow()
  $bounds = Bounds-For-Hwnd $hwnd
  if ($null -eq $bounds) { $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen; Emit-Capture "screen" $bounds $Out; exit 0 }
  Emit-Capture "foreground-window" $bounds $Out
  exit 0
}

if ($Command -eq "window-id") {
  if ([string]::IsNullOrWhiteSpace($Out)) { [Console]::Error.WriteLine("agent-screen: failed: missing output path"); exit 1 }
  if ([string]::IsNullOrWhiteSpace($WindowId)) { [Console]::Error.WriteLine("agent-screen: failed: missing --window-id"); exit 1 }
  try { $hwnd = [IntPtr]([int64]$WindowId) } catch { [Console]::Error.WriteLine("agent-screen: failed: invalid --window-id '$WindowId'"); exit 1 }
  if ([AgentScreenNative]::IsIconic($hwnd)) { [Console]::Error.WriteLine("agent-screen: failed: window id '$WindowId' is minimized; restore it before capture"); exit 1 }
  $bounds = Bounds-For-Hwnd $hwnd
  if ($null -eq $bounds) { [Console]::Error.WriteLine("agent-screen: failed: no capturable window for id '$WindowId'"); exit 1 }
  Emit-WindowCapture "window-id" $hwnd $bounds $Out
  exit 0
}

if ($Command -eq "window-query") {
  if ([string]::IsNullOrWhiteSpace($Out)) { [Console]::Error.WriteLine("agent-screen: failed: missing output path"); exit 1 }
  if ([string]::IsNullOrWhiteSpace($Query)) { [Console]::Error.WriteLine("agent-screen: failed: missing --window query"); exit 1 }
  $matches = @(Get-Windows | Where-Object {
    ($_.fullTitle -like ("*" + $Query + "*")) -or ($_.process -like ("*" + $Query + "*"))
  })
  if ($matches.Count -eq 0) {
    [Console]::Error.WriteLine("agent-screen: failed: no visible Windows-host window matched query '$Query'")
    exit 1
  }
  if ($matches.Count -gt 1) {
    [Console]::Error.WriteLine("agent-screen: failed: query '$Query' matched multiple Windows-host windows; use --window-id")
    $candidates = $matches | Select-Object -First 8 | ForEach-Object {
      [pscustomobject]@{ id=$_.id; title=$_.title; process=$_.process; x=$_.x; y=$_.y; width=$_.width; height=$_.height }
    }
    [Console]::Error.WriteLine((Write-Json @($candidates)))
    exit 1
  }
  if ($matches[0].minimized) { [Console]::Error.WriteLine("agent-screen: failed: matched window is minimized; restore it before capture"); exit 1 }
  $hwnd = [IntPtr]([int64]$matches[0].id)
  $bounds = Bounds-For-Hwnd $hwnd
  if ($null -eq $bounds) { [Console]::Error.WriteLine("agent-screen: failed: matched window but could not read bounds"); exit 1 }
  Emit-WindowCapture "window" $hwnd $bounds $Out
  Write-Output ("window_id=" + $matches[0].id)
  Write-Output ("process=" + $matches[0].process)
  exit 0
}

[Console]::Error.WriteLine("agent-screen: failed: unknown Windows-host command '$Command'")
exit 1
PS1
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
  chmod 0644 "$OUT" 2>/dev/null || true
}

capture_windows_host_png() {
  local command="${1:-active}" selector="${2:-}" ps ps1 win_out unix_out
  is_wsl || return 1
  ps="$(resolve_powershell)" || return 1
  command -v wslpath >/dev/null 2>&1 || return 1

  ps1="$(mktemp --suffix=.ps1)"
  windows_host_ps1 "$ps1"
  local output mode x y width height ps_args err rc
  err="$(mktemp)"
  ps_args=(-NoProfile -ExecutionPolicy Bypass -File "$ps1" -Command "$command")
  case "$command" in
    active|screen) ;;
    window-id) ps_args+=(-WindowId "$selector") ;;
    window-query) ps_args+=(-Query "$selector") ;;
    *) rm -f -- "$ps1" "$err"; return 1 ;;
  esac
  ps_args+=(-Out "$TMP_OUT")
  set +e
  output="$("$ps" "${ps_args[@]}" 2>"$err" | tr -d '\r')"
  rc=$?
  set -e
  rm -f -- "$ps1"
  if [ "$rc" -ne 0 ]; then
    cat "$err" >&2
    rm -f -- "$err" "$TMP_OUT"
    return "$rc"
  fi
  rm -f -- "$err"
  win_out="$(printf '%s\n' "$output" | awk -F= '$1=="out" {print $2; exit}')"
  mode="$(printf '%s\n' "$output" | awk -F= '$1=="mode" {print $2; exit}')"
  x="$(printf '%s\n' "$output" | awk -F= '$1=="x" {print $2; exit}')"
  y="$(printf '%s\n' "$output" | awk -F= '$1=="y" {print $2; exit}')"
  width="$(printf '%s\n' "$output" | awk -F= '$1=="width" {print $2; exit}')"
  height="$(printf '%s\n' "$output" | awk -F= '$1=="height" {print $2; exit}')"
  [ -s "$TMP_OUT" ] || { rm -f -- "$TMP_OUT"; return 1; }
  mv -f -- "$TMP_OUT" "$OUT"
  chmod 0644 "$OUT" 2>/dev/null || true
  echo "agent-screen: status=ok backend=windows-host mode=$mode x=$x y=$y width=$width height=$height wrote=$OUT"
  printf '%s\n' "$output" | awk -F= '$1=="window_id" || $1=="process" {print "  " $0}'
  return 0
}

cmd_windows_list() {
  local verbose="$1" ps ps1 err rc
  is_wsl || return 1
  ps="$(resolve_powershell)" || return 1
  ps1="$(mktemp --suffix=.ps1)"
  err="$(mktemp)"
  windows_host_ps1 "$ps1"
  set +e
  if [ "$verbose" = "yes" ]; then
    "$ps" -NoProfile -ExecutionPolicy Bypass -File "$ps1" -Command list -VerboseTitles 2>"$err" | tr -d '\r'
    rc=${PIPESTATUS[0]}
  else
    "$ps" -NoProfile -ExecutionPolicy Bypass -File "$ps1" -Command list 2>"$err" | tr -d '\r'
    rc=${PIPESTATUS[0]}
  fi
  set -e
  rm -f -- "$ps1"
  if [ "$rc" -ne 0 ]; then
    cat "$err" >&2
    rm -f -- "$err"
    return "$rc"
  fi
  rm -f -- "$err"
}

cmd_doctor() {
  resolve_root
  local windows_ok="no" x11_ok="yes"
  echo "agent-screen: doctor"
  echo "  backends=windows-host,x11grab"
  if is_wsl && PS="$(resolve_powershell)"; then
    echo "  windows_host=available powershell=$PS"
    windows_ok="yes"
  else
    echo "  windows_host=unavailable"
  fi
  echo "  display=${DISPLAY:-}"
  if [ -z "${DISPLAY:-}" ]; then
    echo "  x11grab=unavailable reason=no-display"
    x11_ok="no"
    [ "$windows_ok" = "yes" ] && return 0
    echo "  status=unavailable reason=no-backend"
    exit 1
  fi
  if FFMPEG="$(resolve_external ffmpeg)"; then echo "  ffmpeg=$FFMPEG"; else echo "  ffmpeg=missing"; x11_ok="no"; fi
  if XDO="$(resolve_external xdotool)"; then echo "  xdotool=$XDO"; else echo "  xdotool=missing"; fi
  if command -v xdpyinfo >/dev/null 2>&1; then
    SCREEN_SIZE="$(xdpyinfo 2>/dev/null | awk '/dimensions:/ {value=$2} END {print value}' || true)"
    echo "  screen_size=${SCREEN_SIZE:-unknown}"
  else
    echo "  xdpyinfo=missing"
    x11_ok="no"
  fi
  if command -v xwininfo >/dev/null 2>&1; then echo "  xwininfo=$(command -v xwininfo)"; else echo "  xwininfo=missing"; fi
  [ "$windows_ok" = "yes" ] || [ "$x11_ok" = "yes" ] || exit 1
}

cmd_list_windows() {
  local json="no" verbose="no"
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json="yes"; shift ;;
      --verbose) verbose="yes"; shift ;;
      -h|--help) usage; exit 0 ;;
      -*) die_usage "unknown list-windows flag '$1'" ;;
      *) die_usage "unexpected list-windows argument '$1'" ;;
    esac
  done
  if cmd_windows_list "$verbose"; then
    return 0
  fi
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
  local mode="" query="" window_id="" out="" wid="" x="" y="" w="" h="" geom_record
  while [ $# -gt 0 ]; do
    case "$1" in
      --active) mode="active"; shift ;;
      --screen) mode="screen"; shift ;;
      --window) [ $# -ge 2 ] || die_usage "--window requires a value"; mode="window"; query="$2"; shift 2 ;;
      --window=*) mode="window"; query="${1#*=}"; shift ;;
      --window-id) [ $# -ge 2 ] || die_usage "--window-id requires a value"; mode="window-id"; window_id="$2"; shift 2 ;;
      --window-id=*) mode="window-id"; window_id="${1#*=}"; shift ;;
      --out) [ $# -ge 2 ] || die_usage "--out requires a value"; out="$2"; shift 2 ;;
      --out=*) out="${1#*=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      -*) die_usage "unknown flag '$1'" ;;
      *) die_usage "unexpected argument '$1'" ;;
    esac
  done
  [ -n "$mode" ] || die_usage "screenshot requires --active, --screen, --window-id <id>, or --window <query>"
  [ "$mode" != "window" ] || [ -n "$query" ] || die_usage "--window requires a non-empty query"
  [ "$mode" != "window-id" ] || [ -n "$window_id" ] || die_usage "--window-id requires a non-empty id"

  prepare_out "$out"

  case "$mode" in
    screen)
      capture_windows_host_png screen || exit 1
      return 0
      ;;
    window-id)
      capture_windows_host_png window-id "$window_id" || exit 1
      return 0
      ;;
    window)
      if is_wsl && resolve_powershell >/dev/null 2>&1; then
        capture_windows_host_png window-query "$query" || exit 1
        return 0
      fi
      ;;
  esac

  if [ "$mode" = "window" ]; then
    require_base_backend
    read -r wid x y w h < <(resolve_window_query "$query")
    capture_png "${DISPLAY}+${x},${y}" "${w}x${h}"
    geom_record="window_id=$wid x=$x y=$y width=$w height=$h"
    echo "agent-screen: status=ok mode=window $geom_record wrote=$OUT"
    return 0
  fi

  if capture_windows_host_png active; then
    return 0
  fi

  require_base_backend

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
  list-windows) cmd_list_windows "$@" ;;
  screenshot) cmd_screenshot "$@" ;;
  -h|--help|help) usage ;;
  *) die_usage "unknown command '$cmd'" ;;
esac

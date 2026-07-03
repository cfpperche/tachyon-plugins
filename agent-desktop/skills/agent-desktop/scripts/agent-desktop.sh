#!/usr/bin/env bash
# agent-desktop (spec 334) - explicit desktop-control primitives for installed-app dogfood.
# V1 controls the Windows host desktop from WSL via PowerShell/Win32 APIs.
set -euo pipefail

PLUGIN="agent-desktop"

usage() {
  cat >&2 <<'EOF'
usage:
  agent-desktop doctor
  agent-desktop list-windows [--json] [--verbose]
  agent-desktop launch --app <name-or-path> [--json]
  agent-desktop open-url --browser chrome [--new-window] <http-or-https-url> [--json]
  agent-desktop wait-window --process <name> [--title <substring>] --timeout <seconds> [--json]
  agent-desktop focus --window-id <id> [--json]
  agent-desktop focus --process <name> [--title <substring>] [--json]
  agent-desktop restore --window-id <id> [--json]
EOF
}

json_escape() {
  if command -v perl >/dev/null 2>&1; then
    perl -MJSON::PP -0ne 'print JSON::PP->new->ascii->encode($_)'
    return 0
  fi
  printf '"'
  sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g; s/\r/\\r/g; s/$/\\n/' | tr -d '\n' | sed 's/\\n$//'
  printf '"'
}

emit_shell_error() {
  local code="$1" error="$2" message="$3"
  printf '{"ok":false,"plugin":"%s","error":"%s","message":%s,"exit_code":%s}\n' \
    "$PLUGIN" "$error" "$(printf '%s' "$message" | json_escape)" "$code"
  exit "$code"
}

die_usage() {
  usage
  emit_shell_error 64 "invalid-argument" "$*"
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

run_with_timeout() {
  local seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

windows_host_ps1() {
  local ps1="$1"
  cat > "$ps1" <<'PS1'
param(
  [Parameter(Mandatory=$true)][string]$Command,
  [string]$WindowId = "",
  [string]$ProcessName = "",
  [string]$Title = "",
  [int]$TimeoutSeconds = 10,
  [string]$App = "",
  [string]$Browser = "",
  [string]$Url = "",
  [switch]$NewWindow,
  [switch]$VerboseTitles
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class AgentDesktopDpi {
  [DllImport("user32.dll")]
  public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")]
  public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);
}
"@
try {
  [void][AgentDesktopDpi]::SetProcessDpiAwarenessContext([IntPtr](-4))
} catch {
  try { [void][AgentDesktopDpi]::SetProcessDPIAware() } catch {}
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class AgentDesktopNative {
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
  public static extern IntPtr GetAncestor(IntPtr hwnd, uint gaFlags);
  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll")]
  public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("user32.dll")]
  public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  [DllImport("kernel32.dll")]
  public static extern uint GetCurrentThreadId();
  [DllImport("dwmapi.dll")]
  public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }
}
"@

function Finish([int]$Code, [object]$Payload) {
  $Payload | Add-Member -NotePropertyName plugin -NotePropertyValue "agent-desktop" -Force
  $Payload | Add-Member -NotePropertyName exit_code -NotePropertyValue $Code -Force
  $Payload | ConvertTo-Json -Compress -Depth 8
  exit $Code
}

function Error-Payload([string]$ErrorName, [string]$Message, [object[]]$Candidates = @()) {
  $obj = [ordered]@{ ok = $false; error = $ErrorName; message = $Message }
  if ($Candidates.Count -gt 0) { $obj.candidates = $Candidates }
  return [pscustomobject]$obj
}

function Bounds-From-Rect([AgentDesktopNative+RECT]$rect) {
  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  if ($width -le 0 -or $height -le 0) { return $null }
  return New-Object System.Drawing.Rectangle $rect.Left, $rect.Top, $width, $height
}

function Bounds-For-Hwnd([IntPtr]$hwnd) {
  if ($hwnd -eq [IntPtr]::Zero) { return $null }
  $rect = New-Object AgentDesktopNative+RECT
  $dwmResult = [AgentDesktopNative]::DwmGetWindowAttribute(
    $hwnd,
    9,
    [ref]$rect,
    [System.Runtime.InteropServices.Marshal]::SizeOf([type][AgentDesktopNative+RECT])
  )
  if ($dwmResult -eq 0) {
    $bounds = Bounds-From-Rect $rect
    if ($null -ne $bounds) { return $bounds }
  }
  $rect = New-Object AgentDesktopNative+RECT
  if (-not [AgentDesktopNative]::GetWindowRect($hwnd, [ref]$rect)) { return $null }
  return Bounds-From-Rect $rect
}

function Get-WindowTitle([IntPtr]$hwnd) {
  $len = [AgentDesktopNative]::GetWindowTextLength($hwnd)
  if ($len -le 0) { return "" }
  $sb = New-Object System.Text.StringBuilder ($len + 1)
  [void][AgentDesktopNative]::GetWindowText($hwnd, $sb, $sb.Capacity)
  return $sb.ToString()
}

function Short-Title([string]$Value) {
  if ($VerboseTitles -or $Value.Length -le 80) { return $Value }
  return $Value.Substring(0, 77) + "..."
}

function Root-Hwnd([IntPtr]$hwnd) {
  if ($hwnd -eq [IntPtr]::Zero) { return [IntPtr]::Zero }
  $root = [AgentDesktopNative]::GetAncestor($hwnd, 2)
  if ($root -eq [IntPtr]::Zero) { return $hwnd }
  return $root
}

function Get-ForegroundRootId {
  return (Root-Hwnd ([AgentDesktopNative]::GetForegroundWindow())).ToInt64().ToString()
}

function Window-Object([IntPtr]$hwnd) {
  $titleValue = Get-WindowTitle $hwnd
  if ([string]::IsNullOrWhiteSpace($titleValue)) { return $null }
  $bounds = Bounds-For-Hwnd $hwnd
  if ($null -eq $bounds) { return $null }
  [uint32]$pidValue = 0
  [void][AgentDesktopNative]::GetWindowThreadProcessId($hwnd, [ref]$pidValue)
  $processValue = ""
  try { $processValue = (Get-Process -Id ([int]$pidValue) -ErrorAction Stop).ProcessName } catch {}
  $root = Root-Hwnd $hwnd
  return [pscustomobject]@{
    id = $hwnd.ToInt64().ToString()
    title = (Short-Title $titleValue)
    fullTitle = $titleValue
    process = $processValue
    pid = [int64]$pidValue
    x = $bounds.X
    y = $bounds.Y
    width = $bounds.Width
    height = $bounds.Height
    minimized = [AgentDesktopNative]::IsIconic($hwnd)
    foreground = ($root.ToInt64().ToString() -eq (Get-ForegroundRootId))
  }
}

function Public-Window([object]$Window) {
  if ($null -eq $Window) { return $null }
  $obj = [ordered]@{
    id = $Window.id
    title = $Window.title
    process = $Window.process
    pid = $Window.pid
    x = $Window.x
    y = $Window.y
    width = $Window.width
    height = $Window.height
    minimized = $Window.minimized
    foreground = $Window.foreground
  }
  if ($VerboseTitles) { $obj.fullTitle = $Window.fullTitle }
  return [pscustomobject]$obj
}

function Get-Windows {
  $items = New-Object System.Collections.Generic.List[object]
  $callback = [AgentDesktopNative+EnumWindowsProc]{
    param([IntPtr]$hwnd, [IntPtr]$lparam)
    if (-not [AgentDesktopNative]::IsWindowVisible($hwnd)) { return $true }
    $item = Window-Object $hwnd
    if ($null -ne $item) { $items.Add($item) }
    return $true
  }
  [void][AgentDesktopNative]::EnumWindows($callback, [IntPtr]::Zero)
  return @($items | Sort-Object process, title, id)
}

function Resolve-Target {
  $windows = @(Get-Windows)
  if (-not [string]::IsNullOrWhiteSpace($WindowId)) {
    $match = @($windows | Where-Object { $_.id -eq $WindowId })
    if ($match.Count -eq 1) { return $match[0] }
    Finish 71 (Error-Payload "not-found" "No visible top-level window matched window id '$WindowId'.")
  }
  if ([string]::IsNullOrWhiteSpace($ProcessName)) {
    Finish 64 (Error-Payload "invalid-argument" "Pass --window-id or --process for this command.")
  }
  $processNeedle = $ProcessName.ToLowerInvariant()
  $titleNeedle = $Title.ToLowerInvariant()
  $matches = @($windows | Where-Object {
    $proc = ("" + $_.process).ToLowerInvariant()
    $titleValue = ("" + $_.fullTitle).ToLowerInvariant()
    $proc.Contains($processNeedle) -and ([string]::IsNullOrWhiteSpace($Title) -or $titleValue.Contains($titleNeedle))
  })
  if ($matches.Count -eq 0) {
    Finish 71 (Error-Payload "not-found" "No visible top-level window matched process '$ProcessName' and title '$Title'.")
  }
  if ($matches.Count -gt 1) {
    $candidates = @($matches | Select-Object -First 8 | ForEach-Object { Public-Window $_ })
    Finish 72 (Error-Payload "ambiguous" "Multiple windows matched; retry with --window-id." $candidates)
  }
  return $matches[0]
}

function Restore-TargetWindow([object]$Window) {
  $hwnd = [IntPtr]::new([int64]$Window.id)
  $wasMinimized = [AgentDesktopNative]::IsIconic($hwnd)
  [void][AgentDesktopNative]::ShowWindow($hwnd, 9)
  Start-Sleep -Milliseconds 250
  $stillMinimized = [AgentDesktopNative]::IsIconic($hwnd)
  if ($stillMinimized) {
    Finish 1 (Error-Payload "failed" "Window '$($Window.id)' is still minimized after restore request.")
  }
  $fresh = Window-Object $hwnd
  return [pscustomobject]@{
    restored = $wasMinimized
    window = (Public-Window $fresh)
  }
}

function Focus-TargetWindow([object]$Window) {
  $hwnd = [IntPtr]::new([int64]$Window.id)
  $targetRoot = (Root-Hwnd $hwnd).ToInt64().ToString()
  $attempts = New-Object System.Collections.ArrayList
  $restoreResult = Restore-TargetWindow $Window

  function Is-Focused {
    return ((Get-ForegroundRootId) -eq $targetRoot)
  }
  function Add-Attempt([string]$Name, [bool]$ApiOk) {
    Start-Sleep -Milliseconds 180
    [void]$attempts.Add([pscustomobject]@{ name = $Name; api_ok = $ApiOk; focused = (Is-Focused) })
  }

  $ok = [AgentDesktopNative]::SetForegroundWindow($hwnd)
  Add-Attempt "set-foreground" $ok
  if (-not (Is-Focused)) {
    [AgentDesktopNative]::keybd_event([byte]0x12, [byte]0, [uint32]0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 40
    [AgentDesktopNative]::keybd_event([byte]0x12, [byte]0, [uint32]2, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    $ok = [AgentDesktopNative]::SetForegroundWindow($hwnd)
    Add-Attempt "alt-unlock-set-foreground" $ok
  }
  if (-not (Is-Focused)) {
    $foreground = [AgentDesktopNative]::GetForegroundWindow()
    [uint32]$targetPid = 0
    [uint32]$foregroundPid = 0
    $targetThread = [AgentDesktopNative]::GetWindowThreadProcessId($hwnd, [ref]$targetPid)
    $foregroundThread = [AgentDesktopNative]::GetWindowThreadProcessId($foreground, [ref]$foregroundPid)
    $attachedTarget = $false
    $attachedForeground = $false
    try {
      $currentThread = [AgentDesktopNative]::GetCurrentThreadId()
      if ($targetThread -ne $currentThread) {
        $attachedTarget = [AgentDesktopNative]::AttachThreadInput($currentThread, $targetThread, $true)
      }
      if ($foregroundThread -ne 0 -and $foregroundThread -ne $currentThread) {
        $attachedForeground = [AgentDesktopNative]::AttachThreadInput($currentThread, $foregroundThread, $true)
      }
      [void][AgentDesktopNative]::BringWindowToTop($hwnd)
      $ok = [AgentDesktopNative]::SetForegroundWindow($hwnd)
      Add-Attempt "attach-thread-set-foreground" $ok
    } finally {
      if ($attachedTarget) { [void][AgentDesktopNative]::AttachThreadInput([AgentDesktopNative]::GetCurrentThreadId(), $targetThread, $false) }
      if ($attachedForeground) { [void][AgentDesktopNative]::AttachThreadInput([AgentDesktopNative]::GetCurrentThreadId(), $foregroundThread, $false) }
    }
  }

  $focused = Is-Focused
  $fresh = Window-Object $hwnd
  if (-not $focused) {
    $payload = Error-Payload "focus-denied" "Windows did not allow the target window to become foreground."
    $payload | Add-Member -NotePropertyName window -NotePropertyValue (Public-Window $fresh) -Force
    $payload | Add-Member -NotePropertyName attempts -NotePropertyValue @($attempts.ToArray()) -Force
    Finish 74 $payload
  }
  return [pscustomobject]@{
    restored = $restoreResult.restored
    focused = $true
    window = (Public-Window $fresh)
    attempts = @($attempts.ToArray())
  }
}

function Resolve-ChromePath {
  $candidates = @()
  try {
    $appPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction Stop)."(default)"
    if (-not [string]::IsNullOrWhiteSpace($appPath)) { $candidates += $appPath }
  } catch {}
  try {
    $appPath = (Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction Stop)."(default)"
    if (-not [string]::IsNullOrWhiteSpace($appPath)) { $candidates += $appPath }
  } catch {}
  $candidates += @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
  )
  foreach ($candidate in $candidates) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) { return $candidate }
  }
  $cmd = Get-Command "chrome.exe" -ErrorAction SilentlyContinue
  if ($null -ne $cmd) { return $cmd.Source }
  return $null
}

function Resolve-AppPath([string]$NameOrPath) {
  if ([string]::IsNullOrWhiteSpace($NameOrPath)) {
    Finish 64 (Error-Payload "invalid-argument" "Pass --app <name-or-path>.")
  }
  if (Test-Path -LiteralPath $NameOrPath) { return (Resolve-Path -LiteralPath $NameOrPath).Path }
  switch -Regex ($NameOrPath.ToLowerInvariant()) {
    "^(chrome|chrome\.exe|google-chrome|google-chrome-stable)$" {
      $chrome = Resolve-ChromePath
      if ($null -eq $chrome) { Finish 71 (Error-Payload "not-found" "Chrome executable was not found on the Windows host.") }
      return $chrome
    }
    "^(code|code\.exe|vscode|visual-studio-code)$" {
      $cmd = Get-Command "Code.exe" -ErrorAction SilentlyContinue
      if ($null -ne $cmd) { return $cmd.Source }
      $candidates = @(
        "$env:LocalAppData\Programs\Microsoft VS Code\Code.exe",
        "$env:ProgramFiles\Microsoft VS Code\Code.exe"
      )
      foreach ($candidate in $candidates) { if (Test-Path -LiteralPath $candidate) { return $candidate } }
      Finish 71 (Error-Payload "not-found" "VS Code executable was not found on the Windows host.")
    }
    "^(discord|discord\.exe)$" {
      $cmd = Get-Command "Discord.exe" -ErrorAction SilentlyContinue
      if ($null -ne $cmd) { return $cmd.Source }
      $candidate = "$env:LocalAppData\Discord\Update.exe"
      if (Test-Path -LiteralPath $candidate) { return $candidate }
      Finish 71 (Error-Payload "not-found" "Discord executable was not found on the Windows host.")
    }
    "^(explorer|explorer\.exe)$" {
      return "$env:WINDIR\explorer.exe"
    }
  }
  return $NameOrPath
}

function Command-Doctor {
  $chrome = Resolve-ChromePath
  $payload = [pscustomobject]@{
    ok = $true
    command = "doctor"
    backend = "windows-host"
    powershell = $PSHOME
    chrome_available = ($null -ne $chrome)
    chrome_path = $chrome
  }
  Finish 0 $payload
}

function Command-ListWindows {
  $windows = @(Get-Windows | ForEach-Object { Public-Window $_ })
  Finish 0 ([pscustomobject]@{ ok = $true; command = "list-windows"; windows = $windows; count = $windows.Count })
}

function Command-Launch {
  $path = Resolve-AppPath $App
  try {
    $proc = Start-Process -FilePath $path -PassThru
  } catch {
    Finish 1 (Error-Payload "failed" "Could not launch '$App': $($_.Exception.Message)")
  }
  Finish 0 ([pscustomobject]@{
    ok = $true
    command = "launch"
    app = $App
    path = $path
    launched = $true
    pid = $proc.Id
  })
}

function Command-OpenUrl {
  if ($Browser.ToLowerInvariant() -ne "chrome") {
    Finish 64 (Error-Payload "invalid-argument" "Only --browser chrome is supported in v1.")
  }
  if ($Url -notmatch '^(?i:https?)://') {
    Finish 64 (Error-Payload "invalid-argument" "open-url only accepts http:// or https:// URLs.")
  }
  $chrome = Resolve-ChromePath
  if ($null -eq $chrome) {
    Finish 71 (Error-Payload "not-found" "Chrome executable was not found on the Windows host.")
  }
  $beforeIds = @{}
  foreach ($window in @(Get-Windows | Where-Object { ("" + $_.process).ToLowerInvariant().Contains("chrome") })) {
    $beforeIds[$window.id] = $true
  }
  $args = @("--new-window", $Url)
  try {
    $proc = Start-Process -FilePath $chrome -ArgumentList $args -PassThru
  } catch {
    Finish 1 (Error-Payload "failed" "Could not open URL in Chrome: $($_.Exception.Message)")
  }
  $deadline = (Get-Date).AddSeconds(8)
  $newWindows = @()
  do {
    $chromeWindows = @(Get-Windows | Where-Object { ("" + $_.process).ToLowerInvariant().Contains("chrome") })
    $newWindows = @($chromeWindows | Where-Object { -not $beforeIds.ContainsKey($_.id) })
    if ($newWindows.Count -eq 1) { break }
    if ($newWindows.Count -gt 1) {
      $foregroundNew = @($newWindows | Where-Object { $_.foreground })
      if ($foregroundNew.Count -eq 1) {
        $newWindows = @($foregroundNew[0])
        break
      }
    }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  if ($newWindows.Count -eq 0) {
    Finish 73 (Error-Payload "timeout" "Chrome launched, but agent-desktop could not identify the new top-level window.")
  }
  if ($newWindows.Count -gt 1) {
    $candidates = @($newWindows | Select-Object -First 8 | ForEach-Object { Public-Window $_ })
    Finish 72 (Error-Payload "ambiguous" "Chrome opened more than one new matching top-level window." $candidates)
  }
  $window = Public-Window $newWindows[0]
  Finish 0 ([pscustomobject]@{
    ok = $true
    command = "open-url"
    browser = "chrome"
    path = $chrome
    url = $Url
    new_window = $true
    launched = $true
    pid = $proc.Id
    window_id = $window.id
    window = $window
  })
}

function Command-WaitWindow {
  if ([string]::IsNullOrWhiteSpace($ProcessName)) {
    Finish 64 (Error-Payload "invalid-argument" "wait-window requires --process <name>.")
  }
  if ($TimeoutSeconds -lt 1) {
    Finish 64 (Error-Payload "invalid-argument" "--timeout must be at least 1 second.")
  }
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $windows = @(Get-Windows)
    $processNeedle = $ProcessName.ToLowerInvariant()
    $titleNeedle = $Title.ToLowerInvariant()
    $matches = @($windows | Where-Object {
      $proc = ("" + $_.process).ToLowerInvariant()
      $titleValue = ("" + $_.fullTitle).ToLowerInvariant()
      $proc.Contains($processNeedle) -and ([string]::IsNullOrWhiteSpace($Title) -or $titleValue.Contains($titleNeedle))
    })
    if ($matches.Count -eq 1) {
      Finish 0 ([pscustomobject]@{
        ok = $true
        command = "wait-window"
        process = $ProcessName
        title = $Title
        window_id = $matches[0].id
        window = (Public-Window $matches[0])
      })
    }
    if ($matches.Count -gt 1) {
      $candidates = @($matches | Select-Object -First 8 | ForEach-Object { Public-Window $_ })
      Finish 72 (Error-Payload "ambiguous" "Multiple windows matched while waiting; retry with a narrower --title or --window-id." $candidates)
    }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  Finish 73 (Error-Payload "timeout" "No matching window appeared before timeout.")
}

try {
  switch ($Command) {
    "doctor" { Command-Doctor }
    "list-windows" { Command-ListWindows }
    "launch" { Command-Launch }
    "open-url" { Command-OpenUrl }
    "wait-window" { Command-WaitWindow }
    "focus" {
      $target = Resolve-Target
      $result = Focus-TargetWindow $target
      Finish 0 ([pscustomobject]@{
        ok = $true
        command = "focus"
        window_id = $result.window.id
        restored = $result.restored
        focused = $result.focused
        window = $result.window
        attempts = $result.attempts
      })
    }
    "restore" {
      $target = Resolve-Target
      $result = Restore-TargetWindow $target
      Finish 0 ([pscustomobject]@{
        ok = $true
        command = "restore"
        window_id = $result.window.id
        restored = $result.restored
        window = $result.window
      })
    }
    default {
      Finish 64 (Error-Payload "invalid-argument" "Unknown command '$Command'.")
    }
  }
} catch {
  Finish 1 (Error-Payload "failed" $_.Exception.Message)
}
PS1
}

invoke_windows_host() {
  local command="$1" timeout_seconds="$2"
  shift 2

  is_wsl || emit_shell_error 70 "backend-unavailable" "agent-desktop v1 requires WSL controlling a Windows host desktop."
  local ps
  ps="$(resolve_powershell)" || emit_shell_error 70 "backend-unavailable" "powershell.exe was not found."
  command -v wslpath >/dev/null 2>&1 || emit_shell_error 70 "backend-unavailable" "wslpath was not found."

  local ps1 ps1_win
  ps1="$(mktemp --suffix=.ps1)"
  if [ -z "${AGENT_DESKTOP_KEEP_HELPER:-}" ]; then
    trap 'rm -f -- "$ps1"' RETURN
  else
    echo "agent-desktop: debug helper: $ps1" >&2
  fi
  windows_host_ps1 "$ps1"
  ps1_win="$(wslpath -w "$ps1")" || emit_shell_error 70 "backend-unavailable" "could not convert helper path with wslpath."

  run_with_timeout "$timeout_seconds" "$ps" -NoProfile -ExecutionPolicy Bypass -File "$ps1_win" -Command "$command" "$@"
}

command_name="${1:-}"
[ -n "$command_name" ] || die_usage "missing command"
shift || true

case "$command_name" in
  doctor)
    [ "$#" -eq 0 ] || die_usage "doctor takes no arguments"
    invoke_windows_host doctor 10
    ;;
  list-windows)
    verbose_args=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) shift ;;
        --verbose) verbose_args+=("-VerboseTitles"); shift ;;
        *) die_usage "unknown list-windows argument: $1" ;;
      esac
    done
    invoke_windows_host list-windows 15 "${verbose_args[@]}"
    ;;
  launch)
    app=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) shift ;;
        --app) [ "$#" -ge 2 ] || die_usage "--app requires a value"; app="$2"; shift 2 ;;
        *) die_usage "unknown launch argument: $1" ;;
      esac
    done
    [ -n "$app" ] || die_usage "launch requires --app <name-or-path>"
    invoke_windows_host launch 20 -App "$app"
    ;;
  open-url)
    browser=""
    url=""
    new_window=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) shift ;;
        --browser) [ "$#" -ge 2 ] || die_usage "--browser requires a value"; browser="$2"; shift 2 ;;
        --new-window) new_window=("-NewWindow"); shift ;;
        --*) die_usage "unknown open-url argument: $1" ;;
        *) [ -z "$url" ] || die_usage "open-url accepts exactly one URL"; url="$1"; shift ;;
      esac
    done
    [ -n "$browser" ] || die_usage "open-url requires --browser chrome"
    [ -n "$url" ] || die_usage "open-url requires a URL"
    invoke_windows_host open-url 20 -Browser "$browser" -Url "$url" "${new_window[@]}"
    ;;
  wait-window)
    process_name=""
    title=""
    timeout_seconds="10"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) shift ;;
        --process) [ "$#" -ge 2 ] || die_usage "--process requires a value"; process_name="$2"; shift 2 ;;
        --title) [ "$#" -ge 2 ] || die_usage "--title requires a value"; title="$2"; shift 2 ;;
        --timeout) [ "$#" -ge 2 ] || die_usage "--timeout requires a value"; timeout_seconds="$2"; shift 2 ;;
        *) die_usage "unknown wait-window argument: $1" ;;
      esac
    done
    [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || die_usage "--timeout must be an integer number of seconds"
    [ -n "$process_name" ] || die_usage "wait-window requires --process <name>"
    invoke_windows_host wait-window "$((timeout_seconds + 10))" -ProcessName "$process_name" -Title "$title" -TimeoutSeconds "$timeout_seconds"
    ;;
  focus|restore)
    window_id=""
    process_name=""
    title=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) shift ;;
        --window-id) [ "$#" -ge 2 ] || die_usage "--window-id requires a value"; window_id="$2"; shift 2 ;;
        --process) [ "$#" -ge 2 ] || die_usage "--process requires a value"; process_name="$2"; shift 2 ;;
        --title) [ "$#" -ge 2 ] || die_usage "--title requires a value"; title="$2"; shift 2 ;;
        *) die_usage "unknown $command_name argument: $1" ;;
      esac
    done
    if [ -z "$window_id" ] && [ -z "$process_name" ]; then
      die_usage "$command_name requires --window-id <id> or --process <name>"
    fi
    invoke_windows_host "$command_name" 20 -WindowId "$window_id" -ProcessName "$process_name" -Title "$title"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    die_usage "unknown command: $command_name"
    ;;
esac

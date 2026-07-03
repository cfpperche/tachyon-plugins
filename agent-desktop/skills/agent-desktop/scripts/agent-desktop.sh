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
  agent-desktop apps find <name-or-path> [--json]
  agent-desktop apps list [--json]
  agent-desktop launch --app <name-or-path> [--dry-run] [--wait-window] [--timeout <seconds>] [--session <id>] [--json]
  agent-desktop open-url --browser chrome [--new-window] [--session <id>] <http-or-https-url> [--json]
  agent-desktop wait-window --process <name> [--title <substring>] --timeout <seconds> [--json]
  agent-desktop focus --window-id <id> [--session <id>] [--json]
  agent-desktop focus --process <name> [--title <substring>] [--session <id>] [--json]
  agent-desktop restore --window-id <id> [--session <id>] [--json]
  agent-desktop close --window-id <id> [--session <id>] [--json]
  agent-desktop type --window-id <id> --text <text> --session <id> [--dry-run] [--json]
  agent-desktop key --window-id <id> --key <key-or-chord> --session <id> [--dry-run] [--json]
  agent-desktop click --window-id <id> --x <px> --y <px> --session <id> [--expected-bounds <json>] [--dry-run] [--json]
  agent-desktop cleanup --session <id> [--dry-run] [--json]
  agent-desktop cleanup --mine [--dry-run] [--json]
  agent-desktop sessions list [--json]
  agent-desktop sessions show --session <id> [--json]
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

workspace_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$root" ]; then
    printf '%s\n' "$root"
  else
    pwd
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
  [string]$SessionId = "",
  [string]$TextB64 = "",
  [string]$Key = "",
  [int]$X = -1,
  [int]$Y = -1,
  [string]$ExpectedBounds = "",
  [string]$LedgerRoot = "",
  [string]$ProfileRoot = "",
  [switch]$NewWindow,
  [switch]$DryRun,
  [switch]$WaitWindow,
  [switch]$VerboseTitles
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$script:PendingInputFailureLedger = $null
$script:PendingInputFailureData = $null

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Threading;
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
  public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
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
  public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
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

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class AgentDesktopInput {
  public const uint INPUT_MOUSE = 0;
  public const uint INPUT_KEYBOARD = 1;
  public const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
  public const uint KEYEVENTF_KEYUP = 0x0002;
  public const uint KEYEVENTF_UNICODE = 0x0004;
  public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
  public const uint MOUSEEVENTF_LEFTUP = 0x0004;
  public const ushort VK_SHIFT = 0x10;

  [StructLayout(LayoutKind.Sequential)]
  public struct POINT {
    public int X;
    public int Y;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT {
    public uint type;
    public InputUnion U;
  }

  [StructLayout(LayoutKind.Explicit)]
  public struct InputUnion {
    [FieldOffset(0)] public MOUSEINPUT mi;
    [FieldOffset(0)] public KEYBDINPUT ki;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct MOUSEINPUT {
    public int dx;
    public int dy;
    public uint mouseData;
    public uint dwFlags;
    public uint time;
    public UIntPtr dwExtraInfo;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct KEYBDINPUT {
    public ushort wVk;
    public ushort wScan;
    public uint dwFlags;
    public uint time;
    public UIntPtr dwExtraInfo;
  }

  [DllImport("user32.dll", SetLastError=true)]
  public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
  [DllImport("user32.dll")]
  public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")]
  public static extern IntPtr WindowFromPoint(POINT Point);
  [DllImport("user32.dll")]
  public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")]
  public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);
  [DllImport("user32.dll")]
  public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern short VkKeyScan(char ch);

  public static bool SendUnicodeText(string text) {
    foreach (char ch in text) {
      if (!SendCharacter(ch)) {
        return false;
      }
      System.Threading.Thread.Sleep(8);
    }
    return true;
  }

  public static bool SendVirtualKey(ushort vk, bool ctrl, bool extendedKey) {
    ushort ctrlVk = 0x11;
    INPUT ctrlDown = KeyInput(ctrlVk, false, false);
    INPUT ctrlUp = KeyInput(ctrlVk, true, false);
    INPUT down = KeyInput(vk, false, extendedKey);
    INPUT up = KeyInput(vk, true, extendedKey);
    INPUT[] inputs = ctrl ? new INPUT[] { ctrlDown, down, up, ctrlUp } : new INPUT[] { down, up };
    uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
    if (sent < inputs.Length) {
      INPUT[] release = ctrl ? new INPUT[] { up, ctrlUp } : new INPUT[] { up };
      SendInput((uint)release.Length, release, Marshal.SizeOf(typeof(INPUT)));
    }
    return sent == inputs.Length;
  }

  public static bool SendCharacter(char ch) {
    if (ch >= 32 && ch <= 126) {
      short mapped = VkKeyScan(ch);
      if (mapped != -1) {
        ushort vk = (ushort)(mapped & 0xFF);
        byte shiftState = (byte)((mapped >> 8) & 0xFF);
        bool needsShift = (shiftState & 1) != 0;
        bool needsCtrl = (shiftState & 2) != 0;
        bool needsAlt = (shiftState & 4) != 0;
        if (!needsCtrl && !needsAlt) {
          return SendPrintableVirtualKey(vk, needsShift);
        }
      }
    }
    return SendUnicodeCharacter(ch);
  }

  public static bool SendPrintableVirtualKey(ushort vk, bool shift) {
    INPUT shiftDown = KeyInput(VK_SHIFT, false, false);
    INPUT shiftUp = KeyInput(VK_SHIFT, true, false);
    INPUT down = KeyInput(vk, false, false);
    INPUT up = KeyInput(vk, true, false);
    INPUT[] inputs = shift ? new INPUT[] { shiftDown, down, up, shiftUp } : new INPUT[] { down, up };
    uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
    if (sent < inputs.Length) {
      INPUT[] release = shift ? new INPUT[] { up, shiftUp } : new INPUT[] { up };
      SendInput((uint)release.Length, release, Marshal.SizeOf(typeof(INPUT)));
    }
    return sent == inputs.Length;
  }

  public static bool SendUnicodeCharacter(char ch) {
    INPUT down = new INPUT();
    down.type = INPUT_KEYBOARD;
    down.U.ki.wVk = 0;
    down.U.ki.wScan = ch;
    down.U.ki.dwFlags = KEYEVENTF_UNICODE;
    down.U.ki.dwExtraInfo = UIntPtr.Zero;

    INPUT up = down;
    up.U.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;

    INPUT[] inputs = new INPUT[] { down, up };
    return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT))) == inputs.Length;
  }

  public static bool LeftClick(int x, int y) {
    if (!SetCursorPos(x, y)) { return false; }
    INPUT down = new INPUT();
    down.type = INPUT_MOUSE;
    down.U.mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
    down.U.mi.dwExtraInfo = UIntPtr.Zero;
    INPUT up = down;
    up.U.mi.dwFlags = MOUSEEVENTF_LEFTUP;
    INPUT[] inputs = new INPUT[] { down, up };
    return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT))) == inputs.Length;
  }

  public static int HitTest(IntPtr hWnd, int x, int y) {
    int packed = ((y & 0xFFFF) << 16) | (x & 0xFFFF);
    return SendMessage(hWnd, 0x0084, IntPtr.Zero, new IntPtr(packed)).ToInt32();
  }

  private static INPUT KeyInput(ushort vk, bool up, bool extendedKey) {
    INPUT input = new INPUT();
    input.type = INPUT_KEYBOARD;
    input.U.ki.wVk = vk;
    input.U.ki.wScan = 0;
    input.U.ki.dwFlags = (up ? KEYEVENTF_KEYUP : 0) | (extendedKey ? KEYEVENTF_EXTENDEDKEY : 0);
    input.U.ki.dwExtraInfo = UIntPtr.Zero;
    return input;
  }
}
"@

function Finish([int]$Code, [object]$Payload) {
  if ($Code -ne 0 -and $null -ne $script:PendingInputFailureLedger -and $null -ne $script:PendingInputFailureData) {
    try {
      $failure = $script:PendingInputFailureData
      $failure | Add-Member -NotePropertyName result -NotePropertyValue "failed" -Force
      $failure | Add-Member -NotePropertyName error -NotePropertyValue ("" + $Payload.error) -Force
      $failure | Add-Member -NotePropertyName message -NotePropertyValue ("" + $Payload.message) -Force
      $failure | Add-Member -NotePropertyName exit_code -NotePropertyValue $Code -Force
      Add-LedgerEvent $script:PendingInputFailureLedger "input" $failure
      Write-Ledger $script:PendingInputFailureLedger
    } catch {}
    $script:PendingInputFailureLedger = $null
    $script:PendingInputFailureData = $null
  }
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

function Get-WindowClass([IntPtr]$hwnd) {
  $sb = New-Object System.Text.StringBuilder 256
  [void][AgentDesktopNative]::GetClassName($hwnd, $sb, $sb.Capacity)
  return $sb.ToString()
}

function Get-ProcessStartTimeIso([int64]$PidValue) {
  try {
    return (Get-Process -Id ([int]$PidValue) -ErrorAction Stop).StartTime.ToUniversalTime().ToString("o")
  } catch {
    return ""
  }
}

function Get-ProcessCommandLine([int64]$PidValue) {
  try {
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$PidValue" -ErrorAction Stop
    return ("" + $proc.CommandLine)
  } catch {
    return ""
  }
}

function Get-ProcessExecutablePath([int64]$PidValue) {
  try {
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$PidValue" -ErrorAction Stop
    return ("" + $proc.ExecutablePath)
  } catch {
    return ""
  }
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
  $pidInt = [int64]$pidValue
  $root = Root-Hwnd $hwnd
  return [pscustomobject]@{
    id = $hwnd.ToInt64().ToString()
    title = (Short-Title $titleValue)
    fullTitle = $titleValue
    process = $processValue
    pid = $pidInt
    process_start_time = (Get-ProcessStartTimeIso $pidInt)
    executable_path = (Get-ProcessExecutablePath $pidInt)
    class = (Get-WindowClass $hwnd)
    command_line = (Get-ProcessCommandLine $pidInt)
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
    process_start_time = $Window.process_start_time
    executable_path = $Window.executable_path
    class = $Window.class
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

function New-SessionId {
  return ("ad-" + (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ") + "-" + ([guid]::NewGuid().ToString("N").Substring(0, 8)))
}

function Normalize-SessionId([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return New-SessionId }
  if ($Value -notmatch '^[A-Za-z0-9._-]{1,96}$') {
    Finish 64 (Error-Payload "invalid-argument" "Session id may contain only letters, numbers, dot, underscore, and dash.")
  }
  return $Value
}

function Require-LedgerRoot {
  if ([string]::IsNullOrWhiteSpace($LedgerRoot)) {
    Finish 64 (Error-Payload "invalid-argument" "Ledger root was not provided by the launcher.")
  }
  New-Item -ItemType Directory -Force -Path $LedgerRoot | Out-Null
}

function Ledger-Path([string]$Sid) {
  Require-LedgerRoot
  return (Join-Path $LedgerRoot "$Sid.json")
}

function Session-ProfilePath([string]$Sid) {
  $base = Join-Path $env:TEMP "agent-desktop-profiles"
  $path = Join-Path $base $Sid
  New-Item -ItemType Directory -Force -Path $path | Out-Null
  return $path
}

function Session-ProfileRoot {
  return (Join-Path $env:TEMP "agent-desktop-profiles")
}

function Host-BootMarker {
  try {
    return (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString("o")
  } catch {
    return ""
  }
}

function New-Ledger([string]$Sid) {
  return [pscustomobject]@{
    schema_version = 1
    session_id = $Sid
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    updated_at = (Get-Date).ToUniversalTime().ToString("o")
    host_boot = (Host-BootMarker)
    windows = @()
    events = @()
  }
}

function Read-Ledger([string]$Sid, [switch]$AllowMissing) {
  $path = Ledger-Path $Sid
  if (-not (Test-Path -LiteralPath $path)) {
    if ($AllowMissing) { return (New-Ledger $Sid) }
    Finish 71 (Error-Payload "not-found" "Session ledger '$Sid' was not found.")
  }
  try {
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $ledger = $raw | ConvertFrom-Json
    if ($null -eq $ledger.windows) { $ledger | Add-Member -NotePropertyName windows -NotePropertyValue @() -Force }
    if ($null -eq $ledger.events) { $ledger | Add-Member -NotePropertyName events -NotePropertyValue @() -Force }
    return $ledger
  } catch {
    $bad = "$path.corrupt-$(Get-Date -Format yyyyMMddHHmmss)"
    try { Move-Item -LiteralPath $path -Destination $bad -Force } catch {}
    $payload = Error-Payload "corrupt-ledger" "Session ledger '$Sid' could not be parsed and was quarantined."
    $payload | Add-Member -NotePropertyName quarantined_path -NotePropertyValue $bad -Force
    Finish 1 $payload
  }
}

function Write-Ledger([object]$Ledger) {
  $sid = "" + $Ledger.session_id
  $path = Ledger-Path $sid
  $Ledger.updated_at = (Get-Date).ToUniversalTime().ToString("o")
  $tmp = "$path.tmp-$PID-$([guid]::NewGuid().ToString("N"))"
  $Ledger | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tmp -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Add-LedgerEvent([object]$Ledger, [string]$Type, [object]$Data) {
  $events = @($Ledger.events)
  $events += [pscustomobject]@{
    at = (Get-Date).ToUniversalTime().ToString("o")
    type = $Type
    data = $Data
  }
  $Ledger.events = @($events)
}

function Ledger-WindowRecord([object]$Window, [string]$Sid, [string]$Kind, [bool]$Owned, [string]$ProfilePath, [string]$UrlValue) {
  return [pscustomobject]@{
    id = $Window.id
    window_id = $Window.id
    owned = $Owned
    touched = (-not $Owned)
    kind = $Kind
    url = $UrlValue
    status = "open"
    recorded_at = (Get-Date).ToUniversalTime().ToString("o")
    title = $Window.title
    full_title = $Window.fullTitle
    process = $Window.process
    pid = $Window.pid
    process_start_time = $Window.process_start_time
    executable_path = $Window.executable_path
    class = $Window.class
    command_line = $Window.command_line
    profile_path = $ProfilePath
    session_id = $Sid
    x = $Window.x
    y = $Window.y
    width = $Window.width
    height = $Window.height
  }
}

function Upsert-LedgerWindow([object]$Ledger, [object]$Record) {
  $windows = @($Ledger.windows)
  $updated = $false
  for ($i = 0; $i -lt $windows.Count; $i++) {
    if (("" + $windows[$i].window_id) -eq ("" + $Record.window_id)) {
      $existing = $windows[$i]
      if ([bool]$existing.owned -and -not [bool]$Record.owned) {
        $updated = $true
        break
      }
      foreach ($propName in @("pre_mutation_minimized", "pre_mutation_foreground")) {
        $existingProp = $existing.PSObject.Properties[$propName]
        if ($null -ne $existingProp) {
          $Record | Add-Member -NotePropertyName $propName -NotePropertyValue $existingProp.Value -Force
        }
      }
      $windows[$i] = $Record
      $updated = $true
      break
    }
  }
  if (-not $updated) { $windows += $Record }
  $Ledger.windows = @($windows)
}

function Find-LedgerWindow([object]$Ledger, [string]$TargetWindowId) {
  $matches = @(@($Ledger.windows) | Where-Object { ("" + $_.window_id) -eq ("" + $TargetWindowId) })
  if ($matches.Count -gt 0) { return $matches[0] }
  return $null
}

function Verify-OwnedWindow([object]$Record) {
  $result = [ordered]@{
    ok = $false
    state = "not_found"
    reason = ""
    window = $null
  }
  $hwnd = [IntPtr]::new([int64]$Record.window_id)
  if (-not [AgentDesktopNative]::IsWindow($hwnd)) {
    $result.state = "already_closed"
    $result.reason = "window id no longer exists"
    return [pscustomobject]$result
  }
  $window = Window-Object $hwnd
  if ($null -eq $window) {
    $result.state = "already_closed"
    $result.reason = "window is no longer visible or has no title"
    return [pscustomobject]$result
  }
  $mismatches = New-Object System.Collections.ArrayList
  if (("" + $window.pid) -ne ("" + $Record.pid)) { [void]$mismatches.Add("pid") }
  if (("" + $window.process) -ne ("" + $Record.process)) { [void]$mismatches.Add("process") }
  if (("" + $window.process_start_time) -ne ("" + $Record.process_start_time)) { [void]$mismatches.Add("process_start_time") }
  $recordExe = "" + $Record.executable_path
  if (-not [string]::IsNullOrWhiteSpace($recordExe) -and ("" + $window.executable_path) -ne $recordExe) { [void]$mismatches.Add("executable_path") }
  if (("" + $window.class) -ne ("" + $Record.class)) { [void]$mismatches.Add("class") }
  $profile = "" + $Record.profile_path
  if (-not [string]::IsNullOrWhiteSpace($profile)) {
    $cmd = "" + $window.command_line
    if ($cmd.IndexOf($profile, [StringComparison]::OrdinalIgnoreCase) -lt 0) { [void]$mismatches.Add("profile_path") }
  }
  $result.window = (Public-Window $window)
  if ($mismatches.Count -gt 0) {
    $result.state = "mismatched"
    $result.reason = "identity mismatch: " + (($mismatches.ToArray()) -join ",")
    return [pscustomobject]$result
  }
  $result.ok = $true
  $result.state = "alive"
  return [pscustomobject]$result
}

function Close-OwnedRecord([object]$Record, [switch]$Preview) {
  $base = [ordered]@{
    window_id = "" + $Record.window_id
    owned = [bool]$Record.owned
    dry_run = [bool]$Preview
    result = ""
    reason = ""
    window = $null
  }
  if (-not [bool]$Record.owned) {
    $base.result = "not_owned"
    $base.reason = "ledger record is not owned by this session"
    return [pscustomobject]$base
  }
  $verification = Verify-OwnedWindow $Record
  $base.window = $verification.window
  if (-not $verification.ok) {
    $base.result = $verification.state
    $base.reason = $verification.reason
    return [pscustomobject]$base
  }
  if ($Preview) {
    $base.result = "would_close"
    $base.reason = "identity verified"
    return [pscustomobject]$base
  }
  $hwnd = [IntPtr]::new([int64]$Record.window_id)
  [void][AgentDesktopNative]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
  $deadline = (Get-Date).AddSeconds(4)
  do {
    Start-Sleep -Milliseconds 200
    if (-not [AgentDesktopNative]::IsWindow($hwnd)) {
      $base.result = "closed"
      $base.reason = "WM_CLOSE accepted"
      return [pscustomobject]$base
    }
  } while ((Get-Date) -lt $deadline)
  $base.result = "still_open"
  $base.reason = "window still exists after WM_CLOSE timeout"
  return [pscustomobject]$base
}

function Restore-TouchedRecord([object]$Record, [switch]$Preview) {
  $base = [ordered]@{
    window_id = "" + $Record.window_id
    owned = [bool]$Record.owned
    touched = [bool]$Record.touched
    dry_run = [bool]$Preview
    result = ""
    reason = ""
    window = $null
  }
  if ([bool]$Record.owned -or -not [bool]$Record.touched) {
    $base.result = "not_touched"
    $base.reason = "ledger record is not a non-owned touched window"
    return [pscustomobject]$base
  }
  $verification = Verify-OwnedWindow $Record
  $base.window = $verification.window
  if (-not $verification.ok) {
    $base.result = $verification.state
    $base.reason = $verification.reason
    return [pscustomobject]$base
  }
  $wasMinimized = $false
  try { $wasMinimized = [bool]$Record.pre_mutation_minimized } catch {}
  if (-not $wasMinimized) {
    $base.result = "unchanged"
    $base.reason = "window was not minimized before touch"
    return [pscustomobject]$base
  }
  if ($Preview) {
    $base.result = "would_minimize"
    $base.reason = "window was minimized before touch"
    return [pscustomobject]$base
  }
  $hwnd = [IntPtr]::new([int64]$Record.window_id)
  [void][AgentDesktopNative]::ShowWindow($hwnd, 6)
  Start-Sleep -Milliseconds 250
  $fresh = Window-Object $hwnd
  $base.window = (Public-Window $fresh)
  $base.result = "minimized"
  $base.reason = "restored pre-touch minimized state"
  return [pscustomobject]$base
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

function Require-InputSession {
  if ([string]::IsNullOrWhiteSpace($SessionId)) {
    Finish 64 (Error-Payload "invalid-argument" "$Command requires --session <id>.")
  }
  return (Normalize-SessionId $SessionId)
}

function Resolve-InputWindow {
  if ([string]::IsNullOrWhiteSpace($WindowId)) {
    Finish 64 (Error-Payload "invalid-argument" "$Command requires --window-id <id>.")
  }
  if ($WindowId -notmatch '^[0-9]+$') {
    Finish 64 (Error-Payload "invalid-argument" "$Command requires a numeric --window-id.")
  }
  $matches = @(Get-Windows | Where-Object { ("" + $_.id) -eq ("" + $WindowId) })
  if ($matches.Count -eq 1) { return $matches[0] }
  Finish 71 (Error-Payload "not-found" "No visible top-level window matched window id '$WindowId'.")
}

function Ensure-InputLedgerTarget([string]$Sid, [object]$Target, [switch]$Preview) {
  $ledger = Read-Ledger $Sid -AllowMissing
  if (("" + $ledger.host_boot) -ne (Host-BootMarker)) {
    Finish 71 (Error-Payload "stale-ledger" "Session ledger '$Sid' was created before the current Windows boot; refusing input.")
  }
  $record = Find-LedgerWindow $ledger $Target.id
  if ($null -ne $record) {
    $verification = Verify-OwnedWindow $record
    if (-not $verification.ok) {
      $payload = Error-Payload $verification.state "Ledger target '$($Target.id)' is $($verification.state): $($verification.reason)."
      $payload | Add-Member -NotePropertyName window_id -NotePropertyValue $Target.id -Force
      $payload | Add-Member -NotePropertyName state -NotePropertyValue $verification.state -Force
      $payload | Add-Member -NotePropertyName reason -NotePropertyValue $verification.reason -Force
      if ($verification.state -eq "mismatched") { Finish 72 $payload }
      Finish 71 $payload
    }
    return [pscustomobject]@{ ledger = $ledger; record = $record; target = $Target; known = $true }
  }

  if ($Preview) {
    return [pscustomobject]@{ ledger = $ledger; record = $null; target = $Target; known = $false }
  }

  $touch = Ledger-WindowRecord $Target $Sid "input-touch" $false "" ""
  $touch | Add-Member -NotePropertyName pre_mutation_minimized -NotePropertyValue ([bool]$Target.minimized) -Force
  $touch | Add-Member -NotePropertyName pre_mutation_foreground -NotePropertyValue ([bool]$Target.foreground) -Force
  Upsert-LedgerWindow $ledger $touch
  Write-Ledger $ledger
  return [pscustomobject]@{ ledger = $ledger; record = $touch; target = $Target; known = $false }
}

function Input-EventData([string]$Action, [object]$Target, [bool]$Preview, [object]$Extra) {
  $data = [ordered]@{
    action = $Action
    window_id = $Target.id
    pid = $Target.pid
    process = $Target.process
    process_start_time = $Target.process_start_time
    class = $Target.class
    dry_run = $Preview
  }
  if ($null -ne $Extra) {
    foreach ($prop in $Extra.PSObject.Properties) {
      $data[$prop.Name] = $prop.Value
    }
  }
  return [pscustomobject]$data
}

function Set-PendingInputFailure([object]$Ledger, [string]$Action, [object]$Target, [object]$Extra) {
  $script:PendingInputFailureLedger = $Ledger
  $script:PendingInputFailureData = (Input-EventData $Action $Target $false $Extra)
}

function Clear-PendingInputFailure {
  $script:PendingInputFailureLedger = $null
  $script:PendingInputFailureData = $null
}

function Finish-InputDryRun([string]$Action, [object]$Ledger, [object]$Target, [object]$Extra) {
  Add-LedgerEvent $Ledger "input" (Input-EventData $Action $Target $true $Extra)
  Write-Ledger $Ledger
  Finish 0 ([pscustomobject]@{
    ok = $true
    command = $Action
    session_id = $Ledger.session_id
    window_id = $Target.id
    dry_run = $true
    planned = $Extra
    window = (Public-Window $Target)
  })
}

function Get-FreshInputTarget([string]$WindowIdValue) {
  $fresh = Window-Object ([IntPtr]::new([int64]$WindowIdValue))
  if ($null -eq $fresh) {
    Finish 71 (Error-Payload "not-found" "Target window disappeared before input.")
  }
  return $fresh
}

function Key-Spec([string]$KeyValue) {
  $normalized = ("" + $KeyValue).Trim().ToLowerInvariant()
  $map = @{
    "enter" = [pscustomobject]@{ key = "enter"; vk = [uint16]0x0D; ctrl = $false; extended = $false }
    "escape" = [pscustomobject]@{ key = "escape"; vk = [uint16]0x1B; ctrl = $false; extended = $false }
    "tab" = [pscustomobject]@{ key = "tab"; vk = [uint16]0x09; ctrl = $false; extended = $false }
    "backspace" = [pscustomobject]@{ key = "backspace"; vk = [uint16]0x08; ctrl = $false; extended = $false }
    "delete" = [pscustomobject]@{ key = "delete"; vk = [uint16]0x2E; ctrl = $false; extended = $true }
    "up" = [pscustomobject]@{ key = "up"; vk = [uint16]0x26; ctrl = $false; extended = $true }
    "down" = [pscustomobject]@{ key = "down"; vk = [uint16]0x28; ctrl = $false; extended = $true }
    "left" = [pscustomobject]@{ key = "left"; vk = [uint16]0x25; ctrl = $false; extended = $true }
    "right" = [pscustomobject]@{ key = "right"; vk = [uint16]0x27; ctrl = $false; extended = $true }
    "ctrl+a" = [pscustomobject]@{ key = "ctrl+a"; vk = [uint16]0x41; ctrl = $true; extended = $false }
    "ctrl+f" = [pscustomobject]@{ key = "ctrl+f"; vk = [uint16]0x46; ctrl = $true; extended = $false }
    "ctrl+s" = [pscustomobject]@{ key = "ctrl+s"; vk = [uint16]0x53; ctrl = $true; extended = $false }
    "ctrl+z" = [pscustomobject]@{ key = "ctrl+z"; vk = [uint16]0x5A; ctrl = $true; extended = $false }
  }
  if (-not $map.ContainsKey($normalized)) {
    Finish 64 (Error-Payload "invalid-argument" "Unsupported key/chord '$KeyValue'. Allowed: enter, escape, tab, backspace, delete, up, down, left, right, ctrl+a, ctrl+f, ctrl+s, ctrl+z.")
  }
  return $map[$normalized]
}

function Decode-TypeText {
  if ([string]::IsNullOrWhiteSpace($TextB64)) {
    Finish 64 (Error-Payload "invalid-argument" "type requires --text <text>.")
  }
  try {
    $bytes = [Convert]::FromBase64String($TextB64)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  } catch {
    Finish 64 (Error-Payload "invalid-argument" "type text transport was not valid base64 UTF-8.")
  }
  if ($text.Length -gt 1024) {
    Finish 64 (Error-Payload "invalid-argument" "type text must be 1024 characters or fewer.")
  }
  foreach ($ch in $text.ToCharArray()) {
    if ([char]::IsControl($ch)) {
      Finish 64 (Error-Payload "invalid-argument" "type text cannot contain newline, carriage return, or control characters; use key enter explicitly.")
    }
  }
  return $text
}

function Parse-ExpectedBounds {
  if ([string]::IsNullOrWhiteSpace($ExpectedBounds)) { return $null }
  try {
    $bounds = $ExpectedBounds | ConvertFrom-Json
    foreach ($name in @("x", "y", "width", "height")) {
      if ($null -eq $bounds.PSObject.Properties[$name]) {
        Finish 64 (Error-Payload "invalid-argument" "--expected-bounds must include x, y, width, and height.")
      }
    }
    return $bounds
  } catch {
    Finish 64 (Error-Payload "invalid-argument" "--expected-bounds must be a JSON object with x, y, width, and height.")
  }
}

function Assert-ExpectedBounds([object]$Window, [object]$Bounds) {
  if ($null -eq $Bounds) { return }
  foreach ($name in @("x", "y", "width", "height")) {
    if ([int]$Window.$name -ne [int]$Bounds.$name) {
      Finish 64 (Error-Payload "invalid-argument" "Target window bounds changed since screenshot; refusing click.")
    }
  }
}

function Assert-ClientPoint([IntPtr]$Hwnd, [int]$ScreenX, [int]$ScreenY) {
  $hitTest = [AgentDesktopInput]::HitTest($Hwnd, $ScreenX, $ScreenY)
  if ($hitTest -ne 1) {
    Finish 64 (Error-Payload "invalid-argument" "Click point is outside the target client area/nonclient clicks are refused.")
  }
  $rect = New-Object AgentDesktopInput+RECT
  if (-not [AgentDesktopInput]::GetClientRect($Hwnd, [ref]$rect)) {
    Finish 64 (Error-Payload "invalid-argument" "Could not read target client area for click validation.")
  }
  $topLeft = New-Object AgentDesktopInput+POINT
  $topLeft.X = $rect.Left
  $topLeft.Y = $rect.Top
  $bottomRight = New-Object AgentDesktopInput+POINT
  $bottomRight.X = $rect.Right
  $bottomRight.Y = $rect.Bottom
  [void][AgentDesktopInput]::ClientToScreen($Hwnd, [ref]$topLeft)
  [void][AgentDesktopInput]::ClientToScreen($Hwnd, [ref]$bottomRight)
  if ($ScreenX -lt $topLeft.X -or $ScreenX -ge $bottomRight.X -or $ScreenY -lt $topLeft.Y -or $ScreenY -ge $bottomRight.Y) {
    Finish 64 (Error-Payload "invalid-argument" "Click point is outside the target client area/nonclient clicks are refused.")
  }
}

function Assert-PointTopmostTarget([IntPtr]$Hwnd, [int]$ScreenX, [int]$ScreenY) {
  $point = New-Object AgentDesktopInput+POINT
  $point.X = $ScreenX
  $point.Y = $ScreenY
  $hit = [AgentDesktopInput]::WindowFromPoint($point)
  $hitRoot = Root-Hwnd $hit
  $targetRoot = Root-Hwnd $Hwnd
  if ($hitRoot -eq [IntPtr]::Zero -or $hitRoot.ToInt64() -ne $targetRoot.ToInt64()) {
    $payload = Error-Payload "focus-denied" "Click point is not topmost for the target window; refusing obscured click."
    $payload | Add-Member -NotePropertyName hit_window_id -NotePropertyValue $hitRoot.ToInt64().ToString() -Force
    $payload | Add-Member -NotePropertyName target_window_id -NotePropertyValue $targetRoot.ToInt64().ToString() -Force
    Finish 74 $payload
  }
}

function Command-TypeInput {
  $sid = Require-InputSession
  $text = Decode-TypeText
  $target = Resolve-InputWindow
  $state = Ensure-InputLedgerTarget $sid $target -Preview:$DryRun
  $extra = [pscustomobject]@{ chars = $text.Length }
  if ($DryRun) { Finish-InputDryRun "type" $state.ledger $target $extra }
  Set-PendingInputFailure $state.ledger "type" $target $extra

  $focusResult = Focus-TargetWindow $target
  $fresh = Get-FreshInputTarget $focusResult.window.id
  if ((Get-ForegroundRootId) -ne (Root-Hwnd ([IntPtr]::new([int64]$fresh.id))).ToInt64().ToString()) {
    Finish 74 (Error-Payload "focus-denied" "Foreground changed before text input.")
  }
  $ok = [AgentDesktopInput]::SendUnicodeText($text)
  if (-not $ok) { Finish 1 (Error-Payload "failed" "SendInput did not accept all text input events.") }
  $postForeground = Get-ForegroundRootId
  Clear-PendingInputFailure
  Add-LedgerEvent $state.ledger "input" (Input-EventData "type" $fresh $false $extra)
  Write-Ledger $state.ledger
  Finish 0 ([pscustomobject]@{
    ok = $true
    command = "type"
    session_id = $sid
    window_id = $fresh.id
    dry_run = $false
    chars = $text.Length
    focused = $true
    restored = $focusResult.restored
    window = (Public-Window $fresh)
    post_foreground_window_id = $postForeground
  })
}

function Command-KeyInput {
  $sid = Require-InputSession
  if ([string]::IsNullOrWhiteSpace($Key)) {
    Finish 64 (Error-Payload "invalid-argument" "key requires --key <key-or-chord>.")
  }
  $spec = Key-Spec $Key
  $target = Resolve-InputWindow
  $state = Ensure-InputLedgerTarget $sid $target -Preview:$DryRun
  $extra = [pscustomobject]@{ key = $spec.key }
  if ($DryRun) { Finish-InputDryRun "key" $state.ledger $target $extra }
  Set-PendingInputFailure $state.ledger "key" $target $extra

  $focusResult = Focus-TargetWindow $target
  $fresh = Get-FreshInputTarget $focusResult.window.id
  if ((Get-ForegroundRootId) -ne (Root-Hwnd ([IntPtr]::new([int64]$fresh.id))).ToInt64().ToString()) {
    Finish 74 (Error-Payload "focus-denied" "Foreground changed before key input.")
  }
  $ok = [AgentDesktopInput]::SendVirtualKey([uint16]$spec.vk, [bool]$spec.ctrl, [bool]$spec.extended)
  if (-not $ok) { Finish 1 (Error-Payload "failed" "SendInput did not accept all key input events.") }
  $postForeground = Get-ForegroundRootId
  Clear-PendingInputFailure
  Add-LedgerEvent $state.ledger "input" (Input-EventData "key" $fresh $false $extra)
  Write-Ledger $state.ledger
  Finish 0 ([pscustomobject]@{
    ok = $true
    command = "key"
    session_id = $sid
    window_id = $fresh.id
    dry_run = $false
    key = $spec.key
    focused = $true
    restored = $focusResult.restored
    window = (Public-Window $fresh)
    post_foreground_window_id = $postForeground
  })
}

function Command-ClickInput {
  $sid = Require-InputSession
  if ($X -lt 0 -or $Y -lt 0) {
    Finish 64 (Error-Payload "invalid-argument" "click requires non-negative --x and --y.")
  }
  $target = Resolve-InputWindow
  $expected = Parse-ExpectedBounds
  Assert-ExpectedBounds $target $expected
  if ($X -ge [int]$target.width -or $Y -ge [int]$target.height) {
    Finish 64 (Error-Payload "invalid-argument" "Click coordinate is outside the target DWM bounds.")
  }
  $screenX = [int]$target.x + $X
  $screenY = [int]$target.y + $Y
  Assert-ClientPoint ([IntPtr]::new([int64]$target.id)) $screenX $screenY
  $state = Ensure-InputLedgerTarget $sid $target -Preview:$DryRun
  $extra = [pscustomobject]@{ x = $X; y = $Y; screen_x = $screenX; screen_y = $screenY }
  if ($DryRun) { Finish-InputDryRun "click" $state.ledger $target $extra }
  Set-PendingInputFailure $state.ledger "click" $target $extra

  $focusResult = Focus-TargetWindow $target
  $fresh = Get-FreshInputTarget $focusResult.window.id
  Assert-ExpectedBounds $fresh $expected
  if ($X -ge [int]$fresh.width -or $Y -ge [int]$fresh.height) {
    Finish 64 (Error-Payload "invalid-argument" "Click coordinate is outside the current target DWM bounds.")
  }
  $screenX = [int]$fresh.x + $X
  $screenY = [int]$fresh.y + $Y
  $hwnd = [IntPtr]::new([int64]$fresh.id)
  if ((Get-ForegroundRootId) -ne (Root-Hwnd $hwnd).ToInt64().ToString()) {
    Finish 74 (Error-Payload "focus-denied" "Foreground changed before click input.")
  }
  Assert-ClientPoint $hwnd $screenX $screenY
  Assert-PointTopmostTarget $hwnd $screenX $screenY
  $ok = [AgentDesktopInput]::LeftClick($screenX, $screenY)
  if (-not $ok) { Finish 1 (Error-Payload "failed" "SendInput did not accept the mouse click events.") }
  $postForeground = Get-ForegroundRootId
  $extra = [pscustomobject]@{ x = $X; y = $Y; screen_x = $screenX; screen_y = $screenY }
  Clear-PendingInputFailure
  Add-LedgerEvent $state.ledger "input" (Input-EventData "click" $fresh $false $extra)
  Write-Ledger $state.ledger
  Finish 0 ([pscustomobject]@{
    ok = $true
    command = "click"
    session_id = $sid
    window_id = $fresh.id
    dry_run = $false
    x = $X
    y = $Y
    screen_x = $screenX
    screen_y = $screenY
    focused = $true
    restored = $focusResult.restored
    window = (Public-Window $fresh)
    post_foreground_window_id = $postForeground
  })
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

function Test-ExistingPath([string]$PathValue) {
  if ([string]::IsNullOrWhiteSpace($PathValue)) { return $false }
  try { return (Test-Path -LiteralPath $PathValue) } catch { return $false }
}

function Test-LaunchablePath([string]$PathValue) {
  if (-not (Test-ExistingPath $PathValue)) { return $false }
  try {
    $ext = [System.IO.Path]::GetExtension($PathValue).ToLowerInvariant()
    return (@(".exe", ".cmd", ".bat", ".com") -contains $ext)
  } catch {
    return $false
  }
}

function New-AppCandidate(
  [string]$Source,
  [string]$DisplayName,
  [string]$Target,
  [string]$Arguments,
  [int]$Score,
  [string]$MatchKind,
  [string]$LaunchStrategy = "process",
  [string]$ProcessHint = "",
  [string]$DeniedReason = ""
) {
  $confidence = "low"
  if ($Score -ge 95) { $confidence = "high" } elseif ($Score -ge 70) { $confidence = "medium" }
  if ([string]::IsNullOrWhiteSpace($ProcessHint) -and -not [string]::IsNullOrWhiteSpace($Target)) {
    try { $ProcessHint = [System.IO.Path]::GetFileNameWithoutExtension($Target) } catch {}
  }
  return [pscustomobject]@{
    source = $Source
    display_name = $DisplayName
    target = $Target
    arguments = $Arguments
    score = $Score
    confidence = $confidence
    match_kind = $MatchKind
    launch_strategy = $LaunchStrategy
    process_hint = $ProcessHint
    denied_reason = $DeniedReason
  }
}

function App-MatchScore([string]$Needle, [string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return 0 }
  $n = $Needle.ToLowerInvariant()
  $v = $Value.ToLowerInvariant()
  $stem = ""
  try { $stem = [System.IO.Path]::GetFileNameWithoutExtension($Value).ToLowerInvariant() } catch {}
  if ($v -eq $n -or $stem -eq $n) { return 100 }
  if ($v.EndsWith("\" + $n + ".exe") -or $v.EndsWith("\" + $n)) { return 95 }
  if ($v.StartsWith($n) -or $stem.StartsWith($n)) { return 80 }
  if ($v.Contains($n) -or $stem.Contains($n)) { return 60 }
  return 0
}

function Denied-AppReason([string]$Query, [string]$Target, [string]$DisplayName) {
  $queryAndDisplay = (("" + $Query) + " " + ("" + $DisplayName)).ToLowerInvariant()
  if ($queryAndDisplay -match '(^|[\s\\/_-])(uninstall|remove|setup|installer|updater|update|maintenance)([\s\\/_\.-]|$)') {
    return "installer-or-maintenance-target"
  }
  $targetLeaf = ""
  try { $targetLeaf = [System.IO.Path]::GetFileNameWithoutExtension($Target).ToLowerInvariant() } catch {}
  if ($targetLeaf -match '^(uninstall|setup|installer|updater|maintenance)$') {
    return "installer-or-maintenance-target"
  }
  $browserText = (("" + $Query) + " " + ("" + $Target) + " " + ("" + $DisplayName)).ToLowerInvariant()
  if ($browserText -match '(^|[\s\\/_-])(chrome|browser|edge|msedge|firefox)([\s\\/_\.-]|$)') {
    return "browser-use-open-url"
  }
  return ""
}

function Add-AppCandidate([System.Collections.ArrayList]$Candidates, [object]$Candidate) {
  if ($null -eq $Candidate) { return }
  if ([string]::IsNullOrWhiteSpace($Candidate.target)) { return }
  $key = (("" + $Candidate.target) + "`n" + ("" + $Candidate.arguments)).ToLowerInvariant()
  foreach ($existing in @($Candidates)) {
    $existingKey = (("" + $existing.target) + "`n" + ("" + $existing.arguments)).ToLowerInvariant()
    if ($existingKey -eq $key) {
      if ($Candidate.score -gt $existing.score) {
        $existing.source = $Candidate.source
        $existing.display_name = $Candidate.display_name
        $existing.score = $Candidate.score
        $existing.confidence = $Candidate.confidence
        $existing.match_kind = $Candidate.match_kind
        $existing.denied_reason = $Candidate.denied_reason
      }
      return
    }
  }
  [void]$Candidates.Add($Candidate)
}

function Add-BuiltinAppCandidates([string]$Query, [System.Collections.ArrayList]$Candidates, [System.Collections.ArrayList]$Checked) {
  [void]$Checked.Add("builtins")
  $q = $Query.ToLowerInvariant()
  $builtins = @(
    [pscustomobject]@{ names = @("notepad", "notepad.exe"); display = "Notepad"; target = "$env:WINDIR\System32\notepad.exe"; process = "notepad"; score = 90 },
    [pscustomobject]@{ names = @("explorer", "explorer.exe"); display = "File Explorer"; target = "$env:WINDIR\explorer.exe"; process = "explorer"; score = 100 },
    [pscustomobject]@{ names = @("code", "code.exe", "vscode", "visual-studio-code"); display = "Visual Studio Code"; target = "$env:LocalAppData\Programs\Microsoft VS Code\Code.exe"; process = "Code"; score = 100 },
    [pscustomobject]@{ names = @("discord", "discord.exe"); display = "Discord"; target = "$env:LocalAppData\Discord\Update.exe"; process = "Discord"; score = 90 }
  )
  foreach ($item in $builtins) {
    if ($item.names -contains $q) {
      if (Test-LaunchablePath $item.target) {
        $deny = Denied-AppReason $Query $item.target $item.display
        Add-AppCandidate $Candidates (New-AppCandidate "builtin" $item.display $item.target "" ([int]$item.score) "alias" "process" $item.process $deny)
      }
    }
  }
  if ($q -eq "blender" -or $q -eq "blender.exe") {
    $roots = @("$env:ProgramFiles\Blender Foundation", "${env:ProgramFiles(x86)}\Blender Foundation", "$env:LocalAppData\Programs\Blender Foundation")
    foreach ($root in $roots) {
      if (-not (Test-ExistingPath $root)) { continue }
      foreach ($path in @(Get-ChildItem -LiteralPath $root -Recurse -Filter "blender.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 8)) {
        Add-AppCandidate $Candidates (New-AppCandidate "builtin-glob" "Blender" $path.FullName "" 100 "alias" "process" "blender" "")
      }
    }
  }
}

function Resolve-AppCandidates([string]$Query) {
  if ([string]::IsNullOrWhiteSpace($Query)) {
    Finish 64 (Error-Payload "invalid-argument" "Pass --app <name-or-path>.")
  }
  $candidates = New-Object System.Collections.ArrayList
  $checked = New-Object System.Collections.ArrayList
  [void]$checked.Add("literal-path")
  if (Test-ExistingPath $Query) {
    $resolved = (Resolve-Path -LiteralPath $Query).Path
    if (-not (Test-LaunchablePath $resolved)) {
      $payload = Error-Payload "invalid-argument" "Explicit app path is not a supported executable type."
      $payload | Add-Member -NotePropertyName checked -NotePropertyValue @("literal-path") -Force
      Finish 64 $payload
    }
    $deny = Denied-AppReason $Query $resolved $resolved
    Add-AppCandidate $candidates (New-AppCandidate "literal-path" ([System.IO.Path]::GetFileNameWithoutExtension($resolved)) $resolved "" 100 "path" "process" "" $deny)
  }

  Add-BuiltinAppCandidates $Query $candidates $checked

  [void]$checked.Add("app-paths-registry")
  foreach ($root in @("HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths")) {
    foreach ($item in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
      $display = [System.IO.Path]::GetFileNameWithoutExtension($item.PSChildName)
      $score = [Math]::Max((App-MatchScore $Query $item.PSChildName), (App-MatchScore $Query $display))
      if ($score -le 0) { continue }
      try { $target = "" + (Get-ItemProperty -LiteralPath $item.PSPath -ErrorAction Stop)."(default)" } catch { $target = "" }
      if ([string]::IsNullOrWhiteSpace($target) -or -not (Test-LaunchablePath $target)) { continue }
      $deny = Denied-AppReason $Query $target $display
      Add-AppCandidate $candidates (New-AppCandidate "app-paths-registry" $display $target "" $score "registry" "process" "" $deny)
    }
  }

  [void]$checked.Add("path")
  $cmdNames = @($Query)
  if (-not $Query.ToLowerInvariant().EndsWith(".exe")) { $cmdNames += "$Query.exe" }
  foreach ($cmdName in $cmdNames) {
    $cmd = Get-Command $cmdName -ErrorAction SilentlyContinue
    if ($null -eq $cmd -or [string]::IsNullOrWhiteSpace($cmd.Source)) { continue }
    if (-not (Test-LaunchablePath $cmd.Source)) { continue }
    $score = App-MatchScore $Query $cmd.Name
    if ($score -eq 100) { $score = 95 }
    $deny = Denied-AppReason $Query $cmd.Source $cmd.Name
    Add-AppCandidate $candidates (New-AppCandidate "path" $cmd.Name $cmd.Source "" $score "path-command" "process" "" $deny)
  }

  [void]$checked.Add("start-menu-shortcuts")
  $shell = $null
  try { $shell = New-Object -ComObject WScript.Shell } catch {}
  if ($null -ne $shell) {
    $startRoots = @(
      "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
      "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    )
    foreach ($root in $startRoots) {
      if (-not (Test-ExistingPath $root)) { continue }
      foreach ($shortcut in @(Get-ChildItem -LiteralPath $root -Recurse -Filter "*.lnk" -File -ErrorAction SilentlyContinue)) {
        $score = App-MatchScore $Query $shortcut.BaseName
        if ($score -le 0) { continue }
        try {
          $lnk = $shell.CreateShortcut($shortcut.FullName)
          $target = "" + $lnk.TargetPath
          if ([string]::IsNullOrWhiteSpace($target) -or -not (Test-LaunchablePath $target)) { continue }
          $argsValue = "" + $lnk.Arguments
          $processHint = ""
          if ($argsValue -match '(?i)--processStart\s+"?([^"\s]+)') {
            try { $processHint = [System.IO.Path]::GetFileNameWithoutExtension($Matches[1]) } catch { $processHint = $Matches[1] }
          }
          $deny = Denied-AppReason $Query $target $shortcut.BaseName
          Add-AppCandidate $candidates (New-AppCandidate "start-menu-shortcut" $shortcut.BaseName $target $argsValue $score "shortcut" "process" $processHint $deny)
        } catch {}
      }
    }
  }

  [void]$checked.Add("common-install-dirs")
  if ($Query.Trim().Length -ge 3) {
    $installRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LocalAppData "Programs"))
    foreach ($root in $installRoots) {
      if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-ExistingPath $root)) { continue }
      $queryLower = $Query.ToLowerInvariant()
      $dirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name.ToLowerInvariant().Contains($queryLower) -or $queryLower.Contains($_.Name.ToLowerInvariant())
      } | Select-Object -First 12)
      foreach ($dir in $dirs) {
        foreach ($exe in @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -Filter "*.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 24)) {
          $score = App-MatchScore $Query $exe.BaseName
          if ($score -le 0) { continue }
          $deny = Denied-AppReason $Query $exe.FullName $exe.BaseName
          Add-AppCandidate $candidates (New-AppCandidate "common-install-dirs" $exe.BaseName $exe.FullName "" $score "install-dir" "process" "" $deny)
        }
      }
    }
  }

  $ordered = @($candidates | Sort-Object @{ Expression = "score"; Descending = $true }, display_name, target)
  return [pscustomobject]@{ candidates = $ordered; checked = @($checked.ToArray()) }
}

function Select-AppCandidate([string]$Query) {
  $resolved = Resolve-AppCandidates $Query
  $allowed = @($resolved.candidates | Where-Object { [string]::IsNullOrWhiteSpace($_.denied_reason) })
  if ($allowed.Count -eq 0) {
    $denied = @($resolved.candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_.denied_reason) })
    if ($denied.Count -gt 0) {
      $payload = Error-Payload "invalid-argument" "The best candidate is not launchable by generic launch; use the indicated command instead." @($denied | Select-Object -First 8)
      $payload | Add-Member -NotePropertyName checked -NotePropertyValue $resolved.checked -Force
      Finish 64 $payload
    }
    $payload = Error-Payload "not-found" "No launchable app candidate was found for '$Query'."
    $payload | Add-Member -NotePropertyName checked -NotePropertyValue $resolved.checked -Force
    Finish 71 $payload
  }
  $top = $allowed[0]
  $ties = @($allowed | Where-Object { $_.score -eq $top.score -and ("" + $_.target).ToLowerInvariant() -ne ("" + $top.target).ToLowerInvariant() })
  if ($ties.Count -gt 0 -and ("" + $top.source) -ne "literal-path") {
    $payload = Error-Payload "ambiguous" "Multiple app candidates matched '$Query'; use a more specific name or an explicit path." @($allowed | Select-Object -First 8)
    $payload | Add-Member -NotePropertyName checked -NotePropertyValue $resolved.checked -Force
    Finish 72 $payload
  }
  return [pscustomobject]@{ candidate = $top; candidates = @($resolved.candidates | Select-Object -First 8); checked = $resolved.checked }
}

function Command-AppsFind {
  $resolved = Resolve-AppCandidates $App
  $allowed = @($resolved.candidates | Where-Object { [string]::IsNullOrWhiteSpace($_.denied_reason) })
  $denied = @($resolved.candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_.denied_reason) })
  $chosen = $null
  $refusedReason = ""
  if ($allowed.Count -gt 0) {
    $chosen = $allowed[0]
  } elseif ($denied.Count -gt 0) {
    $refusedReason = "" + $denied[0].denied_reason
  }
  Finish 0 ([pscustomobject]@{
    ok = $true
    command = "apps-find"
    query = $App
    chosen = $chosen
    refused_reason = $refusedReason
    candidates = @($resolved.candidates | Select-Object -First 20)
    count = @($resolved.candidates).Count
    checked = $resolved.checked
  })
}

function Command-AppsList {
  $aliases = @("notepad", "explorer", "code", "vscode", "discord", "blender")
  Finish 0 ([pscustomobject]@{
    ok = $true
    command = "apps-list"
    aliases = $aliases
    sources = @("literal-path", "builtins", "app-paths-registry", "path", "start-menu-shortcuts", "common-install-dirs")
  })
}

function Command-Doctor {
  $chrome = Resolve-ChromePath
  $checks = @(
    [pscustomobject]@{ name = "windows-host"; ok = $true; detail = "PowerShell Win32 backend is running" },
    [pscustomobject]@{ name = "powershell"; ok = $true; detail = $PSHOME },
    [pscustomobject]@{ name = "chrome"; ok = ($null -ne $chrome); detail = $chrome },
    [pscustomobject]@{ name = "ledger_root"; ok = (-not [string]::IsNullOrWhiteSpace($LedgerRoot)); detail = $LedgerRoot },
    [pscustomobject]@{ name = "profile_root"; ok = $true; detail = (Session-ProfileRoot) }
  )
  $payload = [pscustomobject]@{
    ok = $true
    command = "doctor"
    backend = "windows-host"
    powershell = $PSHOME
    chrome_available = ($null -ne $chrome)
    chrome_path = $chrome
    requirements = $checks
    docs = "https://github.com/cfpperche/tachyon-plugins/tree/main/agent-desktop"
  }
  Finish 0 $payload
}

function Command-ListWindows {
  $windows = @(Get-Windows | ForEach-Object { Public-Window $_ })
  Finish 0 ([pscustomobject]@{ ok = $true; command = "list-windows"; windows = $windows; count = $windows.Count })
}

function Process-CreatedAfter([object]$Proc, [datetime]$SinceUtc) {
  if ($null -eq $Proc) { return $false }
  try {
    if ($Proc.CreationDate -is [datetime]) {
      $created = ([datetime]$Proc.CreationDate).ToUniversalTime()
    } else {
      $created = ([System.Management.ManagementDateTimeConverter]::ToDateTime("" + $Proc.CreationDate)).ToUniversalTime()
    }
    return ($created -ge $SinceUtc.AddSeconds(-1))
  } catch {
    return $false
  }
}

function Get-ProcessTreeIds([int]$RootPid, [datetime]$SinceUtc) {
  $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Select-Object ProcessId, ParentProcessId, ExecutablePath, CreationDate)
  $ids = New-Object System.Collections.ArrayList
  $root = @($all | Where-Object { [int]$_.ProcessId -eq [int]$RootPid } | Select-Object -First 1)
  if ($root.Count -eq 1 -and (Process-CreatedAfter $root[0] $SinceUtc)) {
    [void]$ids.Add([int]$RootPid)
  }
  $changed = $true
  while ($changed) {
    $changed = $false
    foreach ($proc in $all) {
      if ($ids.Contains([int]$proc.ProcessId)) { continue }
      if (-not (Process-CreatedAfter $proc $SinceUtc)) { continue }
      if ($ids.Contains([int]$proc.ParentProcessId)) {
        [void]$ids.Add([int]$proc.ProcessId)
        $changed = $true
      }
    }
  }
  return @($ids.ToArray())
}

function Window-HasOwnableIdentity([object]$Window) {
  if ($null -eq $Window) { return $false }
  if ([int64]$Window.pid -le 0) { return $false }
  if ([string]::IsNullOrWhiteSpace("" + $Window.process)) { return $false }
  if ([string]::IsNullOrWhiteSpace("" + $Window.process_start_time)) { return $false }
  if ([string]::IsNullOrWhiteSpace("" + $Window.executable_path)) { return $false }
  if ([string]::IsNullOrWhiteSpace("" + $Window.class)) { return $false }
  return $true
}

function Window-StartedAfter([object]$Window, [datetime]$SinceUtc) {
  try {
    $started = ([datetime]("" + $Window.process_start_time)).ToUniversalTime()
    return ($started -ge $SinceUtc.AddSeconds(-1))
  } catch {
    return $false
  }
}

function Candidate-ProcessMatchesWindow([object]$Candidate, [object]$Window) {
  $hint = ("" + $Candidate.process_hint).ToLowerInvariant()
  if (-not [string]::IsNullOrWhiteSpace($hint) -and ("" + $Window.process).ToLowerInvariant() -eq $hint) { return $true }
  $target = "" + $Candidate.target
  if (-not [string]::IsNullOrWhiteSpace($target) -and ("" + $Window.executable_path).Equals($target, [StringComparison]::OrdinalIgnoreCase)) { return $true }
  return $false
}

function Candidate-DirectExeMatchesWindow([object]$Candidate, [object]$Window) {
  $target = "" + $Candidate.target
  return (-not [string]::IsNullOrWhiteSpace($target) -and ("" + $Window.executable_path).Equals($target, [StringComparison]::OrdinalIgnoreCase))
}

function Candidate-HintMatchesWindow([object]$Candidate, [object]$Window) {
  $hint = ("" + $Candidate.process_hint).ToLowerInvariant()
  return (-not [string]::IsNullOrWhiteSpace($hint) -and ("" + $Window.process).ToLowerInvariant() -eq $hint)
}

function Command-Launch {
  if ($TimeoutSeconds -lt 1) {
    Finish 64 (Error-Payload "invalid-argument" "--timeout must be at least 1 second.")
  }
  $selection = Select-AppCandidate $App
  $candidate = $selection.candidate
  if ($DryRun) {
    Finish 0 ([pscustomobject]@{
      ok = $true
      command = "launch"
      dry_run = $true
      app = $App
      candidate = $candidate
      candidates = $selection.candidates
      checked = $selection.checked
      would_launch = $true
    })
  }
  $sid = Normalize-SessionId $SessionId
  $beforeWindows = @(Get-Windows)
  $beforeIds = @{}
  foreach ($window in $beforeWindows) { $beforeIds[$window.id] = $true }
  $arguments = "" + $candidate.arguments
  $launchStartedAt = (Get-Date).ToUniversalTime()
  try {
    if ([string]::IsNullOrWhiteSpace($arguments)) {
      $proc = Start-Process -FilePath $candidate.target -PassThru
    } else {
      $proc = Start-Process -FilePath $candidate.target -ArgumentList $arguments -PassThru
    }
  } catch {
    Finish 1 (Error-Payload "failed" "Could not launch '$App': $($_.Exception.Message)")
  }
  if (-not $WaitWindow) {
    Finish 0 ([pscustomobject]@{
      ok = $true
      command = "launch"
      app = $App
      candidate = $candidate
      session_id = $sid
      launched = $true
      owned = $false
      ownership_reason = "wait-window-not-requested"
      pid = $proc.Id
    })
  }

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $newWindows = @()
  do {
    $treeIds = @(Get-ProcessTreeIds ([int]$proc.Id) $launchStartedAt)
    $windows = @(Get-Windows | Where-Object {
      (-not $beforeIds.ContainsKey($_.id)) -and
      (($treeIds -contains ([int]$_.pid)) -or (Candidate-DirectExeMatchesWindow $candidate $_) -or (Candidate-HintMatchesWindow $candidate $_)) -and
      (Window-StartedAfter $_ $launchStartedAt) -and
      (Window-HasOwnableIdentity $_) -and
      (Candidate-ProcessMatchesWindow $candidate $_)
    })
    if ($windows.Count -gt 0) {
      $newWindows = @($windows)
      break
    }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)

  if ($newWindows.Count -eq 0) {
    $existingMatches = @($beforeWindows | Where-Object { Candidate-ProcessMatchesWindow $candidate $_ })
    if ($existingMatches.Count -eq 1) {
      $preTouch = $existingMatches[0]
      $ledger = Read-Ledger $sid -AllowMissing
      $touch = Ledger-WindowRecord $preTouch $sid "launch-existing" $false "" ""
      $touch | Add-Member -NotePropertyName pre_mutation_minimized -NotePropertyValue ([bool]$preTouch.minimized) -Force
      $touch | Add-Member -NotePropertyName pre_mutation_foreground -NotePropertyValue ([bool]$preTouch.foreground) -Force
      Upsert-LedgerWindow $ledger $touch
      Add-LedgerEvent $ledger "launch-existing" ([pscustomobject]@{ window_id = $touch.window_id; app = $App; target = $candidate.target; pid = $proc.Id; owned = $false })
      Write-Ledger $ledger
      $focusResult = Focus-TargetWindow $preTouch
      Finish 0 ([pscustomobject]@{
        ok = $true
        command = "launch"
        app = $App
        candidate = $candidate
        session_id = $sid
        launched = $true
        owned = $false
        touched = $true
        ownership_reason = "existing-window-reused"
        pid = $proc.Id
        window_id = $focusResult.window.id
        window = $focusResult.window
        focused = $focusResult.focused
        restored = $focusResult.restored
        attempts = $focusResult.attempts
      })
    }
    if ($existingMatches.Count -gt 1) {
      $candidates = @($existingMatches | Select-Object -First 8 | ForEach-Object { Public-Window $_ })
      Finish 72 (Error-Payload "ambiguous" "The app launched but matched multiple pre-existing windows; ownership was not claimed." $candidates)
    }
    Finish 73 ([pscustomobject]@{
      ok = $false
      error = "timeout"
      message = "The app launched, but no new or reusable top-level window could be identified before timeout."
      command = "launch"
      app = $App
      candidate = $candidate
      session_id = $sid
      launched = $true
      owned = $false
      wait_window = "timeout"
      pid = $proc.Id
    })
  }
  if ($newWindows.Count -gt 1) {
    $foregroundNew = @($newWindows | Where-Object { $_.foreground })
    if ($foregroundNew.Count -eq 1) {
      $newWindows = @($foregroundNew[0])
    } else {
      $candidates = @($newWindows | Select-Object -First 8 | ForEach-Object { Public-Window $_ })
      Finish 72 (Error-Payload "ambiguous" "The app created more than one matching new top-level window." $candidates)
    }
  }

  $ledger = Read-Ledger $sid -AllowMissing
  $record = Ledger-WindowRecord $newWindows[0] $sid "launch" $true "" ""
  Upsert-LedgerWindow $ledger $record
  Add-LedgerEvent $ledger "launch" ([pscustomobject]@{ window_id = $record.window_id; app = $App; target = $candidate.target; pid = $proc.Id })
  Write-Ledger $ledger

  $focusResult = Focus-TargetWindow $newWindows[0]
  $newWindows = @(Get-Windows | Where-Object { $_.id -eq $focusResult.window.id })
  if ($newWindows.Count -ne 1) {
    Finish 71 (Error-Payload "not-found" "The launched window disappeared after focus.")
  }
  $record = Ledger-WindowRecord $newWindows[0] $sid "launch" $true "" ""
  Upsert-LedgerWindow $ledger $record
  Add-LedgerEvent $ledger "launch-focused" ([pscustomobject]@{ window_id = $record.window_id; focused = $focusResult.focused; restored = $focusResult.restored })
  Write-Ledger $ledger
  $window = Public-Window $newWindows[0]
  Finish 0 ([pscustomobject]@{
    ok = $true
    command = "launch"
    app = $App
    candidate = $candidate
    session_id = $sid
    launched = $true
    owned = $true
    pid = $proc.Id
    window_id = $window.id
    process_start_time = $record.process_start_time
    executable_path = $record.executable_path
    class = $record.class
    window = $window
    focused = $focusResult.focused
    restored = $focusResult.restored
    attempts = $focusResult.attempts
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
  $sid = Normalize-SessionId $SessionId
  $profilePath = Session-ProfilePath $sid
  $ledger = Read-Ledger $sid -AllowMissing
  $beforeIds = @{}
  foreach ($window in @(Get-Windows | Where-Object { ("" + $_.process).ToLowerInvariant().Contains("chrome") -and ("" + $_.command_line).IndexOf($profilePath, [StringComparison]::OrdinalIgnoreCase) -ge 0 })) {
    $beforeIds[$window.id] = $true
  }
  $args = @("--user-data-dir=$profilePath", "--no-first-run", "--no-default-browser-check", "--new-window", $Url)
  try {
    $proc = Start-Process -FilePath $chrome -ArgumentList $args -PassThru
  } catch {
    Finish 1 (Error-Payload "failed" "Could not open URL in Chrome: $($_.Exception.Message)")
  }
  $deadline = (Get-Date).AddSeconds(8)
  $newWindows = @()
  do {
    $chromeWindows = @(Get-Windows | Where-Object {
      ("" + $_.process).ToLowerInvariant().Contains("chrome") -and
      ("" + $_.command_line).IndexOf($profilePath, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
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
  $windowRecord = Ledger-WindowRecord $newWindows[0] $sid "open-url" $true $profilePath $Url
  Upsert-LedgerWindow $ledger $windowRecord
  Add-LedgerEvent $ledger "open-url" ([pscustomobject]@{ window_id = $windowRecord.window_id; url = $Url; profile_path = $profilePath })
  Write-Ledger $ledger
  $window = Public-Window $newWindows[0]
  Finish 0 ([pscustomobject]@{
    ok = $true
    command = "open-url"
    session_id = $sid
    owned = $true
    browser = "chrome"
    path = $chrome
    url = $Url
    new_window = $true
    profile_path = $profilePath
    launched = $true
    pid = $proc.Id
    window_id = $window.id
    process_start_time = $windowRecord.process_start_time
    class = $windowRecord.class
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

function Session-Summary([object]$Ledger) {
  $owned = @(@($Ledger.windows) | Where-Object { [bool]$_.owned })
  $open = @($owned | Where-Object { ("" + $_.status) -ne "closed" })
  return [pscustomobject]@{
    session_id = $Ledger.session_id
    schema_version = $Ledger.schema_version
    created_at = $Ledger.created_at
    updated_at = $Ledger.updated_at
    owned_count = $owned.Count
    open_owned_count = $open.Count
    path = (Ledger-Path ("" + $Ledger.session_id))
  }
}

function Command-SessionsList {
  Require-LedgerRoot
  $items = @()
  foreach ($file in @(Get-ChildItem -LiteralPath $LedgerRoot -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
    try {
      $ledger = (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) | ConvertFrom-Json
      $items += (Session-Summary $ledger)
    } catch {
      $items += [pscustomobject]@{ session_id = [System.IO.Path]::GetFileNameWithoutExtension($file.Name); corrupt = $true; path = $file.FullName }
    }
  }
  Finish 0 ([pscustomobject]@{ ok = $true; command = "sessions-list"; sessions = $items; count = $items.Count })
}

function Command-SessionsShow {
  $sid = Normalize-SessionId $SessionId
  $ledger = Read-Ledger $sid
  $windows = @()
  foreach ($record in @($ledger.windows)) {
    $verification = $null
    if ([bool]$record.owned -and ("" + $record.status) -ne "closed") {
      $verification = Verify-OwnedWindow $record
    }
    $windows += [pscustomobject]@{
      window_id = $record.window_id
      owned = [bool]$record.owned
      touched = [bool]$record.touched
      status = $record.status
      kind = $record.kind
      title = $record.title
      process = $record.process
      pid = $record.pid
      profile_path = $record.profile_path
      live_state = $(if ($null -ne $verification) { $verification.state } else { "" })
      live_reason = $(if ($null -ne $verification) { $verification.reason } else { "" })
    }
  }
  Finish 0 ([pscustomobject]@{
    ok = $true
    command = "sessions-show"
    session = (Session-Summary $ledger)
    windows = $windows
  })
}

function Update-RecordStatus([object]$Ledger, [string]$WindowIdValue, [string]$StatusValue, [string]$ReasonValue) {
  $windows = @($Ledger.windows)
  for ($i = 0; $i -lt $windows.Count; $i++) {
    if (("" + $windows[$i].window_id) -eq ("" + $WindowIdValue)) {
      $windows[$i].status = $StatusValue
      $windows[$i] | Add-Member -NotePropertyName last_result -NotePropertyValue $ReasonValue -Force
      $windows[$i] | Add-Member -NotePropertyName updated_at -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("o")) -Force
      break
    }
  }
  $Ledger.windows = @($windows)
}

function Command-CleanupSession {
  $sid = Normalize-SessionId $SessionId
  $ledger = Read-Ledger $sid
  if (("" + $ledger.host_boot) -ne (Host-BootMarker)) {
    $payload = Error-Payload "stale-ledger" "Session ledger '$sid' was created before the current Windows boot; refusing cleanup."
    $payload | Add-Member -NotePropertyName session_id -NotePropertyValue $sid -Force
    Finish 1 $payload
  }
  $results = @()
  foreach ($record in @($ledger.windows)) {
    if (-not [bool]$record.owned) {
      if ([bool]$record.touched) {
        $touchResult = Restore-TouchedRecord $record -Preview:$DryRun
        $results += $touchResult
        if (-not $DryRun -and ($touchResult.result -eq "minimized" -or $touchResult.result -eq "unchanged")) {
          Update-RecordStatus $ledger $record.window_id "restored" $touchResult.reason
        }
      }
      continue
    }
    if (("" + $record.status) -eq "closed" -and -not $DryRun) {
      $results += [pscustomobject]@{ window_id = $record.window_id; result = "already_closed"; owned = $true; dry_run = $false; reason = "ledger already marked closed" }
      continue
    }
    $closeResult = Close-OwnedRecord $record -Preview:$DryRun
    $results += $closeResult
    if (-not $DryRun) {
      switch ($closeResult.result) {
        "closed" { Update-RecordStatus $ledger $record.window_id "closed" $closeResult.reason }
        "already_closed" { Update-RecordStatus $ledger $record.window_id "closed" $closeResult.reason }
        "mismatched" { Update-RecordStatus $ledger $record.window_id "mismatched" $closeResult.reason }
        "stale" { Update-RecordStatus $ledger $record.window_id "stale" $closeResult.reason }
        default { Update-RecordStatus $ledger $record.window_id $closeResult.result $closeResult.reason }
      }
    }
  }
  Add-LedgerEvent $ledger "cleanup" ([pscustomobject]@{ dry_run = [bool]$DryRun; results = $results })
  if (-not $DryRun) { Write-Ledger $ledger }
  $closed = @($results | Where-Object { $_.result -eq "closed" })
  $wouldClose = @($results | Where-Object { $_.result -eq "would_close" })
  $restored = @($results | Where-Object { $_.result -eq "minimized" -or $_.result -eq "unchanged" })
  Finish 0 ([pscustomobject]@{
    ok = $true
    command = "cleanup"
    session_id = $sid
    dry_run = [bool]$DryRun
    results = $results
    closed = $closed
    would_close = $wouldClose
    restored = $restored
  })
}

function Command-CleanupMine {
  Require-LedgerRoot
  $allResults = @()
  foreach ($file in @(Get-ChildItem -LiteralPath $LedgerRoot -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
    $sid = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $SessionId = $sid
    $ledger = Read-Ledger $sid
    if (("" + $ledger.host_boot) -ne (Host-BootMarker)) {
      foreach ($record in @($ledger.windows)) {
        $allResults += [pscustomobject]@{
          session_id = $sid
          window_id = "" + $record.window_id
          owned = [bool]$record.owned
          touched = [bool]$record.touched
          dry_run = [bool]$DryRun
          result = "stale"
          reason = "session ledger was created before the current Windows boot"
        }
      }
      continue
    }
    foreach ($record in @($ledger.windows)) {
      if (-not [bool]$record.owned) {
        if ([bool]$record.touched) {
          $touchResult = Restore-TouchedRecord $record -Preview:$DryRun
          $touchResult | Add-Member -NotePropertyName session_id -NotePropertyValue $sid -Force
          $allResults += $touchResult
          if (-not $DryRun -and ($touchResult.result -eq "minimized" -or $touchResult.result -eq "unchanged")) {
            Update-RecordStatus $ledger $record.window_id "restored" $touchResult.reason
          }
        }
        continue
      }
      $closeResult = Close-OwnedRecord $record -Preview:$DryRun
      $closeResult | Add-Member -NotePropertyName session_id -NotePropertyValue $sid -Force
      $allResults += $closeResult
      if (-not $DryRun -and ($closeResult.result -eq "closed" -or $closeResult.result -eq "already_closed")) {
        Update-RecordStatus $ledger $record.window_id "closed" $closeResult.reason
      }
    }
    if (-not $DryRun) { Write-Ledger $ledger }
  }
  Finish 0 ([pscustomobject]@{ ok = $true; command = "cleanup-mine"; dry_run = [bool]$DryRun; results = $allResults; closed = @($allResults | Where-Object { $_.result -eq "closed" }) })
}

function Command-CloseWindow {
  if ([string]::IsNullOrWhiteSpace($WindowId)) {
    Finish 64 (Error-Payload "invalid-argument" "close requires --window-id <id>.")
  }
  $ledgers = @()
  if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
    $ledgers += (Read-Ledger (Normalize-SessionId $SessionId))
  } else {
    Require-LedgerRoot
    foreach ($file in @(Get-ChildItem -LiteralPath $LedgerRoot -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
      try { $ledgers += ((Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) | ConvertFrom-Json) } catch {}
    }
  }
  foreach ($ledger in $ledgers) {
    $record = Find-LedgerWindow $ledger $WindowId
    if ($null -eq $record) { continue }
    if (-not [bool]$record.owned) {
      Finish 1 (Error-Payload "not-owned" "Window '$WindowId' is recorded but is not owned by agent-desktop.")
    }
    $result = Close-OwnedRecord $record
    if ($result.result -eq "closed" -or $result.result -eq "already_closed") {
      Update-RecordStatus $ledger $record.window_id "closed" $result.reason
      Write-Ledger $ledger
    }
    Finish 0 ([pscustomobject]@{ ok = $true; command = "close"; session_id = $ledger.session_id; result = $result })
  }
  Finish 71 (Error-Payload "not-found" "No owned ledger record matched window id '$WindowId'.")
}

try {
  switch ($Command) {
    "doctor" { Command-Doctor }
    "list-windows" { Command-ListWindows }
    "apps-find" { Command-AppsFind }
    "apps-list" { Command-AppsList }
    "launch" { Command-Launch }
    "open-url" { Command-OpenUrl }
    "wait-window" { Command-WaitWindow }
    "sessions-list" { Command-SessionsList }
    "sessions-show" { Command-SessionsShow }
    "cleanup" { Command-CleanupSession }
    "cleanup-mine" { Command-CleanupMine }
    "close" { Command-CloseWindow }
    "type" { Command-TypeInput }
    "key" { Command-KeyInput }
    "click" { Command-ClickInput }
    "focus" {
      $target = Resolve-Target
      $result = Focus-TargetWindow $target
      if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $sid = Normalize-SessionId $SessionId
        $ledger = Read-Ledger $sid -AllowMissing
        $touch = Ledger-WindowRecord $target $sid "focus" $false "" ""
        $touch | Add-Member -NotePropertyName pre_mutation_minimized -NotePropertyValue ([bool]$target.minimized) -Force
        $touch | Add-Member -NotePropertyName pre_mutation_foreground -NotePropertyValue ([bool]$target.foreground) -Force
        Upsert-LedgerWindow $ledger $touch
        Add-LedgerEvent $ledger "focus" ([pscustomobject]@{ window_id = $touch.window_id; owned = $false })
        Write-Ledger $ledger
      }
      Finish 0 ([pscustomobject]@{
        ok = $true
        command = "focus"
        session_id = $SessionId
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
      if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $sid = Normalize-SessionId $SessionId
        $ledger = Read-Ledger $sid -AllowMissing
        $touch = Ledger-WindowRecord $target $sid "restore" $false "" ""
        $touch | Add-Member -NotePropertyName pre_mutation_minimized -NotePropertyValue ([bool]$target.minimized) -Force
        $touch | Add-Member -NotePropertyName pre_mutation_foreground -NotePropertyValue ([bool]$target.foreground) -Force
        Upsert-LedgerWindow $ledger $touch
        Add-LedgerEvent $ledger "restore" ([pscustomobject]@{ window_id = $touch.window_id; owned = $false })
        Write-Ledger $ledger
      }
      Finish 0 ([pscustomobject]@{
        ok = $true
        command = "restore"
        session_id = $SessionId
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

  local ps1 ps1_win root ledger_root profile_root ledger_root_win profile_root_win
  ps1="$(mktemp --suffix=.ps1)"
  if [ -z "${AGENT_DESKTOP_KEEP_HELPER:-}" ]; then
    trap 'rm -f -- "$ps1"' RETURN
  else
    echo "agent-desktop: debug helper: $ps1" >&2
  fi
  windows_host_ps1 "$ps1"
  ps1_win="$(wslpath -w "$ps1")" || emit_shell_error 70 "backend-unavailable" "could not convert helper path with wslpath."
  root="$(workspace_root)"
  ledger_root="$root/.tachyon/agent-desktop/sessions"
  profile_root="$root/.tachyon/agent-desktop/profiles"
  mkdir -p "$ledger_root" "$profile_root"
  ledger_root_win="$(wslpath -w "$ledger_root")" || emit_shell_error 70 "backend-unavailable" "could not convert ledger path with wslpath."
  profile_root_win="$(wslpath -w "$profile_root")" || emit_shell_error 70 "backend-unavailable" "could not convert profile path with wslpath."

  run_with_timeout "$timeout_seconds" "$ps" -NoProfile -ExecutionPolicy Bypass -File "$ps1_win" -Command "$command" -LedgerRoot "$ledger_root_win" -ProfileRoot "$profile_root_win" "$@"
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
  apps)
    sub="${1:-}"
    [ -n "$sub" ] || die_usage "apps requires find or list"
    shift || true
    case "$sub" in
      find)
        query=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --json) shift ;;
            --*) die_usage "unknown apps find argument: $1" ;;
            *) [ -z "$query" ] || die_usage "apps find accepts exactly one query"; query="$1"; shift ;;
          esac
        done
        [ -n "$query" ] || die_usage "apps find requires <name-or-path>"
        invoke_windows_host apps-find 25 -App "$query"
        ;;
      list)
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --json) shift ;;
            *) die_usage "unknown apps list argument: $1" ;;
          esac
        done
        invoke_windows_host apps-list 15
        ;;
      *) die_usage "unknown apps subcommand: $sub" ;;
    esac
    ;;
  launch)
    app=""
    session_id=""
    dry_run=()
    wait_window=()
    timeout_seconds="10"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) shift ;;
        --app) [ "$#" -ge 2 ] || die_usage "--app requires a value"; app="$2"; shift 2 ;;
        --session) [ "$#" -ge 2 ] || die_usage "--session requires a value"; session_id="$2"; shift 2 ;;
        --dry-run) dry_run=("-DryRun"); shift ;;
        --wait-window) wait_window=("-WaitWindow"); shift ;;
        --timeout) [ "$#" -ge 2 ] || die_usage "--timeout requires a value"; timeout_seconds="$2"; shift 2 ;;
        *) die_usage "unknown launch argument: $1" ;;
      esac
    done
    [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || die_usage "--timeout must be an integer number of seconds"
    [ -n "$app" ] || die_usage "launch requires --app <name-or-path>"
    invoke_windows_host launch "$((timeout_seconds + 20))" -App "$app" -SessionId "$session_id" -TimeoutSeconds "$timeout_seconds" "${dry_run[@]}" "${wait_window[@]}"
    ;;
  open-url)
    browser=""
    url=""
    session_id=""
    new_window=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) shift ;;
        --browser) [ "$#" -ge 2 ] || die_usage "--browser requires a value"; browser="$2"; shift 2 ;;
        --new-window) new_window=("-NewWindow"); shift ;;
        --session) [ "$#" -ge 2 ] || die_usage "--session requires a value"; session_id="$2"; shift 2 ;;
        --*) die_usage "unknown open-url argument: $1" ;;
        *) [ -z "$url" ] || die_usage "open-url accepts exactly one URL"; url="$1"; shift ;;
      esac
    done
    [ -n "$browser" ] || die_usage "open-url requires --browser chrome"
    [ -n "$url" ] || die_usage "open-url requires a URL"
    invoke_windows_host open-url 25 -Browser "$browser" -Url "$url" -SessionId "$session_id" "${new_window[@]}"
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
    session_id=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) shift ;;
        --window-id) [ "$#" -ge 2 ] || die_usage "--window-id requires a value"; window_id="$2"; shift 2 ;;
        --process) [ "$#" -ge 2 ] || die_usage "--process requires a value"; process_name="$2"; shift 2 ;;
        --title) [ "$#" -ge 2 ] || die_usage "--title requires a value"; title="$2"; shift 2 ;;
        --session) [ "$#" -ge 2 ] || die_usage "--session requires a value"; session_id="$2"; shift 2 ;;
        *) die_usage "unknown $command_name argument: $1" ;;
      esac
    done
    if [ -z "$window_id" ] && [ -z "$process_name" ]; then
      die_usage "$command_name requires --window-id <id> or --process <name>"
    fi
    invoke_windows_host "$command_name" 20 -WindowId "$window_id" -ProcessName "$process_name" -Title "$title" -SessionId "$session_id"
    ;;
  close)
    window_id=""
    session_id=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) shift ;;
        --window-id) [ "$#" -ge 2 ] || die_usage "--window-id requires a value"; window_id="$2"; shift 2 ;;
        --session) [ "$#" -ge 2 ] || die_usage "--session requires a value"; session_id="$2"; shift 2 ;;
        *) die_usage "unknown close argument: $1" ;;
      esac
    done
    [ -n "$window_id" ] || die_usage "close requires --window-id <id>"
    invoke_windows_host close 20 -WindowId "$window_id" -SessionId "$session_id"
    ;;
  type)
    window_id=""
    session_id=""
    text=""
    dry_run=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) shift ;;
        --window-id) [ "$#" -ge 2 ] || die_usage "--window-id requires a value"; window_id="$2"; shift 2 ;;
        --text) [ "$#" -ge 2 ] || die_usage "--text requires a value"; text="$2"; shift 2 ;;
        --session) [ "$#" -ge 2 ] || die_usage "--session requires a value"; session_id="$2"; shift 2 ;;
        --dry-run) dry_run=("-DryRun"); shift ;;
        *) die_usage "unknown type argument: $1" ;;
      esac
    done
    [ -n "$window_id" ] || die_usage "type requires --window-id <id>"
    [ -n "$session_id" ] || die_usage "type requires --session <id>"
    [ -n "$text" ] || die_usage "type requires --text <text>"
    text_b64="$(printf '%s' "$text" | base64 | tr -d '\n')"
    type_timeout=$((30 + (${#text} / 30)))
    invoke_windows_host type "$type_timeout" -WindowId "$window_id" -SessionId "$session_id" -TextB64 "$text_b64" "${dry_run[@]}"
    ;;
  key)
    window_id=""
    session_id=""
    key_value=""
    dry_run=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) shift ;;
        --window-id) [ "$#" -ge 2 ] || die_usage "--window-id requires a value"; window_id="$2"; shift 2 ;;
        --key) [ "$#" -ge 2 ] || die_usage "--key requires a value"; key_value="$2"; shift 2 ;;
        --session) [ "$#" -ge 2 ] || die_usage "--session requires a value"; session_id="$2"; shift 2 ;;
        --dry-run) dry_run=("-DryRun"); shift ;;
        *) die_usage "unknown key argument: $1" ;;
      esac
    done
    [ -n "$window_id" ] || die_usage "key requires --window-id <id>"
    [ -n "$session_id" ] || die_usage "key requires --session <id>"
    [ -n "$key_value" ] || die_usage "key requires --key <key-or-chord>"
    invoke_windows_host key 20 -WindowId "$window_id" -SessionId "$session_id" -Key "$key_value" "${dry_run[@]}"
    ;;
  click)
    window_id=""
    session_id=""
    x_value=""
    y_value=""
    expected_bounds=""
    dry_run=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) shift ;;
        --window-id) [ "$#" -ge 2 ] || die_usage "--window-id requires a value"; window_id="$2"; shift 2 ;;
        --x) [ "$#" -ge 2 ] || die_usage "--x requires a value"; x_value="$2"; shift 2 ;;
        --y) [ "$#" -ge 2 ] || die_usage "--y requires a value"; y_value="$2"; shift 2 ;;
        --expected-bounds) [ "$#" -ge 2 ] || die_usage "--expected-bounds requires a value"; expected_bounds="$2"; shift 2 ;;
        --session) [ "$#" -ge 2 ] || die_usage "--session requires a value"; session_id="$2"; shift 2 ;;
        --dry-run) dry_run=("-DryRun"); shift ;;
        *) die_usage "unknown click argument: $1" ;;
      esac
    done
    [ -n "$window_id" ] || die_usage "click requires --window-id <id>"
    [ -n "$session_id" ] || die_usage "click requires --session <id>"
    [[ "$x_value" =~ ^[0-9]+$ ]] || die_usage "click requires non-negative integer --x"
    [[ "$y_value" =~ ^[0-9]+$ ]] || die_usage "click requires non-negative integer --y"
    invoke_windows_host click 20 -WindowId "$window_id" -SessionId "$session_id" -X "$x_value" -Y "$y_value" -ExpectedBounds "$expected_bounds" "${dry_run[@]}"
    ;;
  cleanup)
    session_id=""
    mine=false
    dry_run=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) shift ;;
        --session) [ "$#" -ge 2 ] || die_usage "--session requires a value"; session_id="$2"; shift 2 ;;
        --mine) mine=true; shift ;;
        --dry-run) dry_run=("-DryRun"); shift ;;
        *) die_usage "unknown cleanup argument: $1" ;;
      esac
    done
    if [ "$mine" = true ]; then
      invoke_windows_host cleanup-mine 60 "${dry_run[@]}"
    else
      [ -n "$session_id" ] || die_usage "cleanup requires --session <id> or --mine"
      invoke_windows_host cleanup 60 -SessionId "$session_id" "${dry_run[@]}"
    fi
    ;;
  sessions)
    sub="${1:-}"
    [ -n "$sub" ] || die_usage "sessions requires list or show"
    shift || true
    session_id=""
    case "$sub" in
      list)
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --json) shift ;;
            *) die_usage "unknown sessions list argument: $1" ;;
          esac
        done
        invoke_windows_host sessions-list 20
        ;;
      show)
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --json) shift ;;
            --session) [ "$#" -ge 2 ] || die_usage "--session requires a value"; session_id="$2"; shift 2 ;;
            *) die_usage "unknown sessions show argument: $1" ;;
          esac
        done
        [ -n "$session_id" ] || die_usage "sessions show requires --session <id>"
        invoke_windows_host sessions-show 20 -SessionId "$session_id"
        ;;
      *) die_usage "unknown sessions subcommand: $sub" ;;
    esac
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    die_usage "unknown command: $command_name"
    ;;
esac

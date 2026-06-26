#!/bin/sh
# agent-browser plugin — preflight doctor.
#
# Proves the two things a browse needs before the agent attempts one:
#   1. the provisioned, checksum-verified agent-browser binary runs (via the plugin-scoped launcher), and
#   2. a usable Chrome/Chromium is present on the host.
#
# Chrome is NOT provisioned by the plugin (it is a multi-file browser runtime, not a single verifiable
# executable), so its absence must FAIL LOUD here — never let the agent pretend it can browse. On a missing
# browser this prints `BROWSER_RUNTIME_MISSING` + the exact remediation and exits non-zero.
#
# Run from the workspace root (or anywhere inside it). POSIX sh; no bashisms.
set -u

# --- locate the plugin-scoped launcher by walking up to the workspace root ---
find_launcher() {
  d=$(pwd)
  while [ -n "$d" ]; do
    if [ -x "$d/.tachyon/bin/_tachyon-tool" ]; then printf '%s\n' "$d/.tachyon/bin/_tachyon-tool"; return 0; fi
    [ "$d" = "/" ] && break
    d=$(dirname "$d")
  done
  return 1
}

LAUNCHER=$(find_launcher) || {
  echo "BROWSER_RUNTIME_MISSING: the agent-browser plugin launcher (.tachyon/bin/_tachyon-tool) was not found." >&2
  echo "  Remediation: install the agent-browser plugin in this workspace via the Tachyon Plugins view, then re-run doctor." >&2
  exit 4
}

# --- 1) the provisioned binary runs --------------------------------------------------------------------
if ! VER=$("$LAUNCHER" agent-browser agent-browser --version 2>/dev/null); then
  echo "BROWSER_RUNTIME_MISSING: the provisioned agent-browser binary did not run through the launcher." >&2
  echo "  Remediation: reinstall the agent-browser plugin (the launcher re-validates the binary hash on every run)." >&2
  exit 4
fi

# --- 2) a usable Chrome/Chromium is present ------------------------------------------------------------
have_chrome() {
  # explicit override wins
  if [ -n "${AGENT_BROWSER_EXECUTABLE_PATH:-}" ] && [ -x "${AGENT_BROWSER_EXECUTABLE_PATH}" ]; then return 0; fi
  # common PATH names (Linux + Brave/Chromium variants)
  for c in google-chrome google-chrome-stable chromium chromium-browser brave-browser chrome; do
    command -v "$c" >/dev/null 2>&1 && return 0
  done
  # macOS app bundles
  for p in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
           "/Applications/Chromium.app/Contents/MacOS/Chromium" \
           "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"; do
    [ -x "$p" ] && return 0
  done
  # agent-browser's own Chrome-for-Testing cache (populated by `agent-browser install`)
  for d in "${HOME}/.cache/agent-browser" "${HOME}/Library/Caches/agent-browser" "${HOME}/.agent-browser"; do
    [ -d "$d" ] && find "$d" -type f -name 'chrome*' 2>/dev/null | grep -q . && return 0
  done
  return 1
}

if ! have_chrome; then
  echo "BROWSER_RUNTIME_MISSING: no usable Chrome/Chromium found on this host." >&2
  echo "  Remediation (pick one):" >&2
  echo "    - install Google Chrome or Chromium from your OS package manager, OR" >&2
  echo "    - let agent-browser fetch a pinned Chrome-for-Testing:  $LAUNCHER agent-browser agent-browser install" >&2
  echo "    - or point AGENT_BROWSER_EXECUTABLE_PATH at an existing Chrome binary." >&2
  exit 4
fi

echo "agent-browser OK — binary: ${VER}; a usable Chrome was detected. Browsing is available."

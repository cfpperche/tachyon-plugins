#!/bin/sh
# agent-browser plugin — preflight doctor.
#
# Delegates to the CLI's own `agent-browser doctor` (run through the plugin-scoped launcher), which does a REAL
# usability check — CLI version, Chrome detection, AND a headless launch test (about:blank) — not mere presence
# detection. Chrome is NOT provisioned by the plugin (it is a multi-file browser runtime, not a single verifiable
# executable), so a Chrome/launch failure must FAIL LOUD here: this prints `BROWSER_RUNTIME_MISSING` + remediation
# and exits non-zero, so the agent never pretends it can browse.
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

# --- run the CLI's own doctor (binary + Chrome + headless launch test) ---
OUT=$("$LAUNCHER" agent-browser agent-browser doctor 2>&1)
RC=$?
printf '%s\n' "$OUT"

# A non-zero exit, or any FAIL in the Chrome / Launch-test sections, means a browse will not work. The CLI marks
# hard failures with `fail` lines and a `Summary: … N fail`; provider/key items are `info` and do not count.
if [ "$RC" -ne 0 ] || printf '%s\n' "$OUT" | grep -qiE '^[[:space:]]*fail[[:space:]]+(.*chrome|.*launch|.*browser)'; then
  echo "" >&2
  echo "BROWSER_RUNTIME_MISSING: the browser preflight failed (see the doctor report above)." >&2
  echo "  Remediation (pick one):" >&2
  echo "    - install Google Chrome or Chromium from your OS package manager, OR" >&2
  echo "    - let agent-browser fetch a pinned Chrome-for-Testing:  $LAUNCHER agent-browser agent-browser install --with-deps" >&2
  echo "    - or point AGENT_BROWSER_EXECUTABLE_PATH at an existing Chrome binary, then re-run doctor." >&2
  exit 4
fi

echo ""
echo "agent-browser OK — binary + Chrome + headless launch test all passed. Browsing is available."

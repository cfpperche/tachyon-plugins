#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JQ_BIN="$(command -v jq || true)"
[ -n "$JQ_BIN" ] || { echo "dogfood: jq is required" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
git init -q
mkdir -p .tachyon assets/generated/mockups

FAKE_CURL="$WORK/fake-curl"
AUTH_LOG="$WORK/auth.log"
export DOGFOOD_AUTH_LOG="$AUTH_LOG"

cat > "$FAKE_CURL" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out=""
cfg=""
want_code=0
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then out="$arg"; prev=""; continue; fi
  if [ "$prev" = "--config" ]; then cfg="$arg"; prev=""; continue; fi
  case "$arg" in
    -o|--config) prev="$arg" ;;
    -w) want_code=1; prev="$arg" ;;
    *) [ "$prev" = "-w" ] && prev="" ;;
  esac
done
[ -z "$cfg" ] || cat "$cfg" >> "${DOGFOOD_AUTH_LOG:?}"
if [ "$want_code" = "1" ]; then
  [ -n "$out" ] && printf '{"images":[{"url":"https://example.invalid/fake.jpg"}]}\n' > "$out"
  printf '200'
  exit 0
fi
[ -n "$out" ] && printf 'fake image bytes\n' > "$out"
SH
chmod +x "$FAKE_CURL"

# Os scripts resolvem curl/jq do PATH, com um override por env que existe justamente para isto.
# Injetar por ali exercita o caminho REAL de resolução, em vez de um shim que já não existe.
export IMAGE_CURL="$FAKE_CURL" SOUND_CURL="$FAKE_CURL" VIDEO_CURL="$FAKE_CURL"
export IMAGE_JQ="$JQ_BIN"      SOUND_JQ="$JQ_BIN"      VIDEO_JQ="$JQ_BIN"

IMAGE="$ROOT/image/skills/image/scripts/image.sh"
SOUND="$ROOT/sound/skills/sound/scripts/sound.sh"
VIDEO="$ROOT/video/skills/video/scripts/video.sh"

missing_key() {
  script="$1"; shift
  if env -u FAL_KEY bash "$script" "$@" >/tmp/fal-dogfood-out 2>/tmp/fal-dogfood-err; then
    echo "dogfood: expected missing-key failure for $script" >&2
    exit 1
  fi
  grep -q "FAL_KEY is not set" /tmp/fal-dogfood-err
}

rm -f .tachyon/secrets.env
missing_key "$IMAGE" --tier draft "fallback test"
missing_key "$SOUND" "fallback test" --kind sfx --duration 1
missing_key "$VIDEO" submit "fallback test" --tier premium --duration 1 --confirm-cost-usd 0.60

printf 'FAL_KEY=file-key\n' > .tachyon/secrets.env
chmod 600 .tachyon/secrets.env
env -u FAL_KEY bash "$IMAGE" --tier draft --name file-fallback "fallback test" >/tmp/fal-dogfood-out
grep -q "Authorization: Key file-key" "$AUTH_LOG"

: > "$AUTH_LOG"
printf 'FAL_KEY=file-key\n' > .tachyon/secrets.env
FAL_KEY=env-key bash "$IMAGE" --tier draft --name env-wins "fallback test" >/tmp/fal-dogfood-out
grep -q "Authorization: Key env-key" "$AUTH_LOG"
if grep -q "Authorization: Key file-key" "$AUTH_LOG"; then
  echo "dogfood: .tachyon/secrets.env overrode the explicit environment" >&2
  exit 1
fi

echo "dogfood: fal secrets env fallback passed"

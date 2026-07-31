#!/usr/bin/env bash
# Capture README marquee screenshots by launching ShadowDeck with an in-app
# exporter (no Screen Recording permission required).
#
# Uses an ephemeral in-memory sample library only — never your on-disk personal data.
#
# Usage:
#   Scripts/capture_readme_screenshots.sh
#   SHADOWDECK_APP=/path/to/ShadowDeck.app Scripts/capture_readme_screenshots.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Docs/Screenshots"
mkdir -p "$OUT"

# Prefer Debug build from DerivedData; fall back to release_build output.
DEFAULT_DEBUG="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/ShadowDeck-*/Build/Products/Debug/ShadowDeck.app 2>/dev/null | head -1 || true)"
APP="${SHADOWDECK_APP:-${DEFAULT_DEBUG:-$ROOT/build/Release/ShadowDeck.app}}"

if [[ ! -d "$APP" ]]; then
  echo "Building Debug ShadowDeck…"
  xcodebuild -project "$ROOT/ShadowDeck.xcodeproj" -scheme ShadowDeck \
    -destination 'platform=macOS' -configuration Debug build
  APP="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/ShadowDeck-*/Build/Products/Debug/ShadowDeck.app 2>/dev/null | head -1)"
fi

if [[ ! -d "$APP" ]]; then
  echo "error: ShadowDeck.app not found. Build the project first." >&2
  exit 1
fi

echo "Using app: $APP"
echo "Repo out:  $OUT"

# Sandboxed app writes here; we copy into the repo afterward.
CONTAINER_OUT="$HOME/Library/Containers/com.shadowdeck.ShadowDeck/Data/Library/Application Support/ShadowDeck/MarketingScreenshots"
# Non-sandboxed fallback (if entitlements ever change):
HOST_AS="$HOME/Library/Application Support/ShadowDeck/MarketingScreenshots"

# Quit any interactive instance so we get a clean launch + splash.
pkill -x ShadowDeck 2>/dev/null || true
sleep 0.6

# Launch with capture flags. open(1) does not forward env to GUI apps reliably
# on all macOS versions, so we exec the binary directly.
export SHADOWDECK_CAPTURE_SCREENSHOTS=1

# Run until the app terminates after captures (timeout safety).
set +e
"$APP/Contents/MacOS/ShadowDeck" --capture-screenshots &
PID=$!
set -e

# Wait up to ~3 min for stills + denser GIF storyboards / crossfades.
for i in $(seq 1 360); do
  if ! kill -0 "$PID" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

if kill -0 "$PID" 2>/dev/null; then
  echo "Timed out waiting for captures; terminating." >&2
  kill "$PID" 2>/dev/null || true
  sleep 0.3
  kill -9 "$PID" 2>/dev/null || true
fi

SRC=""
if compgen -G "$CONTAINER_OUT"/0*.jpg > /dev/null 2>&1 || compgen -G "$CONTAINER_OUT"/0*.gif > /dev/null 2>&1; then
  SRC="$CONTAINER_OUT"
elif compgen -G "$HOST_AS"/0*.jpg > /dev/null 2>&1 || compgen -G "$HOST_AS"/0*.gif > /dev/null 2>&1; then
  SRC="$HOST_AS"
elif compgen -G "$CONTAINER_OUT"/0*.png > /dev/null 2>&1; then
  SRC="$CONTAINER_OUT"
elif compgen -G "$HOST_AS"/0*.png > /dev/null 2>&1; then
  SRC="$HOST_AS"
else
  echo "No screenshots found in:" >&2
  echo "  $CONTAINER_OUT" >&2
  echo "  $HOST_AS" >&2
  exit 1
fi

echo "Copying from: $SRC"
rm -f "$OUT"/0*.png "$OUT"/0*.jpg "$OUT"/0*.gif "$OUT"/_*.png 2>/dev/null || true
# README uses JPEG stills + silent GIFs.
cp -f "$SRC"/0*.jpg "$OUT"/ 2>/dev/null || true
cp -f "$SRC"/0*.gif "$OUT"/ 2>/dev/null || true
# Drop retired marquees from older captures.
rm -f "$OUT"/05-run-library.jpg "$OUT"/06-run-detail.jpg \
  "$OUT"/thumbs/05-run-library.jpg "$OUT"/thumbs/06-run-detail.jpg 2>/dev/null || true

echo ""
echo "Captured files:"
ls -la "$OUT"/0*.jpg "$OUT"/0*.gif 2>/dev/null || {
  echo "Copy failed." >&2
  exit 1
}

# Normalize still sizes: full UI/splash to 1800px long edge; equal thumbs for UI shots.
for f in "$OUT"/0*.jpg; do
  [[ -f "$f" ]] || continue
  sips -Z 1800 "$f" >/dev/null
  sips -s format jpeg -s formatOptions 85 "$f" --out "$f" >/dev/null
done

mkdir -p "$OUT/thumbs"
for base in 02-library 03-generation-role 04-character-sheet; do
  if [[ -f "$OUT/${base}.jpg" ]]; then
    sips -Z 960 "$OUT/${base}.jpg" --out "$OUT/thumbs/${base}.jpg" >/dev/null
    sips -s format jpeg -s formatOptions 82 "$OUT/thumbs/${base}.jpg" --out "$OUT/thumbs/${base}.jpg" >/dev/null
  fi
done

# Quantize/resize GIFs for GitHub-friendly sizes (crossfades make raw ImageIO huge).
if compgen -G "$OUT"/0*.gif > /dev/null 2>&1; then
  VENV="${TMPDIR:-/tmp}/shadowdeck-gif-venv"
  if [[ ! -x "$VENV/bin/python" ]]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q Pillow
  fi
  "$VENV/bin/python" - "$OUT" <<'PY'
from PIL import Image
import glob, os, sys
root = sys.argv[1]
for path in sorted(glob.glob(os.path.join(root, "0*.gif"))):
    im = Image.open(path)
    frames, durations = [], []
    try:
        while True:
            fr = im.convert("RGBA")
            w, h = fr.size
            long_edge = max(w, h)
            if long_edge > 640:
                scale = 640 / long_edge
                fr = fr.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.Resampling.LANCZOS)
            frames.append(fr.convert("P", palette=Image.ADAPTIVE, colors=96))
            durations.append(max(int(im.info.get("duration", 220)), 80))
            im.seek(im.tell() + 1)
    except EOFError:
        pass
    if not frames:
        continue
    frames[0].save(
        path,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        optimize=True,
        disposal=2,
    )
    print(f"  optimized {os.path.basename(path)} → {os.path.getsize(path)//1024} KB ({len(frames)} frames)")
PY
fi

echo "Done."
ls -la "$OUT"/*.jpg "$OUT"/*.gif "$OUT/thumbs"/*.jpg 2>/dev/null || true

#!/usr/bin/env bash
# Build a Release configuration of ShadowDeck (unsigned local archive-style product).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

OUT="${ROOT}/build/Release"
mkdir -p "$OUT"

echo "==> ShadowDeck Release build"
echo "    Project: $ROOT"
echo "    Output:  $OUT"

xcodebuild \
  -project ShadowDeck.xcodeproj \
  -scheme ShadowDeck \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$OUT/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$(find "$OUT/DerivedData/Build/Products/Release" -maxdepth 1 -name 'ShadowDeck.app' -print -quit)"
if [[ -z "${APP}" || ! -d "${APP}" ]]; then
  echo "error: ShadowDeck.app not found under Release products" >&2
  exit 1
fi

DEST="$OUT/ShadowDeck.app"
rm -rf "$DEST"
cp -R "$APP" "$DEST"

echo "==> Built $DEST"
echo "    Version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist" 2>/dev/null || echo '?')"
echo "    Open with: open \"$DEST\""

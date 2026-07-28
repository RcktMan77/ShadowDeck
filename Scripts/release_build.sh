#!/usr/bin/env bash
# Build a Release configuration of ShadowDeck and optionally a distributable zip.
#
#   Scripts/release_build.sh           # app only → build/Release/ShadowDeck.app
#   Scripts/release_build.sh --zip     # also → dist/ShadowDeck-<version>.zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MAKE_ZIP=0
for arg in "$@"; do
  case "$arg" in
    --zip|-z) MAKE_ZIP=1 ;;
    -h|--help)
      echo "Usage: $0 [--zip]"
      exit 0
      ;;
  esac
done

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

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist" 2>/dev/null || echo '0.0.0')"
echo "==> Built $DEST"
echo "    Version: $VERSION"
echo "    Open with: open \"$DEST\""

if [[ "$MAKE_ZIP" -eq 1 ]]; then
  DIST="${ROOT}/dist"
  mkdir -p "$DIST"
  ZIP_NAME="ShadowDeck-${VERSION}-macos.zip"
  ZIP_PATH="$DIST/$ZIP_NAME"
  rm -f "$ZIP_PATH"
  # ditto preserves app bundle structure and resource forks better than zip alone.
  (
    cd "$OUT"
    ditto -c -k --sequesterRsrc --keepParent "ShadowDeck.app" "$ZIP_PATH"
  )
  echo "==> Packaged $ZIP_PATH"
  ls -lh "$ZIP_PATH"
fi

#!/usr/bin/env bash
# Build a Release configuration of ShadowDeck and optionally zip / sign / notarize.
#
#   Scripts/release_build.sh                      # unsigned app → build/Release/ShadowDeck.app
#   Scripts/release_build.sh --zip                # also → dist/ShadowDeck-<version>-macos.zip
#   Scripts/release_build.sh --zip --sign         # Developer ID Application sign + hardened runtime
#   Scripts/release_build.sh --zip --sign --notarize
#       Notarize with notarytool (needs a keychain profile; default SHADOWDECK_NOTARY_PROFILE
#       or "AC_PASSWORD"). Staples the ticket onto the app and re-zips.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MAKE_ZIP=0
DO_SIGN=0
DO_NOTARIZE=0
IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Zachary Davis (3G7J26XFL3)}"
NOTARY_PROFILE="${SHADOWDECK_NOTARY_PROFILE:-AC_PASSWORD}"

for arg in "$@"; do
  case "$arg" in
    --zip|-z) MAKE_ZIP=1 ;;
    --sign|-s) DO_SIGN=1 ;;
    --notarize|-n) DO_NOTARIZE=1; DO_SIGN=1; MAKE_ZIP=1 ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
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

ENTITLEMENTS="$ROOT/ShadowDeck/ShadowDeck.entitlements"
if [[ "$DO_SIGN" -eq 1 ]]; then
  echo "==> Codesigning with: $IDENTITY"
  # Deep sign nested frameworks/dylibs first if any appear later; currently app is flat.
  /usr/bin/codesign \
    --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    --timestamp \
    "$DEST"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$DEST"
  echo "    Signature OK"
fi

package_zip() {
  local DIST="${ROOT}/dist"
  mkdir -p "$DIST"
  local ZIP_NAME="ShadowDeck-${VERSION}-macos.zip"
  local ZIP_PATH="$DIST/$ZIP_NAME"
  rm -f "$ZIP_PATH"
  (
    cd "$OUT"
    ditto -c -k --sequesterRsrc --keepParent "ShadowDeck.app" "$ZIP_PATH"
  )
  echo "==> Packaged $ZIP_PATH"
  ls -lh "$ZIP_PATH"
  echo "$ZIP_PATH"
}

ZIP_PATH="${ROOT}/dist/ShadowDeck-${VERSION}-macos.zip"
if [[ "$MAKE_ZIP" -eq 1 ]]; then
  package_zip >/dev/null
  # Re-run packaging with visible logs:
  DIST="${ROOT}/dist"
  mkdir -p "$DIST"
  rm -f "$ZIP_PATH"
  (
    cd "$OUT"
    ditto -c -k --sequesterRsrc --keepParent "ShadowDeck.app" "$ZIP_PATH"
  )
  echo "==> Packaged $ZIP_PATH"
  ls -lh "$ZIP_PATH"
fi

if [[ "$DO_NOTARIZE" -eq 1 ]]; then
  if [[ ! -f "$ZIP_PATH" ]]; then
    echo "error: zip missing for notarization" >&2
    exit 1
  fi
  echo "==> Submitting to Apple notary service (profile: $NOTARY_PROFILE)"
  if ! xcrun notarytool submit "$ZIP_PATH" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait; then
    echo ""
    echo "Notarization failed. Store credentials once with:"
    echo "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
    echo "    --apple-id YOU@example.com --team-id 3G7J26XFL3 --password app-specific-password"
    echo "Or set SHADOWDECK_NOTARY_PROFILE to an existing keychain profile name."
    exit 1
  fi
  echo "==> Stapling notarization ticket"
  xcrun stapler staple "$DEST"
  xcrun stapler validate "$DEST"
  # Re-zip stapled app for distribution.
  rm -f "$ZIP_PATH"
  (
    cd "$OUT"
    ditto -c -k --sequesterRsrc --keepParent "ShadowDeck.app" "$ZIP_PATH"
  )
  echo "==> Notarized distribution ready: $ZIP_PATH"
  ls -lh "$ZIP_PATH"
fi

echo "    Open with: open \"$DEST\""

#!/usr/bin/env bash
# Build a Release configuration of ShadowDeck and optionally zip / sign / notarize.
#
# Maintainer docs: Docs/RELEASE.md
#
#   Scripts/release_build.sh                 # unsigned app → build/Release/ShadowDeck.app
#   Scripts/release_build.sh --zip           # also → dist/ShadowDeck-<version>-macos.zip
#   Scripts/release_build.sh --zip --sign    # Developer ID sign + hardened runtime
#   Scripts/release_build.sh --zip --sign --notarize
#   Scripts/release_build.sh --notarize      # implies --zip --sign; staple + re-zip
#
# Signing / notarization read local env only (not hard-coded personal identity):
#   CODESIGN_IDENTITY          Full "Developer ID Application: …" string (required for --sign)
#   SHADOWDECK_NOTARY_PROFILE  notarytool keychain profile name (required for --notarize)
#   DEVELOPER_DIR              Optional; defaults to /Applications/Xcode.app/…
#
# Store notary credentials once (profile name must match SHADOWDECK_NOTARY_PROFILE):
#   xcrun notarytool store-credentials "$SHADOWDECK_NOTARY_PROFILE" \
#     --apple-id YOU@example.com --team-id YOUR_TEAM_ID --password app-specific-password
#
# Done when: with credentials present, --sign --notarize produces a stapled .app
# inside dist/ShadowDeck-<version>-macos.zip (spctl assess should succeed).
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MAKE_ZIP=0
DO_SIGN=0
DO_NOTARIZE=0

for arg in "$@"; do
  case "$arg" in
    --zip|-z) MAKE_ZIP=1 ;;
    --sign|-s) DO_SIGN=1 ;;
    --notarize|-n) DO_NOTARIZE=1; DO_SIGN=1; MAKE_ZIP=1 ;;
    -h|--help)
      awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Resolve signing identity only when needed (env required; no personal default in-repo).
IDENTITY=""
if [[ "$DO_SIGN" -eq 1 ]]; then
  if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
    echo "error: CODESIGN_IDENTITY is not set." >&2
    echo "  Export your Developer ID Application identity, e.g.:" >&2
    echo "    export CODESIGN_IDENTITY=\"Developer ID Application: Your Name (TEAMID)\"" >&2
    echo "  List identities with: security find-identity -v -p codesigning" >&2
    exit 1
  fi
  IDENTITY="$CODESIGN_IDENTITY"
fi

NOTARY_PROFILE=""
if [[ "$DO_NOTARIZE" -eq 1 ]]; then
  if [[ -z "${SHADOWDECK_NOTARY_PROFILE:-}" ]]; then
    echo "error: SHADOWDECK_NOTARY_PROFILE is not set." >&2
    echo "  Export the notarytool keychain profile name, e.g.:" >&2
    echo "    export SHADOWDECK_NOTARY_PROFILE=\"notarytool-profile\"" >&2
    echo "  Create it once with: xcrun notarytool store-credentials \"\$SHADOWDECK_NOTARY_PROFILE\" …" >&2
    exit 1
  fi
  NOTARY_PROFILE="$SHADOWDECK_NOTARY_PROFILE"
fi

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
  /usr/bin/codesign \
    --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    --timestamp \
    "$DEST"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$DEST"
  echo "    Signature OK"
fi

ZIP_PATH="${ROOT}/dist/ShadowDeck-${VERSION}-macos.zip"
if [[ "$MAKE_ZIP" -eq 1 ]]; then
  mkdir -p "${ROOT}/dist"
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
    echo "Notarization failed. Ensure credentials exist for profile \"$NOTARY_PROFILE\":"
    echo "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
    echo "    --apple-id YOU@example.com --team-id YOUR_TEAM_ID --password app-specific-password"
    exit 1
  fi
  echo "==> Stapling notarization ticket"
  xcrun stapler staple "$DEST"
  xcrun stapler validate "$DEST"
  rm -f "$ZIP_PATH"
  (
    cd "$OUT"
    ditto -c -k --sequesterRsrc --keepParent "ShadowDeck.app" "$ZIP_PATH"
  )
  echo "==> Notarized distribution ready: $ZIP_PATH"
  ls -lh "$ZIP_PATH"
fi

echo "    Open with: open \"$DEST\""

#!/usr/bin/env bash
# Local developer bootstrap helpers for ShadowDeck.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "==> ShadowDeck bootstrap"
echo "    Project: $ROOT"
echo "    Developer dir: $DEVELOPER_DIR"

if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "error: Xcode not found at $DEVELOPER_DIR" >&2
  exit 1
fi

if ! xcodebuild -license check 2>/dev/null; then
  echo "error: Xcode license not accepted. Run:" >&2
  echo "  sudo xcodebuild -license" >&2
  exit 1
fi

echo "==> Building ShadowDeck (Debug)"
xcodebuild \
  -project ShadowDeck.xcodeproj \
  -scheme ShadowDeck \
  -destination 'platform=macOS' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> Done. Open with: open ShadowDeck.xcodeproj"

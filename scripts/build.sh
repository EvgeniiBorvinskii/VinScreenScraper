#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="VinScreenScraper.app"
BUILD_APP="$ROOT/App/$APP_NAME"
INSTALL_APP="/Applications/$APP_NAME"
CONTENTS="$BUILD_APP/Contents"
MACOS="$CONTENTS/MacOS"
BUNDLE_ID="com.vinscreenscraper.app"
ENTITLEMENTS="$ROOT/Resources/VinScreenScraper.entitlements"

# Prefer a real Apple Development identity so TCC can stick across rebuilds.
SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:.*\)".*/\1/p' | head -1 || true)"
if [[ -z "${SIGN_ID}" ]]; then
  SIGN_ID="-"
fi

echo "→ Building VinScreenScraper…"
cd "$ROOT"
swift build -c release --product VinScreenScraper
BIN="$(swift build -c release --show-bin-path)/VinScreenScraper"

echo "→ Assembling app bundle…"
rm -rf "$BUILD_APP"
mkdir -p "$MACOS" "$CONTENTS/Resources"
cp "$BIN" "$MACOS/VinScreenScraper"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

echo "→ Signing with: $SIGN_ID"
if [[ "$SIGN_ID" == "-" ]]; then
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$BUILD_APP"
else
  codesign --force --deep --sign "$SIGN_ID" --identifier "$BUNDLE_ID" --entitlements "$ENTITLEMENTS" "$BUILD_APP"
fi

echo "→ Installing to $INSTALL_APP…"
pkill -x VinScreenScraper 2>/dev/null || true
pkill -f "$APP_NAME/Contents/MacOS/VinScreenScraper" 2>/dev/null || true
# Also stop the previous product name if still running.
pkill -x VinScreenScraper 2>/dev/null || true
sleep 0.4
rm -rf "$INSTALL_APP"
# Remove old install name if present.
rm -rf /Applications/VinScreenScraper.app
cp -R "$BUILD_APP" "$INSTALL_APP"
xattr -cr "$INSTALL_APP" 2>/dev/null || true

if [[ "$SIGN_ID" == "-" ]]; then
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$INSTALL_APP"
else
  codesign --force --deep --sign "$SIGN_ID" --identifier "$BUNDLE_ID" --entitlements "$ENTITLEMENTS" "$INSTALL_APP"
fi

codesign --verify --deep --strict "$INSTALL_APP"
codesign -dv --verbose=2 "$INSTALL_APP" 2>&1 | egrep 'Identifier|Authority|TeamIdentifier|Signature' || true

echo "✓ Installed: $INSTALL_APP"
open "$INSTALL_APP"
echo ""
echo "This build bypasses Screen Recording when needed:"
echo "  ⌘⇧1 triggers system screenshot-to-clipboard (⌃⌘⇧4 under the hood)."
echo "  Allow Accessibility for VinScreenScraper if prompted."

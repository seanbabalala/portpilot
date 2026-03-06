#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.build/derived"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg-root"

SCHEME="PortPilot"
PROJECT="$ROOT_DIR/PortPilot.xcodeproj"

mkdir -p "$DIST_DIR"

echo "==> Building Release app"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

APP_PATH="$DERIVED_DATA_DIR/Build/Products/Release/PortPilot.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded but app bundle not found: $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo '1.0.0')"
DMG_PATH="$DIST_DIR/PortPilot-${VERSION}.dmg"
ZIP_PATH="$DIST_DIR/PortPilot-${VERSION}.zip"

echo "==> Preparing staging folder"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating DMG: $DMG_PATH"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "PortPilot" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "==> Creating ZIP: $ZIP_PATH"
rm -f "$ZIP_PATH"
(
  cd "$DERIVED_DATA_DIR/Build/Products/Release"
  ditto -c -k --sequesterRsrc --keepParent "PortPilot.app" "$ZIP_PATH"
)

rm -rf "$STAGING_DIR"

echo
echo "Done."
echo "DMG: $DMG_PATH"
echo "ZIP: $ZIP_PATH"
echo
echo "Note: For public distribution without warning dialogs, use Developer ID signing + notarization."

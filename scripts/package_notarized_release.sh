#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.build/derived-notarized"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg-root"

SCHEME="PortPilot"
PROJECT="$ROOT_DIR/PortPilot.xcodeproj"

DEV_ID_APP_CERT="${DEV_ID_APP_CERT:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-PortPilotNotary}"

if [[ -z "$DEV_ID_APP_CERT" ]]; then
  echo "Missing DEV_ID_APP_CERT."
  echo "Example:"
  echo "  DEV_ID_APP_CERT='Developer ID Application: Your Name (TEAMID)' ./scripts/package_notarized_release.sh"
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "$DEV_ID_APP_CERT"; then
  echo "Developer ID cert not found in keychain: $DEV_ID_APP_CERT" >&2
  echo "Import/install Developer ID Application certificate first." >&2
  exit 1
fi

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
ZIP_PATH="$DIST_DIR/PortPilot-${VERSION}.zip"
DMG_PATH="$DIST_DIR/PortPilot-${VERSION}.dmg"
NOTARY_APP_LOG="$DIST_DIR/notary-app-${VERSION}.json"
NOTARY_DMG_LOG="$DIST_DIR/notary-dmg-${VERSION}.json"

echo "==> Signing app with Developer ID"
codesign --force --deep --options runtime --timestamp --sign "$DEV_ID_APP_CERT" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Zipping app for notarization"
rm -f "$ZIP_PATH"
(
  cd "$DERIVED_DATA_DIR/Build/Products/Release"
  ditto -c -k --sequesterRsrc --keepParent "PortPilot.app" "$ZIP_PATH"
)

echo "==> Notarizing app ZIP (profile: $NOTARY_PROFILE)"
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json >"$NOTARY_APP_LOG"

echo "==> Stapling app"
xcrun stapler staple -v "$APP_PATH"

echo "==> Building DMG"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "PortPilot" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null
rm -rf "$STAGING_DIR"

echo "==> Signing DMG"
codesign --force --timestamp --sign "$DEV_ID_APP_CERT" "$DMG_PATH"

echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json >"$NOTARY_DMG_LOG"

echo "==> Stapling DMG"
xcrun stapler staple -v "$DMG_PATH"

echo "==> Verifying Gatekeeper"
spctl -a -vv --type execute "$APP_PATH" || true
spctl -a -vv --type open "$DMG_PATH" || true

echo
echo "Done."
echo "App: $APP_PATH"
echo "ZIP: $ZIP_PATH"
echo "DMG: $DMG_PATH"
echo "Notary logs:"
echo "  $NOTARY_APP_LOG"
echo "  $NOTARY_DMG_LOG"

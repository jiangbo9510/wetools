#!/bin/bash

set -euo pipefail

VERSION="${VERSION:-0.0.1}"
BUNDLE_ID="${BUNDLE_ID:-com.yourname.Wetools}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/ReleaseDerivedData"
PRODUCT_APP="$DERIVED_DATA/Build/Products/Release/Wetools.app"
DIST_DIR="$ROOT_DIR/dist/v$VERSION"
STAGING_DIR="$DIST_DIR/staging"
STAGED_APP="$STAGING_DIR/Wetools.app"
DMG_PATH="$DIST_DIR/Wetools-v$VERSION.dmg"
ZIP_PATH="$DIST_DIR/Wetools-v$VERSION.zip"
ENTITLEMENTS="$ROOT_DIR/Wetools/Resources/Wetools.entitlements"

rm -rf "$DERIVED_DATA" "$DIST_DIR"
mkdir -p "$STAGING_DIR"

xcodebuild \
  -project "$ROOT_DIR/Wetools.xcodeproj" \
  -scheme Wetools \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGNING_ALLOWED=NO \
  build

ditto "$PRODUCT_APP" "$STAGED_APP"
codesign \
  --force \
  --deep \
  --sign "$SIGN_IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  --timestamp=none \
  "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

ln -s /Applications "$STAGING_DIR/Applications"
ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$ZIP_PATH"
hdiutil create \
  -volname "Wetools v$VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING_DIR"
shasum -a 256 "$DMG_PATH" "$ZIP_PATH" > "$DIST_DIR/SHA256SUMS.txt"

echo "Release artifacts:"
echo "  $DMG_PATH"
echo "  $ZIP_PATH"
echo "  $DIST_DIR/SHA256SUMS.txt"

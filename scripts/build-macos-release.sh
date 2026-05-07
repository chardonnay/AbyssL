#!/usr/bin/env bash
set -euo pipefail

APP_EXECUTABLE="AbyssLTranslator"
APP_DISPLAY_NAME="AbyssL Translator"
BUNDLE_IDENTIFIER="org.abyssl.translator"
RESOURCE_BUNDLE="AbyssLTranslator_AbyssLTranslator.bundle"
DIST_DIR="${DIST_DIR:-dist}"
APP_VERSION="${APP_VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

swift build -c release --arch arm64

BINARY_PATH="$(find .build -path "*/release/$APP_EXECUTABLE" -type f | sort | head -n 1)"
RESOURCE_BUNDLE_PATH="$(find .build -path "*/release/$RESOURCE_BUNDLE" -type d | sort | head -n 1)"

if [[ -z "$BINARY_PATH" || ! -f "$BINARY_PATH" ]]; then
  echo "Release binary not found for $APP_EXECUTABLE." >&2
  exit 1
fi

if [[ -z "$RESOURCE_BUNDLE_PATH" || ! -d "$RESOURCE_BUNDLE_PATH" ]]; then
  echo "SwiftPM resource bundle not found: $RESOURCE_BUNDLE." >&2
  exit 1
fi

if ! lipo -archs "$BINARY_PATH" | tr ' ' '\n' | grep -qx "arm64"; then
  echo "Release binary is not an arm64 Apple Silicon binary: $BINARY_PATH" >&2
  lipo -archs "$BINARY_PATH" >&2
  exit 1
fi

APP_BUNDLE="$DIST_DIR/$APP_EXECUTABLE.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/$APP_EXECUTABLE"
cp -R "$RESOURCE_BUNDLE_PATH" "$APP_BUNDLE/$RESOURCE_BUNDLE"
chmod 755 "$MACOS_DIR/$APP_EXECUTABLE"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_IDENTIFIER</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS_DIR/Info.plist"

BINARY_ARCHIVE="$DIST_DIR/$APP_EXECUTABLE-macos-arm64-binary.tar.gz"
tar -czf "$BINARY_ARCHIVE" -C "$(dirname "$BINARY_PATH")" "$APP_EXECUTABLE" "$RESOURCE_BUNDLE"

DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_EXECUTABLE-macos-arm64.dmg"
mkdir -p "$DMG_ROOT"
cp -R "$APP_BUNDLE" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "$APP_DISPLAY_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Built $BINARY_ARCHIVE"
echo "Built $DMG_PATH"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="$ROOT_DIR/apps/macos-host"
RESOURCES_DIR="$HOST_DIR/Resources"
APP_NAME="WidgetDesk"
BUNDLE_ID="${WIDGETDESK_BUNDLE_ID:-com.paranoidearth.WidgetDesk}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"
ICON_PATH="$RESOURCES_DIR/AppIcon.icns"
VENDOR_PATH="$HOST_DIR/Sources/WidgetDeskCore/Resources/Vendor"

if [[ ! -f "$ICON_PATH" ]]; then
  "$ROOT_DIR/scripts/generate-app-icon.sh"
fi

swift build -c release --package-path "$HOST_DIR" --product WidgetDeskHost
BIN_DIR="$(swift build -c release --package-path "$HOST_DIR" --show-bin-path)"

rm -rf "$APP_DIR" "$ZIP_PATH"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/WidgetDeskHost" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ICON_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"
if [[ -d "$VENDOR_PATH" ]]; then
  cp -R "$VENDOR_PATH" "$APP_DIR/Contents/Resources/Vendor"
fi

cat >"$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign "${CODESIGN_IDENTITY:--}" --timestamp=none "$APP_DIR" >/dev/null
fi

ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Packaged $APP_DIR"
echo "Created $ZIP_PATH"

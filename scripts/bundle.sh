#!/bin/bash
# Assemble build/CamTwizzle.app from the binaries produced by build.sh, then sign it.
#
# Environment:
#   BUNDLE_ID      base bundle identifier (default dev.camtwizzle.CamTwizzle)
#   TEAM_ID        Apple Developer team ID (enables the camera extension; see README › Signing)
#   SIGN_IDENTITY  codesign identity for team builds ("Apple Development: …" / "Developer ID Application: …")
#   APP_PROFILE / EXT_PROFILE  provisioning profiles to embed (team builds)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/CamTwizzle.app"
BUNDLE_ID="${BUNDLE_ID:-dev.camtwizzle.CamTwizzle}"
EXT_ID="$BUNDLE_ID.Camera"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo 1.0)"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
TEAM_ID="${TEAM_ID:-}"

echo "▸ bundling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/SystemExtensions"
cp "$BUILD/bin/CamTwizzle" "$APP/Contents/MacOS/CamTwizzle"
cp "$BUILD/bin/twizzle" "$APP/Contents/MacOS/twizzle"
rsync -a --delete --exclude '.DS_Store' "$ROOT/Filters/" "$APP/Contents/Resources/Filters/"
[[ -f "$ROOT/Resources/AppIcon.icns" ]] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
[[ -d "$ROOT/Resources/Thumbnails" ]] && rsync -a "$ROOT/Resources/Thumbnails/" "$APP/Contents/Resources/Thumbnails/"
cp "$ROOT/docs/PLUGINS.md" "$APP/Contents/Resources/" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CamTwizzle</string>
  <key>CFBundleDisplayName</key><string>CamTwizzle</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>CamTwizzle</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSCameraUsageDescription</key><string>CamTwizzle uses your cameras as video sources and talks to virtual camera drivers.</string>
  <key>NSMicrophoneUsageDescription</key><string>CamTwizzle does not record audio; movie sources may contain sound.</string>
  <key>NSSystemExtensionUsageDescription</key><string>Installs the CamTwizzle virtual camera so other apps can see your effects.</string>
</dict>
</plist>
EOF

# Camera extension bundle
EXT="$APP/Contents/Library/SystemExtensions/$EXT_ID.systemextension"
mkdir -p "$EXT/Contents/MacOS"
cp "$BUILD/bin/CamTwizzleCamera" "$EXT/Contents/MacOS/CamTwizzleCamera"
MACH_SERVICE="${TEAM_ID:+$TEAM_ID.}$EXT_ID"
cat > "$EXT/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CamTwizzle Camera</string>
  <key>CFBundleDisplayName</key><string>CamTwizzle Camera</string>
  <key>CFBundleIdentifier</key><string>$EXT_ID</string>
  <key>CFBundleExecutable</key><string>CamTwizzleCamera</string>
  <key>CFBundlePackageType</key><string>SYSX</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSSystemExtensionUsageDescription</key><string>Provides the CamTwizzle virtual camera.</string>
  <key>CMIOExtension</key>
  <dict>
    <key>CMIOExtensionMachServiceName</key><string>$MACH_SERVICE</string>
  </dict>
  <key>CamTwizzleDeviceCount</key><integer>${DEVICE_COUNT:-2}</integer>
  <key>CamTwizzleDeviceName</key><string>CamTwizzle</string>
</dict>
</plist>
EOF

"$ROOT/scripts/sign.sh" "$APP"
echo "✓ $APP"

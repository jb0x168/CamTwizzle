#!/bin/bash
# Sign CamTwizzle.app.
#
# Two modes:
#  • Team build (TEAM_ID + SIGN_IDENTITY set): signs app + camera extension with the
#    restricted entitlements needed to install the Camera Extension, embedding
#    APP_PROFILE / EXT_PROFILE provisioning profiles if given.
#  • Local build (default): signs with a self-signed "CamTwizzle Local Signing"
#    identity kept in build/signing.keychain-db. The identity is stable across
#    rebuilds so macOS privacy permissions (camera, screen recording) persist.
#    The camera extension can't be installed in this mode; use the OBS route.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/CamTwizzle.app}"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")"
EXT="$(ls -d "$APP"/Contents/Library/SystemExtensions/*.systemextension 2>/dev/null | head -1 || true)"
TMP="$ROOT/build/tmp"
mkdir -p "$TMP"

if [[ -n "${TEAM_ID:-}" && -n "${SIGN_IDENTITY:-}" ]]; then
  echo "▸ team signing ($TEAM_ID, $SIGN_IDENTITY)"
  cat > "$TMP/ext.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.application-groups</key><array><string>$TEAM_ID.$BUNDLE_ID</string></array>
</dict></plist>
EOF
  cat > "$TMP/app.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.developer.system-extension.install</key><true/>
  <key>com.apple.security.application-groups</key><array><string>$TEAM_ID.$BUNDLE_ID</string></array>
  <key>com.apple.security.device.camera</key><true/>
</dict></plist>
EOF
  [[ -n "${EXT_PROFILE:-}" && -n "$EXT" ]] && cp "$EXT_PROFILE" "$EXT/Contents/embedded.provisionprofile"
  [[ -n "${APP_PROFILE:-}" ]] && cp "$APP_PROFILE" "$APP/Contents/embedded.provisionprofile"
  [[ -n "$EXT" ]] && codesign --force --options runtime --timestamp --entitlements "$TMP/ext.entitlements" -s "$SIGN_IDENTITY" "$EXT"
  codesign --force --options runtime --timestamp -s "$SIGN_IDENTITY" "$APP/Contents/MacOS/twizzle"
  codesign --force --options runtime --timestamp --entitlements "$TMP/app.entitlements" -s "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict "$APP" && echo "✓ signed for team $TEAM_ID"
  exit 0
fi

# ---- Local self-signed identity -------------------------------------------------
KC="$ROOT/build/signing.keychain-db"
KCPASS="camtwizzle-local"
CN="CamTwizzle Local Signing"
if [[ ! -f "$KC" ]]; then
  echo "▸ creating local signing identity ($CN)"
  security create-keychain -p "$KCPASS" "$KC"
  security set-keychain-settings "$KC"   # no auto-lock
  cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CN
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
  # -legacy keeps the PKCS#12 readable by macOS' security tool with OpenSSL 3.
  openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:$KCPASS 2>/dev/null \
    || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:$KCPASS
  security import "$TMP/id.p12" -k "$KC" -P "$KCPASS" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KC" >/dev/null 2>&1 || true
  rm -f "$TMP/key.pem" "$TMP/id.p12"
fi
security unlock-keychain -p "$KCPASS" "$KC"
# Make the keychain searchable by codesign (keep the user's existing list).
if ! security list-keychains -d user | grep -q "signing.keychain-db"; then
  security list-keychains -d user -s $(security list-keychains -d user | tr -d '"') "$KC"
fi
HASH="$(security find-certificate -c "$CN" -Z "$KC" | awk '/SHA-1/{print $3}')"
[[ -n "$EXT" ]] && codesign --force --keychain "$KC" -s "$HASH" "$EXT"
codesign --force --keychain "$KC" -s "$HASH" "$APP/Contents/MacOS/twizzle"
codesign --force --keychain "$KC" -s "$HASH" "$APP"
echo "✓ signed locally ($CN)"

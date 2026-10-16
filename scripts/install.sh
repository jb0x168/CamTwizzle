#!/bin/bash
# Build (if needed) and install CamTwizzle.app into /Applications, plus the
# `twizzle` CLI into /usr/local/bin (if writable).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build.sh"
APP="$ROOT/build/CamTwizzle.app"
DEST="/Applications/CamTwizzle.app"
# Quit a running copy so the new one is picked up.
osascript -e 'tell application id "dev.camtwizzle.CamTwizzle" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST"
ditto "$APP" "$DEST"
echo "✓ installed $DEST"
if [[ -w /usr/local/bin ]]; then
  ln -sf "$DEST/Contents/MacOS/twizzle" /usr/local/bin/twizzle
  echo "✓ linked /usr/local/bin/twizzle"
fi

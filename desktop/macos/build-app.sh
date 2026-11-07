#!/usr/bin/env bash
# Build Mox.app bundle from the SwiftPM executable.
# Usage: ./build-app.sh
set -euo pipefail

cd "$(dirname "$0")"

echo "Building release binary…"
swift build -c release

BIN=".build/release/Mox"
APP="Mox.app"

if [[ ! -x "$BIN" ]]; then
  echo "Build failed: $BIN not found." >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Mox"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

if [[ -f .env ]]; then
  cp .env "$APP/Contents/Resources/.env"
  echo "Bundled .env into $APP/Contents/Resources/.env"
else
  echo "Note: no .env found at project root — fill in .env or set MOX_ENV before running."
fi

# Ad-hoc sign so it can be launched locally without Gatekeeper friction.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
echo "Run with: open $APP"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/dist/ThermoMole.app"
STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/thermomole-app.XXXXXX")"
STAGED_APP="$STAGE_ROOT/ThermoMole.app"
CONTENTS="$STAGED_APP/Contents"
MACOS="$CONTENTS/MacOS"

cleanup() {
  rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

cd "$ROOT"
swift build -c release

mkdir -p "$MACOS"
cp "$ROOT/.build/arm64-apple-macosx/release/ThermoMole" "$MACOS/ThermoMole"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>ThermoMole</string>
  <key>CFBundleIdentifier</key>
  <string>local.thermomole.app</string>
  <key>CFBundleName</key>
  <string>ThermoMole</string>
  <key>CFBundleDisplayName</key>
  <string>ThermoMole</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"
xattr -cr "$STAGED_APP" 2>/dev/null || true
codesign --force --sign - "$STAGED_APP" >/dev/null
rm -rf "$APP_DIR"
mkdir -p "$(dirname "$APP_DIR")"
mv "$STAGED_APP" "$APP_DIR"
echo "$APP_DIR"

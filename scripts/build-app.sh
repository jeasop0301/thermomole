#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/dist/Patina.app"
STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/thermomole-app.XXXXXX")"
STAGED_APP="$STAGE_ROOT/Patina.app"
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

# Stage bundled fonts (SIL OFL) — macOS registers them at launch via ATSApplicationFontsPath
FONTS_SRC="$ROOT/Sources/ThermoMole/Resources/Fonts"
FONTS_DST="$CONTENTS/Resources/Fonts"
mkdir -p "$FONTS_DST"
cp "$FONTS_SRC/"*.ttf "$FONTS_DST/"
cp "$FONTS_SRC/"*.txt "$FONTS_DST/"

# Stage .lproj localizations into Contents/Resources so Bundle.main (the .app) resolves
# them. English is the development-language fallback (keys are English), so only ko.lproj
# ships; en users and the test runner see the English keys unchanged.
LOC_SRC="$ROOT/Sources/ThermoMole/Resources/Localization"
if [ -d "$LOC_SRC" ]; then
  for lproj in "$LOC_SRC"/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$CONTENTS/Resources/"
  done
fi

# WINDOWED=1 builds a regular (dock-visible) app so screen-control tools can
# enumerate and grant it. Default is a menu-bar-only agent (LSUIElement=true).
if [ "${WINDOWED:-0}" = "1" ]; then
  LSUI_VALUE="false"
else
  LSUI_VALUE="true"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>ThermoMole</string>
  <key>CFBundleIdentifier</key>
  <string>local.thermomole.app</string>
  <key>CFBundleName</key>
  <string>Patina</string>
  <key>CFBundleDisplayName</key>
  <string>Patina</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>ko</string>
  </array>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <${LSUI_VALUE}/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>ATSApplicationFontsPath</key>
  <string>Fonts</string>
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

#!/usr/bin/env bash
set -euo pipefail

# Build a Developer ID-signed, notarized, stapled Patina.app + zip for release.
#
# Required environment:
#   DEVID_APP   : "Developer ID Application: NAME (TEAMID)"  (codesign identity)
#                 e.g. "Developer ID Application: Jisub Lee (MR6HYXNYF5)"
#   AC_PROFILE  : notarytool keychain profile name created once via:
#                 xcrun notarytool store-credentials AC_PROFILE \
#                   --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PW
# Optional:
#   BUNDLE_ID   : default local.thermomole.app (kept stable on purpose)
#   SKIP_NOTARIZE=1 : sign + staple-skip; just produce a Developer ID-signed app (for testing the signature)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/dist/Patina.app"
ZIP_PATH="$ROOT/dist/Patina.zip"
EXEC="$APP_DIR/Contents/MacOS/ThermoMole"
BUNDLE_ID="${BUNDLE_ID:-local.thermomole.app}"
: "${DEVID_APP:?set DEVID_APP to your Developer ID Application identity}"

cd "$ROOT"

# Stage the bundle (menu-bar agent layout), then re-sign with Developer ID.
WINDOWED=0 "$ROOT/scripts/build-app.sh" >/dev/null

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Contents/Info.plist"

# Hardened-runtime Developer ID signature (required for notarization). Sign the nested
# executable first, then the bundle, so the runtime flag/timestamp apply to both.
codesign --force --options runtime --timestamp --sign "$DEVID_APP" "$EXEC"
codesign --force --options runtime --timestamp --sign "$DEVID_APP" "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"
echo "signed: $(codesign -dvv "$APP_DIR" 2>&1 | grep -E 'Authority=Developer ID' | head -1)"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "SKIP_NOTARIZE=1 — Developer ID signed only (not notarized)."
  echo "$APP_DIR"
  exit 0
fi

: "${AC_PROFILE:?set AC_PROFILE to your notarytool keychain profile}"

# Zip, notarize, staple.
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$AC_PROFILE" --wait
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
spctl -a -vvv --type execute "$APP_DIR" 2>&1 | head -3 || true

# Re-zip the stapled app for upload.
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
echo "$ZIP_PATH"

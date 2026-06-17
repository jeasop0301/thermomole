#!/usr/bin/env bash
set -euo pipefail

# Build a Developer ID-signed, notarized, stapled ThermoMole.app + zip for release.
#
# Required environment:
#   DEVID_APP   : "Developer ID Application: NAME (TEAMID)"  (codesign identity)
#   AC_PROFILE  : notarytool keychain profile name created via:
#                 xcrun notarytool store-credentials AC_PROFILE \
#                   --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PW
# Optional:
#   BUNDLE_ID   : default com.jeasop0301.thermomole

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/dist/ThermoMole.app"
ZIP_PATH="$ROOT/dist/ThermoMole.zip"
BUNDLE_ID="${BUNDLE_ID:-com.jeasop0301.thermomole}"
: "${DEVID_APP:?set DEVID_APP to your Developer ID Application identity}"
: "${AC_PROFILE:?set AC_PROFILE to your notarytool keychain profile}"

cd "$ROOT"
swift build -c release

# Stage the bundle (reuse build-app.sh layout, then re-sign with Developer ID).
"$ROOT/scripts/build-app.sh" >/dev/null

# Patch bundle id for distribution.
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Contents/Info.plist"

# Hardened-runtime Developer ID signature (required for notarization).
codesign --force --options runtime --timestamp --sign "$DEVID_APP" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

# Zip, notarize, staple.
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$AC_PROFILE" --wait
xcrun stapler staple "$APP_DIR"

# Re-zip the stapled app for upload.
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
echo "$ZIP_PATH"

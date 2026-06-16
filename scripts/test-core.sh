#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/.build/arm64-apple-macosx/debug/ThermoMolePackageTests.xctest"

cd "$ROOT"
swift build --build-tests --disable-swift-testing

STAGE_ROOT="${TMPDIR:-/tmp}/ThermoMoleTests-$$"
STAGED_BUNDLE="$STAGE_ROOT/ThermoMolePackageTests.xctest"
EXECUTABLE="$STAGED_BUNDLE/Contents/MacOS/ThermoMolePackageTests"
rm -rf "$STAGE_ROOT"
mkdir -p "$STAGE_ROOT"
/usr/bin/ditto "$BUNDLE" "$STAGED_BUNDLE"
xattr -cr "$STAGED_BUNDLE" 2>/dev/null || true
codesign --force --sign - "$EXECUTABLE" >/dev/null
xattr -cr "$STAGED_BUNDLE" 2>/dev/null || true
xcrun xctest "$STAGED_BUNDLE"

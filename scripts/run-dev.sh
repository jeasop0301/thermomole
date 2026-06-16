#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift build
codesign --force --sign - .build/arm64-apple-macosx/debug/ThermoMole >/dev/null
exec .build/arm64-apple-macosx/debug/ThermoMole

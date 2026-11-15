#!/usr/bin/env bash
# Build Sylvra, launch it (optionally with demo data) and capture the main window.
#   scripts/screenshot.sh <name> [extra app arguments…]
# Output: docs/screenshots/<name>.png
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${1:?usage: scripts/screenshot.sh <name> [app args…]}"
shift || true
DERIVED="${SYLVRA_DERIVED_DATA:-$PWD/.build/DerivedData}"
APP="$DERIVED/Build/Products/Debug/Sylvra.app"

xcodebuild -project Sylvra.xcodeproj -scheme Sylvra -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" build CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | grep -v appintents || true

pkill -x Sylvra 2>/dev/null || true
open -n "$APP" --args "$@"

WINDOW_ID=""
for _ in $(seq 1 40); do
  WINDOW_ID=$(swift scripts/window-id.swift Sylvra 2>/dev/null | head -1 || true)
  [ -n "$WINDOW_ID" ] && break
  /bin/sleep 0.25
done
[ -n "$WINDOW_ID" ] || { echo "Sylvra window not found" >&2; exit 1; }
/bin/sleep "${SYLVRA_SCREENSHOT_DELAY:-2}"

mkdir -p docs/screenshots
screencapture -x -o -l "$WINDOW_ID" "docs/screenshots/$NAME.png"
pkill -x Sylvra 2>/dev/null || true
echo "docs/screenshots/$NAME.png"

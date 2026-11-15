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

# Compile the window lookup once (running `swift script.swift` in a loop is slow and CPU heavy).
WINDOW_ID_TOOL=".build/window-id"
[ "$WINDOW_ID_TOOL" -nt scripts/window-id.swift ] || swiftc -O -o "$WINDOW_ID_TOOL" scripts/window-id.swift

# Windows are only created on an awake display: wake it and keep it on for the capture only.
caffeinate -d -u -t 45 &
CAFFEINATE_PID=$!
trap 'kill $CAFFEINATE_PID 2>/dev/null || true' EXIT
/bin/sleep 2

# The window occasionally does not appear on the first launch — retry a few times.
WINDOW_ID=""
for attempt in 1 2 3; do
  pkill -x Sylvra 2>/dev/null || true
  /bin/sleep 1
  open -n "$APP" --args -ApplePersistenceIgnoreState YES "$@"
  for _ in $(seq 1 20); do
    /bin/sleep 0.5
    WINDOW_ID=$("$WINDOW_ID_TOOL" Sylvra 2>/dev/null | head -1 || true)
    [ -n "$WINDOW_ID" ] && break
  done
  [ -n "$WINDOW_ID" ] && break
  echo "Window not found (attempt $attempt), retrying…" >&2
done
[ -n "$WINDOW_ID" ] || { echo "Sylvra window not found — is the Mac locked? Window screenshots need an unlocked screen." >&2; exit 1; }
/bin/sleep "${SYLVRA_SCREENSHOT_DELAY:-2}"

mkdir -p docs/screenshots
screencapture -x -o -l "$WINDOW_ID" "docs/screenshots/$NAME.png"
pkill -x Sylvra 2>/dev/null || true
echo "docs/screenshots/$NAME.png"

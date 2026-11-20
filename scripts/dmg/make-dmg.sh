#!/usr/bin/env bash
# Builds the styled installer DMG: violet background with a golden vein arrow, the app on the left, Applications on
# the right, Sylvra's icon as the volume icon. Uses dmgbuild (pinned, in a venv under .build), which writes the
# Finder layout directly — no Finder automation, nothing pops up.
#
#   scripts/dmg/make-dmg.sh <Sylvra.app> <out.dmg> <volume name>
set -euo pipefail
APP="$1"
DMG="$2"
VOLNAME="$3"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
VENV="$ROOT/.build/dmg-venv"
DMGBUILD_VERSION="1.6.5"

if [[ ! -x "$VENV/bin/dmgbuild" ]] || ! "$VENV/bin/pip" show dmgbuild 2>/dev/null | grep -q "^Version: ${DMGBUILD_VERSION}$"; then
  echo "▸ Installing dmgbuild ${DMGBUILD_VERSION}…"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --disable-pip-version-check "dmgbuild==${DMGBUILD_VERSION}"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "▸ Rendering the DMG background…"
swift "$HERE/make-background.swift" "$ROOT/assets/AppIcon-preview.png" "$WORK"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" \
  >/dev/null 2>&1

DEFINES=(-D "app=$APP" -D "background=$WORK/background.tiff")
ICNS="$APP/Contents/Resources/AppIcon.icns"
if [[ -f "$ICNS" ]]; then DEFINES+=(-D "volume_icon=$ICNS"); fi

echo "▸ Building the DMG…"
rm -f "$DMG"
"$VENV/bin/dmgbuild" -s "$HERE/settings.py" "${DEFINES[@]}" "$VOLNAME" "$DMG" >/dev/null

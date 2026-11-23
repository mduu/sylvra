#!/usr/bin/env bash
# Builds a signed, notarized Sylvra.dmg for installing on other Macs (Developer ID, outside the App Store).
#
#   scripts/release.sh                 # archive, sign, notarize, staple → .build/release/Sylvra-<version>.dmg
#   SKIP_NOTARIZE=1 scripts/release.sh # signed only (other Macs: right-click → Open the first time)
#
# One-time setup for notarization (stores an app-specific password in the Keychain):
#   xcrun notarytool store-credentials sylvra-notary --apple-id <apple-id> --team-id UYT5K989XD
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="UYT5K989XD"
PROFILE="${NOTARY_PROFILE:-sylvra-notary}"
OUT=".build/release"
ARCHIVE="$OUT/Sylvra.xcarchive"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "▸ Archiving (Release)…"
xcodebuild -project Sylvra.xcodeproj -scheme Sylvra -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" archive -quiet

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

echo "▸ Exporting with Developer ID…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -quiet
APP="$OUT/export/Sylvra.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
DMG="$OUT/Sylvra-$VERSION.dmg"

# The `sylvra` command line tool (local AI reviews, used by the Claude Code skill) ships in Contents/Helpers —
# not Contents/MacOS, where `sylvra` would replace the app's `Sylvra` binary on a case-insensitive volume.
# It is signed like the app (Developer ID, hardened runtime); the app is re-signed to seal it, keeping its
# entitlements, flags and designated requirement.
echo "▸ Adding the command line tool…"
swift build --package-path Packages/SylvraKit -c release --product sylvra --arch arm64 -q
TOOL="$(swift build --package-path Packages/SylvraKit -c release --product sylvra --arch arm64 --show-bin-path)/sylvra"
mkdir -p "$APP/Contents/Helpers"
cp "$TOOL" "$APP/Contents/Helpers/sylvra"
codesign --force --sign "Developer ID Application" --options runtime --timestamp "$APP/Contents/Helpers/sylvra"
codesign --force --sign "Developer ID Application" --options runtime --timestamp \
  --preserve-metadata=entitlements,requirements,flags "$APP"

codesign --verify --deep --strict "$APP"
echo "▸ Signed: $(codesign -dvv "$APP" 2>&1 | grep '^Authority=' | head -1)"

echo "▸ Creating DMG…"
scripts/dmg/make-dmg.sh "$APP" "$DMG" "Sylvra $VERSION"
codesign --sign "Developer ID Application" --timestamp "$DMG"

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  echo "⚠️  Not notarized (SKIP_NOTARIZE=1). On other Macs: right-click Sylvra → Open the first time."
else
  echo "▸ Notarizing (a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
fi

echo "✅ $DMG  (version $VERSION, build $BUILD)"

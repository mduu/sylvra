#!/usr/bin/env bash
# Build the app and run all package tests.
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --package-path Packages/SylvraKit
xcodebuild -project Sylvra.xcodeproj -scheme Sylvra -destination 'platform=macOS' -skipPackagePluginValidation build CODE_SIGNING_ALLOWED=NO -quiet
echo "✅ Build and tests passed"

#!/usr/bin/env bash
# Lint: SwiftLint (rules) + swift format (formatting check).
set -euo pipefail
cd "$(dirname "$0")/.."

PATHS=(App Packages/SylvraKit/Sources Packages/SylvraKit/Tests)

if command -v swiftlint >/dev/null 2>&1; then
  swiftlint lint --strict --quiet
else
  echo "⚠️  swiftlint not installed — skipping (brew install swiftlint)" >&2
fi

swift format lint --strict --recursive "${PATHS[@]}" Packages/SylvraKit/Package.swift
echo "✅ Lint passed"

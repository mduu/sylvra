#!/usr/bin/env bash
# Format all Swift sources in place with swift format.
set -euo pipefail
cd "$(dirname "$0")/.."
swift format format --in-place --recursive App Packages/SylvraKit/Sources Packages/SylvraKit/Tests Packages/SylvraKit/Package.swift
echo "✅ Formatted"

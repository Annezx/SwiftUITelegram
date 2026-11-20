#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f "Config/Secrets.xcconfig" ]; then
  cp "Config/Secrets.xcconfig.example" "Config/Secrets.xcconfig"
  echo "Created Config/Secrets.xcconfig from template."
  echo "Tip: You can fill TELEGRAM_API_ID & TELEGRAM_API_HASH there, or enter them inside the app on first launch."
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is not installed."
  echo "Install it via Homebrew: brew install xcodegen"
  echo "Or open Package.swift directly in Xcode 16+."
  exit 1
fi

xcodegen generate
echo "Generated SwiftUITelegram.xcodeproj successfully."
echo "Run: open SwiftUITelegram.xcodeproj"

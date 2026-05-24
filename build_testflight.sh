#!/bin/bash
# build_testflight.sh — Build Cultioo App IPA for TestFlight
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "📦 Cultioo App — TestFlight Build"
echo "================================="

echo "→ flutter clean..."
flutter clean

echo "→ flutter pub get..."
flutter pub get

echo "→ pod install..."
(cd ios && pod install --repo-update)

echo "→ flutter build ipa..."
flutter build ipa \
  --release \
  --export-options-plist=ios/ExportOptions.plist

IPA_PATH="build/ios/ipa"
echo ""
echo "✅ Build complete!"
echo "📁 IPA location: $SCRIPT_DIR/$IPA_PATH"
echo ""
echo "Next step: Upload via Transporter or xcrun altool:"
echo "  xcrun altool --upload-app -f \"$SCRIPT_DIR/$IPA_PATH/*.ipa\" --type ios --apiKey <KEY> --apiIssuer <ISSUER>"
echo "  — or drag the IPA into Apple Transporter (Mac App Store)"

#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
# Cultioo – macOS Release Build Script
# Builds: macOS → .dmg with proper app name and icon
# ─────────────────────────────────────────────────────────────────────────────

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$APP_DIR/dist"
APP_NAME="cultioo"
BUNDLE_NAME="Cultioo"

# Read version from pubspec.yaml
VERSION=$(grep '^version:' "$APP_DIR/pubspec.yaml" | sed 's/version: //' | sed 's/+.*//' | tr -d ' ')
echo "▶ Version: $VERSION"
echo "▶ Platform: macOS"

mkdir -p "$OUT_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# Build macOS .app
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building macOS .app …"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$APP_DIR"
flutter build macos --release

APP_PATH="$APP_DIR/build/macos/Build/Products/Release/$BUNDLE_NAME.app"

if [ ! -d "$APP_PATH" ]; then
  echo "✗ macOS build failed – .app not found at: $APP_PATH"
  exit 1
fi

echo ""
echo "  Creating DMG …"

DMG_TMP="$OUT_DIR/tmp_dmg"
DMG_OUT="$OUT_DIR/${APP_NAME}_${VERSION}_macos.dmg"

rm -rf "$DMG_TMP"
mkdir -p "$DMG_TMP"
cp -R "$APP_PATH" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"

hdiutil create \
  -volname "$BUNDLE_NAME" \
  -srcfolder "$DMG_TMP" \
  -ov \
  -format UDZO \
  "$DMG_OUT"

rm -rf "$DMG_TMP"
echo "✓ DMG created: $DMG_OUT"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Done!"
echo "  macOS DMG: $DMG_OUT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

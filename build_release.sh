#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
# Cultioo – Release Build Script
# Builds:  macOS → .dmg   (locally on this Mac)
#          Windows → .exe  (triggered via GitHub Actions)
# ─────────────────────────────────────────────────────────────────────────────

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$APP_DIR/dist"
APP_NAME="cultioo"
BUNDLE_NAME="Cultioo"

# Read version from pubspec.yaml
VERSION=$(grep '^version:' "$APP_DIR/pubspec.yaml" | sed 's/version: //' | sed 's/+.*//' | tr -d ' ')
echo "▶ Version: $VERSION"

mkdir -p "$OUT_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# 1. macOS → DMG
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
# 2. Windows → trigger GitHub Actions (builds .exe installer)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Triggering Windows EXE build via GitHub Actions …"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if command -v gh &>/dev/null; then
  cd "$APP_DIR"
  # Check if inside a git repo with a remote
  if git remote get-url origin &>/dev/null; then
    gh workflow run build_desktop.yml
    echo "✓ GitHub Actions workflow triggered."
    echo "  → Download the Windows installer from:"
    REPO=$(git remote get-url origin | sed 's/.*github.com[:/]//' | sed 's/\.git$//')
    echo "    https://github.com/$REPO/actions"
  else
    echo "⚠ No git remote found. Push the repo to GitHub first."
  fi
else
  echo "⚠ GitHub CLI (gh) not installed."
  echo "  → Push to GitHub and the Windows EXE will be built automatically via Actions."
  echo "  → Or install gh: brew install gh"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Done!"
echo "  macOS DMG : $DMG_OUT"
echo "  Windows   : Check GitHub Actions for cultioo_setup.exe"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

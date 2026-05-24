#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
# Cultioo – Linux Release Build Script
# Builds: Linux AppImage and .deb package
# ─────────────────────────────────────────────────────────────────────────────

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="cultioo"

# Read version from pubspec.yaml
VERSION=$(grep '^version:' "$APP_DIR/pubspec.yaml" | sed 's/version: //' | sed 's/+.*//' | tr -d ' ')
echo "▶ Version: $VERSION"
echo "▶ Platform: Linux"

# ─────────────────────────────────────────────────────────────────────────────
# Build Linux AppImage locally
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building Linux AppImage …"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$APP_DIR"

# Check if we're on Linux
if [[ "$OSTYPE" != "linux"* ]]; then
  echo ""
  echo "⚠ This script must be run on Linux to build the AppImage."
  echo ""
  echo "Alternative: Trigger GitHub Actions build"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if command -v gh &>/dev/null; then
    if git remote get-url origin &>/dev/null; then
      echo "  Triggering Linux build via GitHub Actions …"
      gh workflow run build_linux.yml
      echo "✓ GitHub Actions workflow triggered."
      echo ""
      echo "  → Download the Linux installer from:"
      REPO=$(git remote get-url origin | sed 's/.*github.com[:/]//' | sed 's/\.git$//')
      echo "    https://github.com/$REPO/actions"
      echo ""
      echo "  The installer will be named: cultioo-$VERSION-x86_64.AppImage"
    else
      echo "⚠ No git remote found. Push the repo to GitHub first."
      exit 1
    fi
  else
    echo "⚠ GitHub CLI (gh) not installed."
    echo "  → Install with: sudo apt install gh (or brew install gh on macOS)"
    echo "  → Then authenticate: gh auth login"
    exit 1
  fi
else
  # We're on Linux - build locally
  echo "  Building Flutter Linux release …"
  flutter build linux --release
  
  RELEASE_BUILD="$APP_DIR/build/linux/x64/release/bundle"
  if [ ! -d "$RELEASE_BUILD" ]; then
    echo "✗ Linux build failed"
    exit 1
  fi
  
  echo ""
  echo "  ✓ Linux build complete"
  echo "  Release bundle: $RELEASE_BUILD"
  echo ""
  echo "  To create an AppImage, install linuxdeploy:"
  echo "  → wget https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
  echo "  → chmod +x linuxdeploy-x86_64.AppImage"
  echo ""
  echo "  Then run:"
  echo "  → ./linuxdeploy-x86_64.AppImage --appdir=AppDir --executable=$RELEASE_BUILD/cultioo --output=appimage"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Done!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

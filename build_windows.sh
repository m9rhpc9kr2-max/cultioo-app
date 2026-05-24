#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
# Cultioo – Windows Release Build Script
# Builds: Windows .exe installer ONLY (no macOS, no Web)
# ─────────────────────────────────────────────────────────────────────────────

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="cultioo"

# Read version from pubspec.yaml
VERSION=$(grep '^version:' "$APP_DIR/pubspec.yaml" | sed 's/version: //' | sed 's/+.*//' | tr -d ' ')
echo "▶ Version: $VERSION"
echo "▶ Platform: Windows"

# ─────────────────────────────────────────────────────────────────────────────
# Build Windows EXE locally
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building Windows EXE …"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$APP_DIR"

# Check if we're on Windows
if [[ "$OSTYPE" != "msys" && "$OSTYPE" != "win32" && "$OSTYPE" != "cygwin" ]]; then
  echo ""
  echo "⚠ This script must be run on Windows to build the EXE."
  echo ""
  echo "Alternative: Trigger GitHub Actions build"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if command -v gh &>/dev/null; then
    if git remote get-url origin &>/dev/null; then
      echo "  Triggering Windows EXE build via GitHub Actions …"
      gh workflow run build_desktop.yml
      echo "✓ GitHub Actions workflow triggered."
      echo ""
      echo "  → Download the Windows installer from:"
      REPO=$(git remote get-url origin | sed 's/.*github.com[:/]//' | sed 's/\.git$//')
      echo "    https://github.com/$REPO/actions"
      echo ""
      echo "  The installer will be named: cultioo_setup.exe"
    else
      echo "⚠ No git remote found. Push the repo to GitHub first."
      exit 1
    fi
  else
    echo "⚠ GitHub CLI (gh) not installed."
    echo "  → Install with: brew install gh"
    echo "  → Then authenticate: gh auth login"
    exit 1
  fi
else
  # We're on Windows - build locally
  flutter build windows --release
  
  RELEASE_BUILD="$APP_DIR/build/windows/x64/runner/Release"
  if [ ! -d "$RELEASE_BUILD" ]; then
    echo "✗ Windows build failed"
    exit 1
  fi
  
  echo ""
  echo "  Creating EXE installer with Inno Setup …"
  
  # Copy files for Inno Setup
  if [ -d "windows/installer/release_build" ]; then
    rm -rf "windows/installer/release_build"
  fi
  mkdir -p "windows/installer/release_build"
  cp -R "$RELEASE_BUILD"/* "windows/installer/release_build/"
  
  # Build installer (requires Inno Setup on Windows)
  # This would need to be run on Windows with Inno Setup installed
  echo "⚠ Note: Inno Setup installer build requires Windows with Inno Setup installed."
  echo "  For now, the release build is ready at: $RELEASE_BUILD"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Done!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

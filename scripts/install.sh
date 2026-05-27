#!/usr/bin/env bash
set -euo pipefail

REPO="rayjohnson/mcp-inator"
APP_NAME="mcp-inator"
INSTALL_DIR="/Applications"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Error: mcp-inator requires macOS." >&2
  exit 1
fi

echo "Fetching latest release..."
VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')

if [[ -z "$VERSION" ]]; then
  echo "Error: could not determine latest version." >&2
  exit 1
fi

echo "Installing mcp-inator ${VERSION}..."

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${DMG_NAME}"
TMP_DIR=$(mktemp -d)
DMG_PATH="${TMP_DIR}/${DMG_NAME}"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "Downloading ${DMG_NAME}..."
curl -fsSL --progress-bar "$DOWNLOAD_URL" -o "$DMG_PATH"

echo "Mounting disk image..."
MOUNT_POINT=$(hdiutil attach "$DMG_PATH" -nobrowse -noautoopen \
  | awk '/\/Volumes\//{print $NF}')

if [[ -z "$MOUNT_POINT" ]]; then
  echo "Error: failed to mount disk image." >&2
  exit 1
fi

if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
  echo "Quitting running instance..."
  pkill -x "$APP_NAME" || true
  sleep 1
fi

echo "Copying to ${INSTALL_DIR}..."
cp -R "${MOUNT_POINT}/${APP_NAME}.app" "${INSTALL_DIR}/"

xattr -dr com.apple.quarantine "${INSTALL_DIR}/${APP_NAME}.app" 2>/dev/null || true

hdiutil detach "$MOUNT_POINT" -quiet

echo ""
echo "mcp-inator ${VERSION} installed to ${INSTALL_DIR}/${APP_NAME}.app"
echo "Launch it from Spotlight or Finder. Future updates are delivered in-app."

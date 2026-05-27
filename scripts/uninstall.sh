#!/usr/bin/env bash
set -euo pipefail

APP_NAME="mcp-inator"
BUNDLE_ID="io.moov.mcp-inator"
INSTALL_DIR="/Applications"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Error: This script is for macOS only." >&2
  exit 1
fi

echo "Uninstalling ${APP_NAME}..."

if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
  echo "Quitting ${APP_NAME}..."
  pkill -x "$APP_NAME" || true
  sleep 1
fi

REMOVED=0

if [[ -d "${INSTALL_DIR}/${APP_NAME}.app" ]]; then
  echo "Removing ${INSTALL_DIR}/${APP_NAME}.app..."
  rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
  REMOVED=$((REMOVED + 1))
fi

APP_SUPPORT="${HOME}/Library/Application Support/${APP_NAME}"
if [[ -d "$APP_SUPPORT" ]]; then
  echo "Removing application data..."
  rm -rf "$APP_SUPPORT"
  REMOVED=$((REMOVED + 1))
fi

PREFS="${HOME}/Library/Preferences/${BUNDLE_ID}.plist"
if [[ -f "$PREFS" ]]; then
  echo "Removing preferences..."
  rm -f "$PREFS"
  REMOVED=$((REMOVED + 1))
fi

CACHE="${HOME}/Library/Caches/${BUNDLE_ID}"
if [[ -d "$CACHE" ]]; then
  echo "Removing caches..."
  rm -rf "$CACHE"
  REMOVED=$((REMOVED + 1))
fi

if [[ $REMOVED -eq 0 ]]; then
  echo "Nothing to remove — ${APP_NAME} does not appear to be installed."
else
  echo ""
  echo "${APP_NAME} has been removed."
  echo "Note: your agent configurations (Claude, Gemini, etc.) are unchanged."
fi

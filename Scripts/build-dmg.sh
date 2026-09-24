#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DIST_DIR="${DIST_DIR:-$ROOT/dist}"
APP_NAME="TouchingBar"
APP_DIR="${APP_DIR:-$DIST_DIR/$APP_NAME.app}"
DMG_PATH="${DMG_PATH:-$DIST_DIR/$APP_NAME.dmg}"
VOLUME_NAME="${VOLUME_NAME:-$APP_NAME}"

if [ ! -d "$APP_DIR" ]; then
    echo "App bundle not found: $APP_DIR" >&2
    echo "Run Scripts/build-app.sh first." >&2
    exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
    echo "hdiutil is required to build a DMG." >&2
    exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/touchingbar-dmg.XXXXXX")"
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$DIST_DIR" "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

hdiutil verify "$DMG_PATH"

echo "DMG: $DMG_PATH"

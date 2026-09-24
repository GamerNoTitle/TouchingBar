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

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/touchingbar-dmg.XXXXXX")"
STAGING_DIR="$TMP_DIR/staging"
RW_DMG="$TMP_DIR/$APP_NAME-rw.dmg"
MOUNT_DIR=""
MOUNT_DEVICE=""
BACKGROUND_PATH="${DMG_BACKGROUND_PATH:-$ROOT/assets/TouchingBar600.png}"
MOUNTED=0

cleanup() {
    if [ "$MOUNTED" -eq 1 ]; then
        if [ -n "$MOUNT_DEVICE" ]; then
            hdiutil detach "$MOUNT_DEVICE" -force >/dev/null 2>&1 || true
        else
            hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
        fi
    fi
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$DIST_DIR" "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

if [ ! -f "$BACKGROUND_PATH" ]; then
    echo "DMG background not found: $BACKGROUND_PATH" >&2
    echo "Restore assets/TouchingBar600.png or set DMG_BACKGROUND_PATH to a 600x400 image." >&2
    exit 1
fi

if command -v sips >/dev/null 2>&1; then
    BACKGROUND_WIDTH="$(sips -g pixelWidth "$BACKGROUND_PATH" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
    BACKGROUND_HEIGHT="$(sips -g pixelHeight "$BACKGROUND_PATH" 2>/dev/null | awk '/pixelHeight/ { print $2 }')"
    if [ "$BACKGROUND_WIDTH" != "600" ] || [ "$BACKGROUND_HEIGHT" != "400" ]; then
        echo "Warning: DMG background is ${BACKGROUND_WIDTH}x${BACKGROUND_HEIGHT}; expected 600x400." >&2
    fi
fi

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    "$RW_DMG" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUTPUT" | awk -F '\t' '/\/Volumes\// { print $NF; exit }')"
if [ -z "$MOUNT_DIR" ] || [ ! -d "$MOUNT_DIR" ]; then
    echo "Could not determine DMG mount point." >&2
    exit 1
fi
MOUNTED=1

mkdir -p "$MOUNT_DIR/.background"
cp "$BACKGROUND_PATH" "$MOUNT_DIR/.background/background.png"
chflags hidden "$MOUNT_DIR/.background" 2>/dev/null || true
BACKGROUND_POSIX_PATH="$MOUNT_DIR/.background/background.png"
open "$MOUNT_DIR"
sleep 2

# Finder bounds include the title bar. 600x426 outer bounds keeps the
# background content area at the intended 600x400 design canvas.

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {360, 120, 960, 546}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 104
        set text size of theViewOptions to 13
        set background picture of theViewOptions to (POSIX file "$BACKGROUND_POSIX_PATH")
        set position of item "$APP_NAME.app" of container window to {150, 205}
        set position of item "Applications" of container window to {450, 205}
        close container window
        open container window
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT

sync
if [ -n "$MOUNT_DEVICE" ]; then
    hdiutil detach "$MOUNT_DEVICE" -force >/dev/null 2>&1 || true
else
    hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
fi
MOUNTED=0

OUTPUT_BASE="${DMG_PATH%.dmg}"
hdiutil convert "$RW_DMG" -ov -format UDZO -o "$OUTPUT_BASE" >/dev/null
if [ "$OUTPUT_BASE.dmg" != "$DMG_PATH" ]; then
    mv -f "$OUTPUT_BASE.dmg" "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH"
echo "DMG: $DMG_PATH"

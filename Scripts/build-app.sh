#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-release}"
ARCHS="${ARCHS:-$(uname -m)}"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
APP_NAME="TouchingBar"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT/Resources/Info.plist")"

build_arch() {
    local arch="$1"
    local scratch="$ROOT/.build/$arch"
    local triple="${arch}-apple-macosx${DEPLOYMENT_TARGET}"
    swift build \
        --configuration "$CONFIGURATION" \
        --triple "$triple" \
        --scratch-path "$scratch" \
        --product "$APP_NAME"
    swift build \
        --configuration "$CONFIGURATION" \
        --triple "$triple" \
        --scratch-path "$scratch" \
        --product TouchingBarCtl
    local bin_path
    bin_path="$(swift build \
        --configuration "$CONFIGURATION" \
        --triple "$triple" \
        --scratch-path "$scratch" \
        --show-bin-path | tail -n 1)"
    if [ ! -f "$bin_path/$APP_NAME" ]; then
        bin_path="$(dirname "$(find "$scratch" -type f -name "$APP_NAME" -perm -111 -print -quit)")"
    fi
    if [ ! -f "$bin_path/$APP_NAME" ] || [ ! -f "$bin_path/TouchingBarCtl" ]; then
        echo "Could not locate $arch build products under $scratch" >&2
        exit 1
    fi
    echo "$bin_path"
}

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$CONTENTS_DIR/Frameworks"
cp "$ROOT/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

MRA_BUILD_DIR="$(MRA_BUILD_DIR="$ROOT/.build/mediaremote-adapter" "$ROOT/Scripts/build-mediaremote-adapter.sh" "$ARCHS" | tail -n 1)"
cp -R "$MRA_BUILD_DIR/MediaRemoteAdapter.framework" "$CONTENTS_DIR/Frameworks/"
cp "$ROOT/ThirdParty/mediaremote-adapter/bin/mediaremote-adapter.pl" "$RESOURCES_DIR/"

BIN_PATHS=()
CTL_PATHS=()
for arch in $ARCHS; do
    bin_path="$(build_arch "$arch" | tail -n 1)"
    BIN_PATHS+=("$bin_path/$APP_NAME")
    CTL_PATHS+=("$bin_path/TouchingBarCtl")
done

for path in "${BIN_PATHS[@]}" "${CTL_PATHS[@]}"; do
    if [ ! -f "$path" ]; then
        echo "Missing build product: $path" >&2
        exit 1
    fi
done

if [ "${#BIN_PATHS[@]}" -eq 1 ]; then
    cp "${BIN_PATHS[0]}" "$MACOS_DIR/$APP_NAME"
    cp "${CTL_PATHS[0]}" "$MACOS_DIR/TouchingBarCtl"
else
    lipo -create "${BIN_PATHS[@]}" -output "$MACOS_DIR/$APP_NAME"
    lipo -create "${CTL_PATHS[@]}" -output "$MACOS_DIR/TouchingBarCtl"
fi

chmod +x "$MACOS_DIR/$APP_NAME" "$MACOS_DIR/TouchingBarCtl"

if command -v codesign >/dev/null 2>&1; then
    # A stable designated requirement keeps TCC grants (Accessibility,
    # Automation) tied to the bundle identifier instead of a changing CDHash.
    codesign         --force         --deep         --sign -         --identifier "$BUNDLE_ID"         -r="designated => identifier \"$BUNDLE_ID\""         "$APP_DIR"
fi

if command -v ditto >/dev/null 2>&1; then
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$DIST_DIR/$APP_NAME.zip"
fi

echo "Built: $APP_DIR"
if [ -f "$DIST_DIR/$APP_NAME.zip" ]; then
    echo "Archive: $DIST_DIR/$APP_NAME.zip"
fi

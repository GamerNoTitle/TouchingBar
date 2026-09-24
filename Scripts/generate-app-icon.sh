#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:-$ROOT/Resources/AppIcon.icns}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/touchingbar-icon.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/render-icon.swift" <<'SWIFT'
import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("missing output path\n".utf8))
    exit(2)
}

let canvas = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)
image.lockFocus()
guard let context = NSGraphicsContext.current else {
    FileHandle.standardError.write(Data("unable to create drawing context\n".utf8))
    exit(3)
}
context.shouldAntialias = true
context.imageInterpolation = .high

NSColor.clear.setFill()
NSRect(origin: .zero, size: canvas).fill()

let backgroundRect = NSRect(x: 72, y: 72, width: 880, height: 880)
let background = NSBezierPath(roundedRect: backgroundRect, xRadius: 210, yRadius: 210)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor(
    srgbRed: 0,
    green: 123.0 / 255.0,
    blue: 1,
    alpha: 1
).setFill()
background.fill()
NSShadow().set()

let border = NSBezierPath(
    roundedRect: backgroundRect.insetBy(dx: 5, dy: 5),
    xRadius: 205,
    yRadius: 205
)
NSColor.white.withAlphaComponent(0.20).setStroke()
border.lineWidth = 3
border.stroke()

let pointSize = canvas.width * 0.46
let baseConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
let colorConfiguration = NSImage.SymbolConfiguration(paletteColors: [.white])
let configuration = baseConfiguration.applying(colorConfiguration)
guard let symbol = NSImage(
    systemSymbolName: "rectangle.topthird.inset.filled",
    accessibilityDescription: nil
)?.withSymbolConfiguration(configuration) else {
    FileHandle.standardError.write(Data("unable to load app icon symbol\n".utf8))
    exit(4)
}

let symbolSize = symbol.size
let symbolRect = NSRect(
    x: (canvas.width - symbolSize.width) / 2,
    y: (canvas.height - symbolSize.height) / 2 - 12,
    width: symbolSize.width,
    height: symbolSize.height
)
let symbolShadow = NSShadow()
symbolShadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
symbolShadow.shadowBlurRadius = 28
symbolShadow.shadowOffset = NSSize(width: 0, height: -9)
symbolShadow.set()
symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
NSShadow().set()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("unable to encode app icon\n".utf8))
    exit(5)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
SWIFT

swift "$TMP_DIR/render-icon.swift" "$TMP_DIR/icon_1024.png" >/dev/null
SRGB_PROFILE="/System/Library/ColorSync/Profiles/sRGB Profile.icc"
if [ -f "$SRGB_PROFILE" ]; then
    sips -m "$SRGB_PROFILE" "$TMP_DIR/icon_1024.png" >/dev/null
fi
ICONSET="$TMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
sips -z 16 16 "$TMP_DIR/icon_1024.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$TMP_DIR/icon_1024.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$TMP_DIR/icon_1024.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$TMP_DIR/icon_1024.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$TMP_DIR/icon_1024.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$TMP_DIR/icon_1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$TMP_DIR/icon_1024.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$TMP_DIR/icon_1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$TMP_DIR/icon_1024.png" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$TMP_DIR/icon_1024.png" "$ICONSET/icon_512x512@2x.png"

mkdir -p "$(dirname "$OUTPUT")"
iconutil -c icns "$ICONSET" -o "$OUTPUT"
echo "Generated: $OUTPUT"

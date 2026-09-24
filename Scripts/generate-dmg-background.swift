import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "DMGBackground.png"
let size = NSSize(width: 600, height: 400)

let image = NSImage(size: size, flipped: true) { rect in
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.20, alpha: 1),
        NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.31, alpha: 1),
        NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.15, alpha: 1)
    ])
    gradient?.draw(in: rect, angle: 0)

    let glow = NSBezierPath(ovalIn: NSRect(x: 110, y: 100, width: 380, height: 220))
    NSColor(calibratedRed: 0.25, green: 0.50, blue: 1.0, alpha: 0.10).setFill()
    glow.fill()

    let titleStyle = NSMutableParagraphStyle()
    titleStyle.alignment = .center
    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 27, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: titleStyle
    ]
    ("TouchingBar" as NSString).draw(
        in: NSRect(x: 0, y: 34, width: size.width, height: 36),
        withAttributes: titleAttributes
    )

    let subtitleStyle = NSMutableParagraphStyle()
    subtitleStyle.alignment = .center
    let subtitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.66),
        .paragraphStyle: subtitleStyle
    ]
    ("Drag TouchingBar to Applications" as NSString).draw(
        in: NSRect(x: 0, y: 72, width: size.width, height: 22),
        withAttributes: subtitleAttributes
    )

    let arrow = NSBezierPath()
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 232, y: 208))
    arrow.line(to: NSPoint(x: 368, y: 208))
    arrow.move(to: NSPoint(x: 348, y: 188))
    arrow.line(to: NSPoint(x: 368, y: 208))
    arrow.line(to: NSPoint(x: 348, y: 228))
    NSColor(calibratedRed: 0.45, green: 0.67, blue: 1.0, alpha: 0.95).setStroke()
    arrow.stroke()

    let divider = NSBezierPath()
    divider.lineWidth = 1
    divider.move(to: NSPoint(x: 54, y: 294))
    divider.line(to: NSPoint(x: 546, y: 294))
    NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
    divider.stroke()

    return true
}

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render DMG background\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
} catch {
    fputs("Could not write DMG background: \(error.localizedDescription)\n", stderr)
    exit(1)
}

import AppKit

extension NSColor {
    convenience init?(hexRGB value: String) {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6, let number = UInt32(text, radix: 16) else {
            return nil
        }
        self.init(
            red: CGFloat((number >> 16) & 0xFF) / 255.0,
            green: CGFloat((number >> 8) & 0xFF) / 255.0,
            blue: CGFloat(number & 0xFF) / 255.0,
            alpha: 1
        )
    }

    var hexRGB: String {
        guard let color = usingColorSpace(.deviceRGB) else { return "#000000" }
        return String(
            format: "#%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }
}

import SwiftUI

extension Color {
    init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x9B5CFF
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// Rounded, not truncated: Int(0.6078 * 255) = 154 turned #9B5CFF into #9B5BFF on every save.
    var hex: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#9B5CFF" }
        return String(format: "#%02X%02X%02X", lround(c.redComponent * 255), lround(c.greenComponent * 255), lround(c.blueComponent * 255))
    }
}

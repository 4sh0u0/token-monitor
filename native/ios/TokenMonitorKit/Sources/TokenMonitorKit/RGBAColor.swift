import Foundation

/// Colour components parsed from a hex string; SwiftUI's `Color(hex:)` in
/// TokenMonitorUI is built on it. Lives in the core so parsing is tested on
/// every platform.
public struct RGBAColor: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses `#rgb`, `#rrggbb` or `#rrggbbaa` (the `#` is optional).
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        red = Double((rgb >> 16) & 0xff) / 255
        green = Double((rgb >> 8) & 0xff) / 255
        blue = Double(rgb & 0xff) / 255
        alpha = hasAlpha ? Double(value & 0xff) / 255 : 1
    }

    /// The Kit's default vendor colour (`VendorCatalog.defaultColorHex`).
    public static let fallback = RGBAColor(hex: VendorCatalog.defaultColorHex) ?? RGBAColor(red: 106 / 255, green: 180 / 255, blue: 240 / 255)
}

#if canImport(SwiftUI)
import SwiftUI
import TokenMonitorKit

extension Color {
    /// `#rgb`, `#rrggbb` or `#rrggbbaa`; invalid input paints the default
    /// vendor colour rather than black, so a bad value stays visible.
    public init(hex: String, opacity: Double = 1) {
        let rgba = RGBAColor(hex: hex) ?? .fallback
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha * opacity)
    }

    /// A vendor paint on Token Monitor's dark surfaces: near-black marks use
    /// the light ink.
    public init(paint: VendorPaint) {
        switch paint {
        case .ink: self = TMTheme.ink
        case .hex(let hex): self.init(hex: hex)
        }
    }
}

/// Token Monitor's dark blue-black palette, shared with the desktop widget
/// (`src/electron/renderer/styles.css`) and the macOS widget
/// (`native/macos/TokenMonitorWidget`). Surfaces are designed dark-first: use
/// `TMBackground` behind them, including in light mode.
public enum TMTheme {
    /// The widget base (macOS `WidgetBackground`).
    public static let background = Color(.sRGB, red: 0.035, green: 0.043, blue: 0.055, opacity: 1)
    /// Cards and grouped rows on `background`.
    public static let card = Color.white.opacity(0.05)
    public static let cardStroke = Color.white.opacity(0.08)
    public static let divider = Color.white.opacity(0.14)
    /// Meter and bar tracks.
    public static let track = Color.white.opacity(0.07)

    public static let text = Color(hex: "#eef5fb")
    /// Headline figures.
    public static let number = Color(hex: "#f3fbf7")
    /// Secondary text, stale data.
    public static let muted = Color(hex: "#a3adbb")
    /// The light ink near-black vendor marks are drawn with.
    public static let ink = Color.white.opacity(0.86)

    /// The desktop's mint accent (`--accent`).
    public static let accent = Color(hex: "#b7ead4")
    /// Trend lines (`--chart-color`).
    public static let chartBlue = Color(hex: "#73bdf5")
    /// Bars (`--chart-bar`).
    public static let chartBar = Color(hex: "#6ab4f0")

    public static let success = Color(hex: "#b7ead4")
    public static let warning = Color(hex: "#f1d973")
    public static let caution = Color(hex: "#f4a073")
    public static let critical = Color(hex: "#f47788")
    public static let purple = Color(hex: "#b394f4")

    /// Activity heat levels 0...4 (`--chart-heat-*`).
    public static func heat(_ level: Int) -> Color {
        switch max(0, min(4, level)) {
        case 0: return Color.white.opacity(0.03)
        case 1: return Color(.sRGB, red: 90 / 255, green: 170 / 255, blue: 1, opacity: 0.18)
        case 2: return Color(.sRGB, red: 120 / 255, green: 190 / 255, blue: 1, opacity: 0.45)
        case 3: return Color(.sRGB, red: 150 / 255, green: 210 / 255, blue: 1, opacity: 0.8)
        default: return Color(.sRGB, red: 180 / 255, green: 230 / 255, blue: 1, opacity: 1)
        }
    }

    /// A meter tint from how much is left (0...1): calm while there is room,
    /// amber under a quarter, red under a tenth; muted when unknown.
    public static func quotaColor(remainingFraction: Double?) -> Color {
        guard let remainingFraction else { return muted }
        if remainingFraction < 0.1 { return critical }
        if remainingFraction < 0.25 { return caution }
        return success
    }

    public static func statusColor(_ category: LimitStatusCategory) -> Color {
        switch category {
        case .available: return success
        case .needsSignIn: return caution
        case .rateLimited: return warning
        case .unavailable: return critical
        case .inactive: return muted
        }
    }
}

/// The widget/app background: the base colour with the macOS widget's faint
/// diagonal glow.
public struct TMBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            TMTheme.background
            LinearGradient(
                colors: [Color.white.opacity(0.025), TMTheme.chartBlue.opacity(0.13)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
    }
}

/// Vendor colours for SwiftUI (see `VendorCatalog`).
public enum VendorColor {
    /// A client, model vendor or limits provider mark on dark surfaces.
    public static func color(for id: String?) -> Color {
        Color(paint: VendorCatalog.paint(for: id))
    }

    /// A model row: its vendor's colour, or a stable fallback colour.
    public static func model(_ name: String) -> Color {
        Color(paint: VendorCatalog.modelPaint(for: name))
    }

    /// The unmodified brand colour (light surfaces, settings swatches).
    public static func brand(for id: String?) -> Color {
        Color(hex: VendorCatalog.brandColorHex(for: id))
    }
}

extension UsageShare {
    public var color: Color { Color(paint: paint) }
}

extension LimitProvider {
    public var color: Color { VendorColor.color(for: provider) }
}
#endif

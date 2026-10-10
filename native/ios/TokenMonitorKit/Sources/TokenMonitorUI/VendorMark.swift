#if canImport(SwiftUI)
import SwiftUI
import TokenMonitorKit

/// What a row's leading mark stands for. The cases follow the desktop's row
/// kinds (`app.js` `iconKindFor`), which decide between an icon and a dot.
public enum VendorMarkSubject: Hashable, Sendable {
    /// A tracked client, also a session's client.
    case client(String)
    /// A model row. `source` is the model's attribution source; it only
    /// matters for the `"unknown"` row, which draws Codex's mark when Codex is
    /// the source (`UsagePeriod`'s unknown-model source) and a dot otherwise.
    case model(String, source: String? = nil)
    /// A limits provider (or a limits account's mark id).
    case provider(String)
    /// A device, by platform family (`VendorCatalog.osIconAssetNames`).
    case device(DevicePlatformFamily)
    /// A device by its OS mark asset, as resolved from the raw platform
    /// string (`DevicePresentation.osIconAssetName(platform:)`, which also maps
    /// FreeBSD/OpenBSD to the Linux mark); nil draws a dot.
    case operatingSystem(iconAssetName: String?)
    /// A project row.
    case project
    /// Token Monitor's own Σ mark (totals, models with no vendor).
    case tokenMonitor
}

/// What a mark draws.
public enum VendorMarkGlyph: Hashable, Sendable {
    /// A template image from the target's own `VendorIcons.xcassets`.
    case asset(String)
    /// An SF Symbol (the desktop's Σ is `sum`).
    case symbol(String)
    /// A filled circle in the subject's colour.
    case dot
}

extension VendorMarkSubject {
    /// The SF Symbol standing in for the desktop's Σ (token-monitor.svg is a
    /// text glyph, so it has no asset).
    public static let sumSymbolName = "sum"

    /// The glyph this subject draws while tool icons are on.
    ///
    /// - Parameter context: `.limits` on the Limits page, where a few
    ///   providers draw other artwork (grok draws grok.svg rather than xAI's
    ///   mark). Providers draw an icon for every known mark in either context,
    ///   as the desktop's `limitMarksWithIcon`.
    public func glyph(context: VendorIconContext = .usage) -> VendorMarkGlyph {
        switch self {
        case .client(let id):
            return VendorCatalog.iconAssetName(for: id, context: context).map(VendorMarkGlyph.asset) ?? .dot
        case .model(let name, let source):
            if name == "unknown" {
                guard source == "codex", let asset = VendorCatalog.iconAssetName(for: "codex") else { return .dot }
                return .asset(asset)
            }
            if let vendor = VendorCatalog.modelVendor(for: name),
               let asset = VendorCatalog.iconAssetName(for: vendor, context: .usage) {
                return .asset(asset)
            }
            return .symbol(Self.sumSymbolName)
        case .provider(let id):
            // The Home limits module asks for the usage artwork (grok as xAI)
            // but still draws the relays and Factory that have no colour.
            let asset = VendorCatalog.iconAssetName(for: id, context: context)
                ?? VendorCatalog.iconAssetName(for: id, context: .limits)
            return asset.map(VendorMarkGlyph.asset) ?? .dot
        case .device(let family):
            return VendorCatalog.osIconAssetNames[family].map(VendorMarkGlyph.asset) ?? .dot
        case .operatingSystem(let asset):
            return asset.map(VendorMarkGlyph.asset) ?? .dot
        case .project:
            return .asset(VendorCatalog.projectIconAssetName)
        case .tokenMonitor:
            return .symbol(Self.sumSymbolName)
        }
    }

    /// The colour of this subject's dot (tool icons off, or no icon), with
    /// the user's vendor-colour overrides applied.
    public func dotColor(palette: VendorPalette, muted: Bool = false) -> Color {
        switch self {
        case .client(let id), .provider(let id):
            return VendorColor.color(for: id, palette: palette)
        case .model(let name, _):
            return VendorColor.model(name, palette: palette)
        case .device, .operatingSystem, .project, .tokenMonitor:
            return muted ? TMTheme.staleMuted : TMTheme.deviceAccent
        }
    }
}

/// A row's leading mark: the vendor/OS/project icon from the target's asset
/// catalog, tinted with the text colour, or a dot in the vendor colour.
///
/// Icons follow the `showToolIcons` preference from `tmPresentation` unless
/// `showsIcon` says otherwise; the Limits page (`context: .limits`) always
/// draws them. The mark always occupies a `size` square, so rows line up
/// whichever way it draws. It is decorative (hidden from accessibility).
public struct VendorMark: View {
    @Environment(\.tmPresentation) private var presentation

    private let subject: VendorMarkSubject
    private let size: CGFloat
    private let showsIcon: Bool?
    private let context: VendorIconContext
    private let muted: Bool
    private let dotColor: Color?
    private let hidesWhenIconsOff: Bool

    /// - Parameters:
    ///   - size: the side of the square the mark occupies; a dot is 70 % of it.
    ///   - showsIcon: forces icons on or off; nil follows the preference (and
    ///     `.limits` context, which always draws icons).
    ///   - context: `.limits` on the Limits page (grok's own artwork).
    ///   - muted: a stale row (dimmed; devices use the stale grey dot).
    ///   - dotColor: overrides the dot colour (e.g. a project's dominant tool).
    ///   - hidesWhenIconsOff: draws nothing at all when icons are off
    ///     (subscription and status rows), instead of a dot.
    public init(
        _ subject: VendorMarkSubject,
        size: CGFloat = 12,
        showsIcon: Bool? = nil,
        context: VendorIconContext = .usage,
        muted: Bool = false,
        dotColor: Color? = nil,
        hidesWhenIconsOff: Bool = false
    ) {
        self.subject = subject
        self.size = size
        self.showsIcon = showsIcon
        self.context = context
        self.muted = muted
        self.dotColor = dotColor
        self.hidesWhenIconsOff = hidesWhenIconsOff
    }

    /// Whether marks draw icons under `presentation` for `context`.
    public static func iconsEnabled(in presentation: PresentationContext, context: VendorIconContext = .usage) -> Bool {
        context == .limits || presentation.preferences.showToolIcons
    }

    private var resolvedGlyph: VendorMarkGlyph? {
        let iconsOn = showsIcon ?? Self.iconsEnabled(in: presentation, context: context)
        if iconsOn { return subject.glyph(context: context) }
        return hidesWhenIconsOff ? nil : .dot
    }

    public var body: some View {
        if let glyph = resolvedGlyph {
            glyphView(glyph)
                .frame(width: size, height: size)
                .opacity(muted ? 0.55 : 1)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func glyphView(_ glyph: VendorMarkGlyph) -> some View {
        switch glyph {
        case .asset(let name):
            // Not every artwork is square; fitting it reproduces the desktop's
            // `mask-size: contain`.
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(TMTheme.iconTint)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.85, weight: .semibold))
                .foregroundStyle(TMTheme.iconTint)
        case .dot:
            Circle()
                .fill(dotColor ?? subject.dotColor(palette: presentation.palette, muted: muted))
                .frame(width: size * 0.7, height: size * 0.7)
        }
    }
}
#endif

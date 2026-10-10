import Foundation

/// How a vendor mark is painted on Token Monitor's dark surfaces.
///
/// Near-black brand colours (Cursor, OpenCode, Copilot, …) would vanish on the
/// dark widget background, so the shared presentation table marks them as
/// `ink`: draw them in the adaptive light ink (`TMTheme.ink`) instead.
public enum VendorPaint: Sendable, Hashable {
    case hex(String)
    case ink
}

/// Which of the desktop's two mark tables an icon comes from.
public enum VendorIconContext: Sendable, Hashable {
    /// Usage rows (tools, model vendors, sessions, Overview modules, widget and
    /// watch tool rows). Only marks with a brand colour carry an icon, as the
    /// desktop's `clientsWithIcon`; the rest draw a dot.
    case usage
    /// AI Tool Limits rows. Every mark carries an icon, and a few providers
    /// draw other artwork there (grok draws grok.svg, while its usage rows
    /// share xAI's mark).
    case limits
}

/// Labels, colours, icon asset names and the model→vendor resolver shared with
/// the desktop app.
///
/// The data lives in `VendorCatalog+Generated.swift`, written by
/// `npm run sync:ios-vendors` from `src/shared/vendorPresentation.js`,
/// `src/shared/clientCatalog.js`, `src/shared/limits/providers.js`,
/// `modelVendorFor()` and the mask rules in `styles.css`; never edit that file
/// by hand. The same command writes the artwork into `VendorIcons.xcassets` in
/// the app, widget and watch targets as template images.
///
/// A *mark id* is a tracked client (`claude`), a model vendor (`gemini`) or a
/// limits provider (`openrouter`): the three domains share one string and one
/// mark, exactly as on the desktop.
public enum VendorCatalog {
    public struct Mark: Sendable, Equatable {
        public let id: String
        /// Display name when the shared tables name this id.
        public let label: String?
        /// Brand colour as `#rrggbb`, nil for marks without a colour of their own.
        public let brandColorHex: String?
        /// The colour to paint on dark surfaces (`widgetColor` or the brand
        /// colour), nil when the mark uses the light ink.
        public let widgetColorHex: String?
        public let usesInk: Bool
    }

    public struct LimitProviderInfo: Sendable, Equatable {
        public let id: String
        /// The name a live quota row shows ("Claude").
        public let label: String
        /// The name used where the provider is a tool you configure or pay for
        /// ("Claude Code").
        public let settingsLabel: String
    }

    struct ModelVendorRule {
        let pattern: String
        let vendorID: String
    }

    /// What an id with no mark, or an unrecognised model, is painted with.
    public static let defaultColorHex: String = generatedDefaultColorHex

    /// Every mark, in the desktop appearance picker's order.
    public static let marks: [Mark] = generatedMarks

    /// AI Tool Limits providers in the desktop's default display order.
    public static let limitProviders: [LimitProviderInfo] = generatedLimitProviders

    /// Tracked-client ids in the desktop catalog's order.
    public static let trackedClientIDs: [String] = generatedTrackedClientIDs

    /// The asset-catalog image of each device platform's mark, as the desktop's
    /// `osIconFor()` picks it. `.other` has none and draws a dot.
    public static let osIconAssetNames: [DevicePlatformFamily: String] = {
        let keys: [(DevicePlatformFamily, String)] = [(.macOS, "apple"), (.windows, "windows"), (.linux, "linux")]
        var names: [DevicePlatformFamily: String] = [:]
        for (family, key) in keys {
            names[family] = generatedOSIconAssets[key]
        }
        return names
    }()

    /// The asset-catalog image of project rows (the desktop's folder glyph).
    public static let projectIconAssetName: String = generatedProjectIconAsset

    private static let marksByID: [String: Mark] = Dictionary(
        generatedMarks.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    private static let limitProvidersByID: [String: LimitProviderInfo] = Dictionary(
        generatedLimitProviders.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    private static let limitProviderOrder: [String: Int] = Dictionary(
        generatedLimitProviders.enumerated().map { ($0.element.id, $0.offset) },
        uniquingKeysWith: { first, _ in first }
    )

    // Compiled once: the resolver runs for every model row of every refresh.
    // Internal for the test that no generated pattern fails to compile.
    static let modelVendorExpressions: [(NSRegularExpression, String)] = generatedModelVendorRules.compactMap { rule in
        guard let expression = try? NSRegularExpression(pattern: rule.pattern) else { return nil }
        return (expression, rule.vendorID)
    }

    public static func mark(for id: String) -> Mark? {
        marksByID[id]
    }

    /// The name a usage row shows for a tracked client ("Claude Code"); the raw
    /// id when nothing names it.
    public static func clientLabel(_ id: String) -> String {
        generatedClientLabels[id] ?? marksByID[id]?.label ?? limitProvidersByID[id]?.label ?? id
    }

    /// The name a quota row shows for a limits provider ("Claude").
    public static func limitProviderLabel(_ id: String) -> String {
        limitProvidersByID[id]?.label ?? marksByID[id]?.label ?? generatedClientLabels[id] ?? id
    }

    /// The name compact surfaces (widgets, complications) show for a tool.
    ///
    /// Mirrors the macOS widget: where an id is both a client and a limits
    /// provider the limits name wins, so a widget says "Claude" and "Grok"
    /// where the app's usage rows say "Claude Code" and "Grok Build".
    public static func toolLabel(_ id: String) -> String {
        limitProvidersByID[id]?.label ?? generatedClientLabels[id] ?? marksByID[id]?.label ?? id
    }

    /// The name of a model vendor or any other mark id.
    public static func vendorLabel(_ id: String) -> String {
        marksByID[id]?.label ?? generatedClientLabels[id] ?? limitProvidersByID[id]?.label ?? id
    }

    /// Position of a limits provider in the desktop's default order; unknown
    /// providers sort last.
    public static func limitProviderSortIndex(_ id: String) -> Int {
        limitProviderOrder[id] ?? Int.max
    }

    /// The template image (`VendorIcons.xcassets`) that draws a mark, e.g.
    /// `"vendor-claude"`; nil when the row draws a dot instead: an unknown id,
    /// a usage row whose mark has no brand colour (`factory`, `newapi`,
    /// `sub2api`), or artwork the generator could not ship.
    ///
    /// Model rows pass `modelVendor(for:)`; the desktop draws its Σ mark (SF
    /// Symbol `sum` here) for a model whose vendor has no icon.
    public static func iconAssetName(for markID: String, context: VendorIconContext = .usage) -> String? {
        guard let mark = marksByID[markID] else { return nil }
        switch context {
        case .usage:
            guard mark.brandColorHex != nil else { return nil }
            return generatedIconAssets[markID]
        case .limits:
            return generatedLimitIconOverrides[markID] ?? generatedIconAssets[markID]
        }
    }

    /// The brand colour (for light surfaces and settings swatches).
    public static func brandColorHex(for id: String?) -> String {
        guard let id, let hex = marksByID[id]?.brandColorHex else { return defaultColorHex }
        return hex
    }

    /// What to paint a mark with on the dark Token Monitor surfaces.
    public static func paint(for id: String?) -> VendorPaint {
        guard let id, let mark = marksByID[id] else { return .hex(defaultColorHex) }
        if mark.usesInk { return .ink }
        return .hex(mark.widgetColorHex ?? defaultColorHex)
    }

    /// The vendor mark id of a model name (`claude-sonnet-4-5` → `claude`), or
    /// nil when no rule recognises it. Same rules, same order as the desktop's
    /// `modelVendorFor()`.
    public static func modelVendor(for model: String) -> String? {
        let name = model.lowercased()
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        for (expression, vendorID) in modelVendorExpressions where expression.firstMatch(in: name, range: range) != nil {
            return vendorID
        }
        return nil
    }

    /// The paint for a model row: its vendor's paint, or a stable colour from
    /// the desktop's fallback palette so unrelated unknown models stay distinct.
    public static func modelPaint(for model: String) -> VendorPaint {
        if let vendor = modelVendor(for: model), marksByID[vendor] != nil {
            return paint(for: vendor)
        }
        return .hex(fallbackModelColorHex(for: model))
    }

    /// Port of the desktop's `modelColor()` hash: `(hash * 31 + code) | 0` over
    /// UTF-16 code units, so a model keeps the same colour on every surface.
    public static func fallbackModelColorHex(for model: String) -> String {
        let palette = generatedFallbackModelColorHexes
        guard !palette.isEmpty else { return defaultColorHex }
        var hash: Int32 = 0
        for unit in model.lowercased().utf16 {
            hash = hash &* 31 &+ Int32(unit)
        }
        // `Math.abs(hash) % n` without `abs(Int32.min)` or `Int32.max + 1`,
        // which trap (the latter where `Int` is 32-bit).
        return palette[Int(hash.magnitude % UInt32(palette.count))]
    }
}

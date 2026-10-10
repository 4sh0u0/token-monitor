import Foundation

/// `VendorCatalog`'s colours with the user's vendor-colour overrides
/// (`vendorColors` preference) applied, as the desktop applies them.
///
/// An override counts only when it is a `#rrggbb` string and its key is a mark
/// with a brand colour or `"default"` — the keys the desktop's appearance
/// picker offers (`themePresets.js` `normalizeOverrides` against
/// `vendorColors()`). `"default"` repaints every id that has no colour of its
/// own. Model rows follow their vendor's override; the hashed fallback colours
/// of unrecognised models are not overridable, as on the desktop.
public struct VendorPalette: Sendable, Equatable {
    /// Mark id → colour, as stored. Invalid entries are ignored on read.
    public var overrides: [String: String]

    /// The key whose override repaints ids without a colour of their own.
    public static let defaultKey = "default"

    /// Overrides darker than this (relative luminance on 0–255 channels) are
    /// painted with the light ink instead, like the catalog's near-black
    /// brand colours; the dashboard lifts the same colours (`displayColor`).
    public static let inkLuminanceThreshold: Double = 42

    public init(overrides: [String: String] = [:]) {
        self.overrides = overrides
    }

    /// What to paint `id`'s mark with on the dark surfaces: a valid override
    /// wins (as `.ink` when it is near-black), then the catalog's paint.
    public func paint(for id: String?) -> VendorPaint {
        if let id, let hex = overrideHex(for: id) { return Self.paint(hex: hex) }
        if !Self.hasOwnColor(id), let hex = overrideHex(for: Self.defaultKey) { return Self.paint(hex: hex) }
        return VendorCatalog.paint(for: id)
    }

    /// The paint for a model row: its vendor's paint (overrides included), or
    /// the model's stable fallback colour.
    public func modelPaint(for model: String) -> VendorPaint {
        if let vendor = VendorCatalog.modelVendor(for: model), VendorCatalog.mark(for: vendor) != nil {
            return paint(for: vendor)
        }
        return .hex(VendorCatalog.fallbackModelColorHex(for: model))
    }

    /// The brand colour for light surfaces and settings swatches, override
    /// included (never ink-substituted).
    public func brandHex(for id: String?) -> String {
        if let id, let hex = overrideHex(for: id) { return hex }
        if let id, let brand = VendorCatalog.mark(for: id)?.brandColorHex { return brand }
        if let hex = overrideHex(for: Self.defaultKey) { return hex }
        return VendorCatalog.brandColorHex(for: id)
    }

    /// The normalized (`#rrggbb`, lowercase) override for `id`, nil when there
    /// is none, it is invalid, or `id` is not an overridable key.
    public func overrideHex(for id: String) -> String? {
        guard Self.isOverridable(id), let raw = overrides[id] else { return nil }
        return Self.normalizedHex(raw)
    }

    /// Whether the appearance picker offers `id`: a mark with a brand colour,
    /// or `"default"`.
    public static func isOverridable(_ id: String) -> Bool {
        id == defaultKey || VendorCatalog.mark(for: id)?.brandColorHex != nil
    }

    /// `#rrggbb` (any case, surrounding whitespace allowed) → lowercase
    /// `#rrggbb`; nil for anything else (`themePresets.js` `normalizeHex`).
    public static func normalizedHex(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = Array(trimmed.unicodeScalars)
        guard scalars.count == 7, scalars[0] == "#",
              scalars.dropFirst().allSatisfy({ $0.isASCII && Character($0).isHexDigit }) else { return nil }
        return trimmed.lowercased()
    }

    /// Relative luminance `0.2126 r + 0.7152 g + 0.0722 b` on 0–255 channels,
    /// nil for an unparseable colour.
    public static func luminance(hex: String) -> Double? {
        guard let color = RGBAColor(hex: hex) else { return nil }
        // Back to the integer channels, so a colour on the threshold compares
        // exactly as the desktop's parseInt values do.
        let channel = { (value: Double) in (value * 255).rounded() }
        return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }

    private static func paint(hex: String) -> VendorPaint {
        if let value = luminance(hex: hex), value < inkLuminanceThreshold { return .ink }
        return .hex(hex)
    }

    /// The catalog paints `id` with a colour of its own (or the ink), rather
    /// than the default colour.
    private static func hasOwnColor(_ id: String?) -> Bool {
        guard let id, let mark = VendorCatalog.mark(for: id) else { return false }
        return mark.usesInk || mark.widgetColorHex != nil
    }
}

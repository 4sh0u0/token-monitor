import Foundation

/// Everything a surface needs to present numbers and marks the way the user
/// chose: preferences, exchange rates and the UI language
/// (`Bundle.main.preferredLocalizations.first`, which picks the compact
/// units for `localized`).
public struct PresentationContext: Sendable, Equatable {
    public var preferences: DisplayPreferences
    public var rates: CurrencyRates
    /// The app's UI language (`"en"`, `"zh-Hans"`, `"ja"`, …), not the region.
    public var languageIdentifier: String

    /// Vendor colours with the user's overrides applied.
    public var palette: VendorPalette { VendorPalette(overrides: preferences.vendorColors) }

    public init(preferences: DisplayPreferences = .defaults, rates: CurrencyRates = .builtIn, languageIdentifier: String = "en") {
        self.preferences = preferences
        self.rates = rates
        self.languageIdentifier = languageIdentifier
    }

    /// Defaults, built-in rates, English.
    public static let standard = PresentationContext()
}

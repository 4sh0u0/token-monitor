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

extension PresentationContext {
    /// Every number formatted for these preferences, rates and language.
    public var formatter: DisplayFormatter {
        DisplayFormatter(preferences: preferences, rates: rates, languageIdentifier: languageIdentifier)
    }

    /// The context from the shared stores: the stored preferences, the
    /// cached exchange rates with the user's manual rates on top (a stale
    /// cache still counts, as on the desktop; no cache means the built-in
    /// floors), and the UI language of `bundle`.
    public static func load(
        preferences: PreferencesStore = .shared,
        rates: ExchangeRateStore = .shared,
        bundle: Bundle = .main
    ) -> PresentationContext {
        let stored = preferences.load()
        return PresentationContext(
            preferences: stored,
            rates: CurrencyRates.resolve(cache: rates.load(), overrides: stored.currencyRates),
            languageIdentifier: languageIdentifier(of: bundle)
        )
    }

    /// The UI language a bundle runs in (`preferredLocalizations.first`),
    /// which picks the localized compact units; `"en"` when it names none.
    public static func languageIdentifier(of bundle: Bundle) -> String {
        guard let language = bundle.preferredLocalizations.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !language.isEmpty, language.lowercased() != "base" else { return "en" }
        return language
    }
}

extension PreferencesPayload {
    /// A payload carrying `rateCache` encoded the way `ExchangeRateStore`
    /// stores it (nil: no rates).
    public init(preferences: DisplayPreferences, rateCache: ExchangeRateCache?) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.init(preferences: preferences, rateCacheData: rateCache.flatMap { try? encoder.encode($0) })
    }

    /// The exchange-rate cache the payload carries; nil when it has none or
    /// it does not decode.
    public var rateCache: ExchangeRateCache? {
        rateCacheData.flatMap { try? JSONDecoder().decode(ExchangeRateCache.self, from: $0) }
    }
}

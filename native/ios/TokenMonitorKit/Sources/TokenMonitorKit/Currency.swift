import Foundation

/// Where a currency's USD multiplier came from.
public enum RateOrigin: String, Codable, Sendable {
    /// The desktop's built-in floor (`currency.js` `CURRENCY_RATES`).
    case builtIn
    /// The daily exchange-rate fetch.
    case fetched
    /// The user's manual override (`currencyRates` preference).
    case manual
}

/// USD → display-currency multipliers, keyed by ISO code (`"TWD"`).
public struct CurrencyRates: Sendable, Equatable, Codable {
    public var multipliers: [String: Double]
    public var origins: [String: RateOrigin]
    /// The `date` of the fetched rates (`yyyy-MM-dd`), nil when none were
    /// fetched.
    public var fetchedDate: String?

    /// The desktop's built-in rates, used when nothing better is known.
    public static let floors: [String: Double] = ["USD": 1, "TWD": 31.5, "HKD": 7.8, "CNY": 6.8]

    /// The floors alone.
    public static let builtIn = CurrencyRates(
        multipliers: floors,
        origins: floors.mapValues { _ in RateOrigin.builtIn },
        fetchedDate: nil
    )

    public init(multipliers: [String: Double], origins: [String: RateOrigin] = [:], fetchedDate: String? = nil) {
        self.multipliers = multipliers
        self.origins = origins
        self.fetchedDate = fetchedDate
    }

    /// The multiplier for `currency`: its entry when finite and positive,
    /// otherwise the floor (1 for USD).
    public func multiplier(for currency: DisplayCurrency) -> Double {
        if let value = multipliers[currency.rawValue], value.isFinite, value > 0 { return value }
        return Self.floors[currency.rawValue] ?? 1
    }

    /// Where `multiplier(for:)` came from; `.builtIn` when not recorded.
    public func origin(for currency: DisplayCurrency) -> RateOrigin {
        if let value = multipliers[currency.rawValue], value.isFinite, value > 0 {
            return origins[currency.rawValue] ?? .builtIn
        }
        return .builtIn
    }
}

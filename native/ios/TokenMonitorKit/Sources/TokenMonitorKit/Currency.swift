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

extension CurrencyRates {
    /// `currency.js` `isValidRate`: finite and positive.
    public static func isValidRate(_ value: Double?) -> Bool {
        guard let value else { return false }
        return value.isFinite && value > 0
    }

    /// `resolveEffectiveRates(fetched, overrides)`: for each supported
    /// currency a valid manual override wins, then a valid fetched rate, then
    /// the built-in floor.
    ///
    /// USD is always 1. The desktop function would accept a USD override,
    /// but its settings never write one, and costs are USD to begin with.
    /// Codes outside `DisplayCurrency` are ignored.
    public static func resolve(fetched: [String: Double], overrides: [String: Double], fetchedDate: String? = nil) -> CurrencyRates {
        var multipliers: [String: Double] = [:]
        var origins: [String: RateOrigin] = [:]
        for currency in DisplayCurrency.allCases {
            let code = currency.rawValue
            if currency == .usd {
                multipliers[code] = 1
                origins[code] = .builtIn
            } else if let value = overrides[code], isValidRate(value) {
                multipliers[code] = value
                origins[code] = .manual
            } else if let value = fetched[code], isValidRate(value) {
                multipliers[code] = value
                origins[code] = .fetched
            } else {
                multipliers[code] = floors[code] ?? 1
                origins[code] = .builtIn
            }
        }
        return CurrencyRates(multipliers: multipliers, origins: origins, fetchedDate: fetchedDate)
    }

    /// `resolve` against the cached daily rates. A stale cache still counts,
    /// as on the desktop (`main.js` `applyEffectiveRates`): the stale rates
    /// are kept until a refresh succeeds.
    public static func resolve(cache: ExchangeRateCache?, overrides: [String: Double]) -> CurrencyRates {
        resolve(fetched: cache?.rates ?? [:], overrides: overrides, fetchedDate: cache?.date)
    }

    /// These rates with the user's manual `overrides` laid on top: a valid
    /// override always wins. USD and unknown codes are ignored. Applying the
    /// same overrides twice changes nothing.
    public func applying(overrides: [String: Double]) -> CurrencyRates {
        var result = self
        for currency in DisplayCurrency.allCases where currency != .usd {
            if let value = overrides[currency.rawValue], Self.isValidRate(value) {
                result.multipliers[currency.rawValue] = value
                result.origins[currency.rawValue] = .manual
            }
        }
        return result
    }

    /// The effective rate of every supported currency, the desktop's
    /// `currencyRatesEffective` map.
    public var effectiveMultipliers: [String: Double] {
        Dictionary(uniqueKeysWithValues: DisplayCurrency.allCases.map { ($0.rawValue, multiplier(for: $0)) })
    }
}

// MARK: - Cost formatting (currency.js, compactMoney.js)

/// Ports of `src/shared/currency.js` and `src/shared/compactMoney.js`. Costs
/// arrive in USD and are converted with the effective `CurrencyRates`.
///
/// The output matches the desktop byte for byte. It has the symbol directly
/// before the amount, no grouping (`$1234.50`) and a sign after the symbol
/// (`$-3.5000`).
public enum CurrencyFormat {
    /// `normalizeCurrency`: a stored currency string trimmed and upper-cased,
    /// or `fallback` (USD) when it is not supported.
    public static func normalize(_ raw: String?, fallback: DisplayCurrency = .usd) -> DisplayCurrency {
        let code = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return DisplayCurrency(rawValue: code) ?? fallback
    }

    /// `convertUsd`: `Number((usd * rate).toFixed(6))`. NaN reads as 0.
    public static func convert(usd: Double, to currency: DisplayCurrency, rates: CurrencyRates = .builtIn) -> Double {
        let amount = usd.isNaN ? 0 : usd
        let text = JSCompat.toFixed(amount * rates.multiplier(for: currency), 6)
        return Double(text) ?? .nan
    }

    /// `fractionDigitsFor`: USD keeps four decimals below $10, so small
    /// costs stay readable, and two from $10 up. Other currencies keep four
    /// decimals below 1 and two from 1 up.
    public static func fractionDigits(amount: Double, currency: DisplayCurrency) -> Int {
        if currency == .usd { return abs(amount) >= 10 ? 2 : 4 }
        return abs(amount) >= 1 ? 2 : 4
    }

    /// `formatCurrencyFromUsd`: `$0.4200`, `$12.34`, `NT$13.23`, `¥6.80`.
    public static func format(usd: Double, currency: DisplayCurrency, rates: CurrencyRates = .builtIn) -> String {
        let amount = convert(usd: usd, to: currency, rates: rates)
        return currency.symbol + JSCompat.toFixed(amount, fractionDigits(amount: amount, currency: currency))
    }

    /// `formatCompactCurrencyFromUsd(usd, currency, units, language, options)`.
    ///
    /// Below the unit threshold (1,000, or 10,000 for localized units) this is
    /// `format(usd:currency:rates:)`, which keeps small costs exact (`$0.1250`).
    /// From the threshold up the converted amount goes through
    /// `CompactNumberFormat.format` (`$1.2K`, `¥7.25萬`).
    ///
    /// - Parameters:
    ///   - fractionDigits: a fixed precision, clamped to 0...4, used both
    ///     below and above the threshold. It keeps trailing zeros (`$20.00K`).
    ///     nil is the desktop's `'auto'`.
    ///   - keepTrailingZeros: keeps zeros with the automatic precision.
    ///   - useUnits: false is the desktop's `compact: false`. It never adds a
    ///     unit.
    public static func compact(
        usd: Double,
        currency: DisplayCurrency,
        rates: CurrencyRates = .builtIn,
        units: CompactTokenUnits = .western,
        language: String = "en",
        fractionDigits: Int? = nil,
        keepTrailingZeros: Bool = false,
        useUnits: Bool = true
    ) -> String {
        let amount = convert(usd: usd, to: currency, rates: rates)
        let threshold = CompactNumberFormat.threshold(units, language: language)
        let digits = fractionDigits.map(CompactNumberFormat.clampedFractionDigits)

        if !useUnits || !amount.isFinite || abs(amount) < threshold {
            guard let digits else { return format(usd: usd, currency: currency, rates: rates) }
            return currency.symbol + JSCompat.toFixed(amount, digits)
        }
        return currency.symbol + CompactNumberFormat.format(
            amount,
            units: units,
            language: language,
            fractionDigits: digits,
            keepTrailingZeros: digits != nil || keepTrailingZeros
        )
    }
}

// MARK: - Provider balances (limits/balanceDisplay.js)

/// A port of the money formatting in `src/shared/limits/balanceDisplay.js`.
/// A provider balance keeps its own currency and is never converted.
///
/// The rules:
/// - USD and CNY get their symbol: `$13.80`, `¥86.42`.
/// - `CREDITS` (provider points) prints the bare amount, because the window
///   label already names the unit.
/// - Any other three-to-eight-letter code is a prefix: `EUR 12.50`.
/// - A missing or invalid code is USD.
public enum BalanceFormat {
    /// The currencies written as a symbol.
    public static let symbols: [String: String] = ["CNY": "¥", "USD": "$"]

    /// `normalizeCurrencyCode`: trimmed, upper-cased, and USD unless it is
    /// three to eight ASCII letters.
    public static func normalizeCode(_ raw: String?) -> String {
        let code = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isValid = (3...8).contains(code.utf8.count)
            && code.utf8.allSatisfy { (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains($0) }
        return isValid ? code : "USD"
    }

    /// `formatMoney`: two decimals, `""` for a missing or non-finite amount.
    public static func format(amount: Double?, currency: String?) -> String {
        guard let amount, amount.isFinite else { return "" }
        let code = normalizeCode(currency)
        let fixed = JSCompat.toFixed(amount, 2)
        if code == "CREDITS" { return fixed }
        if let symbol = symbols[code] { return symbol + fixed }
        return "\(code) \(fixed)"
    }

    /// `formatCompactMoney`: `format` below 100,000.
    ///
    /// From 100,000 up it uses localized units when they are in effect
    /// (`$12.3萬`). Otherwise it uses en-US `Intl` compact notation with up
    /// to two decimals (`$123.46K`, `$1.25M`, `$12B`).
    public static func compact(amount: Double?, currency: String?, units: CompactTokenUnits = .western, language: String = "en") -> String {
        guard let amount, amount.isFinite else { return "" }
        if abs(amount) < 100_000 { return format(amount: amount, currency: currency) }
        let code = normalizeCode(currency)
        let prefix = code == "CREDITS" ? "" : (symbols[code] ?? "\(code) ")
        if CompactNumberFormat.effectiveUnits(units, language: language) == .localized {
            return prefix + CompactNumberFormat.format(amount, units: .localized, language: language)
        }
        return prefix + IntlNumberFormat.englishCompact(amount, maximumFractionDigits: 2)
    }
}

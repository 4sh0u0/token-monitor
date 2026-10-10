import Foundation

/// A cost with its unpriced-token caveat, for the target to localize.
///
/// The desktop writes these with `usage.unpricedTokens` (`unpriced tokens`,
/// `未定价 tokens`, …):
/// - `.plain(cost)`: `$1.2345`
/// - `.partial(cost, unpriced)`: `$1.2345 + 1,234 unpriced tokens`
/// - `.unknown(unpriced)`: `— (1,234 unpriced tokens)`
/// - `.compactPartial(cost)`: `$1.2345 + ?`
/// - `.compactUnknown`: `—`
///
/// The amounts are already formatted. `unpriced` is a full en-US count.
public enum CostLabel: Equatable, Sendable {
    case plain(String)
    case partial(cost: String, unpriced: String)
    case unknown(unpriced: String)
    case compactPartial(cost: String)
    case compactUnknown
}

/// Every number a surface shows, formatted the way the desktop formats it for
/// the user's units, currency, rates and UI language.
///
/// Values only. The targets localize the sentences around them ("%@ left",
/// "%@ tok/s"). Get one from `PresentationContext`, or build one directly.
public struct DisplayFormatter: Sendable, Equatable {
    /// The `compactTokenUnits` setting. `effectiveUnits` is what applies.
    public var units: CompactTokenUnits
    public var currency: DisplayCurrency
    /// Effective USD multipliers, the user's manual overrides already applied.
    public var rates: CurrencyRates
    /// The app's UI language (`Bundle.main.preferredLocalizations.first`).
    public var languageIdentifier: String

    /// Uses `preferences.compactTokenUnits` and `currency`. `rates` gets
    /// `preferences.currencyRates` laid on top, so a manual rate always wins.
    public init(preferences: DisplayPreferences = .defaults, rates: CurrencyRates = .builtIn, languageIdentifier: String = "en") {
        self.init(
            units: preferences.compactTokenUnits,
            currency: preferences.currency,
            rates: rates.applying(overrides: preferences.currencyRates),
            languageIdentifier: languageIdentifier
        )
    }

    public init(units: CompactTokenUnits, currency: DisplayCurrency = .usd, rates: CurrencyRates = .builtIn, languageIdentifier: String = "en") {
        self.units = units
        self.currency = currency
        self.rates = rates
        self.languageIdentifier = languageIdentifier
    }

    // MARK: Units

    /// The units actually used. Localized units fall back to western outside
    /// zh, ja and ko.
    public var effectiveUnits: CompactTokenUnits {
        CompactNumberFormat.effectiveUnits(units, language: languageIdentifier)
    }

    /// Whether the UI language has localized units. Settings shows the picker
    /// only then.
    public var supportsLocalizedUnits: Bool {
        CompactNumberFormat.supportsLocalizedUnits(languageIdentifier)
    }

    /// The magnitude from which compact numbers get a unit: 1,000 for western
    /// units and 10,000 for localized ones.
    public var compactThreshold: Double {
        CompactNumberFormat.threshold(units, language: languageIdentifier)
    }

    // MARK: Tokens

    /// `formatCompact`: `999`, `1.5K`, `2.95億`.
    public func compactTokens(_ value: Int) -> String {
        CompactNumberFormat.tokens(value, units: units, language: languageIdentifier)
    }

    /// `compactTokens` for a fractional count, rounded first.
    public func compactTokens(_ value: Double) -> String {
        CompactNumberFormat.tokens(value, units: units, language: languageIdentifier)
    }

    /// `formatCompactValue`, which keeps fractions below the first unit
    /// (`999.5`, `1.2K`).
    public func compactNumber(_ value: Double) -> String {
        CompactNumberFormat.format(value, units: units, language: languageIdentifier)
    }

    /// `formatNumber`: a full count, rounded, always with en-US grouping
    /// (`1,234,567`) in every language, as on the desktop.
    public func fullTokens(_ value: Int) -> String {
        Self.groupedInteger(value)
    }

    /// `fullTokens` for a fractional count, rounded with `Math.round`. A
    /// non-finite value reads as 0.
    public func fullTokens(_ value: Double) -> String {
        let rounded = value.isFinite ? JSCompat.round(value) : 0
        guard abs(rounded) < 9.2e18 else { return JSCompat.numberString(rounded) }
        return Self.groupedInteger(Int(rounded))
    }

    /// The `showCompactTotalTokens` line under a full total: `≈ 1.2M`. It is
    /// nil below `compactThreshold`, where the compact form adds nothing. The
    /// caller checks the preference.
    public func compactApproximation(_ tokens: Int) -> String? {
        guard Double(tokens.magnitude) >= compactThreshold else { return nil }
        return "≈ " + compactTokens(tokens)
    }

    // MARK: Money

    /// `formatCurrencyFromUsd`: a USD cost in the display currency
    /// (`$0.4200`, `NT$13.23`).
    public func cost(_ usd: Double) -> String {
        CurrencyFormat.format(usd: usd, currency: currency, rates: rates)
    }

    /// `formatCompactCurrencyFromUsd`: `cost` below the unit threshold, then
    /// `$1.2K`, `¥7.25萬`.
    public func compactCost(_ usd: Double) -> String {
        CurrencyFormat.compact(usd: usd, currency: currency, rates: rates, units: units, language: languageIdentifier)
    }

    /// A cost that may exclude unpriced tokens. This follows
    /// `usageCostLabel` (`compact: false`) and `compactUsageCostLabel`
    /// (`compact: true`).
    ///
    /// Without unpriced tokens it is `.plain`. With them, a positive cost is
    /// partial and a zero cost is unknown. `compactAmount` formats the amount
    /// with `compactCost` instead of `cost`. The desktop uses the full form in
    /// both labels.
    public func costLabel(_ usd: Double, unpricedTokens: Int?, compact: Bool, compactAmount: Bool = false) -> CostLabel {
        let amount = usd.isFinite ? usd : 0
        let format: (Double) -> String = compactAmount ? compactCost : cost
        guard let unpricedTokens, unpricedTokens > 0 else { return .plain(format(amount)) }
        if compact {
            return amount > 0 ? .compactPartial(cost: format(amount)) : .compactUnknown
        }
        let missing = fullTokens(unpricedTokens)
        return amount > 0 ? .partial(cost: format(amount), unpriced: missing) : .unknown(unpriced: missing)
    }

    /// `balanceDisplay.formatMoney`: a provider balance in its own currency
    /// (`$13.80`, `¥86.42`, `EUR 12.50`, bare for `CREDITS`). It is `""` when
    /// there is no amount.
    public func balance(_ amount: Double?, currency: String?) -> String {
        BalanceFormat.format(amount: amount, currency: currency)
    }

    /// `balanceDisplay.formatCompactMoney`: `balance` below 100,000, then
    /// `$123.46K` or localized `$12.3萬`.
    public func compactBalance(_ amount: Double?, currency: String?) -> String {
        BalanceFormat.compact(amount: amount, currency: currency, units: units, language: languageIdentifier)
    }

    // MARK: Percent and rates

    /// `formatPercent`: `Math.round(value)%` (`42%`). It is `--` for a
    /// non-finite value.
    public func percent(_ value: Double) -> String {
        guard value.isFinite else { return "--" }
        return JSCompat.numberString(JSCompat.round(value)) + "%"
    }

    /// The desktop Settings' `formatRate`: an exchange rate with two decimals
    /// from 1 up and four below, then shortened (`31.67`, `7.8`, `0.1234`).
    /// It is `""` for a non-finite value.
    public func rate(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        let fixed = JSCompat.toFixed(value, value >= 1 ? 2 : 4)
        return JSCompat.numberString(Double(fixed) ?? value)
    }

    /// `formatLiveTokenRate`: the live tokens-per-second (or per-minute) value
    /// without its unit. A rate below 0.1 is `<0.1`. A rate below 1 gets one
    /// decimal in the UI language's separator (`0.5`). From 1 up it uses
    /// `compactTokens` (`62`, `1.2K`). A negative or non-finite rate is `0`.
    public func liveTokenRate(_ value: Double) -> String {
        let rate = value.isFinite ? max(0, value) : 0
        if rate > 0 && rate < 0.1 { return "<0.1" }
        if rate > 0 && rate < 1 {
            return IntlNumberFormat.decimal(rate, maximumFractionDigits: 1, language: languageIdentifier)
        }
        return compactTokens(rate)
    }

    // MARK: Helpers

    /// `Number.prototype.toLocaleString('en-US')` for an integer.
    static func groupedInteger(_ value: Int) -> String {
        let digits = String(value.magnitude)
        var grouped = ""
        grouped.reserveCapacity(digits.count + digits.count / 3 + 1)
        for (offset, character) in digits.enumerated() {
            if offset > 0 && (digits.count - offset) % 3 == 0 { grouped.append(",") }
            grouped.append(character)
        }
        return value < 0 ? "-" + grouped : grouped
    }
}

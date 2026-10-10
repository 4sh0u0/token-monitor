import Foundation

/// Number, money and time formatting shared by every surface.
///
/// Functions return values only (`1.2M`, `$0.42`, `2h 30m`, `42%`), and the
/// UI targets localize the sentence around them ("%@ left", "Resets in %@").
/// Everything takes an explicit `Locale` (and a reference `Date` where
/// relevant), so widget timelines and tests are deterministic.
///
/// The compact and full token counts follow the desktop
/// (`CompactNumberFormat`). Prefer `DisplayFormatter`, which also applies the
/// user's units, currency and rates. The money and percent helpers here are
/// the original Foundation formatters, kept for compatibility. The desktop's
/// money rules are in `CurrencyFormat` and `BalanceFormat`.
public enum TokenFormat {
    /// Unit system for compact numbers: the `compactTokenUnits` setting.
    /// `.western` is K/M/B. `.localized` is 万/亿 (zh-Hans), 萬/億
    /// (zh-Hant), 万/億 (ja) or 만/억 (ko), and falls back to western for
    /// other languages.
    public typealias CompactUnits = CompactTokenUnits

    // MARK: Tokens

    /// The desktop's `formatCompactTokens`: `999`, `1.2K`, `12.3K`, `1.2M`,
    /// `45.6M`, `4.5B`.
    ///
    /// Western units keep one decimal and have no T. Localized units keep
    /// two decimals below 10 and one above. Trailing zeros are dropped, and
    /// the separator is always `.`. The locale's language picks the
    /// localized units, and its region is ignored.
    /// `DisplayFormatter.compactTokens` is the preference-aware form.
    public static func compactTokens(_ value: Int, units: CompactUnits = .western, locale: Locale = .autoupdatingCurrent) -> String {
        CompactNumberFormat.tokens(value, units: units, language: locale.identifier)
    }

    /// The desktop's `formatCompactValue` for any number (rates, money
    /// amounts). Unlike `compactTokens` it keeps a fraction below the first
    /// unit (`999.5`). A non-finite value is `—`.
    public static func compactNumber(_ value: Double, units: CompactUnits = .western, locale: Locale = .autoupdatingCurrent) -> String {
        guard value.isFinite else { return "—" }
        return CompactNumberFormat.format(value, units: units, language: locale.identifier)
    }

    /// `1,234,567`: the desktop's `formatNumber`, always with en-US grouping.
    /// `locale` is ignored and kept only for source compatibility.
    public static func fullTokens(_ value: Int, locale: Locale = .autoupdatingCurrent) -> String {
        DisplayFormatter.groupedInteger(value)
    }

    // MARK: Money

    /// `$0.42`, `$12.34`, `$1,234.50` (locale-formatted USD). Amounts below one
    /// cent keep up to four decimals (`$0.0042`) instead of reading `$0.00`.
    public static func usd(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        money(value, currency: "USD", locale: locale)
    }

    /// `usd`, but `$1.2K` / `$3.45M` from one thousand up.
    public static func compactUSD(_ value: Double, units: CompactUnits = .western, locale: Locale = .autoupdatingCurrent) -> String {
        compactMoney(value, currency: "USD", units: units, locale: locale)
    }

    /// An amount in its own currency (`¥86.42`, `CN¥86.42`, `US$ 0,42`).
    /// `CREDITS` (provider points) renders as a bare number — the window label
    /// names the unit, as on the desktop. A nil code is USD.
    public static func money(_ value: Double, currency: String?, locale: Locale = .autoupdatingCurrent) -> String {
        guard value.isFinite else { return "—" }
        let code = normalizedCurrency(currency)
        let digits = abs(value) > 0 && abs(value) < 0.01 ? 4 : 2
        if code == "CREDITS" {
            return value.formatted(.number.precision(.fractionLength(2)).locale(locale))
        }
        if isISOCurrency(code) {
            return value.formatted(.currency(code: code).precision(.fractionLength(digits)).locale(locale))
        }
        return "\(code) \(value.formatted(.number.precision(.fractionLength(digits)).locale(locale)))"
    }

    /// `money`, compacted from one thousand up (`$1.2K`, `¥45.6万` with
    /// localized units).
    public static func compactMoney(_ value: Double, currency: String?, units: CompactUnits = .western, locale: Locale = .autoupdatingCurrent) -> String {
        guard value.isFinite else { return "—" }
        guard abs(value) >= 1000 else { return money(value, currency: currency, locale: locale) }
        let code = normalizedCurrency(currency)
        let number = compactNumber(value, units: units, locale: locale)
        if code == "CREDITS" { return number }
        guard isISOCurrency(code) else { return "\(code) \(number)" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = locale
        let prefix = value < 0 ? formatter.negativePrefix ?? "-" : formatter.positivePrefix ?? ""
        let suffix = value < 0 ? formatter.negativeSuffix ?? "" : formatter.positiveSuffix ?? ""
        let unsigned = value < 0 ? String(number.drop(while: { $0 == "-" || $0 == "\u{2212}" })) : number
        return prefix + unsigned + suffix
    }

    // MARK: Percent and rates

    /// `42%` from a 0...100 value.
    public static func percent(_ value: Double, fractionDigits: Int = 0, locale: Locale = .autoupdatingCurrent) -> String {
        guard value.isFinite else { return "—" }
        let digits = max(0, fractionDigits)
        return (value / 100).formatted(.percent.precision(.fractionLength(digits)).locale(locale))
    }

    /// A tokens-per-second rate as a number only (`62`, `7.4`, `1.2K`); the UI
    /// appends its localized unit ("tok/s").
    public static func tokensPerSecond(_ rate: Double, locale: Locale = .autoupdatingCurrent) -> String {
        guard rate.isFinite, rate > 0 else { return "0" }
        if rate >= 1000 { return compactNumber(rate, locale: locale) }
        let digits = rate < 100 ? 1 : 0
        return rate.formatted(.number.precision(.fractionLength(0...digits)).locale(locale))
    }

    // MARK: Time

    /// The time left until `date` as `2h 30m` / `3d 4h` (two largest units,
    /// rounded up to whole minutes, at least one minute) — the macOS widget's
    /// reset countdown, localized by Foundation (`2時間30分`).
    public static func countdown(
        to date: Date,
        from now: Date,
        width: Duration.UnitsFormatStyle.UnitWidth = .narrow,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let seconds = date.timeIntervalSince(now)
        // Whole minutes as a Double: a far-off reset must not overflow `Int`.
        let minutes = seconds.isFinite ? max(1, (seconds / 60).rounded(.up)) : 1
        return Duration.seconds(min(minutes, 1e12) * 60).formatted(
            .units(allowed: [.days, .hours, .minutes], width: width, maximumUnitCount: 2).locale(locale)
        )
    }

    /// A relative phrase ("in 3 hr.", "5 min. ago") for `date` seen from `now`.
    public static func relative(_ date: Date, to now: Date, locale: Locale = .autoupdatingCurrent) -> String {
        #if canImport(Darwin)
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
        #else
        // RelativeDateTimeFormatter is not in swift-corelibs-foundation;
        // RelativeFormatStyle always measures from the current clock, so shift
        // the date by the same offset.
        let shifted = Date().addingTimeInterval(date.timeIntervalSince(now))
        return shifted.formatted(Date.RelativeFormatStyle(presentation: .numeric, unitsStyle: .abbreviated, locale: locale))
        #endif
    }

    /// When a window resets, as a moment: the time if it is on `now`'s day
    /// (`14:00`), weekday and time within a week (`Mon 14:00`), otherwise the
    /// date (`Oct 18`).
    public static func moment(
        _ date: Date,
        relativeTo now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(date, inSameDayAs: now) {
            style = style.hour().minute()
        } else if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day,
                  (1...6).contains(days) {
            style = style.weekday(.abbreviated).hour().minute()
        } else {
            style = style.month(.abbreviated).day()
        }
        return date.formatted(style)
    }

    // MARK: Helpers

    private static func normalizedCurrency(_ value: String?) -> String {
        let code = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return code.isEmpty ? "USD" : code
    }

    private static func isISOCurrency(_ code: String) -> Bool {
        code.count == 3 && code.allSatisfy { $0.isASCII && $0.isLetter }
    }
}

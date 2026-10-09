import Foundation

/// Number, money and time formatting shared by every surface.
///
/// Functions return values only (`1.23M`, `$0.42`, `2h 30m`, `42%`); the UI
/// targets localize the sentence around them ("%@ left", "Resets in %@").
/// Everything takes an explicit `Locale` (and reference `Date` where relevant)
/// so widget timelines and tests are deterministic.
public enum TokenFormat {
    /// Unit system for compact numbers.
    public enum CompactUnits: Sendable {
        /// K / M / B / T.
        case western
        /// 万/億 (ja), 万/亿 (zh-Hans), 萬/億 (zh-Hant), 만/억 (ko) — the
        /// desktop's "localized" option. Falls back to western for other
        /// languages.
        case localized
    }

    // MARK: Tokens

    /// `999`, `1.2K`, `12.3K`, `1.23M`, `45.6M`, `4.5B`.
    ///
    /// Thousands keep one decimal (the desktop's rule); millions and above
    /// keep three significant digits so a headline stays short. Trailing zeros
    /// are dropped; the decimal separator follows `locale`.
    public static func compactTokens(_ value: Int, units: CompactUnits = .western, locale: Locale = .autoupdatingCurrent) -> String {
        compactNumber(Double(value), units: units, locale: locale)
    }

    /// `compactTokens` for any number (rates, money amounts).
    public static func compactNumber(_ value: Double, units: CompactUnits = .western, locale: Locale = .autoupdatingCurrent) -> String {
        guard value.isFinite else { return "—" }
        let scale = compactScale(units: units, locale: locale)
        let magnitude = abs(value)
        guard var index = scale.lastIndex(where: { magnitude >= $0.divisor }) else {
            return plainInteger(value.rounded(), locale: locale)
        }
        var digits = fractionDigits(value / scale[index].divisor, unitIndex: index, localized: scale.isLocalized)
        var display = fixed(value / scale[index].divisor, digits: digits)
        // 999,950 rounds to "1000.0K": promote to the next unit instead.
        if abs(Double(display) ?? 0) >= scale.promotionBoundary, index < scale.units.count - 1 {
            index += 1
            digits = fractionDigits(value / scale[index].divisor, unitIndex: index, localized: scale.isLocalized)
            display = fixed(value / scale[index].divisor, digits: digits)
        }
        return localizedDecimal(trimmingZeros(display), locale: locale) + scale[index].suffix
    }

    /// `1,234,567` with the locale's grouping.
    public static func fullTokens(_ value: Int, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(.number.grouping(.automatic).locale(locale))
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
        let seconds = max(0, date.timeIntervalSince(now))
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return Duration.seconds(minutes * 60).formatted(
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

    private struct CompactScale {
        let units: [(divisor: Double, suffix: String)]
        let isLocalized: Bool
        var promotionBoundary: Double { isLocalized ? 10_000 : 1000 }

        subscript(index: Int) -> (divisor: Double, suffix: String) { units[index] }

        func lastIndex(where predicate: ((divisor: Double, suffix: String)) -> Bool) -> Int? {
            units.lastIndex(where: predicate)
        }
    }

    private static func compactScale(units: CompactUnits, locale: Locale) -> CompactScale {
        if units == .localized, let suffixes = localizedSuffixes(locale) {
            return CompactScale(units: [(1e4, suffixes.0), (1e8, suffixes.1)], isLocalized: true)
        }
        return CompactScale(units: [(1e3, "K"), (1e6, "M"), (1e9, "B"), (1e12, "T")], isLocalized: false)
    }

    // Port of `localizedSuffixes()` in src/shared/compactTokens.js.
    private static func localizedSuffixes(_ locale: Locale) -> (String, String)? {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if identifier.hasPrefix("ko") { return ("만", "억") }
        if identifier.hasPrefix("ja") { return ("万", "億") }
        guard identifier.hasPrefix("zh") else { return nil }
        let simplified = identifier.hasPrefix("zh-hans")
            || identifier.range(of: #"^zh(?:-[a-z0-9]+)*-(?:cn|sg|my)(?:-|$)"#, options: .regularExpression) != nil
        return simplified ? ("万", "亿") : ("萬", "億")
    }

    private static func fractionDigits(_ scaled: Double, unitIndex: Int, localized: Bool) -> Int {
        let magnitude = abs(scaled)
        if localized { return magnitude < 10 ? 2 : 1 }
        if unitIndex == 0 { return 1 }
        if magnitude < 10 { return 2 }
        return magnitude < 100 ? 1 : 0
    }

    private static func fixed(_ value: Double, digits: Int) -> String {
        let factor = pow(10, Double(digits))
        let rounded = (value * factor).rounded() / factor
        var text = String(rounded)
        // String(Double) may use exponent notation for large values; the
        // scaled values here are below 10,000, so it never does.
        if let dot = text.firstIndex(of: ".") {
            let decimals = text.distance(from: text.index(after: dot), to: text.endIndex)
            if decimals < digits { text += String(repeating: "0", count: digits - decimals) }
        } else if digits > 0 {
            text += "." + String(repeating: "0", count: digits)
        }
        return text
    }

    private static func trimmingZeros(_ text: String) -> String {
        guard text.contains(".") else { return text }
        var trimmed = text
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    private static func localizedDecimal(_ text: String, locale: Locale) -> String {
        let separator = locale.decimalSeparator ?? "."
        return separator == "." ? text : text.replacingOccurrences(of: ".", with: separator)
    }

    private static func plainInteger(_ value: Double, locale: Locale) -> String {
        clampedInt(value).formatted(.number.grouping(.never).locale(locale))
    }

    private static func normalizedCurrency(_ value: String?) -> String {
        let code = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return code.isEmpty ? "USD" : code
    }

    private static func isISOCurrency(_ code: String) -> Bool {
        code.count == 3 && code.allSatisfy { $0.isASCII && $0.isLetter }
    }
}

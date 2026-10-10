import Foundation

/// A port of the desktop's compact number formatter (`src/shared/compactTokens.js`).
///
/// Western units are K, M and B, with no T, so a trillion reads `1000B`. Localized
/// units are the UI language's myriads: 万/亿 for Simplified Chinese, 萬/億 for
/// other Chinese, 万/億 for Japanese and 만/억 for Korean. Localized units only
/// apply to zh, ja and ko. Every other language gets western units even when
/// `localized` is chosen.
///
/// `language` is the app's UI language (`"en"`, `"zh-Hans"`, `"ja"`, …), not the
/// region, which matches the desktop's `currentLocale()`. The decimal separator is
/// always `.` on every surface, as on the desktop.
///
/// `.standard` output:
/// - Western: one decimal, trailing zeros trimmed (`1.5K`, `2M`).
/// - Localized: two decimals below 10 and one above (`1.24萬`, `9999.9萬`).
/// - Below the first unit, the number prints as JavaScript's `String(n)`
///   (`999`, `999.5`).
/// - A rounded value that reaches the next unit is promoted (`999,950` → `1M`).
public enum CompactNumberFormat {
    /// The desktop's `style` option.
    public enum Style: Sendable, Equatable {
        /// One decimal for western units, trailing zeros trimmed.
        case standard
        /// The tray and menu-bar precision: western units keep their trailing
        /// zeros, and billions get two decimals (`12.0K`, `1.23B`). Localized
        /// units are unchanged.
        case tray
    }

    /// The smallest magnitude that gets a western unit (1K).
    public static let westernThreshold: Double = 1e3
    /// The smallest magnitude that gets a localized unit (1万).
    public static let localizedThreshold: Double = 1e4

    /// `normalizeCompactTokenUnits`: a stored setting string, with anything
    /// except exactly `"localized"` read as western.
    public static func normalizeUnits(_ raw: String?) -> CompactTokenUnits {
        raw == CompactTokenUnits.localized.rawValue ? .localized : .western
    }

    /// `supportsLocalizedCompactTokenUnits`: true for zh, ja and ko UI languages.
    /// Settings shows the units picker only when this is true.
    public static func supportsLocalizedUnits(_ language: String) -> Bool {
        let primary = normalizedLanguage(language).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return primary == "zh" || primary == "ja" || primary == "ko"
    }

    /// `effectiveCompactTokenUnits`: the units actually used for `language`.
    public static func effectiveUnits(_ units: CompactTokenUnits, language: String) -> CompactTokenUnits {
        units == .localized && supportsLocalizedUnits(language) ? .localized : .western
    }

    /// `compactTokenUnitThreshold`: the magnitude from which a unit is
    /// written. It is 1,000 for western units and 10,000 for localized ones.
    public static func threshold(_ units: CompactTokenUnits, language: String) -> Double {
        effectiveUnits(units, language: language) == .localized ? localizedThreshold : westernThreshold
    }

    /// The desktop's `localizedSuffixes`: the 10⁴ and 10⁸ units for `language`.
    /// Simplified Chinese is `zh-Hans*` or any `zh-…-CN/SG/MY`. Japanese is
    /// 万/億, Korean 만/억, and every other language (including the other
    /// Chinese locales) falls through to 萬/億.
    public static func localizedSuffixes(_ language: String) -> (tenThousand: String, hundredMillion: String) {
        let normalized = normalizedLanguage(language)
        if normalized.hasPrefix("ko") { return ("만", "억") }
        if normalized.hasPrefix("zh-hans") || isSimplifiedChineseRegion(normalized) { return ("万", "亿") }
        if normalized.hasPrefix("ja") { return ("万", "億") }
        return ("萬", "億")
    }

    /// `formatCompactValue(value, units, language, options)`.
    ///
    /// - Parameters:
    ///   - fractionDigits: replaces the automatic precision. It is clamped to
    ///     0...4 and also applies below the first unit (`7.00`). Trailing zeros
    ///     are still trimmed unless `keepTrailingZeros` is set. The desktop
    ///     quirk is kept: an integer display loses its zeros too, so
    ///     `fractionDigits: 0` turns 20,000 into `2K`.
    ///   - keepTrailingZeros: keeps `toFixed`'s zeros (`2.00萬`).
    ///   - style: `.tray` for the tray and menu-bar precision.
    ///
    /// NaN reads as 0, as `Number(value || 0)` does.
    public static func format(
        _ value: Double,
        units: CompactTokenUnits = .western,
        language: String = "en",
        fractionDigits: Int? = nil,
        keepTrailingZeros: Bool = false,
        style: Style = .standard
    ) -> String {
        let effective = effectiveUnits(units, language: language)
        let number = value.isNaN || value == 0 ? 0 : value
        let magnitude = abs(number)
        let table = unitTable(effective, language: language)
        guard var unitIndex = table.lastIndex(where: { magnitude >= $0.divisor }) else {
            if let fractionDigits {
                return JSCompat.toFixed(number, clampedFractionDigits(fractionDigits))
            }
            return JSCompat.numberString(number)
        }

        func scaled(_ index: Int) -> String {
            let scaledValue = number / table[index].divisor
            let digits = decimals(effective, unitIndex: index, scaled: scaledValue, fractionDigits: fractionDigits, style: style)
            return JSCompat.toFixed(scaledValue, digits)
        }

        var display = scaled(unitIndex)
        let promotionBoundary: Double = effective == .localized ? 10_000 : 1000
        if abs(Double(display) ?? 0) >= promotionBoundary, unitIndex < table.count - 1 {
            unitIndex += 1
            display = scaled(unitIndex)
        }

        let keepsZeros = keepTrailingZeros || (style == .tray && effective == .western)
        if !keepsZeros { display = JSCompat.trimTrailingZeros(display) }
        return display + table[unitIndex].suffix
    }

    /// `formatCompactTokens`: `format` after `Math.round`, so token counts
    /// never show a fraction below the first unit.
    public static func tokens(
        _ value: Double,
        units: CompactTokenUnits = .western,
        language: String = "en",
        fractionDigits: Int? = nil,
        keepTrailingZeros: Bool = false,
        style: Style = .standard
    ) -> String {
        let number = value.isNaN ? 0 : JSCompat.round(value)
        return format(number, units: units, language: language, fractionDigits: fractionDigits, keepTrailingZeros: keepTrailingZeros, style: style)
    }

    /// `formatCompactTokens` for an integer count.
    public static func tokens(
        _ value: Int,
        units: CompactTokenUnits = .western,
        language: String = "en",
        fractionDigits: Int? = nil,
        keepTrailingZeros: Bool = false,
        style: Style = .standard
    ) -> String {
        format(Double(value), units: units, language: language, fractionDigits: fractionDigits, keepTrailingZeros: keepTrailingZeros, style: style)
    }

    // MARK: Helpers

    private struct Unit {
        let divisor: Double
        let suffix: String
    }

    private static let westernUnits = [Unit(divisor: 1e3, suffix: "K"), Unit(divisor: 1e6, suffix: "M"), Unit(divisor: 1e9, suffix: "B")]

    private static func unitTable(_ effective: CompactTokenUnits, language: String) -> [Unit] {
        guard effective == .localized else { return westernUnits }
        let suffixes = localizedSuffixes(language)
        return [Unit(divisor: 1e4, suffix: suffixes.tenThousand), Unit(divisor: 1e8, suffix: suffixes.hundredMillion)]
    }

    /// `decimalsFor`.
    private static func decimals(_ effective: CompactTokenUnits, unitIndex: Int, scaled: Double, fractionDigits: Int?, style: Style) -> Int {
        if let fractionDigits { return clampedFractionDigits(fractionDigits) }
        if effective == .localized { return abs(scaled) < 10 ? 2 : 1 }
        if style == .tray { return unitIndex == 2 ? 2 : 1 }
        return 1
    }

    static func clampedFractionDigits(_ digits: Int) -> Int {
        min(max(digits, 0), 4)
    }

    /// `String(locale).replace(/_/g, '-').toLowerCase()`.
    static func normalizedLanguage(_ language: String) -> String {
        language.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    /// `/^(?:zh)(?:-[a-z0-9]+)*-(?:cn|sg|my)(?:-|$)/` on a normalized tag.
    private static func isSimplifiedChineseRegion(_ normalized: String) -> Bool {
        let parts = normalized.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count > 1, parts[0] == "zh" else { return false }
        for part in parts.dropFirst() {
            if part == "cn" || part == "sg" || part == "my" { return true }
            let isAlphanumeric = !part.isEmpty && part.utf8.allSatisfy { byte in
                (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
            }
            if !isAlphanumeric { return false }
        }
        return false
    }
}

// MARK: - ECMA-402 number formatting

/// The parts of `Intl.NumberFormat` the desktop uses, ported for the cases that
/// reach them. ICU rounds the *shortest* decimal form of a double half away from
/// zero (`halfExpand`), so `1.005` keeps its `5` and rounds to `1.01`, unlike
/// `toFixed`. The `en-US` compact notation uses K/M/B/T with min2 grouping.
enum IntlNumberFormat {
    /// `new Intl.NumberFormat('en-US', { notation: 'compact', maximumFractionDigits })`
    /// as ICU 77 formats it: `123.46K`, `1.23M`, `25M`, `1000T`, `15,000T`.
    static func englishCompact(_ value: Double, maximumFractionDigits: Int = 2) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-∞" : "∞" }
        let negative = value.sign == .minus
        var quantity = DecimalQuantity(abs(value))
        var multiplier = 0
        if quantity.isZero {
            quantity.round(fractionDigits: maximumFractionDigits)
        } else {
            // RoundingImpl::chooseMultiplierAndApply.
            let magnitude = quantity.magnitude
            multiplier = compactMultiplier(magnitude)
            quantity.point += multiplier
            quantity.round(fractionDigits: maximumFractionDigits)
            if !quantity.isZero, quantity.magnitude != magnitude + multiplier {
                let next = compactMultiplier(magnitude + 1)
                if next != multiplier {
                    quantity.point += next - multiplier
                    quantity.round(fractionDigits: maximumFractionDigits)
                    multiplier = next
                }
            }
        }
        let suffix: String
        switch multiplier {
        case -3: suffix = "K"
        case -6: suffix = "M"
        case -9: suffix = "B"
        case -12: suffix = "T"
        default: suffix = ""
        }
        return (negative ? "-" : "") + quantity.text(minimumGroupingDigits: 2) + suffix
    }

    /// `value.toLocaleString(locale, { maximumFractionDigits })` for a value
    /// below 1,000, so grouping never applies. Only the decimal separator
    /// depends on `language`.
    static func decimal(_ value: Double, maximumFractionDigits: Int, language: String) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-∞" : "∞" }
        var quantity = DecimalQuantity(abs(value))
        quantity.round(fractionDigits: maximumFractionDigits)
        let text = quantity.text(minimumGroupingDigits: 2)
        let separator = Locale(identifier: language).decimalSeparator ?? "."
        let localized = separator == "." ? text : text.replacingOccurrences(of: ".", with: separator)
        return (value.sign == .minus ? "-" : "") + localized
    }

    /// The en compact short patterns: none below 10³, then one unit per three
    /// magnitudes, and the 10¹⁴ pattern for everything larger.
    private static func compactMultiplier(_ magnitude: Int) -> Int {
        guard magnitude >= 3 else { return 0 }
        return -3 * (min(magnitude, 14) / 3)
    }
}

/// A non-negative decimal `0.d₁d₂… × 10^point`, built from the shortest
/// round-trip digits of a double (what ICU's `DecimalQuantity` holds).
struct DecimalQuantity: Equatable {
    /// Significant digits, 0–9, without leading or trailing zeros; empty for zero.
    var digits: [UInt8]
    var point: Int

    init(_ value: Double) {
        guard value.isFinite, value != 0 else {
            digits = []
            point = 0
            return
        }
        let text = abs(value).description
        let pieces = text.split(separator: "e", maxSplits: 1, omittingEmptySubsequences: false)
        let exponent = pieces.count > 1 ? Int(pieces[1]) ?? 0 : 0
        let mantissa = pieces[0].split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integerDigits = Array(mantissa[0].utf8)
        let fractionDigits = mantissa.count > 1 ? Array(mantissa[1].utf8) : []
        var all = (integerDigits + fractionDigits).map { $0 - UInt8(ascii: "0") }
        var point = integerDigits.count + exponent
        while let first = all.first, first == 0 {
            all.removeFirst()
            point -= 1
        }
        while let last = all.last, last == 0 { all.removeLast() }
        self.digits = all
        self.point = all.isEmpty ? 0 : point
    }

    var isZero: Bool { digits.isEmpty }

    /// The power of ten of the leading digit.
    var magnitude: Int { point - 1 }

    /// Rounds half away from zero to `fractionDigits` decimals.
    mutating func round(fractionDigits: Int) {
        guard !digits.isEmpty else { return }
        let kept = point + fractionDigits
        if kept >= digits.count { return }
        if kept < 0 {
            digits = []
            point = 0
            return
        }
        let roundsUp = digits[kept] >= 5
        var result = Array(digits[..<kept])
        if roundsUp {
            var index = result.count - 1
            while index >= 0 && result[index] == 9 {
                result[index] = 0
                index -= 1
            }
            if index >= 0 {
                result[index] += 1
            } else {
                result.insert(1, at: 0)
                point += 1
            }
        }
        while let last = result.last, last == 0 { result.removeLast() }
        digits = result
        if digits.isEmpty { point = 0 }
    }

    /// The plain decimal text with no trailing zeros. The integer part is
    /// grouped by three with `,` once it has at least `minimumGroupingDigits + 3`
    /// digits (ICU min2 grouping: `1000`, `10,000`).
    func text(minimumGroupingDigits: Int) -> String {
        let zero = UInt8(ascii: "0")
        var integer: [UInt8]
        var fraction: [UInt8]
        if digits.isEmpty {
            integer = [0]
            fraction = []
        } else if point <= 0 {
            integer = [0]
            fraction = Array(repeating: 0, count: -point) + digits
        } else if point >= digits.count {
            integer = digits + Array(repeating: 0, count: point - digits.count)
            fraction = []
        } else {
            integer = Array(digits[..<point])
            fraction = Array(digits[point...])
        }
        var integerText = String(decoding: integer.map { $0 + zero }, as: UTF8.self)
        if integer.count >= minimumGroupingDigits + 3 {
            var grouped: [Character] = []
            for (offset, character) in integerText.enumerated() {
                if offset > 0 && (integer.count - offset) % 3 == 0 { grouped.append(",") }
                grouped.append(character)
            }
            integerText = String(grouped)
        }
        guard !fraction.isEmpty else { return integerText }
        return integerText + "." + String(decoding: fraction.map { $0 + zero }, as: UTF8.self)
    }
}

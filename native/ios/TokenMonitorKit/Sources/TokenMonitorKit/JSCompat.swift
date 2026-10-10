import Foundation

/// Ports of the JavaScript number and string primitives the desktop's
/// formatters are built on, so Swift ports of those formatters produce the
/// same text byte for byte.
///
/// Foundation's formatting does not match them: `printf` and
/// `NumberFormatter` round a decimal tie half to even (or by locale rules),
/// while `Number.prototype.toFixed` rounds half up on the exact binary value,
/// and `Double.description` writes exponents as `1e-07` where JS writes `1e-7`.
public enum JSCompat {
    /// `Number.prototype.toFixed(digits)`.
    ///
    /// Rounds the exact binary value of `x` half up (away from zero for a
    /// negative `x`), so `toFixed(0.125, 2)` is `"0.13"` (0.125 is exact) while
    /// `toFixed(1.005, 2)` is `"1.00"` (1.005 is stored as 1.00499…), and
    /// `toFixed(-0.001, 2)` keeps its sign as `"-0.00"` while `-0.0` gives
    /// `"0.00"`. `|x| >= 1e21` falls back to `numberString(x)`, and NaN and the
    /// infinities print as JS does. `digits` is clamped to `0...20`.
    public static func toFixed(_ x: Double, _ digits: Int) -> String {
        let digits = min(max(digits, 0), 20)
        if x.isNaN { return "NaN" }
        if !x.isFinite || abs(x) >= 1e21 { return numberString(x) }
        let negative = x < 0
        // `%.60f` is the exact binary expansion as far as it matters: a tie at
        // digit d ≤ 20 is a dyadic fraction with at most 21 fractional digits,
        // and any other value of a magnitude that can round up at digit d sits
        // more than 1e-57 from the tie, so printf's own rounding at digit 60
        // can never move it across.
        let expansion = String(format: "%.60f", abs(x))
        let parts = expansion.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integerPart = parts.first.map { Array($0.utf8) } ?? [UInt8(ascii: "0")]
        let fractionPart = parts.count > 1 ? Array(parts[1].utf8) : []
        let zero = UInt8(ascii: "0")
        var kept = integerPart + fractionPart.prefix(digits)
        while kept.count < integerPart.count + digits { kept.append(zero) }
        let next = digits < fractionPart.count ? fractionPart[digits] : zero
        if next >= UInt8(ascii: "5") {
            var index = kept.count - 1
            while index >= 0 {
                if kept[index] == UInt8(ascii: "9") {
                    kept[index] = zero
                    index -= 1
                } else {
                    kept[index] += 1
                    break
                }
            }
            if index < 0 { kept.insert(UInt8(ascii: "1"), at: 0) }
        }
        var text = String(decoding: kept, as: UTF8.self)
        if digits > 0 {
            text.insert(".", at: text.index(text.endIndex, offsetBy: -digits))
        }
        return negative ? "-" + text : text
    }

    /// `String(number)` (`Number::toString` with radix 10).
    ///
    /// The shortest digits that round-trip, written as JS does: integral
    /// values without `.0` (`"5"`, `"100000000000000000000"` up to 1e21),
    /// plain decimals down to 1e-6 (`"0.000001"`), and otherwise exponent form
    /// without zero padding (`"1e-7"`, `"1.5e+21"`). `-0` prints as `"0"`;
    /// NaN and the infinities as `"NaN"`, `"Infinity"` and `"-Infinity"`.
    public static func numberString(_ x: Double) -> String {
        if x.isNaN { return "NaN" }
        if x == 0 { return "0" }
        if x.isInfinite { return x < 0 ? "-Infinity" : "Infinity" }
        if x < 0 { return "-" + numberString(-x) }

        let (digits, n) = shortestDigits(x)
        let k = digits.count
        let zeros = { (count: Int) in String(repeating: "0", count: max(0, count)) }
        if k <= n && n <= 21 {
            return digits + zeros(n - k)
        }
        if 0 < n && n <= 21 {
            let split = digits.index(digits.startIndex, offsetBy: n)
            return String(digits[..<split]) + "." + String(digits[split...])
        }
        if -6 < n && n <= 0 {
            return "0." + zeros(-n) + digits
        }
        let exponent = n - 1
        let exponentText = "e" + (exponent >= 0 ? "+" : "-") + String(abs(exponent))
        if k == 1 { return digits + exponentText }
        return String(digits.prefix(1)) + "." + String(digits.dropFirst()) + exponentText
    }

    /// `JSON.stringify(string)`: wraps in double quotes and escapes `"`, `\`,
    /// `\b`, `\f`, `\n`, `\r`, `\t` and every other C0 control as `\u00xx`
    /// (lowercase hex). Everything else, non-ASCII and U+2028/2029 included,
    /// is written literally.
    public static func jsonQuoted(_ s: String) -> String {
        var out = "\""
        out.reserveCapacity(s.utf8.count + 2)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }

    /// `Math.round(x)`: the nearest integer, a tie going toward +∞
    /// (`round(2.5) == 3`, `round(-2.5) == -2`).
    ///
    /// The exact rule, not the `floor(x + 0.5)` shortcut, which is off by one
    /// for 0.49999999999999994 and for odd integers + 0.5 above 2^52. As in
    /// JS, a value in `[-0.5, -0]` rounds to `-0`, and NaN and the infinities
    /// are returned unchanged.
    public static func round(_ x: Double) -> Double {
        guard x.isFinite else { return x }
        if x < 0 && x >= -0.5 { return -0.0 }
        let down = x.rounded(.down)
        // Exact: `x - floor(x)` is representable for every finite double.
        return x - down >= 0.5 ? down + 1 : down
    }

    /// `value.replace(/\.?0+$/, '')`, the desktop's trailing-zero trim,
    /// quirks included: it is meant for a `toFixed` result, so on an integer
    /// string it strips significant zeros too (`"100"` → `"1"`, `"0"` → `""`).
    /// Callers only pass strings that have a fractional part.
    public static func trimTrailingZeros(_ s: String) -> String {
        let bytes = Array(s.utf8)
        var end = bytes.count
        while end > 0 && bytes[end - 1] == UInt8(ascii: "0") { end -= 1 }
        guard end < bytes.count else { return s }
        if end > 0 && bytes[end - 1] == UInt8(ascii: ".") { end -= 1 }
        return String(decoding: bytes[..<end], as: UTF8.self)
    }

    /// The shortest round-trip digits of a positive finite `x` and the
    /// position `n` of the decimal point (the spec's `s` and `n`:
    /// `x = 0.digits × 10^n`), taken from Swift's own shortest-digits
    /// `description` and stripped of its formatting.
    private static func shortestDigits(_ x: Double) -> (digits: String, n: Int) {
        let text = x.description
        let pieces = text.split(separator: "e", maxSplits: 1, omittingEmptySubsequences: false)
        let mantissa = pieces[0]
        let exponent = pieces.count > 1 ? Int(pieces[1]) ?? 0 : 0
        let mantissaParts = mantissa.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integerDigits = String(mantissaParts[0])
        let fractionDigits = mantissaParts.count > 1 ? String(mantissaParts[1]) : ""
        var digits = Array((integerDigits + fractionDigits).utf8)
        var point = integerDigits.count + exponent
        while let first = digits.first, first == UInt8(ascii: "0") {
            digits.removeFirst()
            point -= 1
        }
        while let last = digits.last, last == UInt8(ascii: "0") {
            digits.removeLast()
        }
        if digits.isEmpty { return ("0", 1) }
        return (String(decoding: digits, as: UTF8.self), point)
    }
}

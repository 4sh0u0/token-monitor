import Foundation

/// `String.prototype.localeCompare` without a locale, which V8 answers with
/// the ICU root collation: punctuation and symbols before digits before
/// letters, case-insensitive first (accents, then lower before upper break
/// the tie). Only used to break exact ties in sorts (usage rows, project
/// rows, the Trends legend, device tool rows, live-rate models), so it
/// models the characters ids and labels actually contain — ASCII exactly,
/// other scripts by code point. One model for every port, so equal values
/// order the same way on every surface.
enum UsageRowCollation {
    /// -1, 0 or 1, like `localeCompare`.
    static func compare(_ left: String, _ right: String) -> Int {
        if left == right { return 0 }
        let a = elements(left)
        let b = elements(right)
        for level in 0..<3 {
            let order = compareLevel(a.map { $0[level] }, b.map { $0[level] })
            if order != 0 { return order }
        }
        return 0
    }

    private static func compareLevel(_ a: [UInt32], _ b: [UInt32]) -> Int {
        let a = a.filter { $0 != 0 }
        let b = b.filter { $0 != 0 }
        for (x, y) in zip(a, b) where x != y { return x < y ? -1 : 1 }
        return a.count == b.count ? 0 : (a.count < b.count ? -1 : 1)
    }

    /// Variable characters in root order (the ASCII ones).
    private static let variableOrder: [Character: UInt32] = {
        let order = " _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$"
        var map: [Character: UInt32] = ["\t": 1, "\n": 2, "\u{0B}": 3, "\u{0C}": 4, "\r": 5]
        for (index, character) in order.enumerated() { map[character] = UInt32(10 + index) }
        return map
    }()

    /// [primary, secondary, tertiary] per collation element; 0 = ignorable.
    private static func elements(_ value: String) -> [[UInt32]] {
        var result: [[UInt32]] = []
        for scalar in value.decomposedStringWithCanonicalMapping.unicodeScalars {
            let properties = scalar.properties
            if properties.generalCategory == .nonspacingMark || properties.generalCategory == .enclosingMark {
                result.append([0, 0x100 + scalar.value, 0])
                continue
            }
            if let weight = variableOrder[Character(scalar)] {
                result.append([weight, 1, 1])
            } else if scalar.isASCII, let digit = Int(String(scalar)) {
                result.append([1000 + UInt32(digit), 1, 1])
            } else if scalar.isASCII, properties.isAlphabetic {
                let lower = scalar.value | 0x20
                result.append([2000 + lower, 1, properties.isUppercase ? 2 : 1])
            } else if properties.isAlphabetic {
                let lower = properties.lowercaseMapping.unicodeScalars.first?.value ?? scalar.value
                result.append([0x10_0000 + lower, 1, properties.isUppercase ? 2 : 1])
            } else {
                result.append([500 + min(scalar.value, 400), 1, 1])
            }
        }
        return result
    }
}

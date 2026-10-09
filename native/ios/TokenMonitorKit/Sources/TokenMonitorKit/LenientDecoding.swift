import Foundation

// The Hub is the trust boundary and normalizes what devices post, but this app
// talks to Hubs of different ages (Node, the embedded widget Host, the Worker)
// and the wire shape grows additively. Every wire decoder in the Kit therefore
// reads field by field and falls back to a default instead of throwing: a
// missing, null or oddly typed field must never discard the whole response.

/// A coding key for JSON objects whose keys are data (client ids, model names).
struct AnyCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init(_ string: String) {
        stringValue = string
        intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// Decodes an element without ever failing, so one malformed row in an array
/// is dropped instead of failing the array (and with it the response).
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

enum ISODate {
    // Format styles are Sendable value types, so one shared instance each is
    // safe from widgets, the app and background tasks alike.
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle()

    static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (try? fractional.parse(trimmed)) ?? (try? whole.parse(trimmed))
    }

    /// Mirrors the Hub's `normalizeIsoTimestamp`: numbers below 2e10 are epoch
    /// seconds, larger ones epoch milliseconds.
    static func fromEpoch(_ value: Double) -> Date? {
        guard value.isFinite else { return nil }
        return Date(timeIntervalSince1970: value < 20_000_000_000 ? value : value / 1000)
    }

    /// UTC with millisecond precision, rounded rather than truncated, so a
    /// `.082` that a `Double` holds as `.08199…` does not come back a
    /// millisecond early.
    static func string(from date: Date) -> String {
        let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        let seconds = (milliseconds / 1000).rounded(.down)
        let fraction = Int(milliseconds - seconds * 1000)
        let base = whole.format(Date(timeIntervalSince1970: seconds))
        guard base.hasSuffix("Z") else { return fractional.format(date) }
        let digits = String(fraction)
        return "\(base.dropLast()).\(String(repeating: "0", count: max(0, 3 - digits.count)))\(digits)Z"
    }
}

extension KeyedDecodingContainer {
    func isNullOrMissing(_ key: Key) -> Bool {
        guard contains(key) else { return true }
        return (try? decodeNil(forKey: key)) ?? true
    }

    /// A finite number from a JSON number or a numeric string.
    func lenientDouble(_ key: Key) -> Double? {
        guard !isNullOrMissing(key) else { return nil }
        if let value = try? decode(Double.self, forKey: key) {
            return value.isFinite ? value : nil
        }
        if let string = try? decode(String.self, forKey: key),
           let value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)),
           value.isFinite {
            return value
        }
        return nil
    }

    /// An integer from any finite number, rounded and clamped to `Int`.
    func lenientInt(_ key: Key) -> Int? {
        lenientDouble(key).map(clampedInt)
    }

    /// A trimmed, non-empty string.
    func lenientString(_ key: Key) -> String? {
        guard !isNullOrMissing(key), let raw = try? decode(String.self, forKey: key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func lenientBool(_ key: Key) -> Bool? {
        guard !isNullOrMissing(key) else { return nil }
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let string = try? decode(String.self, forKey: key) {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }
        return nil
    }

    /// An ISO 8601 string (with or without fractional seconds) or an epoch number.
    func lenientDate(_ key: Key) -> Date? {
        guard !isNullOrMissing(key) else { return nil }
        if let string = try? decode(String.self, forKey: key) { return ISODate.parse(string) }
        if let number = try? decode(Double.self, forKey: key) { return ISODate.fromEpoch(number) }
        return nil
    }

    /// A `{ key: number }` object; non-numeric values are skipped.
    func lenientNumberMap(_ key: Key) -> [String: Double] {
        guard !isNullOrMissing(key),
              let nested = try? nestedContainer(keyedBy: AnyCodingKey.self, forKey: key) else { return [:] }
        var result: [String: Double] = [:]
        for nestedKey in nested.allKeys {
            if let value = nested.lenientDouble(nestedKey) { result[nestedKey.stringValue] = value }
        }
        return result
    }

    /// The number of keys in an object, without decoding its values.
    func lenientKeyCount(_ key: Key) -> Int {
        guard !isNullOrMissing(key),
              let nested = try? nestedContainer(keyedBy: AnyCodingKey.self, forKey: key) else { return 0 }
        return nested.allKeys.count
    }

    /// An array whose undecodable elements are dropped.
    func lenientArray<Element: Decodable>(_ key: Key, of type: Element.Type = Element.self) -> [Element] {
        guard !isNullOrMissing(key), let rows = try? decode([Lossy<Element>].self, forKey: key) else { return [] }
        return rows.compactMap(\.value)
    }

    /// An array of trimmed, non-empty strings.
    func lenientStringArray(_ key: Key) -> [String] {
        lenientArray(key, of: String.self)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// A nested object decoded with its own lenient decoder, or nil.
    func lenientObject<Value: Decodable>(_ key: Key, as type: Value.Type = Value.self) -> Value? {
        guard !isNullOrMissing(key) else { return nil }
        return try? decode(Value.self, forKey: key)
    }
}

extension KeyedEncodingContainer {
    mutating func encodeISODate(_ date: Date?, forKey key: Key) throws {
        guard let date else { return }
        try encode(ISODate.string(from: date), forKey: key)
    }
}

func clampedInt(_ value: Double) -> Int {
    guard value.isFinite else { return 0 }
    let rounded = value.rounded()
    if rounded >= Double(Int.max) { return Int.max }
    if rounded <= Double(Int.min) { return Int.min }
    return Int(rounded)
}

func nonNegative(_ value: Int) -> Int { max(0, value) }
func nonNegative(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }

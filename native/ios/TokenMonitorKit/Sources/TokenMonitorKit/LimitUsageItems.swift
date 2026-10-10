import Foundation

// Port of `src/shared/limits/usageItems.js` (which rows of a provider's
// limits card the user has hidden) and of the window naming it relies on,
// `src/shared/limits/windowLabels.js`.
//
// Item ids are stored in the shared `limitProviderHiddenItems` setting, so the
// window keys below must be the exact strings the desktop's `JSON.stringify`
// writes: an iPhone that wrote `["weekly","Opus","",false]` any other way
// would hide nothing on the desktop, and the other way round.

/// The card rows that keep one identity however the payload carries them:
/// the money balance (`credits`), the spend line (`spend`) and the
/// reset-credit line (`resets`). Every other row is keyed by its window.
public enum LimitUsageFixedItem: String, Sendable, Codable, CaseIterable {
    case credits
    case spend
    case resets

    /// The desktop checklist's fixed English name ("Balance", "Spend",
    /// "Resets"); targets localize the case instead.
    public var desktopText: String {
        switch self {
        case .credits: return "Balance"
        case .spend: return "Spend"
        case .resets: return "Resets"
        }
    }
}

/// The name a provider gives a window kind when the window carries no label
/// of its own (`windowLabels.js` `limitWindowKindLabel`).
public enum LimitWindowKindName: String, Sendable, Codable, CaseIterable {
    case session
    /// The rolling window of the vendors that publish it as "5-hour".
    case fiveHour
    case daily
    case weekly
    /// `billing` windows.
    case monthly

    /// `FIVE_HOUR_WINDOW_PROVIDERS`.
    public static let fiveHourProviders: Set<String> = [
        "alibaba", "antigravity", "cline", "commandcode", "kimi", "volcengine", "zai", "zaiteam"
    ]

    /// The name for `kind` (any spelling the desktop accepts: trimmed and
    /// lowercased first), or nil for a kind nobody names.
    public static func forKind(_ kind: String, provider: String) -> LimitWindowKindName? {
        switch LimitUsageItems.normalizedID(kind) {
        case "session":
            return fiveHourProviders.contains(LimitUsageItems.normalizedID(provider)) ? .fiveHour : .session
        case "daily": return .daily
        case "weekly": return .weekly
        case "billing": return .monthly
        default: return nil
        }
    }

    public static func forKind(_ kind: LimitWindowKind, provider: String) -> LimitWindowKindName {
        forKind(kind.rawValue, provider: provider) ?? .monthly
    }

    /// The desktop's English wording; targets localize the case instead.
    public var desktopText: String {
        switch self {
        case .session: return "Session"
        case .fiveHour: return "5-hour"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

/// What a window is called (`windowLabels.js` `limitWindowLabel`): the
/// collector's own label always wins, else the provider's name for the kind.
public enum LimitWindowTitle: Sendable, Hashable {
    /// Provider-supplied text, shown as is.
    case label(String)
    case kind(LimitWindowKindName)
    /// A stored key's kind that no provider names; shown as is (the desktop's
    /// `String(window.kind)` fallback).
    case rawKind(String)

    public static func of(_ window: LimitWindow, provider: String) -> LimitWindowTitle {
        if let label = window.label.map(LimitUsageItems.jsTrim), !label.isEmpty { return .label(label) }
        return .kind(LimitWindowKindName.forKind(window.kind, provider: provider))
    }

    /// The desktop's English text.
    public var desktopText: String {
        switch self {
        case .label(let text), .rawKind(let text): return text
        case .kind(let name): return name.desktopText
        }
    }
}

/// An item's name on the visible-items checklist when no row names it
/// (`usageItemFallbackLabel`). Structured so targets localize the fixed and
/// kind names and show provider text verbatim.
public enum LimitUsageItemLabel: Sendable, Hashable {
    case fixed(LimitUsageFixedItem)
    case window(LimitWindowTitle)
    /// An additional pool's key keeps its backend id but not its name, and
    /// its period alone would read like the main window: `"<limitID> · <title>"`.
    case additional(limitID: String, title: LimitWindowTitle)

    /// The desktop's text, byte for byte (`"codex_bengalfox · Weekly"`).
    public var desktopText: String {
        switch self {
        case .fixed(let item): return item.desktopText
        case .window(let title): return title.desktopText
        case let .additional(limitID, title): return "\(limitID) · \(title.desktopText)"
        }
    }
}

/// One row of a provider's visible-items checklist.
public struct LimitUsageItem: Sendable, Hashable, Identifiable {
    /// The stored item id: a `LimitUsageFixedItem` raw value or a window key.
    public var id: String
    public var label: LimitUsageItemLabel
    /// The window's Limits-page name when the row is a window
    /// (`LimitPresentation.windowName`). `label` keeps the desktop's
    /// checklist wording, which flattens an odd cadence ("3-hour") and
    /// "Additional limit" into English text; targets word this instead
    /// whenever it is set. Nil for the fixed rows (balance, spend, resets)
    /// and for balance or spend windows, which keep their own label.
    public var windowName: LimitWindowName?

    public init(id: String, label: LimitUsageItemLabel, windowName: LimitWindowName? = nil) {
        self.id = id
        self.label = label
        self.windowName = windowName
    }
}

/// `usageItems.js`. The hidden-items value is the `limitProviderHiddenItems`
/// setting: `[providerId: [itemId]]`, the hidden half, so a row that appears
/// later is shown by default.
public enum LimitUsageItems {
    /// `USAGE_ITEM_IDS`.
    public static let fixedItemIDs: [String] = LimitUsageFixedItem.allCases.map(\.rawValue)
    /// Per provider, after de-duplication (`MAX_HIDDEN_ITEMS`).
    public static let maxHiddenItems = 64
    /// The longest stored window key accepted, in UTF-16 code units.
    public static let maxWindowKeyLength = 400

    /// The window fields an item key is built from, as the desktop reads them
    /// off a window object. Stored keys parse back into this shape (without a
    /// label for `["id", …]` keys).
    public struct KeyFields: Sendable, Hashable {
        public var kind: String
        public var label: String
        public var metric: String
        public var additional: Bool
        public var limitId: String
        public var windowMinutes: Double?

        public init(kind: String, label: String = "", metric: String = "", additional: Bool = false, limitId: String = "", windowMinutes: Double? = nil) {
            self.kind = kind
            self.label = label
            self.metric = metric
            self.additional = additional
            self.limitId = limitId
            self.windowMinutes = windowMinutes
        }

        public init(_ window: LimitWindow) {
            self.init(
                kind: window.kind.rawValue,
                label: window.label ?? "",
                metric: window.metric?.rawValue ?? "",
                additional: window.isAdditional,
                limitId: window.limitId ?? "",
                windowMinutes: window.windowMinutes
            )
        }
    }

    // MARK: Window keys

    /// `legacyLimitWindowKey`: `JSON.stringify([kind, label, metric, additional])`.
    public static func legacyWindowKey(_ fields: KeyFields) -> String {
        guard !fields.kind.isEmpty else { return "" }
        return jsonArray([
            JSCompat.jsonQuoted(fields.kind),
            JSCompat.jsonQuoted(fields.label),
            JSCompat.jsonQuoted(fields.metric),
            fields.additional ? "true" : "false"
        ])
    }

    /// `limitWindowKey`: the backend `limitId` (with kind, metric, additional
    /// and cadence) when the window has one, else the legacy key.
    public static func windowKey(_ fields: KeyFields) -> String {
        let legacy = legacyWindowKey(fields)
        guard !legacy.isEmpty else { return "" }
        let limitId = jsTrim(fields.limitId)
        guard !limitId.isEmpty else { return legacy }
        let minutes: String
        if let value = fields.windowMinutes, value.isFinite, value > 0 {
            minutes = JSCompat.numberString(value)
        } else {
            minutes = "null"
        }
        return jsonArray([
            JSCompat.jsonQuoted("id"),
            JSCompat.jsonQuoted(limitId),
            JSCompat.jsonQuoted(fields.kind),
            JSCompat.jsonQuoted(fields.metric),
            fields.additional ? "true" : "false",
            minutes
        ])
    }

    /// `limitWindowKeys`: the current key, then the legacy one if different.
    public static func windowKeys(_ fields: KeyFields) -> [String] {
        var keys: [String] = []
        for key in [windowKey(fields), legacyWindowKey(fields)] where !key.isEmpty && !keys.contains(key) {
            keys.append(key)
        }
        return keys
    }

    public static func legacyWindowKey(_ window: LimitWindow) -> String { legacyWindowKey(KeyFields(window)) }
    public static func windowKey(_ window: LimitWindow) -> String { windowKey(KeyFields(window)) }
    public static func windowKeys(_ window: LimitWindow) -> [String] { windowKeys(KeyFields(window)) }

    // MARK: Item ids

    /// `limitUsageItemId`: the item a window's row belongs to. Cline folds its
    /// spend into the credits row; older Hubs send Claude's spend window and
    /// OpenRouter's balance window without a metric.
    public static func itemID(for fields: KeyFields, provider: String) -> String {
        let provider = normalizedID(provider)
        let metric = normalizedID(fields.metric)
        if provider == "cline" && metric == "spend" { return LimitUsageFixedItem.credits.rawValue }
        if provider == "claude" && metric.isEmpty && fields.kind == "billing" && fields.label == "Usage credits" {
            return LimitUsageFixedItem.spend.rawValue
        }
        if provider == "openrouter" && metric.isEmpty && fields.label == "Credits" { return LimitUsageFixedItem.credits.rawValue }
        if metric == "credits" || metric == "spend" { return metric }
        return windowKey(fields)
    }

    public static func itemID(for window: LimitWindow, provider: String) -> String {
        itemID(for: KeyFields(window), provider: provider)
    }

    /// `normalizeWindowKey`: a stored key in canonical form, or `""` when
    /// `windowKey` could not have produced it.
    public static func normalizeWindowKey(_ value: String) -> String {
        parseWindowKey(value).map(windowKey) ?? ""
    }

    /// `normalizeUsageItemId`: a fixed item id (trimmed) or a canonical window
    /// key; `""` when invalid.
    public static func normalizeItemID(_ value: String) -> String {
        let id = jsTrim(value)
        return fixedItemIDs.contains(id) ? id : normalizeWindowKey(id)
    }

    /// `usageItemFallbackLabel`: what an item is called when its row gives
    /// no name, or while nothing in the payload draws it. Nil where the
    /// desktop returns `""` (an id that is neither fixed nor a window key).
    public static func fallbackLabel(provider: String, itemID: String) -> LimitUsageItemLabel? {
        if let fixed = LimitUsageFixedItem(rawValue: itemID) { return .fixed(fixed) }
        guard let parsed = parseWindowKey(itemID) else { return nil }
        let title: LimitWindowTitle
        let explicit = jsTrim(parsed.label)
        if !explicit.isEmpty {
            title = .label(explicit)
        } else if let name = LimitWindowKindName.forKind(parsed.kind, provider: provider) {
            title = .kind(name)
        } else {
            title = .rawKind(parsed.kind)
        }
        if parsed.additional && !parsed.limitId.isEmpty {
            return .additional(limitID: parsed.limitId, title: title)
        }
        return .window(title)
    }

    // MARK: The hidden-items setting

    /// `normalizeLimitProviderHiddenItems`: unknown providers, malformed ids
    /// and empty selections dropped, ids de-duplicated in order and capped at
    /// `maxHiddenItems`, provider keys lowercased.
    ///
    /// Swift dictionaries have no key order, so where two keys lowercase to
    /// one provider the already-lowercase key is applied last (the desktop
    /// applies object keys in insertion order, and its own writes put the
    /// lowercase key last).
    public static func normalizeHiddenItems(_ value: [String: [String]]) -> [String: [String]] {
        let known = knownProviderIDs
        let keys = value.keys.sorted { left, right in
            let leftCanonical = normalizedID(left) == left
            let rightCanonical = normalizedID(right) == right
            if leftCanonical != rightCanonical { return !leftCanonical }
            return left < right
        }
        var result: [String: [String]] = [:]
        for key in keys {
            let provider = normalizedID(key)
            guard known.contains(provider) else { continue }
            let items = hiddenItemList(value[key] ?? [])
            if !items.isEmpty { result[provider] = items }
        }
        return result
    }

    /// `hiddenUsageItemSet`, in stored order: the provider's hidden item ids.
    public static func hiddenItems(_ value: [String: [String]], provider: String) -> [String] {
        hiddenItemList(value[normalizedID(provider)] ?? [])
    }

    /// `hiddenUsageItemSet`.
    public static func hiddenSet(_ value: [String: [String]], provider: String) -> Set<String> {
        Set(hiddenItems(value, provider: provider))
    }

    /// `isLimitWindowHidden`: for surfaces that list a provider's windows
    /// rather than its card rows (Home, widgets, the watch).
    public static func isHidden(_ window: LimitWindow, provider: String, hiddenItems value: [String: [String]]) -> Bool {
        let hidden = hiddenSet(value, provider: provider)
        return !hidden.isEmpty && hidden.contains(itemID(for: window, provider: provider))
    }

    /// `setUsageItemHidden`: the next setting value with one item shown or hidden.
    public static func setHidden(_ value: [String: [String]], provider: String, itemID: String, hidden: Bool) -> [String: [String]] {
        let provider = normalizedID(provider)
        var items = hiddenItems(value, provider: provider)
        if hidden {
            if !items.contains(itemID) { items.append(itemID) }
        } else {
            items.removeAll { $0 == itemID }
        }
        var next = value
        next[provider] = items
        return normalizeHiddenItems(next)
    }

    /// `restoreUsageItemDefaults`: every item of the provider shown again.
    public static func restoreDefaults(_ value: [String: [String]], provider: String) -> [String: [String]] {
        var next = value
        next[normalizedID(provider)] = []
        return normalizeHiddenItems(next)
    }

    // MARK: Internals

    /// `LIMIT_PROVIDER_IDS`: a hidden-items entry for any other key is dropped.
    static let knownProviderIDs: Set<String> = Set(VendorCatalog.limitProviders.map { normalizedID($0.id) })

    private static func hiddenItemList(_ raw: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for value in raw {
            let id = normalizeItemID(value)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            result.append(id)
            if result.count == maxHiddenItems { break }
        }
        return result
    }

    /// `String(value || '').trim().toLowerCase()`.
    static func normalizedID(_ value: String) -> String {
        jsTrim(value).lowercased()
    }

    private static func jsonArray(_ parts: [String]) -> String {
        "[" + parts.joined(separator: ",") + "]"
    }

    /// `String.prototype.trim`: strips ECMAScript WhiteSpace and
    /// LineTerminator code points (Unicode `Zs`, tab, VT, FF, BOM, LF, CR,
    /// U+2028, U+2029), which differs from Foundation's `whitespacesAndNewlines`
    /// (no BOM, adds U+0085).
    static func jsTrim(_ value: String) -> String {
        let scalars = value.unicodeScalars
        guard let start = scalars.firstIndex(where: { !isJSWhitespace($0) }) else { return "" }
        let end = scalars.lastIndex(where: { !isJSWhitespace($0) }) ?? start
        return String(scalars[start...end])
    }

    private static func isJSWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A,
             0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    /// `parseWindowKey`: a stored key back into its fields, or nil. Accepts
    /// exactly the two shapes the desktop accepts: `["id", limitId, kind,
    /// metric, additional, minutes|null]` (limitId kept untrimmed, no label)
    /// and `[kind, label, metric, additional]`.
    static func parseWindowKey(_ value: String) -> KeyFields? {
        guard value.utf16.count <= maxWindowKeyLength,
              let parts = KeyJSONParser.parseScalarArray(value) else { return nil }
        if parts.count == 6, case .string("id") = parts[0] {
            guard case let .string(limitId) = parts[1], !jsTrim(limitId).isEmpty,
                  case let .string(kind) = parts[2], !kind.isEmpty,
                  case let .string(metric) = parts[3],
                  case let .bool(additional) = parts[4] else { return nil }
            let minutes: Double?
            switch parts[5] {
            case .null: minutes = nil
            case .number(let number) where number > 0: minutes = number
            default: return nil
            }
            return KeyFields(kind: kind, metric: metric, additional: additional, limitId: limitId, windowMinutes: minutes)
        }
        guard parts.count == 4,
              case let .string(kind) = parts[0], !kind.isEmpty,
              case let .string(label) = parts[1],
              case let .string(metric) = parts[2],
              case let .bool(additional) = parts[3] else { return nil }
        return KeyFields(kind: kind, label: label, metric: metric, additional: additional)
    }
}

/// A strict `JSON.parse` for the one shape a stored window key can take: a
/// top-level array of scalars. Anything else, including arrays that hold
/// objects or arrays (no valid key does), fails. Strings holding a lone
/// UTF-16 surrogate also fail: Swift cannot represent them, and no window
/// field the desktop writes contains one.
enum KeyJSONParser {
    enum Scalar: Equatable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case null
    }

    static func parseScalarArray(_ text: String) -> [Scalar]? {
        var parser = Cursor(units: Array(text.utf16))
        parser.skipWhitespace()
        guard parser.consume(0x5B) else { return nil } // [
        var values: [Scalar] = []
        parser.skipWhitespace()
        if !parser.consume(0x5D) { // ]
            while true {
                parser.skipWhitespace()
                guard let value = parser.parseScalar() else { return nil }
                values.append(value)
                parser.skipWhitespace()
                if parser.consume(0x2C) { continue } // ,
                guard parser.consume(0x5D) else { return nil }
                break
            }
        }
        parser.skipWhitespace()
        return parser.isAtEnd ? values : nil
    }

    private struct Cursor {
        let units: [UInt16]
        var index = 0

        var isAtEnd: Bool { index >= units.count }

        func peek() -> UInt16? { index < units.count ? units[index] : nil }

        mutating func consume(_ unit: UInt16) -> Bool {
            guard peek() == unit else { return false }
            index += 1
            return true
        }

        mutating func consume(literal: String) -> Bool {
            let literalUnits = Array(literal.utf16)
            guard index + literalUnits.count <= units.count,
                  Array(units[index..<(index + literalUnits.count)]) == literalUnits else { return false }
            index += literalUnits.count
            return true
        }

        mutating func skipWhitespace() {
            while let unit = peek(), unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D { index += 1 }
        }

        mutating func parseScalar() -> Scalar? {
            guard let unit = peek() else { return nil }
            switch unit {
            case 0x22: return parseString().map(Scalar.string)
            case 0x74: return consume(literal: "true") ? .bool(true) : nil
            case 0x66: return consume(literal: "false") ? .bool(false) : nil
            case 0x6E: return consume(literal: "null") ? .null : nil
            case 0x2D, 0x30...0x39: return parseNumber().map(Scalar.number)
            default: return nil
            }
        }

        private static func hexValue(_ unit: UInt16) -> UInt16? {
            switch unit {
            case 0x30...0x39: return unit - 0x30
            case 0x41...0x46: return unit - 0x41 + 10
            case 0x61...0x66: return unit - 0x61 + 10
            default: return nil
            }
        }

        private static func isDigit(_ unit: UInt16?) -> Bool {
            guard let unit else { return false }
            return unit >= 0x30 && unit <= 0x39
        }

        mutating func parseNumber() -> Double? {
            let start = index
            _ = consume(0x2D)
            if consume(0x30) {
                // A leading zero stands alone.
            } else {
                guard Self.isDigit(peek()) else { return nil }
                while Self.isDigit(peek()) { index += 1 }
            }
            if consume(0x2E) {
                guard Self.isDigit(peek()) else { return nil }
                while Self.isDigit(peek()) { index += 1 }
            }
            if peek() == 0x65 || peek() == 0x45 {
                index += 1
                if peek() == 0x2B || peek() == 0x2D { index += 1 }
                guard Self.isDigit(peek()) else { return nil }
                while Self.isDigit(peek()) { index += 1 }
            }
            let literal = String(decoding: units[start..<index], as: UTF16.self)
            // Correctly rounded, like `Number(...)`; overflow gives ±infinity.
            return Double(literal)
        }

        mutating func parseString() -> String? {
            guard consume(0x22) else { return nil }
            var output: [UInt16] = []
            while let unit = peek() {
                index += 1
                switch unit {
                case 0x22:
                    return Self.validString(output)
                case 0x5C:
                    guard let escape = peek() else { return nil }
                    index += 1
                    switch escape {
                    case 0x22, 0x5C, 0x2F: output.append(escape)
                    case 0x62: output.append(0x08)
                    case 0x66: output.append(0x0C)
                    case 0x6E: output.append(0x0A)
                    case 0x72: output.append(0x0D)
                    case 0x74: output.append(0x09)
                    case 0x75:
                        guard index + 4 <= units.count else { return nil }
                        var code: UInt16 = 0
                        for digit in units[index..<(index + 4)] {
                            guard let value = Self.hexValue(digit) else { return nil }
                            code = code << 4 | value
                        }
                        index += 4
                        output.append(code)
                    default:
                        return nil
                    }
                case 0x00..<0x20:
                    return nil
                default:
                    output.append(unit)
                }
            }
            return nil
        }

        /// The string, or nil when it holds a lone surrogate.
        private static func validString(_ units: [UInt16]) -> String? {
            var scalars = String.UnicodeScalarView()
            var iterator = units.makeIterator()
            var decoder = UTF16()
            while true {
                switch decoder.decode(&iterator) {
                case .scalarValue(let scalar): scalars.append(scalar)
                case .emptyInput: return String(scalars)
                case .error: return nil
                }
            }
        }
    }
}

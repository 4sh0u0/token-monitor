import Foundation

// Port of the desktop's model-alias resolver, `src/electron/renderer/modelAliases.js`
// (read path: normalizeModelAliases, normalizeModelAliasGrouping,
// inferModelAliases, createModelAliasResolver), with the "active" rule of
// `aliasPlan` in `src/electron/modelAliasPresentation.js`.
//
// The Hub aggregates raw model names; aliases are applied by each reader. The
// shared group (`GET /api/sync/settings/modelAliases`) carries explicit
// `alias → canonical` pairs plus the automatic grouping mode. Explicit aliases
// always apply; automatic grouping folds spellings of one model that the
// payload itself shows (`duplicates`), or also strips a lone provider prefix
// (`prefix`).
//
// JavaScript string semantics are kept on purpose, so the phone folds exactly
// the names the desktop folds:
// - equality and ordering use UTF-16 code units (`===`, `<`), never Swift's
//   canonical equivalence ("é" and "e\u{301}" stay different models);
// - `trim()` and `\s` use the ECMAScript white-space set (U+FEFF yes, U+0085 no);
// - `toLowerCase()` is the full Unicode mapping including Final_Sigma;
// - `length` counts UTF-16 code units.

/// `modelAliasGrouping`: how spellings of one model are folded automatically.
public enum ModelAliasGrouping: String, Sendable, Codable, CaseIterable, Identifiable {
    /// Explicit aliases only (the desktop default).
    case off
    /// Fold spellings of one model only when two or more are present.
    case duplicates
    /// Like `duplicates`, and also shorten a lone provider-qualified name.
    case prefix

    public var id: String { rawValue }

    /// `normalizeModelAliasGrouping`: trimmed and lowercased; anything else,
    /// including nil, is `.off`.
    public init(normalizing value: String?) {
        let mode = ModelAliasResolver.jsLowercased(ModelAliasResolver.jsTrimmed(value ?? ""))
        self = Self.allCases.first { $0.rawValue.utf16.elementsEqual(mode.utf16) } ?? .off
    }
}

/// One `alias → canonical` pair, in the order the desktop enumerates it.
public struct ModelAliasPair: Sendable, Hashable {
    public var alias: String
    public var canonical: String

    public init(alias: String, canonical: String) {
        self.alias = alias
        self.canonical = canonical
    }
}

/// The desktop's `createModelAliasResolver(aliases, observedModels, grouping)`.
///
/// Build one per stats payload: automatic grouping depends on which model ids
/// the payload shows. Pass the observed ids in the order the desktop collects
/// them (`collectStatsModelIds`); with grouping `.off` they are ignored.
public struct ModelAliasResolver: Sendable, Equatable {
    /// `MAX_ALIASES`: cap on explicit and on inferred pairs.
    public static let maxAliases = 4096
    /// `MAX_DISCOVERED_MODELS`: cap on observed ids considered for grouping.
    public static let maxDiscoveredModels = 16384
    /// `MAX_MODEL_ID_LENGTH`, in UTF-16 code units.
    public static let maxModelIDLength = 256

    public let grouping: ModelAliasGrouping
    /// `normalizeModelAliases(aliases)`, in enumeration order.
    public let explicitAliases: [ModelAliasPair]
    /// `inferModelAliases(observedModels, grouping)`, in enumeration order.
    public let inferredAliases: [ModelAliasPair]

    private let explicit: [CodeUnits: String]
    private let automatic: [CodeUnits: String]

    /// A resolver for a shared document. An uninitialized document (`value:
    /// null`) has no aliases and grouping `.off`, so it resolves every model
    /// to itself.
    public init(document: ModelAliasDocument, observedModels: [String] = []) {
        self.init(aliases: document.aliases, observedModels: observedModels, grouping: document.grouping)
    }

    /// `createModelAliasResolver` over a JSON object's entries, enumerated in
    /// the order the Hub stores them (`ModelAliasResolver.hubOrder`).
    public init(aliases: [String: String], observedModels: [String] = [], grouping: ModelAliasGrouping) {
        self.init(aliases: Self.orderedPairs(aliases), observedModels: observedModels, grouping: grouping)
    }

    /// `createModelAliasResolver` over entries in a known order.
    public init(aliases: [ModelAliasPair], observedModels: [String] = [], grouping: ModelAliasGrouping) {
        self.grouping = grouping
        explicitAliases = Self.normalizeAliases(aliases)
        inferredAliases = Self.inferAliases(observedModels, grouping: grouping)
        var explicit: [CodeUnits: String] = [:]
        for pair in explicitAliases { explicit[CodeUnits(Self.matchKey(pair.alias))] = pair.canonical }
        var automatic: [CodeUnits: String] = [:]
        for pair in inferredAliases { automatic[CodeUnits(Self.matchKey(pair.alias))] = pair.canonical }
        self.explicit = explicit
        self.automatic = automatic
    }

    /// Resolves every model to itself.
    public static let inactive = ModelAliasResolver(aliases: [ModelAliasPair](), grouping: .off)

    /// `aliasPlan(...).active`: some explicit or inferred alias exists. An
    /// inactive resolver maps every model to itself, so callers skip the
    /// projection entirely.
    public var isActive: Bool { !explicit.isEmpty || !automatic.isEmpty }

    /// The display name for a model id: an explicit alias first, then an
    /// inferred one (whose target may itself have an explicit alias), else
    /// `model` unchanged. Lookups go through `matchKey`, so case, `.`/`_`/space
    /// and surrounding white space do not matter.
    public func resolve(_ model: String) -> String {
        guard isActive else { return model }
        let key = CodeUnits(Self.matchKey(model))
        if let direct = explicit[key] { return direct }
        guard let inferred = automatic[key] else { return model }
        return explicit[CodeUnits(Self.matchKey(inferred))] ?? inferred
    }
}

// MARK: - The desktop's pure helpers

extension ModelAliasResolver {
    /// `matchKey`: trimmed, lowercased, every run of `-`, `.`, `_` and white
    /// space collapsed to one `-`, and no leading or trailing `-`.
    public static func matchKey(_ model: String) -> String {
        let lowered = jsLowercased(jsTrimmed(model))
        var result = String.UnicodeScalarView()
        var pendingDash = false
        for scalar in lowered.unicodeScalars {
            if scalar == "-" || scalar == "." || scalar == "_" || isJSWhitespace(scalar) {
                pendingDash = true
            } else {
                if pendingDash, !result.isEmpty { result.append("-") }
                pendingDash = false
                result.append(scalar)
            }
        }
        return String(result)
    }

    /// `modelLeaf`: the last non-empty `/` segment of the trimmed id
    /// (`openai/gpt-4.1` → `gpt-4.1`); the trimmed id itself when it has none.
    public static func modelLeaf(_ model: String) -> String {
        let raw = jsTrimmed(model)
        guard !raw.isEmpty else { return "" }
        let scalars = Array(raw.unicodeScalars)
        var end = scalars.count
        while end > 0, scalars[end - 1] == "/" { end -= 1 }
        guard end > 0 else { return raw }
        var start = end
        while start > 0, scalars[start - 1] != "/" { start -= 1 }
        return String(String.UnicodeScalarView(scalars[start..<end]))
    }

    /// `modelIdentityKey`: `matchKey(modelLeaf(model))`, the grouping key.
    public static func modelIdentityKey(_ model: String) -> String {
        matchKey(modelLeaf(model))
    }

    /// `normalizeModelAliases` over entries in enumeration order: both sides
    /// trimmed; empty, over-long and self-referencing pairs dropped; the first
    /// alias per `matchKey` wins; at most `maxAliases`. The result is in the
    /// order `Object.entries` enumerates the rebuilt object.
    public static func normalizeAliases(_ pairs: [ModelAliasPair]) -> [ModelAliasPair] {
        var entries: [ModelAliasPair] = []
        var seen = Set<CodeUnits>()
        for pair in pairs {
            let alias = jsTrimmed(pair.alias)
            let canonical = jsTrimmed(pair.canonical)
            let aliasKey = CodeUnits(matchKey(alias))
            guard isValidPair(alias: alias, canonical: canonical), !seen.contains(aliasKey) else { continue }
            seen.insert(aliasKey)
            entries.append(ModelAliasPair(alias: alias, canonical: canonical))
            if entries.count == maxAliases { break }
        }
        return jsPropertyOrder(entries, key: \.alias)
    }

    /// `normalizeModelAliases` over a JSON object, enumerated in `hubOrder`.
    public static func normalizeAliases(_ aliases: [String: String]) -> [ModelAliasPair] {
        normalizeAliases(orderedPairs(aliases))
    }

    /// `discoveredModelIds`: trimmed, non-empty, at most `maxModelIDLength`
    /// UTF-16 units, first occurrence only, at most `maxDiscoveredModels`.
    public static func discoveredModelIDs(_ modelIDs: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<CodeUnits>()
        for value in modelIDs {
            let model = jsTrimmed(value)
            guard !model.isEmpty, model.utf16.count <= maxModelIDLength else { continue }
            guard seen.insert(CodeUnits(model)).inserted else { continue }
            result.append(model)
            if result.count == maxDiscoveredModels { break }
        }
        return result
    }

    /// `compareCanonicalCandidates`: -1 when `left` is the better canonical
    /// name for the group `identity`, 1 when `right` is, 0 when they tie.
    /// Prefers, in order: a leaf whose key is the identity, an unprefixed id,
    /// an all-lowercase leaf, a leaf without `.`/`_`/white space, the shorter
    /// leaf (UTF-16 length), then the lowercased leaf and the leaf in UTF-16
    /// code-unit order.
    public static func compareCanonicalCandidates(_ left: String, _ right: String, identity: String) -> Int {
        let a = CanonicalRank(left, identity: identity)
        let b = CanonicalRank(right, identity: identity)
        return a.compare(to: b)
    }

    /// `inferModelAliases`: groups the observed ids by `modelIdentityKey` and
    /// maps every member of a group to the leaf of its best candidate. With
    /// `.duplicates` a group of one is left alone; `.prefix` also folds it.
    public static func inferAliases(_ modelIDs: [String], grouping: ModelAliasGrouping) -> [ModelAliasPair] {
        guard grouping != .off else { return [] }
        let models = discoveredModelIDs(modelIDs)
        guard models.count >= (grouping == .prefix ? 1 : 2) else { return [] }

        var order: [CodeUnits] = []
        var groups: [CodeUnits: (identity: String, members: [String])] = [:]
        for model in models {
            let identity = modelIdentityKey(model)
            guard !identity.isEmpty else { continue }
            let key = CodeUnits(identity)
            if groups[key] == nil {
                order.append(key)
                groups[key] = (identity, [model])
            } else {
                groups[key]?.members.append(model)
            }
        }

        var aliases: [ModelAliasPair] = []
        for key in order {
            guard let group = groups[key] else { continue }
            if grouping != .prefix, group.members.count < 2 { continue }
            // The first minimum, as a stable sort's first element would be.
            var best = group.members[0]
            for candidate in group.members.dropFirst()
            where compareCanonicalCandidates(candidate, best, identity: group.identity) < 0 {
                best = candidate
            }
            let canonical = modelLeaf(best)
            for model in group.members {
                if model.utf16.elementsEqual(canonical.utf16) { continue }
                aliases.append(ModelAliasPair(alias: model, canonical: canonical))
                if aliases.count == maxAliases { return jsPropertyOrder(aliases, key: \.alias) }
            }
        }
        return jsPropertyOrder(aliases, key: \.alias)
    }

    /// The order `Object.entries` enumerates the Hub's stored alias map in:
    /// the Hub sorts aliases by UTF-16 code units (`syncContent.js`), and a JS
    /// object then lists array-index keys ("0"…"4294967294") first, ascending.
    public static func hubOrder(_ keys: [String]) -> [String] {
        jsPropertyOrder(keys.sorted { utf16Less($0, $1) }, key: { $0 })
    }

    private static func orderedPairs(_ aliases: [String: String]) -> [ModelAliasPair] {
        hubOrder(Array(aliases.keys)).compactMap { key in
            aliases[key].map { ModelAliasPair(alias: key, canonical: $0) }
        }
    }

    /// `validPair`: both sides non-empty, at most `maxModelIDLength` UTF-16
    /// units, and not an alias of itself.
    private static func isValidPair(alias: String, canonical: String) -> Bool {
        !alias.isEmpty && !canonical.isEmpty
            && alias.utf16.count <= maxModelIDLength && canonical.utf16.count <= maxModelIDLength
            && !matchKey(alias).utf16.elementsEqual(matchKey(canonical).utf16)
    }
}

// MARK: - JavaScript string semantics

extension ModelAliasResolver {
    /// ECMAScript WhiteSpace and LineTerminator: what `trim()` removes and
    /// what `\s` matches (no U+0085, no U+180E, no U+200B).
    static func isJSWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    /// `String.prototype.trim()`, by code point rather than by grapheme.
    static func jsTrimmed(_ value: String) -> String {
        let scalars = value.unicodeScalars
        guard let first = scalars.firstIndex(where: { !isJSWhitespace($0) }),
              let last = scalars.lastIndex(where: { !isJSWhitespace($0) }) else { return "" }
        if first == scalars.startIndex, scalars.index(after: last) == scalars.endIndex { return value }
        return String(String.UnicodeScalarView(scalars[first...last]))
    }

    /// `String.prototype.toLowerCase()`: the full Unicode lowercase mapping
    /// (`İ` → `i̇`), plus the Final_Sigma rule JS applies and Swift's
    /// `lowercased()` does not (`ΟΔΟΣ` → `οδος`).
    static func jsLowercased(_ value: String) -> String {
        if value.utf8.allSatisfy({ $0 < 0x80 }) { return value.lowercased() }
        let scalars = Array(value.unicodeScalars)
        var result = String.UnicodeScalarView()
        for index in scalars.indices {
            let scalar = scalars[index]
            if scalar.value == 0x3A3 {
                result.append(isFinalSigma(scalars, at: index) ? "\u{3C2}" : "\u{3C3}")
            } else {
                result.append(contentsOf: scalar.properties.lowercaseMapping.unicodeScalars)
            }
        }
        return String(result)
    }

    /// Unicode SpecialCasing Final_Sigma, as ICU evaluates it: preceded by a
    /// cased letter and not followed by one, skipping case-ignorable scalars
    /// in both directions.
    private static func isFinalSigma(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        var before = index - 1
        var preceded = false
        while before >= 0 {
            let properties = scalars[before].properties
            if properties.isCaseIgnorable { before -= 1; continue }
            preceded = properties.isCased
            break
        }
        guard preceded else { return false }
        var after = index + 1
        while after < scalars.count {
            let properties = scalars[after].properties
            if properties.isCaseIgnorable { after += 1; continue }
            return !properties.isCased
        }
        return true
    }

    /// JS `a < b` on strings: UTF-16 code-unit order.
    static func utf16Less(_ lhs: String, _ rhs: String) -> Bool {
        utf16Compare(lhs, rhs) < 0
    }

    static func utf16Compare(_ lhs: String, _ rhs: String) -> Int {
        var left = lhs.utf16.makeIterator()
        var right = rhs.utf16.makeIterator()
        while true {
            switch (left.next(), right.next()) {
            case (nil, nil): return 0
            case (nil, _): return -1
            case (_, nil): return 1
            case let (l?, r?):
                if l != r { return l < r ? -1 : 1 }
            }
        }
    }

    /// `Object.entries(Object.fromEntries(items))` for unique keys: array-index
    /// keys first in ascending numeric order, then the rest as given.
    static func jsPropertyOrder<Item>(_ items: [Item], key: (Item) -> String) -> [Item] {
        var indexed: [(index: UInt64, item: Item)] = []
        var named: [Item] = []
        for item in items {
            if let index = arrayIndex(key(item)) { indexed.append((index, item)) } else { named.append(item) }
        }
        guard !indexed.isEmpty else { return items }
        // Keys are unique, so a plain sort by index is deterministic.
        return indexed.sorted { $0.index < $1.index }.map(\.item) + named
    }

    /// The value of a canonical array-index key: "0" or digits without a
    /// leading zero, at most 2^32 − 2.
    private static func arrayIndex(_ key: String) -> UInt64? {
        let bytes = Array(key.utf8)
        guard !bytes.isEmpty, bytes.count <= 10, bytes.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        if bytes.count > 1, bytes[0] == 0x30 { return nil }
        guard let value = UInt64(key), value <= 4_294_967_294 else { return nil }
        return value
    }
}

extension ModelAliasResolver {
    /// A string compared and hashed by its UTF-16 code units, the way a JS
    /// `Map`, `Set` or `===` sees it.
    fileprivate struct CodeUnits: Hashable, Sendable {
        let units: [UInt16]

        init(_ string: String) {
            units = Array(string.utf16)
        }
    }
}

/// The tuple `compareCanonicalCandidates` ranks a candidate by.
private struct CanonicalRank {
    let identityMismatch: Int
    let prefixed: Int
    let notLowercase: Int
    let hasSeparator: Int
    let length: Int
    let lowercased: String
    let leaf: String

    init(_ model: String, identity: String) {
        let leaf = ModelAliasResolver.modelLeaf(model)
        let lowered = ModelAliasResolver.jsLowercased(leaf)
        identityMismatch = ModelAliasResolver.matchKey(leaf).utf16.elementsEqual(identity.utf16) ? 0 : 1
        prefixed = model.utf16.elementsEqual(leaf.utf16) ? 0 : 1
        notLowercase = leaf.utf16.elementsEqual(lowered.utf16) ? 0 : 1
        hasSeparator = leaf.unicodeScalars.contains { $0 == "." || $0 == "_" || ModelAliasResolver.isJSWhitespace($0) } ? 1 : 0
        length = leaf.utf16.count
        self.lowercased = lowered
        self.leaf = leaf
    }

    func compare(to other: CanonicalRank) -> Int {
        let numbers = [
            (identityMismatch, other.identityMismatch),
            (prefixed, other.prefixed),
            (notLowercase, other.notLowercase),
            (hasSeparator, other.hasSeparator),
            (length, other.length)
        ]
        for (left, right) in numbers where left != right { return left < right ? -1 : 1 }
        let byLowercase = ModelAliasResolver.utf16Compare(lowercased, other.lowercased)
        if byLowercase != 0 { return byLowercase }
        return ModelAliasResolver.utf16Compare(leaf, other.leaf)
    }
}

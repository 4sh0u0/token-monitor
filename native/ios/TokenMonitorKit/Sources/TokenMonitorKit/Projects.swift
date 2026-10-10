import Foundation

/// One entry of `periods.*.projects`: a period's usage for one project
/// folder, merged across devices by its canonical (lower-case) label.
public struct ProjectRollup: Sendable, Hashable, Identifiable {
    /// The map key (the Hub's canonical project key).
    public var id: String
    /// The display label: the wire `label`, or the key when the label is
    /// missing, trimmed and NFC-normalized (`String(entry.label || rawKey)
    /// .trim().normalize('NFC')`). Empty only for a whitespace label, which
    /// the desktop skips.
    public var label: String
    public var tokens: Int
    /// The known (priced) subtotal in USD.
    public var costUsd: Double
    /// Tokens the cost excludes; nil when absent.
    public var unpricedTokens: Int?
    /// Tokens per client id.
    public var clients: [String: Int]

    public init(id: String, label: String, tokens: Int = 0, costUsd: Double = 0, unpricedTokens: Int? = nil, clients: [String: Int] = [:]) {
        self.id = id
        self.label = label
        self.tokens = tokens
        self.costUsd = costUsd
        self.unpricedTokens = unpricedTokens
        self.clients = clients
    }
}

extension ProjectRollup {
    enum WireKeys: String, CodingKey {
        case label, tokens, totalTokens, costUsd, cost, unpricedTokens, clients
    }

    init(key: String, wire container: KeyedDecodingContainer<WireKeys>) {
        let rawLabel = (try? container.decode(String.self, forKey: .label)) ?? ""
        let label = (rawLabel.isEmpty ? key : rawLabel)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        self.init(
            id: key,
            label: label,
            tokens: nonNegative(container.lenientInt(.tokens) ?? container.lenientInt(.totalTokens) ?? 0),
            costUsd: nonNegative(container.lenientDouble(.costUsd) ?? container.lenientDouble(.cost) ?? 0),
            unpricedTokens: container.lenientInt(.unpricedTokens).map(nonNegative),
            clients: container.lenientCountMap(.clients)
        )
    }

    /// A `projects` object. Entries that are not objects are dropped; the
    /// rest come back by tokens descending, then id.
    static func rollups<Key: CodingKey>(in container: KeyedDecodingContainer<Key>, forKey key: Key) -> [ProjectRollup] {
        guard !container.isNullOrMissing(key),
              let nested = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key) else { return [] }
        var rows: [ProjectRollup] = []
        rows.reserveCapacity(nested.allKeys.count)
        for entry in nested.allKeys {
            guard let fields = try? nested.nestedContainer(keyedBy: WireKeys.self, forKey: entry) else { continue }
            rows.append(ProjectRollup(key: entry.stringValue, wire: fields))
        }
        return rows.sorted { left, right in
            if left.tokens != right.tokens { return left.tokens > right.tokens }
            return left.id < right.id
        }
    }
}

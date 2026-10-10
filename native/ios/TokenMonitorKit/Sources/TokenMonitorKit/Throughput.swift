import Foundation

/// Raw throughput counters (`timedTokens`, `timedOutputTokens`,
/// `timedDurationMs`): sums over the usage entries that reported a duration.
/// A rate is a ratio, so these stay sums and are divided only at display time
/// (docs/API.md).
public struct ThroughputCounters: Sendable, Hashable, Codable {
    public var timedTokens: Double
    public var timedOutputTokens: Double
    public var timedDurationMs: Double

    /// The desktop's display cap for any token rate
    /// (`TOKEN_RATE_MAX_DISPLAY_RATE`).
    public static let maximumDisplayRate: Double = 1e12

    public static let zero = ThroughputCounters()

    public init(timedTokens: Double = 0, timedOutputTokens: Double = 0, timedDurationMs: Double = 0) {
        self.timedTokens = timedTokens
        self.timedOutputTokens = timedOutputTokens
        self.timedDurationMs = timedDurationMs
    }

    /// Output tokens per second (`tokenRatePerSecond`), nil when nothing was
    /// timed.
    public var outputTokensPerSecond: Double? {
        guard timedDurationMs > 0, timedOutputTokens > 0 else { return nil }
        return min(Self.maximumDisplayRate, timedOutputTokens * 1000 / timedDurationMs)
    }

    /// All timed tokens per minute (`tokenBurnPerMinute`), nil when nothing
    /// was timed.
    public var tokensPerMinute: Double? {
        guard timedDurationMs > 0, timedTokens > 0 else { return nil }
        return min(Self.maximumDisplayRate, timedTokens * 60000 / timedDurationMs)
    }
}

extension ThroughputCounters {
    enum WireKeys: String, CodingKey {
        case timedTokens, timedOutputTokens, timedDurationMs
    }

    /// `usageCounters()` in `tokenRatePresentation.js`: all three counters
    /// present as finite non-negative numbers (or numeric strings), else nil.
    init?(wire container: KeyedDecodingContainer<WireKeys>) {
        func counter(_ key: WireKeys) -> Double? {
            guard let value = container.lenientDouble(key), value >= 0 else { return nil }
            return value
        }
        guard let timedTokens = counter(.timedTokens),
              let timedOutputTokens = counter(.timedOutputTokens),
              let timedDurationMs = counter(.timedDurationMs) else { return nil }
        self.init(timedTokens: timedTokens, timedOutputTokens: timedOutputTokens, timedDurationMs: timedDurationMs)
    }

    /// A `modelThroughput` object: nil when the key is absent or not an
    /// object (an older producer), otherwise the models whose counters are
    /// complete (`modelCounters()`).
    static func modelMap<Key: CodingKey>(in container: KeyedDecodingContainer<Key>, forKey key: Key) -> [String: ThroughputCounters]? {
        guard !container.isNullOrMissing(key),
              let nested = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key) else { return nil }
        var result: [String: ThroughputCounters] = [:]
        for model in nested.allKeys {
            guard let counters = try? nested.nestedContainer(keyedBy: WireKeys.self, forKey: model),
                  let value = ThroughputCounters(wire: counters) else { continue }
            result[model.stringValue] = value
        }
        return result
    }
}

import Foundation

/// The Hub's three native periods. Raw values are the wire keys of
/// `periods.*` in `GET /api/stats`, and the `period` values of the
/// `tokenmonitor://dashboard?period=` deep link.
public enum UsagePeriodKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case today
    case month
    case allTime

    public var id: String { rawValue }
}

/// One row of a Tools or Models breakdown.
public struct UsageShare: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        case client
        case model
        /// Tokens the period total carries without a Tool/Model identity (or,
        /// in a snapshot, everything beyond the top rows). The UI names it
        /// with its own localized text ("Unclassified" / "Other").
        case remainder
    }

    /// The id of the synthetic remainder row.
    public static let remainderID = "__remainder"

    public var kind: Kind
    /// Client id (`claude`) or model name (`claude-sonnet-4-5`).
    public var id: String
    /// Display name. Clients use `VendorCatalog.clientLabel(_:)` (compact
    /// snapshots use `toolLabel(_:)`); models show their name; remainder rows
    /// carry the label the caller supplied.
    public var label: String
    public var tokens: Int
    public var costUsd: Double?
    /// Mark id for the icon and colour; nil for unrecognised models and
    /// remainder rows.
    public var vendorID: String?

    public init(kind: Kind, id: String, label: String, tokens: Int, costUsd: Double? = nil, vendorID: String? = nil) {
        self.kind = kind
        self.id = id
        self.label = label
        self.tokens = tokens
        self.costUsd = costUsd
        self.vendorID = vendorID
    }

    /// The paint for this row on dark surfaces.
    public var paint: VendorPaint {
        switch kind {
        case .client: return VendorCatalog.paint(for: vendorID ?? id)
        case .model: return VendorCatalog.modelPaint(for: id)
        case .remainder: return .hex(VendorCatalog.defaultColorHex)
        }
    }

    /// This row's share of `total` in 0...1 (0 when `total` is not positive).
    public func fraction(of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(tokens) / Double(total)))
    }

    static func client(_ id: String, tokens: Int, costUsd: Double?, compactLabel: Bool = false) -> UsageShare {
        UsageShare(
            kind: .client,
            id: id,
            label: compactLabel ? VendorCatalog.toolLabel(id) : VendorCatalog.clientLabel(id),
            tokens: tokens,
            costUsd: costUsd,
            vendorID: id
        )
    }

    static func model(_ name: String, tokens: Int, costUsd: Double?) -> UsageShare {
        UsageShare(kind: .model, id: name, label: name, tokens: tokens, costUsd: costUsd, vendorID: VendorCatalog.modelVendor(for: name))
    }

    static func remainder(label: String, tokens: Int, costUsd: Double? = nil) -> UsageShare {
        UsageShare(kind: .remainder, id: remainderID, label: label, tokens: tokens, costUsd: costUsd, vendorID: nil)
    }

    /// Tokens descending, then cost descending, then id — the desktop's and
    /// macOS widget's order, so equal rows never swap between refreshes.
    static func displayOrder(_ left: UsageShare, _ right: UsageShare) -> Bool {
        if left.tokens != right.tokens { return left.tokens > right.tokens }
        let leftCost = left.costUsd ?? 0
        let rightCost = right.costUsd ?? 0
        if leftCost != rightCost { return leftCost > rightCost }
        return left.id < right.id
    }
}

/// The token composition the desktop shows for a period (port of
/// `tokenComponentBreakdown()` in `src/electron/renderer/fixedPeriodRanges.js`).
///
/// `cacheMiss` is input that was not served from cache, so it includes cache
/// writes; `unclassified` is the remainder with no component provenance and is
/// displayed as its own row, never folded into cache miss.
public struct TokenComponents: Sendable, Hashable, Codable {
    public var cacheRead: Int
    public var cacheMiss: Int
    public var output: Int
    public var unclassified: Int

    public init(totalTokens: Int, cacheReadTokens: Int, outputTokens: Int, unclassifiedTokens: Int) {
        let total = max(0, totalTokens)
        let unclassified = min(total, max(0, unclassifiedTokens))
        let classified = total - unclassified
        let cacheRead = min(classified, max(0, cacheReadTokens))
        let output = min(classified - cacheRead, max(0, outputTokens))
        self.cacheRead = cacheRead
        self.output = output
        self.unclassified = unclassified
        cacheMiss = max(0, classified - cacheRead - output)
    }

    /// All input tokens: cache hits plus cache misses.
    public var input: Int { cacheRead + cacheMiss }

    public var total: Int { input + output + unclassified }

    /// Cache hits as a fraction of input, nil when there was no input.
    public var cacheHitFraction: Double? {
        input > 0 ? Double(cacheRead) / Double(input) : nil
    }
}

/// One key of a period's attribution maps (`clients`/`clientCosts`/
/// `clientUnpricedTokens`/`clientCacheReads`/… or the `model*` family).
///
/// Unlike `UsageShare`, nothing is filtered or sorted: every key present in
/// the token, cost or unpriced map has an entry, so the desktop's
/// `attributionRows()` can be ported over it unchanged. A component is nil
/// when its map does not carry the key (the desktop reads that as 0, or as
/// "no explicit value" for unclassified tokens; see `UnclassifiedPresence`).
public struct UsageBreakdownEntry: Sendable, Hashable {
    public var tokens: Int
    /// The known (priced) subtotal in USD.
    public var costUsd: Double
    public var unpricedTokens: Int?
    public var cacheReadTokens: Int?
    public var cacheWriteTokens: Int?
    public var outputTokens: Int?
    public var unclassifiedTokens: Int?

    public init(
        tokens: Int = 0,
        costUsd: Double = 0,
        unpricedTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        cacheWriteTokens: Int? = nil,
        outputTokens: Int? = nil,
        unclassifiedTokens: Int? = nil
    ) {
        self.tokens = tokens
        self.costUsd = costUsd
        self.unpricedTokens = unpricedTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.outputTokens = outputTokens
        self.unclassifiedTokens = unclassifiedTokens
    }
}

/// Which unclassified-token fields the wire carried at all
/// (`hasOwnProperty`), independent of their values. The desktop treats a
/// present map as explicit (a missing key is 0) and an absent one as "derive
/// the remainder" (`fixedPeriodRanges.js` `liveComponentValues`).
public struct UnclassifiedPresence: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// `unclassifiedTokens` on the period.
    public static let period = UnclassifiedPresence(rawValue: 1 << 0)
    /// `clientUnclassifiedTokens`.
    public static let clients = UnclassifiedPresence(rawValue: 1 << 1)
    /// `modelUnclassifiedTokens`.
    public static let models = UnclassifiedPresence(rawValue: 1 << 2)

    public static let all: UnclassifiedPresence = [.period, .clients, .models]
}

/// One aggregated period of `GET /api/stats` (`periods.today|month|allTime`).
///
/// The Hub sums every non-expired device into these totals; costs are the
/// known (priced) subtotal in USD.
public struct UsagePeriod: Sendable, Equatable {
    public var totalTokens: Int
    public var costUsd: Double
    /// Only when the wire carries it; aggregate periods currently do not —
    /// use `components.input` for the desktop's input figure.
    public var inputTokens: Int?
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int
    /// Tokens without component provenance (shown as "Unclassified").
    public var unclassifiedTokens: Int
    /// Only when the wire carries it (sessions do, aggregate periods do not).
    public var reasoningTokens: Int?
    /// Usage whose price was unavailable; `costUsd` excludes it. Nil when the
    /// Hub predates the field — never infer it from a zero cost.
    public var unpricedTokens: Int?
    /// Raw throughput counters (see docs/API.md): divide only at display time.
    public var timedTokens: Int
    public var timedOutputTokens: Int
    public var timedDurationMs: Double
    /// `capabilities.tokenComponents`: every component is exact.
    public var hasExactTokenComponents: Bool
    /// `capabilities.throughput`: every contributing device reported timing.
    public var hasCompleteThroughput: Bool
    /// Tools, sorted by tokens descending.
    public var clients: [UsageShare]
    /// Models, sorted by tokens descending.
    public var models: [UsageShare]
    /// Number of sessions in this period's session map (today/month only),
    /// whatever the decoding options.
    public var sessionCount: Int
    /// Every key of `clients`/`clientCosts`/`clientUnpricedTokens` with its
    /// components. Always decoded.
    public var clientBreakdown: [String: UsageBreakdownEntry]
    /// Every key of `models`/`modelCosts`/`modelUnpricedTokens` with its
    /// components. Always decoded.
    public var modelBreakdown: [String: UsageBreakdownEntry]
    /// Per client, its models (`clientModels`/`clientModelCosts`/
    /// `clientModelUnpricedTokens`). A client is present when either its
    /// token or cost map is an object; components are always nil.
    public var clientModels: [String: [String: UsageBreakdownEntry]]
    /// Per-model throughput counters; nil when the wire has no
    /// `modelThroughput` (aggregate month/allTime, older producers).
    public var modelThroughput: [String: ThroughputCounters]?
    /// The wire carried `clientModels` or `clientModelCosts` (an older Hub
    /// has neither, so tool rows cannot list their models).
    public var hasClientModels: Bool
    /// Which unclassified-token fields the wire carried.
    public var explicitUnclassified: UnclassifiedPresence
    /// The session rows, newest first. Only with
    /// `HubDecodingOptions.includeSessions`; empty otherwise.
    public var sessions: [HubSession]
    /// The project rollup, tokens descending. Only with
    /// `HubDecodingOptions.includeProjects`; empty otherwise.
    public var projects: [ProjectRollup]

    public init(
        totalTokens: Int = 0,
        costUsd: Double = 0,
        inputTokens: Int? = nil,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        unclassifiedTokens: Int = 0,
        reasoningTokens: Int? = nil,
        unpricedTokens: Int? = nil,
        timedTokens: Int = 0,
        timedOutputTokens: Int = 0,
        timedDurationMs: Double = 0,
        hasExactTokenComponents: Bool = true,
        hasCompleteThroughput: Bool = true,
        clients: [UsageShare] = [],
        models: [UsageShare] = [],
        sessionCount: Int = 0,
        clientBreakdown: [String: UsageBreakdownEntry] = [:],
        modelBreakdown: [String: UsageBreakdownEntry] = [:],
        clientModels: [String: [String: UsageBreakdownEntry]] = [:],
        modelThroughput: [String: ThroughputCounters]? = nil,
        hasClientModels: Bool = false,
        explicitUnclassified: UnclassifiedPresence = [],
        sessions: [HubSession] = [],
        projects: [ProjectRollup] = []
    ) {
        self.totalTokens = totalTokens
        self.costUsd = costUsd
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.unclassifiedTokens = unclassifiedTokens
        self.reasoningTokens = reasoningTokens
        self.unpricedTokens = unpricedTokens
        self.timedTokens = timedTokens
        self.timedOutputTokens = timedOutputTokens
        self.timedDurationMs = timedDurationMs
        self.hasExactTokenComponents = hasExactTokenComponents
        self.hasCompleteThroughput = hasCompleteThroughput
        self.clients = clients
        self.models = models
        self.sessionCount = sessionCount
        self.clientBreakdown = clientBreakdown
        self.modelBreakdown = modelBreakdown
        self.clientModels = clientModels
        self.modelThroughput = modelThroughput
        self.hasClientModels = hasClientModels
        self.explicitUnclassified = explicitUnclassified
        self.sessions = sessions
        self.projects = projects
    }

    public static let empty = UsagePeriod()

    /// The period's throughput counters as one value.
    public var throughput: ThroughputCounters {
        ThroughputCounters(
            timedTokens: Double(timedTokens),
            timedOutputTokens: Double(timedOutputTokens),
            timedDurationMs: timedDurationMs
        )
    }

    /// Output tokens per second over the timed entries (the desktop's
    /// `tokenRatePerSecond`), nil when nothing was timed.
    public var outputTokensPerSecond: Double? {
        guard timedDurationMs > 0, timedOutputTokens > 0 else { return nil }
        return min(1e12, Double(timedOutputTokens) * 1000 / timedDurationMs)
    }

    public var components: TokenComponents {
        TokenComponents(
            totalTokens: totalTokens,
            cacheReadTokens: cacheReadTokens,
            outputTokens: outputTokens,
            unclassifiedTokens: unclassifiedTokens
        )
    }

    /// Period tokens no Tool row accounts for.
    public var unattributedClientTokens: Int {
        max(0, totalTokens - clients.reduce(0) { $0 + $1.tokens })
    }

    /// Period tokens no Model row accounts for.
    public var unattributedModelTokens: Int {
        max(0, totalTokens - models.reduce(0) { $0 + $1.tokens })
    }

    /// Tools plus a synthetic remainder row (named by the caller) when the
    /// rows do not add up to the period total, so a stacked bar always
    /// represents the whole period — the convention docs/API.md asks for.
    public func clients(remainderLabel label: String) -> [UsageShare] {
        withRemainder(clients, tokens: unattributedClientTokens, label: label)
    }

    /// Models plus a synthetic remainder row, see `clients(remainderLabel:)`.
    public func models(remainderLabel label: String) -> [UsageShare] {
        withRemainder(models, tokens: unattributedModelTokens, label: label)
    }

    private func withRemainder(_ rows: [UsageShare], tokens: Int, label: String) -> [UsageShare] {
        guard tokens > 0 else { return rows }
        return rows + [UsageShare.remainder(label: label, tokens: tokens)]
    }
}

extension UsagePeriod: Decodable {
    private enum CodingKeys: String, CodingKey {
        case capabilities, totalTokens, costUsd, inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens
        case unclassifiedTokens, reasoningTokens, unpricedTokens, timedTokens, timedOutputTokens, timedDurationMs
        case clients, clientCosts, models, modelCosts, sessions
        case clientUnpricedTokens, clientCacheReads, clientCacheWrites, clientOutputs, clientUnclassifiedTokens
        case modelUnpricedTokens, modelCacheReads, modelCacheWrites, modelOutputs, modelUnclassifiedTokens
        case clientModels, clientModelCosts, clientModelUnpricedTokens, modelThroughput, projects
    }

    private enum CapabilityKeys: String, CodingKey {
        case tokenComponents, throughput
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let capabilities = try? container.nestedContainer(keyedBy: CapabilityKeys.self, forKey: .capabilities)
        totalTokens = nonNegative(container.lenientInt(.totalTokens) ?? 0)
        costUsd = nonNegative(container.lenientDouble(.costUsd) ?? 0)
        inputTokens = container.lenientInt(.inputTokens).map(nonNegative)
        outputTokens = nonNegative(container.lenientInt(.outputTokens) ?? 0)
        cacheReadTokens = nonNegative(container.lenientInt(.cacheReadTokens) ?? 0)
        cacheWriteTokens = nonNegative(container.lenientInt(.cacheWriteTokens) ?? 0)
        unclassifiedTokens = nonNegative(container.lenientInt(.unclassifiedTokens) ?? 0)
        reasoningTokens = container.lenientInt(.reasoningTokens).map(nonNegative)
        unpricedTokens = container.lenientInt(.unpricedTokens).map(nonNegative)
        timedTokens = nonNegative(container.lenientInt(.timedTokens) ?? 0)
        timedOutputTokens = nonNegative(container.lenientInt(.timedOutputTokens) ?? 0)
        timedDurationMs = nonNegative(container.lenientDouble(.timedDurationMs) ?? 0)
        // A missing marker is an older producer, which the desktop treats as
        // "not known to be exact".
        hasExactTokenComponents = capabilities?.lenientBool(.tokenComponents) ?? false
        hasCompleteThroughput = capabilities?.lenientBool(.throughput) ?? false
        let clientTokens = container.lenientNumberMap(.clients)
        let clientCosts = container.lenientNumberMap(.clientCosts)
        let modelTokens = container.lenientNumberMap(.models)
        let modelCosts = container.lenientNumberMap(.modelCosts)
        clients = Self.shares(tokens: clientTokens, costs: clientCosts) { id, tokens, cost in
            UsageShare.client(id, tokens: tokens, costUsd: cost)
        }
        models = Self.shares(tokens: modelTokens, costs: modelCosts) { name, tokens, cost in
            UsageShare.model(name, tokens: tokens, costUsd: cost)
        }
        sessionCount = container.lenientKeyCount(.sessions)

        clientBreakdown = Self.breakdown(
            tokens: clientTokens,
            costs: clientCosts,
            unpriced: container.lenientNumberMap(.clientUnpricedTokens),
            cacheReads: container.lenientNumberMap(.clientCacheReads),
            cacheWrites: container.lenientNumberMap(.clientCacheWrites),
            outputs: container.lenientNumberMap(.clientOutputs),
            unclassified: container.lenientNumberMap(.clientUnclassifiedTokens)
        )
        modelBreakdown = Self.breakdown(
            tokens: modelTokens,
            costs: modelCosts,
            unpriced: container.lenientNumberMap(.modelUnpricedTokens),
            cacheReads: container.lenientNumberMap(.modelCacheReads),
            cacheWrites: container.lenientNumberMap(.modelCacheWrites),
            outputs: container.lenientNumberMap(.modelOutputs),
            unclassified: container.lenientNumberMap(.modelUnclassifiedTokens)
        )
        let perClientTokens = container.lenientNestedNumberMaps(.clientModels)
        let perClientCosts = container.lenientNestedNumberMaps(.clientModelCosts)
        let perClientUnpriced = container.lenientNestedNumberMaps(.clientModelUnpricedTokens)
        var clientModels: [String: [String: UsageBreakdownEntry]] = [:]
        for client in Set(perClientTokens.keys).union(perClientCosts.keys) {
            clientModels[client] = Self.breakdown(
                tokens: perClientTokens[client] ?? [:],
                costs: perClientCosts[client] ?? [:],
                unpriced: perClientUnpriced[client] ?? [:]
            )
        }
        self.clientModels = clientModels
        hasClientModels = container.isObject(.clientModels) || container.isObject(.clientModelCosts)
        modelThroughput = ThroughputCounters.modelMap(in: container, forKey: .modelThroughput)
        var presence: UnclassifiedPresence = []
        if container.contains(.unclassifiedTokens) { presence.insert(.period) }
        if container.contains(.clientUnclassifiedTokens) { presence.insert(.clients) }
        if container.contains(.modelUnclassifiedTokens) { presence.insert(.models) }
        explicitUnclassified = presence

        let options = decoder.hubDecodingOptions
        sessions = options.includeSessions ? HubSession.sessions(in: container, forKey: .sessions) : []
        projects = options.includeProjects ? ProjectRollup.rollups(in: container, forKey: .projects) : []
    }

    /// One entry per key of the token, cost and unpriced maps (the desktop's
    /// `attributionRows()` key set), with whatever components carry that key.
    static func breakdown(
        tokens: [String: Double],
        costs: [String: Double],
        unpriced: [String: Double],
        cacheReads: [String: Double] = [:],
        cacheWrites: [String: Double] = [:],
        outputs: [String: Double] = [:],
        unclassified: [String: Double] = [:]
    ) -> [String: UsageBreakdownEntry] {
        func count(_ value: Double?) -> Int? { value.map { nonNegative(clampedInt($0)) } }
        var result: [String: UsageBreakdownEntry] = [:]
        result.reserveCapacity(tokens.count)
        for key in Set(tokens.keys).union(costs.keys).union(unpriced.keys) where !key.isEmpty {
            result[key] = UsageBreakdownEntry(
                tokens: count(tokens[key]) ?? 0,
                costUsd: nonNegative(costs[key] ?? 0),
                unpricedTokens: count(unpriced[key]),
                cacheReadTokens: count(cacheReads[key]),
                cacheWriteTokens: count(cacheWrites[key]),
                outputTokens: count(outputs[key]),
                unclassifiedTokens: count(unclassified[key])
            )
        }
        return result
    }

    static func shares(
        tokens: [String: Double],
        costs: [String: Double],
        make: (String, Int, Double?) -> UsageShare
    ) -> [UsageShare] {
        var rows: [UsageShare] = []
        rows.reserveCapacity(tokens.count)
        for (key, value) in tokens {
            let id = key.trimmingCharacters(in: .whitespacesAndNewlines)
            // `__`-prefixed keys are internal partitions (e.g. `__unattributed`);
            // their tokens surface through the remainder row instead.
            guard !id.isEmpty, !id.hasPrefix("__") else { continue }
            let tokenCount = nonNegative(clampedInt(value))
            let cost = costs[key].map(nonNegative)
            guard tokenCount > 0 || (cost ?? 0) > 0 else { continue }
            rows.append(make(id, tokenCount, cost))
        }
        return rows.sorted(by: UsageShare.displayOrder)
    }
}

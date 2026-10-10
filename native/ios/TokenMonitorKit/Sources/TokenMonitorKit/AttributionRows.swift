import Foundation

// Port of `src/electron/renderer/usageAttributionRows.js` and
// `src/electron/renderer/toolDetails.js` as `app.js` composes them
// (`toolRowsForPeriod`, `modelRowsForPeriod`, `attributionComponent`): the
// Tools and Models views, each tool's models, and the token components every
// row expands to.

/// A row of the Tools or Models view (or a tool's model list).
public struct AttributionRow: Sendable, Hashable, Identifiable {
    /// The client or model id; `AttributionRows.unattributedKey` for the
    /// remainder no tool or model claimed ("Unclassified",
    /// `dashboard.tooltip.unclassified`).
    public var key: String
    /// The synthetic remainder row.
    public var isUnattributed: Bool
    public var tokens: Int
    /// The known (priced) subtotal in USD.
    public var costUsd: Double
    /// Tokens the cost leaves out; nil when none.
    public var unpricedTokens: Int?
    /// Components (`clientCacheReads`/`modelCacheReads` …; for the remainder
    /// row, the period total minus every row's). 0 for a tool's model rows,
    /// which the wire gives no components.
    public var cacheRead: Int
    public var cacheWrite: Int
    public var output: Int
    public var unclassified: Int
    /// What the row's bar measures: tokens, or cost when models rank by
    /// cost (`rankRowsWithValues`).
    public var barValue: Double
    /// A tool's model rows only: the share of that tool's tokens, 0–100.
    public var percent: Double?
    /// The `unknown` model row only: `codex` when Codex accounts for all of
    /// it (`unknownModelSource`), so it can wear the Codex mark.
    public var modelSource: String?
    /// Tool rows only: the tool's models (`visibleModelRowsForTool`).
    public var modelRows: [AttributionRow]

    public init(
        key: String,
        isUnattributed: Bool = false,
        tokens: Int,
        costUsd: Double,
        unpricedTokens: Int? = nil,
        cacheRead: Int = 0,
        cacheWrite: Int = 0,
        output: Int = 0,
        unclassified: Int = 0,
        barValue: Double = 0,
        percent: Double? = nil,
        modelSource: String? = nil,
        modelRows: [AttributionRow] = []
    ) {
        self.key = key
        self.isUnattributed = isUnattributed
        self.tokens = tokens
        self.costUsd = costUsd
        self.unpricedTokens = unpricedTokens
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.output = output
        self.unclassified = unclassified
        self.barValue = barValue
        self.percent = percent
        self.modelSource = modelSource
        self.modelRows = modelRows
    }

    public var id: String { key }

    /// `tokenComponentBreakdown` of this row: cache hit, cache miss, output
    /// and unclassified, clamped to its tokens.
    public var components: TokenComponents {
        TokenComponents(totalTokens: tokens, cacheReadTokens: cacheRead, outputTokens: output, unclassifiedTokens: unclassified)
    }
}

/// `tokenInputPercentages`: cache hits and misses as shares of input.
public struct InputPercentages: Sendable, Hashable {
    public var hit: Double
    public var miss: Double

    public init(hit: Double, miss: Double) {
        self.hit = hit
        self.miss = miss
    }

    /// `tokenComponentBreakdown`'s `hitPct`: the hit share rounded.
    public var roundedHit: Int { Int(JSCompat.round(hit)) }
    /// `missPct`: `100 - hitPct` when there is input, else 0.
    public var roundedMiss: Int { hit > 0 || miss > 0 ? 100 - roundedHit : 0 }
}

public enum AttributionRows {
    /// `UNATTRIBUTED_KEY`.
    public static let unattributedKey = "__unattributed"

    // MARK: Tools

    /// `toolRowsForPeriod`: the period's tools (and the Unclassified
    /// remainder) by tokens, then hidden, pinned and ordered with
    /// `ClientDisplayOrder` against `known` (the desktop's
    /// `KNOWN_CLIENT_LIST`). Each carries its components and models.
    ///
    /// An empty result for a period with tokens means the Hub sent no tool
    /// split; the desktop then lists devices instead.
    public static func toolRows(
        period: UsagePeriod,
        prefs: DisplayPreferences,
        known: [String] = VendorCatalog.trackedClientIDs,
        formatter: DisplayFormatter = DisplayFormatter()
    ) -> [AttributionRow] {
        ClientDisplayOrder.apply(usageToolRows(period: period, formatter: formatter), id: \.key, preferences: prefs, known: known)
    }

    /// The tool rows before display preferences: tokens descending (ties by
    /// id, the remainder last; the desktop keeps wire order there).
    public static func usageToolRows(period: UsagePeriod, formatter: DisplayFormatter = DisplayFormatter()) -> [AttributionRow] {
        let breakdown = period.clientBreakdown
        let rows = visible(
            attributionRows(breakdown, totalTokens: period.totalTokens, totalCost: period.costUsd, totalUnpriced: period.unpricedTokens),
            formatter: formatter
        ).map { raw -> AttributionRow in
            var row = componentRow(raw, breakdown: breakdown, period: period)
            row.barValue = Double(row.tokens)
            row.modelRows = raw.isUnattributed ? [] : modelRowsForTool(period: period, client: raw.key, formatter: formatter)
            return row
        }
        return rows.sorted { left, right in
            if left.tokens != right.tokens { return left.tokens > right.tokens }
            if left.isUnattributed != right.isUnattributed { return right.isUnattributed }
            return left.key.utf16.lexicographicallyPrecedes(right.key.utf16)
        }
    }

    // MARK: Models

    /// `modelRowsForPeriod`: the period's models (and the Unclassified
    /// remainder) ranked by `ranking` — cost only when some model has a
    /// known cost — then tokens, then id.
    public static func modelRows(
        period: UsagePeriod,
        ranking: RankingMetric = .tokens,
        formatter: DisplayFormatter = DisplayFormatter()
    ) -> [AttributionRow] {
        let breakdown = period.modelBreakdown
        let source = unknownModelSource(period: period)
        let rows = visible(
            attributionRows(breakdown, totalTokens: period.totalTokens, totalCost: period.costUsd, totalUnpriced: period.unpricedTokens),
            formatter: formatter
        ).map { raw -> AttributionRow in
            var row = componentRow(raw, breakdown: breakdown, period: period)
            if raw.key == "unknown" { row.modelSource = source }
            return row
        }
        return rank(rows, metric: ranking)
    }

    /// `visibleModelRowsForTool`: one tool's models (`clientModels`) with
    /// their share of the tool, plus an Unclassified remainder; by tokens,
    /// cost, then id. Empty when the Hub sent no models for the tool.
    public static func modelRowsForTool(
        period: UsagePeriod,
        client: String,
        formatter: DisplayFormatter = DisplayFormatter()
    ) -> [AttributionRow] {
        let key = ModelAliasResolver.jsTrimmed(client)
        guard !key.isEmpty, let models = period.clientModels[key] else { return [] }
        let tool = period.clientBreakdown[key]
        let total = max(0, tool?.tokens ?? 0)
        let rows = attributionRows(models, totalTokens: total, totalCost: max(0, tool?.costUsd ?? 0), totalUnpriced: tool?.unpricedTokens)
            .map { raw in
                AttributionRow(
                    key: raw.key,
                    isUnattributed: raw.isUnattributed,
                    tokens: max(0, raw.tokens),
                    costUsd: max(0, raw.cost),
                    unpricedTokens: raw.unpriced,
                    barValue: Double(max(0, raw.tokens)),
                    percent: total > 0 ? min(100, Double(max(0, raw.tokens)) / Double(total) * 100) : 0
                )
            }
            .sorted { left, right in
                if left.tokens != right.tokens { return left.tokens > right.tokens }
                if left.costUsd != right.costUsd { return left.costUsd > right.costUsd }
                return precedes(left.key, right.key)
            }
        return rows.filter { isVisible($0, formatter: formatter) }
    }

    /// `rankRowsWithValues`: sorted by the effective metric (cost, then
    /// tokens, then id; or tokens, then id), `barValue` set to that metric.
    public static func rank(_ rows: [AttributionRow], metric: RankingMetric) -> [AttributionRow] {
        let effective = effectiveRankingMetric(rows, metric: metric)
        return rows.sorted { left, right in
            if effective == .cost, left.costUsd != right.costUsd { return left.costUsd > right.costUsd }
            if left.tokens != right.tokens { return left.tokens > right.tokens }
            return precedes(left.key, right.key)
        }.map { row in
            var row = row
            row.barValue = max(0, effective == .cost ? row.costUsd : Double(row.tokens))
            return row
        }
    }

    /// `effectiveRankingMetric`: cost ranking needs a known cost on some
    /// non-remainder row; otherwise rows rank by tokens.
    public static func effectiveRankingMetric(_ rows: [AttributionRow], metric: RankingMetric) -> RankingMetric {
        metric == .cost && rows.contains { !$0.isUnattributed && $0.costUsd > 0 } ? .cost : .tokens
    }

    /// `unknownModelSource`: `codex` when the period's `unknown` model
    /// tokens all come from Codex, else nil.
    public static func unknownModelSource(period: UsagePeriod) -> String? {
        guard let total = period.modelBreakdown["unknown"]?.tokens, total > 0 else { return nil }
        guard period.clientModels["codex"]?["unknown"]?.tokens == total else { return nil }
        for (client, models) in period.clientModels where client != "codex" && (models["unknown"]?.tokens ?? 0) > 0 {
            return nil
        }
        return "codex"
    }

    // MARK: Labels

    /// `detailPercentLabel`: `"<1%"` for a sliver, else the rounded percent
    /// capped at 100.
    public static func detailPercentLabel(_ percent: Double) -> String {
        let value = percent.isFinite ? max(0, percent) : 0
        if value > 0, value < 1 { return "<1%" }
        return "\(Int(JSCompat.round(min(100, value))))%"
    }

    /// `tokenInputPercentages` of a component breakdown.
    public static func inputPercentages(_ components: TokenComponents) -> InputPercentages {
        let input = Double(components.cacheRead + components.cacheMiss)
        guard input > 0 else { return InputPercentages(hit: 0, miss: 0) }
        return InputPercentages(hit: Double(components.cacheRead) / input * 100, miss: Double(components.cacheMiss) / input * 100)
    }

    /// `visibleAttributionRows`: a remainder row shows only when it has
    /// tokens, unpriced tokens, or a cost that does not format as zero.
    public static func isVisible(_ row: AttributionRow, formatter: DisplayFormatter = DisplayFormatter()) -> Bool {
        !row.isUnattributed
            || row.tokens > 0
            || (row.unpricedTokens ?? 0) > 0
            || formatter.cost(row.costUsd) != formatter.cost(0)
    }

    // MARK: Port internals

    /// One `attributionRows` entry before components.
    struct RawRow: Hashable {
        var key: String
        var tokens: Int
        var cost: Double
        var unpriced: Int?
        var isUnattributed: Bool
    }

    /// `attributionRows`: every key with tokens, cost or unpriced tokens,
    /// then a remainder row for whatever the totals leave over (its cost
    /// rounded to 6 places, as the Hub rounds costs).
    static func attributionRows(
        _ breakdown: [String: UsageBreakdownEntry],
        totalTokens: Int,
        totalCost: Double,
        totalUnpriced: Int?
    ) -> [RawRow] {
        var rows: [RawRow] = []
        for key in breakdown.keys.sorted(by: { $0.utf16.lexicographicallyPrecedes($1.utf16) }) {
            guard let entry = breakdown[key] else { continue }
            let unpriced = (entry.unpricedTokens ?? 0) > 0 ? entry.unpricedTokens : nil
            guard entry.tokens > 0 || entry.costUsd > 0 || unpriced != nil else { continue }
            rows.append(RawRow(key: key, tokens: entry.tokens, cost: entry.costUsd, unpriced: unpriced, isUnattributed: false))
        }
        let attributedTokens = rows.reduce(0) { $0 + max(0, $1.tokens) }
        let attributedCost = rows.reduce(0.0) { $0 + max(0, $1.cost) }
        let attributedUnpriced = rows.reduce(0) { $0 + max(0, $1.unpriced ?? 0) }
        let remainderTokens = max(0, totalTokens - attributedTokens)
        let rounded = Double(JSCompat.toFixed(totalCost - attributedCost, 6)) ?? 0
        let remainderCost = rounded > 0 ? rounded : 0
        let remainderUnpriced = max(0, (totalUnpriced ?? 0) - attributedUnpriced)
        if remainderTokens > 0 || remainderCost > 0 || remainderUnpriced > 0 {
            rows.append(RawRow(
                key: unattributedKey,
                tokens: remainderTokens,
                cost: remainderCost,
                unpriced: remainderUnpriced > 0 ? remainderUnpriced : nil,
                isUnattributed: true
            ))
        }
        return rows
    }

    static func visible(_ rows: [RawRow], formatter: DisplayFormatter) -> [RawRow] {
        rows.filter { row in
            !row.isUnattributed
                || row.tokens > 0
                || (row.unpriced ?? 0) > 0
                || formatter.cost(row.cost) != formatter.cost(0)
        }
    }

    /// The row with `attributionComponent` values: the key's own component,
    /// or for the remainder the period total minus every key's.
    static func componentRow(_ raw: RawRow, breakdown: [String: UsageBreakdownEntry], period: UsagePeriod) -> AttributionRow {
        func component(_ field: KeyPath<UsageBreakdownEntry, Int?>, total: Int) -> Int {
            guard raw.key == unattributedKey else { return breakdown[raw.key]?[keyPath: field] ?? 0 }
            let attributed = breakdown.values.reduce(0) { $0 + max(0, $1[keyPath: field] ?? 0) }
            return max(0, total - attributed)
        }
        return AttributionRow(
            key: raw.key,
            isUnattributed: raw.isUnattributed,
            tokens: raw.tokens,
            costUsd: raw.cost,
            unpricedTokens: raw.unpriced,
            cacheRead: component(\.cacheReadTokens, total: period.cacheReadTokens),
            cacheWrite: component(\.cacheWriteTokens, total: period.cacheWriteTokens),
            output: component(\.outputTokens, total: period.outputTokens),
            unclassified: component(\.unclassifiedTokens, total: period.unclassifiedTokens),
            barValue: Double(raw.tokens)
        )
    }

    /// `localeCompare` order, made total by UTF-16 order.
    static func precedes(_ left: String, _ right: String) -> Bool {
        let order = UsageRowCollation.compare(left, right)
        return order != 0 ? order < 0 : left.utf16.lexicographicallyPrecedes(right.utf16)
    }
}

import Foundation

// Port of `src/electron/modelAliasPresentation.js` (projectModelAliasStats,
// projectModelAliasHistory, projectModelAliasSessions): the Hub aggregates raw
// model ids and each reader folds them through the shared aliases.
//
// - Every model-keyed map is regrouped by the resolved name and its numbers
//   are summed (`foldModelMap`, `foldModelThroughput`); tool rows are never
//   touched.
// - History buckets merge field by field, and a merged model's unclassified
//   tokens become the sum of both sides' (`mergeHistoryModel`), so folding a
//   monthly bucket (no components) marks the merged model fully unclassified.
// - `summary.favoriteModel` is re-ranked over the grouped rows where the
//   window is known (aggregate History: `daily`; a device's History: only
//   when `daily` and `monthly` agree), else renamed (the stats preview).
// - Stats revisions gain `:aliases:<hash of the plan>` so History caches keyed
//   by them follow alias changes; an absent revision stays absent.
//
// Swift dictionaries have no insertion order, so summation and ties walk keys
// in UTF-16 order (the desktop walks wire order); only the last bits of a sum
// of three or more costs, or an exact tie, can differ.

extension ModelAliasResolver {
    /// The resolver for a stats payload (`aliasPlan` over
    /// `collectStatsModelIds`), nil when it would change nothing — no
    /// document, a group never initialized, or no alias and no inferred
    /// group — so callers skip the projection.
    public static func forStats(_ stats: HubStats, document: ModelAliasDocument?) -> ModelAliasResolver? {
        guard let document, document.isInitialized else { return nil }
        // Collecting the observed ids walks the payload, so only when
        // automatic grouping needs them (as on the desktop).
        let observed = document.grouping == .off ? [] : stats.observedModelIDs
        let resolver = ModelAliasResolver(document: document, observedModels: observed)
        return resolver.isActive ? resolver : nil
    }

    /// The resolver for `GET /api/history` and the `GET /api/devices`
    /// History records shown with it (`projectModelAliasHistory` over
    /// `collectHistoryModelIds`); nil when it would change nothing.
    public static func forHistory(
        _ history: HubHistory?,
        records: [DeviceHistoryRecord] = [],
        document: ModelAliasDocument?
    ) -> ModelAliasResolver? {
        guard let document, document.isInitialized else { return nil }
        var observed: [String] = []
        if document.grouping != .off {
            var collector = ModelIDCollector()
            if let history { collector.add(history) }
            for record in records {
                if let today = record.today { collector.add(today) }
                if let history = record.history { collector.add(history) }
            }
            observed = collector.ids
        }
        let resolver = ModelAliasResolver(document: document, observedModels: observed)
        return resolver.isActive ? resolver : nil
    }

    /// `historyRevision({summary: {modelAliases, automaticModelAliases}})`:
    /// the hash of this resolver's explicit and inferred aliases that the
    /// desktop appends to stats revisions (16 hex digits).
    public var revisionSuffix: String {
        func object(_ pairs: [ModelAliasPair]) -> String {
            var byAlias: [String: String] = [:]
            for pair in pairs where byAlias[pair.alias] == nil { byAlias[pair.alias] = pair.canonical }
            let entries = byAlias.keys.sorted(by: Self.utf16Less).map { key in
                "\(JSCompat.jsonQuoted(key)):\(JSCompat.jsonQuoted(byAlias[key] ?? ""))"
            }
            return "{\(entries.joined(separator: ","))}"
        }
        let summary = "{\"automaticModelAliases\":\(object(inferredAliases)),\"modelAliases\":\(object(explicitAliases))}"
        return StableHash.hex("{\"daily\":[],\"monthly\":[],\"summary\":\(summary)}", length: 16)
    }

    /// `resolve(model) !== model`, by UTF-16 code units.
    fileprivate func renames(_ model: String) -> Bool {
        !resolve(model).utf16.elementsEqual(model.utf16)
    }
}

// MARK: - Observed model ids

extension HubStats {
    /// Every model id these stats show (`collectStatsModelIds`): the model
    /// maps, per-tool models, throughput and sessions of each period, the
    /// same for every decoded device period, and the preview's favourite
    /// model. Trimmed, non-empty, each once; periods in today/month/allTime
    /// order, ids of one map in UTF-16 order.
    public var observedModelIDs: [String] {
        var collector = ModelIDCollector()
        for kind in UsagePeriodKind.allCases { collector.add(self[kind]) }
        for device in devices {
            for kind in UsagePeriodKind.allCases {
                if let detail = device.detail(kind) { collector.add(detail) }
                collector.add(keys: device.usage(kind).modelThroughput?.keys)
            }
        }
        if let favorite = historyPreviewSummary?.favoriteModel { collector.add(favorite) }
        return collector.ids
    }
}

extension HubHistory {
    /// Every model id this History shows (`collectHistoryModelIds`).
    public var observedModelIDs: [String] {
        var collector = ModelIDCollector()
        collector.add(self)
        return collector.ids
    }
}

/// Collects model ids in first-seen order, trimmed like `addModelId`.
private struct ModelIDCollector {
    private(set) var ids: [String] = []
    private var seen = Set<[UInt16]>()

    mutating func add(_ model: String) {
        let trimmed = ModelAliasResolver.jsTrimmed(model)
        guard !trimmed.isEmpty, seen.insert(Array(trimmed.utf16)).inserted else { return }
        ids.append(trimmed)
    }

    mutating func add<Keys: Sequence>(keys: Keys?) where Keys.Element == String {
        guard let keys else { return }
        for key in keys.sorted(by: ModelAliasResolver.utf16Less) { add(key) }
    }

    mutating func add(_ period: UsagePeriod) {
        add(keys: period.modelBreakdown.keys)
        add(keys: period.modelThroughput?.keys)
        for client in period.clientModels.keys.sorted(by: ModelAliasResolver.utf16Less) {
            add(keys: period.clientModels[client]?.keys)
        }
        for session in period.sessions {
            add(keys: session.models.keys)
            add(keys: session.modelCosts.keys)
        }
    }

    mutating func add(_ history: HubHistory) {
        for day in history.daily { add(keys: day.perModel.keys) }
        for month in history.monthly { add(keys: month.perModel.keys) }
        if let favorite = history.summary?.favoriteModel { add(favorite) }
    }
}

// MARK: - Folding

private enum ModelFold {
    /// `foldModelMap` with a custom merge: the map unchanged when no key
    /// renames, else regrouped by resolved name in UTF-16 key order.
    static func map<Value>(
        _ values: [String: Value],
        _ resolver: ModelAliasResolver,
        merge: (Value, Value) -> Value
    ) -> [String: Value] {
        guard values.keys.contains(where: resolver.renames) else { return values }
        var result: [String: Value] = [:]
        result.reserveCapacity(values.count)
        for key in values.keys.sorted(by: ModelAliasResolver.utf16Less) {
            guard let value = values[key] else { continue }
            let target = resolver.resolve(key)
            result[target] = result[target].map { merge($0, value) } ?? value
        }
        return result
    }

    static func sum(_ left: Int?, _ right: Int?) -> Int? {
        guard left != nil || right != nil else { return nil }
        return saturatingAdd(left ?? 0, right ?? 0)
    }

    static func sum(_ left: Double?, _ right: Double?) -> Double? {
        guard left != nil || right != nil else { return nil }
        return (left ?? 0) + (right ?? 0)
    }

    /// Each component map folds on its own, so a component only one side
    /// carries is kept and two are added.
    static func entry(_ left: UsageBreakdownEntry, _ right: UsageBreakdownEntry) -> UsageBreakdownEntry {
        UsageBreakdownEntry(
            tokens: saturatingAdd(left.tokens, right.tokens),
            costUsd: left.costUsd + right.costUsd,
            unpricedTokens: sum(left.unpricedTokens, right.unpricedTokens),
            cacheReadTokens: sum(left.cacheReadTokens, right.cacheReadTokens),
            cacheWriteTokens: sum(left.cacheWriteTokens, right.cacheWriteTokens),
            outputTokens: sum(left.outputTokens, right.outputTokens),
            unclassifiedTokens: sum(left.unclassifiedTokens, right.unclassifiedTokens)
        )
    }

    static func throughput(_ left: ThroughputCounters, _ right: ThroughputCounters) -> ThroughputCounters {
        ThroughputCounters(
            timedTokens: left.timedTokens + right.timedTokens,
            timedOutputTokens: left.timedOutputTokens + right.timedOutputTokens,
            timedDurationMs: left.timedDurationMs + right.timedDurationMs
        )
    }

    /// The `models` rows rebuilt from the folded `models`/`modelCosts` maps:
    /// tokens and costs added (a cost stays nil only when no folded row had
    /// one), the vendor re-resolved for the new name, display order again.
    static func shares(_ rows: [UsageShare], _ resolver: ModelAliasResolver) -> [UsageShare] {
        guard rows.contains(where: { resolver.renames($0.id) }) else { return rows }
        var order: [String] = []
        var grouped: [String: (tokens: Int, cost: Double?)] = [:]
        for row in rows.sorted(by: { ModelAliasResolver.utf16Less($0.id, $1.id) }) {
            let name = resolver.resolve(row.id)
            if let existing = grouped[name] {
                grouped[name] = (saturatingAdd(existing.tokens, row.tokens), sum(existing.cost, row.costUsd))
            } else {
                order.append(name)
                grouped[name] = (row.tokens, row.costUsd)
            }
        }
        return order.compactMap { name in
            grouped[name].map { UsageShare.model(name, tokens: $0.tokens, costUsd: $0.cost) }
        }
        .sorted(by: UsageShare.displayOrder)
    }

    /// `mergeHistoryModel`: every number added; once two buckets merge, the
    /// unclassified tokens are both sides' (`unclassifiedTokensFor`, which
    /// counts a bucket without the field as wholly unclassified).
    static func bucket(_ previous: HistoryBucket, _ bucket: HistoryBucket) -> HistoryBucket {
        var merged = previous
        merged.tokens = saturatingAdd(previous.tokens, bucket.tokens)
        merged.costUsd = previous.costUsd + bucket.costUsd
        merged.messages = saturatingAdd(previous.messages, bucket.messages)
        merged.unpricedTokens = sum(previous.unpricedTokens, bucket.unpricedTokens)
        merged.cacheReadTokens = sum(previous.cacheReadTokens, bucket.cacheReadTokens)
        merged.cacheWriteTokens = sum(previous.cacheWriteTokens, bucket.cacheWriteTokens)
        merged.outputTokens = sum(previous.outputTokens, bucket.outputTokens)
        merged.unclassifiedTokens = saturatingAdd(previous.resolvedUnclassifiedTokens, bucket.resolvedUnclassifiedTokens)
        return merged
    }

    static func buckets(_ values: [String: HistoryBucket], _ resolver: ModelAliasResolver) -> [String: HistoryBucket] {
        map(values, resolver, merge: bucket)
    }

    /// `groupedLeader`: the model with the most tokens over `rows` once
    /// grouped, nil when no row has models. A tie goes to the model seen
    /// first (earliest row, then UTF-16 order within a row).
    static func leader(_ rows: [[String: HistoryBucket]], _ resolver: ModelAliasResolver) -> String? {
        var totals: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var position = 0
        for perModel in rows {
            for model in perModel.keys.sorted(by: ModelAliasResolver.utf16Less) {
                let name = resolver.resolve(model)
                totals[name] = saturatingAdd(totals[name] ?? 0, perModel[model]?.tokens ?? 0)
                if firstSeen[name] == nil {
                    firstSeen[name] = position
                    position += 1
                }
            }
        }
        return totals.min { left, right in
            if left.value != right.value { return left.value > right.value }
            return (firstSeen[left.key] ?? 0) < (firstSeen[right.key] ?? 0)
        }?.key
    }
}

// MARK: - Stats

extension UsagePeriod {
    /// The period with model ids folded through `resolver`
    /// (`projectUsage`): `models`, `modelBreakdown`, every tool's models,
    /// `modelThroughput` and each session's models. Totals and tool rows are
    /// unchanged.
    public func projectingModelAliases(_ resolver: ModelAliasResolver) -> UsagePeriod {
        guard resolver.isActive else { return self }
        var copy = self
        copy.models = ModelFold.shares(models, resolver)
        copy.modelBreakdown = ModelFold.map(modelBreakdown, resolver, merge: ModelFold.entry)
        copy.clientModels = clientModels.mapValues { ModelFold.map($0, resolver, merge: ModelFold.entry) }
        copy.modelThroughput = modelThroughput.map { ModelFold.map($0, resolver, merge: ModelFold.throughput) }
        copy.sessions = sessions.map { $0.projectingModelAliases(resolver) }
        return copy
    }
}

extension HubSession {
    /// The session with its `models` and `modelCosts` folded through
    /// `resolver`.
    public func projectingModelAliases(_ resolver: ModelAliasResolver) -> HubSession {
        guard resolver.isActive else { return self }
        var copy = self
        copy.models = ModelFold.map(models, resolver, merge: saturatingAdd)
        copy.modelCosts = ModelFold.map(modelCosts, resolver, merge: +)
        return copy
    }
}

extension DeviceUsage {
    /// The device period with its `modelThroughput` folded.
    public func projectingModelAliases(_ resolver: ModelAliasResolver) -> DeviceUsage {
        guard resolver.isActive, let modelThroughput else { return self }
        var copy = self
        copy.modelThroughput = ModelFold.map(modelThroughput, resolver, merge: ModelFold.throughput)
        return copy
    }
}

extension DeviceSummary {
    /// The device with every decoded period folded.
    public func projectingModelAliases(_ resolver: ModelAliasResolver) -> DeviceSummary {
        guard resolver.isActive else { return self }
        var copy = self
        copy.today = today.projectingModelAliases(resolver)
        copy.month = month.projectingModelAliases(resolver)
        copy.allTime = allTime.projectingModelAliases(resolver)
        copy.details = details.mapValues { $0.projectingModelAliases(resolver) }
        return copy
    }
}

extension HubStats {
    /// `projectModelAliasStats`: every period, device period and session
    /// folded; the preview's favourite model renamed into its group (the
    /// preview has no per-model rows to re-rank); `historyRevision` and
    /// `deviceHistoryRevision` suffixed with `:aliases:<revisionSuffix>`
    /// when present. Limits and tool rows are unchanged.
    public func projectingModelAliases(_ resolver: ModelAliasResolver) -> HubStats {
        guard resolver.isActive else { return self }
        var copy = self
        for kind in UsagePeriodKind.allCases {
            copy[kind] = self[kind].projectingModelAliases(resolver)
        }
        copy.devices = devices.map { $0.projectingModelAliases(resolver) }
        if let favorite = historyPreviewSummary?.favoriteModel {
            copy.historyPreviewSummary?.favoriteModel = resolver.resolve(favorite)
        }
        let suffix = ":aliases:" + resolver.revisionSuffix
        if let revision = historyRevision, !revision.isEmpty { copy.historyRevision = revision + suffix }
        if let revision = deviceHistoryRevision, !revision.isEmpty { copy.deviceHistoryRevision = revision + suffix }
        return copy
    }
}

// MARK: - History

extension HubHistory {
    /// `projectModelAliasHistory` for `GET /api/history`: every day's and
    /// month's `perModel` regrouped, and the favourite model re-ranked over
    /// the grouped `daily` rows (the aggregate's own window).
    public func projectingModelAliases(_ resolver: ModelAliasResolver) -> HubHistory {
        projected(resolver, deviceSemantics: false)
    }

    /// `projectHistory(..., 'device')`: a device record's History, whose
    /// favourite model was ranked over a window the payload does not name,
    /// so it is re-ranked only when `daily` and `monthly` agree.
    func projected(_ resolver: ModelAliasResolver, deviceSemantics: Bool) -> HubHistory {
        guard resolver.isActive else { return self }
        var copy = self
        copy.daily = daily.map { day in
            var day = day
            day.perModel = ModelFold.buckets(day.perModel, resolver)
            return day
        }
        copy.monthly = monthly.map { month in
            var month = month
            month.perModel = ModelFold.buckets(month.perModel, resolver)
            return month
        }
        if let original = summary?.favoriteModel, !original.isEmpty {
            let renamed = resolver.resolve(original)
            let fromDaily = ModelFold.leader(daily.map(\.perModel), resolver)
            let favorite: String
            if !deviceSemantics {
                favorite = fromDaily ?? renamed
            } else {
                let fromMonthly = ModelFold.leader(monthly.map(\.perModel), resolver)
                if let fromDaily, let fromMonthly {
                    favorite = fromDaily.utf16.elementsEqual(fromMonthly.utf16) ? fromDaily : renamed
                } else {
                    favorite = fromDaily ?? fromMonthly ?? renamed
                }
            }
            copy.summary?.favoriteModel = favorite
        }
        return copy
    }
}

extension DeviceHistoryRecord {
    /// The record with its History folded (device semantics, see
    /// `HubHistory.projected`) and its live `today` period folded.
    public func projectingModelAliases(_ resolver: ModelAliasResolver) -> DeviceHistoryRecord {
        guard resolver.isActive else { return self }
        var copy = self
        copy.history = history?.projected(resolver, deviceSemantics: true)
        copy.today = today?.projectingModelAliases(resolver)
        return copy
    }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TokenMonitorKit

/// Round-2 fixtures (`Fixtures/v2`, goldens in `Fixtures/v2/golden`) for the
/// presentation pipeline: device scope, model-alias projection, the
/// presentation context and the shared-settings refresher.
enum PipelineFixture {
    static func data(_ name: String, golden: Bool = false) throws -> Data {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        let subdirectory = golden ? "Fixtures/v2/golden" : "Fixtures/v2"
        guard let url = Bundle.module.url(
            forResource: parts[0],
            withExtension: parts.count > 1 ? parts[1] : nil,
            subdirectory: subdirectory
        ) else {
            throw NSError(domain: "PipelineFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing fixture \(subdirectory)/\(name)"])
        }
        return try Data(contentsOf: url)
    }

    static func stats(_ options: HubDecodingOptions = .app) throws -> HubStats {
        try HubStats.decode(from: data("stats.json"), options: options)
    }

    static func history() throws -> HubHistory {
        try HubHistory.decode(from: data("history.json"))
    }

    /// The captured `model-aliases.json`, optionally with another grouping.
    static func aliases(grouping: ModelAliasGrouping? = nil) throws -> ModelAliasDocument {
        var document = try ModelAliasDocument.decode(from: data("model-aliases.json"))
        if let grouping { document.grouping = grouping }
        return document
    }

    static func goldenObject(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(name, golden: true)) as? [String: Any])
    }

    /// A golden JSON fragment, re-encoded for a `Decodable`.
    static func decode<Value: Decodable>(_ type: Value.Type, from object: Any, options: HubDecodingOptions = .app) throws -> Value {
        try options.makeDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }

    /// The capture's clock: 2026-10-10T16:30:00Z.
    static let now = Fixture.date("2026-10-10T16:30:00Z")
}

// MARK: - Device scope

final class DeviceScopeTests: XCTestCase {
    func testAllDevicesLeavesTheStatsAlone() throws {
        let stats = try PipelineFixture.stats()
        let scoped = stats.scoped(to: .all)
        XCTAssertEqual(scoped.stats, stats)
        XCTAssertEqual(scoped.scope, .all)
        XCTAssertNil(scoped.device)
        XCTAssertFalse(scoped.isScopeMissing)
        XCTAssertFalse(scoped.isDeviceScoped)
        XCTAssertEqual(scoped.effectiveScope, .all)
        XCTAssertEqual(scoped.sourceUpdatedAt, stats.newestDeviceActivity)
        XCTAssertEqual(scoped.isSourceStale, stats.isSourceStale)
    }

    func testDeviceScopeShowsTheDevicesOwnPeriods() throws {
        let stats = try PipelineFixture.stats()
        let device = try XCTUnwrap(stats.device(id: "studio-mac"))
        let scoped = stats.scoped(to: .device("studio-mac"))
        XCTAssertTrue(scoped.isDeviceScoped)
        XCTAssertFalse(scoped.isScopeMissing)
        XCTAssertEqual(scoped.device, device)
        XCTAssertEqual(scoped.effectiveScope, .device("studio-mac"))
        for kind in UsagePeriodKind.allCases {
            XCTAssertEqual(scoped[kind], try XCTUnwrap(device.detail(kind)), kind.rawValue)
            XCTAssertEqual(scoped[kind].totalTokens, device.usage(kind).tokens, kind.rawValue)
            XCTAssertEqual(scoped[kind].costUsd, device.usage(kind).costUsd, accuracy: 1e-9, kind.rawValue)
        }
        XCTAssertEqual(scoped.stats.today.totalTokens, 61_792_000)
        XCTAssertEqual(scoped.stats.today.clients.map(\.id), ["claude", "codex", "opencode"])
        XCTAssertEqual(scoped.stats.today.sessions.count, 11, "the device's own sessions")
        XCTAssertNotEqual(scoped.stats.today.totalTokens, stats.today.totalTokens)

        // The aggregate's History preview is not the device's.
        XCTAssertEqual(scoped.stats.history, [])
        XCTAssertEqual(scoped.stats.historyMonths, [])
        XCTAssertNil(scoped.stats.historyPreviewSummary)
        XCTAssertNil(scoped.stats.historySummary)
        // Omission counts and project completeness are the device's.
        XCTAssertEqual(scoped.stats.sessionDetailsOmitted, [.month: 12])
        XCTAssertEqual(scoped.stats.periodProjectsOmitted, [:])
        XCTAssertFalse(scoped.stats.projectsIncomplete)
        // Limits and the device list never follow the scope.
        XCTAssertEqual(scoped.stats.limits, stats.limits)
        XCTAssertEqual(scoped.stats.devices, stats.devices)
        XCTAssertEqual(scoped.stats.historyRevision, stats.historyRevision)
        XCTAssertEqual(scoped.stats.deviceHistoryRevision, stats.deviceHistoryRevision)
        XCTAssertEqual(scoped.sourceUpdatedAt, Fixture.date("2026-10-10T16:29:40Z"))
        XCTAssertFalse(scoped.isSourceStale)
    }

    func testProjectCompletenessFollowsTheHubRuleForOneDevice() throws {
        let stats = try PipelineFixture.stats()
        XCTAssertTrue(stats.projectsIncomplete)
        XCTAssertTrue(stats.scoped(to: .device("build-box")).stats.projectsIncomplete, "allTimeProjectsIncomplete")
        XCTAssertEqual(stats.scoped(to: .device("build-box")).stats.periodProjectsOmitted, [.month: 3])
        XCTAssertTrue(stats.scoped(to: .device("tokyo-mac")).stats.projectsIncomplete, "projects off with usage")
        XCTAssertFalse(stats.scoped(to: .device("old-laptop")).stats.projectsIncomplete)
    }

    func testAnExpiredPeriodIsZero() throws {
        let stats = try PipelineFixture.stats()
        let scoped = stats.scoped(to: .device("old-laptop"))
        let device = try XCTUnwrap(scoped.device)
        XCTAssertTrue(device.today.isExpired, "its local day ended at 16:00Z")
        XCTAssertEqual(scoped.stats.today, .empty)
        XCTAssertEqual(scoped.stats.today.totalTokens, 0)
        XCTAssertEqual(scoped.stats.month.totalTokens, 10_800_000, "the month is still live")
        XCTAssertEqual(scoped.stats.allTime.totalTokens, 37_800_000)
        XCTAssertTrue(scoped.isSourceStale, "a stale device's numbers describe the past")
        XCTAssertEqual(scoped.sourceUpdatedAt, Fixture.date("2026-10-10T15:20:00Z"))

        // The same device in the aggregate: its today is not counted either.
        let summed = stats.devices.filter { !$0.today.isExpired }.reduce(0) { $0 + $1.today.tokens }
        XCTAssertEqual(stats.today.totalTokens, summed)
    }

    func testAMissingDeviceFallsBackToAllDevices() throws {
        let stats = try PipelineFixture.stats()
        let scoped = stats.scoped(to: .device("retired-box"))
        XCTAssertEqual(scoped.stats, stats)
        XCTAssertEqual(scoped.scope, .device("retired-box"), "the stored scope is kept for the notice")
        XCTAssertTrue(scoped.isScopeMissing)
        XCTAssertNil(scoped.device)
        XCTAssertFalse(scoped.isDeviceScoped)
        XCTAssertEqual(scoped.effectiveScope, .all)
        XCTAssertEqual(scoped[.today].totalTokens, stats.today.totalTokens)
    }

    func testScopedCompactDecodeMatchesTheAppDecode() throws {
        let app = try PipelineFixture.stats(.app).scoped(to: .device("build-box"))
        let compact = try PipelineFixture.stats(.compact(scopedTo: .device("build-box"))).scoped(to: .device("build-box"))
        for kind in UsagePeriodKind.allCases {
            var expected = app[kind]
            expected.sessions = []
            expected.projects = []
            XCTAssertEqual(compact[kind], expected, kind.rawValue)
        }
        XCTAssertEqual(compact.stats.today.totalTokens, 9_835_000)
    }

    func testDeviceWithoutDetailsFallsBackToItsTotals() throws {
        let stats = try PipelineFixture.stats(.compact)
        let scoped = stats.scoped(to: .device("studio-mac"))
        let device = try XCTUnwrap(scoped.device)
        XCTAssertNil(device.detail(.today), "compact decodes carry no device detail")
        let today = scoped.stats.today
        XCTAssertEqual(today.totalTokens, 61_792_000)
        XCTAssertEqual(today.costUsd, device.today.costUsd)
        XCTAssertEqual(today.unpricedTokens, 90_000)
        XCTAssertEqual(today.clients, device.today.clients)
        XCTAssertEqual(today.unclassifiedTokens, today.totalTokens, "no component provenance")
        XCTAssertFalse(today.hasExactTokenComponents)
        XCTAssertEqual(today.components.unclassified, today.totalTokens)
        XCTAssertEqual(today.clientBreakdown["claude"]?.tokens, 48_302_000)
        XCTAssertEqual(today.models, [])
        XCTAssertEqual(scoped.stats.today.timedOutputTokens, clampedInt(device.today.throughput?.timedOutputTokens ?? 0))
    }

    func testPresentingAppliesAliasesBeforeTheScope() throws {
        let stats = try PipelineFixture.stats()
        let document = try PipelineFixture.aliases()
        let presented = stats.presenting(scope: .device("studio-mac"), aliases: document)
        let resolver = try XCTUnwrap(ModelAliasResolver.forStats(stats, document: document))
        XCTAssertEqual(presented.stats.today, try XCTUnwrap(stats.device(id: "studio-mac")?.detail(.today)).projectingModelAliases(resolver))
        XCTAssertNil(presented.stats.today.modelBreakdown["anthropic/claude-sonnet-4.5"])
        XCTAssertEqual(stats.presenting(scope: .all, aliases: nil).stats, stats, "no document, no projection")
    }
}

// MARK: - Model alias projection

final class ModelAliasProjectionTests: XCTestCase {
    func testObservedModelIDsMatchTheDesktopCollection() throws {
        let golden = try PipelineFixture.goldenObject("aliases.json")
        let expected = Set(try XCTUnwrap(golden["observedModels"] as? [String]))
        XCTAssertEqual(Set(try PipelineFixture.stats(.app).observedModelIDs), expected)
        XCTAssertEqual(Set(try PipelineFixture.stats(.compact).observedModelIDs), expected, "the aggregate alone shows every model")
        let ids = try PipelineFixture.stats(.app).observedModelIDs
        XCTAssertEqual(ids.count, Set(ids).count, "each id once")

        let history = Set(try XCTUnwrap(golden["observedHistoryModels"] as? [String]))
        XCTAssertEqual(Set(try PipelineFixture.history().observedModelIDs), history)
    }

    func testStatsProjectionMatchesTheDesktopGolden() throws {
        let golden = try PipelineFixture.goldenObject("aliases.json")
        let groupings = try XCTUnwrap(golden["groupings"] as? [String: Any])
        let stats = try PipelineFixture.stats(.app)
        for grouping in ModelAliasGrouping.allCases {
            let label = grouping.rawValue
            let entry = try XCTUnwrap(groupings[label] as? [String: Any], label)
            let goldenStats = try XCTUnwrap(entry["stats"] as? [String: Any], label)
            let resolver = try XCTUnwrap(ModelAliasResolver.forStats(stats, document: try PipelineFixture.aliases(grouping: grouping)), label)
            let inferred = try XCTUnwrap(entry["inferred"] as? [String: String], label)
            XCTAssertEqual(
                Dictionary(uniqueKeysWithValues: resolver.inferredAliases.map { ($0.alias, $0.canonical) }), inferred, label
            )

            let projected = stats.projectingModelAliases(resolver)
            XCTAssertEqual(projected.historyRevision, goldenStats["historyRevision"] as? String, label)
            XCTAssertEqual(projected.deviceHistoryRevision, goldenStats["deviceHistoryRevision"] as? String, label)

            let periods = try XCTUnwrap(goldenStats["periods"] as? [String: Any], label)
            XCTAssertFalse(periods.isEmpty)
            for (name, value) in periods {
                let kind = try XCTUnwrap(UsagePeriodKind(rawValue: name))
                let expected = try PipelineFixture.decode(UsagePeriod.self, from: value)
                try Self.assertModels(projected[kind], equal: expected, "\(label) \(name)")
            }
            // Tool rows and totals are never touched.
            for kind in UsagePeriodKind.allCases {
                XCTAssertEqual(projected[kind].clients, stats[kind].clients)
                XCTAssertEqual(projected[kind].clientBreakdown, stats[kind].clientBreakdown)
                XCTAssertEqual(projected[kind].totalTokens, stats[kind].totalTokens)
            }
            XCTAssertEqual(projected.limits, stats.limits)
        }
    }

    func testHistoryProjectionMatchesTheDesktopGolden() throws {
        let golden = try PipelineFixture.goldenObject("aliases.json")
        let groupings = try XCTUnwrap(golden["groupings"] as? [String: Any])
        let history = try PipelineFixture.history()
        for grouping in ModelAliasGrouping.allCases {
            let label = grouping.rawValue
            let entry = try XCTUnwrap(groupings[label] as? [String: Any], label)
            let expected = try XCTUnwrap(entry["history"] as? [String: Any], label)
            let resolver = try XCTUnwrap(ModelAliasResolver.forHistory(history, document: try PipelineFixture.aliases(grouping: grouping)), label)
            let projected = history.projectingModelAliases(resolver)
            XCTAssertEqual(projected.summary?.favoriteModel, expected["summaryFavoriteModel"] as? String, label)

            let days = try XCTUnwrap(expected["lastDaily"] as? [[String: Any]], label)
            XCTAssertEqual(projected.daily.suffix(days.count).map(\.date), days.map { $0["date"] as? String ?? "" }, label)
            for (day, raw) in zip(projected.daily.suffix(days.count), days) {
                try Self.assertBuckets(day.perModel, equal: try PipelineFixture.decode([String: HistoryBucket].self, from: raw["perModel"] ?? [:]), "\(label) \(day.date)")
            }
            let months = try XCTUnwrap(expected["lastMonthly"] as? [[String: Any]], label)
            XCTAssertEqual(projected.monthly.suffix(months.count).map(\.month), months.map { $0["month"] as? String ?? "" }, label)
            for (month, raw) in zip(projected.monthly.suffix(months.count), months) {
                try Self.assertBuckets(month.perModel, equal: try PipelineFixture.decode([String: HistoryBucket].self, from: raw["perModel"] ?? [:]), "\(label) \(month.month)")
            }
            // Totals of the rows are unchanged.
            XCTAssertEqual(projected.daily.map(\.tokens), history.daily.map(\.tokens))
            XCTAssertEqual(projected.daily.map(\.perClient), history.daily.map(\.perClient))
        }
    }

    func testFoldingAMonthlyBucketMarksTheMergedModelUnclassified() throws {
        let resolver = ModelAliasResolver(aliases: ["b-model": "a-model"], grouping: .off)
        let month = HubHistoryMonth(month: "2026-10", tokens: 30, perModel: [
            "a-model": HistoryBucket(tokens: 10, costUsd: 1),
            "b-model": HistoryBucket(tokens: 20, costUsd: 2, unpricedTokens: 5)
        ])
        let day = HubHistoryDay(date: "2026-10-10", tokens: 30, perModel: [
            "a-model": HistoryBucket(tokens: 10, costUsd: 1, cacheReadTokens: 6, outputTokens: 1, unclassifiedTokens: 0),
            "b-model": HistoryBucket(tokens: 20, costUsd: 2, cacheReadTokens: 12, outputTokens: 2, unclassifiedTokens: 3)
        ])
        let projected = HubHistory(daily: [day], monthly: [month]).projectingModelAliases(resolver)
        XCTAssertEqual(projected.monthly[0].perModel, [
            "a-model": HistoryBucket(tokens: 30, costUsd: 3, unpricedTokens: 5, unclassifiedTokens: 30)
        ])
        XCTAssertEqual(projected.daily[0].perModel, [
            "a-model": HistoryBucket(tokens: 30, costUsd: 3, cacheReadTokens: 18, outputTokens: 3, unclassifiedTokens: 3)
        ])
        // A model that folds into nothing keeps its bucket as it was.
        let untouched = HubHistory(daily: [HubHistoryDay(date: "2026-10-10", perModel: ["c": HistoryBucket(tokens: 1)])])
        XCTAssertEqual(untouched.projectingModelAliases(resolver), untouched)
    }

    func testFavouriteModelFollowsEachHistorySemantics() {
        let resolver = ModelAliasResolver(aliases: ["x-old": "x-new"], grouping: .off)
        let daily = [
            HubHistoryDay(date: "2026-10-09", perModel: ["x-old": HistoryBucket(tokens: 6), "y": HistoryBucket(tokens: 10)]),
            HubHistoryDay(date: "2026-10-10", perModel: ["x-new": HistoryBucket(tokens: 6)])
        ]
        let monthly = [HubHistoryMonth(month: "2026-10", perModel: ["y": HistoryBucket(tokens: 50), "x-old": HistoryBucket(tokens: 1)])]
        let history = HubHistory(daily: daily, monthly: monthly, summary: HistorySummary(favoriteModel: "y"))

        // Aggregate: re-ranked over the grouped daily rows (x-new 12 > y 10).
        XCTAssertEqual(history.projectingModelAliases(resolver).summary?.favoriteModel, "x-new")
        // Device: daily (x-new) and monthly (y) disagree, so the stored leader
        // is only renamed.
        let record = DeviceHistoryRecord(id: "d", historyAvailable: true, history: history)
        XCTAssertEqual(record.projectingModelAliases(resolver).history?.summary?.favoriteModel, "y")
        var agreeing = history
        agreeing.monthly = [HubHistoryMonth(month: "2026-10", perModel: ["x-old": HistoryBucket(tokens: 50)])]
        XCTAssertEqual(
            DeviceHistoryRecord(id: "d", historyAvailable: true, history: agreeing).projectingModelAliases(resolver).history?.summary?.favoriteModel,
            "x-new"
        )
        // No leader stays no leader; the preview only renames.
        var none = history
        none.summary?.favoriteModel = nil
        XCTAssertNil(none.projectingModelAliases(resolver).summary?.favoriteModel)
        let stats = HubStats(historyPreviewSummary: HistorySummary(favoriteModel: "x-old"))
        XCTAssertEqual(stats.projectingModelAliases(resolver).historyPreviewSummary?.favoriteModel, "x-new")
    }

    func testSessionsDevicesAndThroughputFold() throws {
        let stats = try PipelineFixture.stats(.app)
        let document = try PipelineFixture.aliases()
        let resolver = try XCTUnwrap(ModelAliasResolver.forStats(stats, document: document))
        let projected = stats.projectingModelAliases(resolver)
        for (device, original) in zip(projected.devices, stats.devices) {
            for kind in UsagePeriodKind.allCases {
                XCTAssertEqual(device.detail(kind), original.detail(kind)?.projectingModelAliases(resolver), "\(device.id) \(kind)")
                XCTAssertEqual(device.usage(kind), original.usage(kind).projectingModelAliases(resolver), "\(device.id) \(kind)")
            }
        }
        let session = HubSession(id: "c:1", client: "c", models: ["glm-4.6-cc": 5, "glm-4.6": 2], modelCosts: ["glm-4.6-cc": 0.5])
        let folded = session.projectingModelAliases(resolver)
        XCTAssertEqual(folded.models, ["glm-4.6": 7])
        XCTAssertEqual(folded.modelCosts, ["glm-4.6": 0.5])
        XCTAssertEqual(folded.id, session.id)

        let period = UsagePeriod(modelThroughput: [
            "other": ThroughputCounters(timedTokens: 1, timedOutputTokens: 2, timedDurationMs: 3),
            "gpt-5-codex-high": ThroughputCounters(timedTokens: 1, timedOutputTokens: 1, timedDurationMs: 1),
            "gpt-5-codex": ThroughputCounters(timedTokens: 2, timedOutputTokens: 2, timedDurationMs: 2)
        ])
        XCTAssertEqual(period.projectingModelAliases(resolver).modelThroughput, [
            "other": ThroughputCounters(timedTokens: 1, timedOutputTokens: 2, timedDurationMs: 3),
            "gpt-5-codex": ThroughputCounters(timedTokens: 3, timedOutputTokens: 3, timedDurationMs: 3)
        ])
        XCTAssertNil(UsagePeriod().projectingModelAliases(resolver).modelThroughput, "an absent map stays absent")
    }

    func testResolverFactoriesSkipInactivePlans() throws {
        let stats = try PipelineFixture.stats(.compact)
        XCTAssertNil(ModelAliasResolver.forStats(stats, document: nil))
        XCTAssertNil(ModelAliasResolver.forStats(stats, document: .uninitialized))
        XCTAssertNil(ModelAliasResolver.forStats(stats, document: ModelAliasDocument(revision: 3)), "no aliases, grouping off")
        XCTAssertNotNil(ModelAliasResolver.forStats(stats, document: ModelAliasDocument(revision: 3, grouping: .duplicates)), "the fixture shows duplicate spellings")
        XCTAssertNil(ModelAliasResolver.forStats(HubStats(), document: ModelAliasDocument(revision: 3, grouping: .duplicates)), "nothing to group")
        XCTAssertNil(ModelAliasResolver.forHistory(nil, document: ModelAliasDocument(revision: 3, grouping: .prefix)))
        XCTAssertNotNil(ModelAliasResolver.forHistory(nil, document: ModelAliasDocument(revision: 3, aliases: ["a": "b"])))

        // An inactive resolver hands everything back unchanged.
        let inactive = ModelAliasResolver.inactive
        XCTAssertEqual(stats.projectingModelAliases(inactive), stats)
        XCTAssertEqual(try PipelineFixture.history().projectingModelAliases(inactive), try PipelineFixture.history())

        // A revision that is absent stays absent.
        let bare = HubStats(historyRevision: nil, deviceHistoryRevision: "")
        let projected = bare.projectingModelAliases(ModelAliasResolver(aliases: ["a": "b"], grouping: .off))
        XCTAssertNil(projected.historyRevision)
        XCTAssertEqual(projected.deviceHistoryRevision, "")
    }

    /// The model maps of a projected period against the golden's.
    static func assertModels(_ actual: UsagePeriod, equal expected: UsagePeriod, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        func entries(_ lhs: [String: UsageBreakdownEntry], _ rhs: [String: UsageBreakdownEntry], _ what: String) {
            XCTAssertEqual(Set(lhs.keys), Set(rhs.keys), "\(label) \(what) keys", file: file, line: line)
            for (key, left) in lhs {
                guard let right = rhs[key] else { continue }
                XCTAssertEqual(left.tokens, right.tokens, "\(label) \(what) \(key)", file: file, line: line)
                XCTAssertEqual(left.costUsd, right.costUsd, accuracy: 1e-9, "\(label) \(what) \(key)", file: file, line: line)
                XCTAssertEqual(left.unpricedTokens, right.unpricedTokens, "\(label) \(what) \(key)", file: file, line: line)
                XCTAssertEqual(left.cacheReadTokens, right.cacheReadTokens, "\(label) \(what) \(key)", file: file, line: line)
                XCTAssertEqual(left.cacheWriteTokens, right.cacheWriteTokens, "\(label) \(what) \(key)", file: file, line: line)
                XCTAssertEqual(left.outputTokens, right.outputTokens, "\(label) \(what) \(key)", file: file, line: line)
                XCTAssertEqual(left.unclassifiedTokens, right.unclassifiedTokens, "\(label) \(what) \(key)", file: file, line: line)
            }
        }
        entries(actual.modelBreakdown, expected.modelBreakdown, "modelBreakdown")
        XCTAssertEqual(Set(actual.clientModels.keys), Set(expected.clientModels.keys), "\(label) clientModels", file: file, line: line)
        for (client, models) in actual.clientModels {
            entries(models, expected.clientModels[client] ?? [:], "clientModels.\(client)")
        }
        XCTAssertEqual(actual.models.map(\.id), expected.models.map(\.id), "\(label) model rows", file: file, line: line)
        for (left, right) in zip(actual.models, expected.models) {
            XCTAssertEqual(left.tokens, right.tokens, "\(label) \(left.id)", file: file, line: line)
            XCTAssertEqual(left.costUsd ?? -1, right.costUsd ?? -1, accuracy: 1e-9, "\(label) \(left.id)", file: file, line: line)
            XCTAssertEqual(left.vendorID, right.vendorID, "\(label) \(left.id)", file: file, line: line)
            XCTAssertEqual(left.label, left.id)
        }
        XCTAssertEqual(actual.modelThroughput?.keys.sorted(), expected.modelThroughput?.keys.sorted(), "\(label) throughput", file: file, line: line)
        for (model, counters) in actual.modelThroughput ?? [:] {
            guard let other = expected.modelThroughput?[model] else { continue }
            XCTAssertEqual(counters.timedTokens, other.timedTokens, accuracy: 1e-6, "\(label) \(model)", file: file, line: line)
            XCTAssertEqual(counters.timedOutputTokens, other.timedOutputTokens, accuracy: 1e-6, "\(label) \(model)", file: file, line: line)
            XCTAssertEqual(counters.timedDurationMs, other.timedDurationMs, accuracy: 1e-6, "\(label) \(model)", file: file, line: line)
        }
        XCTAssertEqual(Set(actual.sessions.map(\.id)), Set(expected.sessions.map(\.id)), "\(label) sessions", file: file, line: line)
        for session in actual.sessions {
            guard let other = expected.sessions.first(where: { $0.id == session.id }) else { continue }
            XCTAssertEqual(session.models, other.models, "\(label) \(session.id)", file: file, line: line)
            XCTAssertEqual(Set(session.modelCosts.keys), Set(other.modelCosts.keys), "\(label) \(session.id)", file: file, line: line)
            for (model, cost) in session.modelCosts {
                XCTAssertEqual(cost, other.modelCosts[model] ?? -1, accuracy: 1e-9, "\(label) \(session.id) \(model)", file: file, line: line)
            }
        }
    }

    static func assertBuckets(_ actual: [String: HistoryBucket], equal expected: [String: HistoryBucket], _ label: String,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(Set(actual.keys), Set(expected.keys), "\(label) keys", file: file, line: line)
        for (model, bucket) in actual {
            guard var other = expected[model] else { continue }
            XCTAssertEqual(bucket.costUsd, other.costUsd, accuracy: 1e-6, "\(label) \(model)", file: file, line: line)
            other.costUsd = bucket.costUsd
            XCTAssertEqual(bucket, other, "\(label) \(model)", file: file, line: line)
        }
    }
}

// MARK: - Presentation context

final class PresentationContextTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "PresentationContextTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testLoadReadsPreferencesRatesAndLanguage() {
        let preferences = PreferencesStore(defaults: defaults)
        let rates = ExchangeRateStore(defaults: defaults)
        var stored = DisplayPreferences.defaults
        stored.currency = .twd
        stored.compactTokenUnits = .localized
        stored.currencyRates = ["HKD": 7.5]
        stored.vendorColors = ["claude": "#123456"]
        preferences.save(stored)
        rates.save(ExchangeRateCache(rates: ["USD": 1, "TWD": 32.25, "HKD": 7.81, "CNY": 7.1], date: "2026-10-10", fetchedAt: PipelineFixture.now))

        let context = PresentationContext.load(preferences: preferences, rates: rates, bundle: .module)
        XCTAssertEqual(context.preferences, stored.normalized())
        XCTAssertEqual(context.rates.multiplier(for: .twd), 32.25)
        XCTAssertEqual(context.rates.origin(for: .twd), .fetched)
        XCTAssertEqual(context.rates.multiplier(for: .hkd), 7.5, "a manual rate wins")
        XCTAssertEqual(context.rates.origin(for: .hkd), .manual)
        XCTAssertEqual(context.rates.fetchedDate, "2026-10-10")
        XCTAssertFalse(context.languageIdentifier.isEmpty)
        XCTAssertEqual(context.palette.overrides, ["claude": "#123456"])

        let formatter = context.formatter
        XCTAssertEqual(formatter, DisplayFormatter(preferences: context.preferences, rates: context.rates, languageIdentifier: context.languageIdentifier))
        XCTAssertEqual(formatter.currency, .twd)
        XCTAssertEqual(formatter.units, .localized)
        XCTAssertEqual(formatter.cost(1), "NT$32.25")
    }

    func testLoadWithoutStoredValuesUsesDefaultsAndFloors() {
        let context = PresentationContext.load(preferences: PreferencesStore(defaults: defaults), rates: ExchangeRateStore(defaults: defaults), bundle: .module)
        XCTAssertEqual(context.preferences, .defaults)
        XCTAssertEqual(context.rates.multiplier(for: .twd), CurrencyRates.floors["TWD"])
        XCTAssertEqual(context.rates.multiplier(for: .usd), 1)
        XCTAssertEqual(PresentationContext.standard.formatter, DisplayFormatter())
    }

    func testPreferencesPayloadCarriesTheRateCache() throws {
        let cache = ExchangeRateCache(rates: ["USD": 1, "TWD": 32.25], date: "2026-10-10", source: "https://cdn.example", fetchedAt: PipelineFixture.now)
        let payload = PreferencesPayload(preferences: .defaults, rateCache: cache)
        XCTAssertEqual(payload.rateCache, cache)
        XCTAssertEqual(PreferencesPayload.decode(try payload.encoded())?.rateCache, cache)

        // The bytes are what the store keeps, so the watch can save them as is.
        let rates = ExchangeRateStore(defaults: defaults)
        XCTAssertTrue(rates.save(data: try XCTUnwrap(payload.rateCacheData)))
        XCTAssertEqual(rates.load(), cache)
        rates.save(cache)
        XCTAssertEqual(rates.data(), payload.rateCacheData)

        XCTAssertNil(PreferencesPayload(preferences: .defaults, rateCache: nil).rateCacheData)
        XCTAssertNil(PreferencesPayload(preferences: .defaults, rateCacheData: Data("{}".utf8)).rateCache)
    }
}

// MARK: - Shared settings refresher

final class SharedSettingsRefresherTests: XCTestCase {
    private var session: URLSession!
    private var directory: URL!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SharedSettingsRefresherTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        StubURLProtocol.reset()
        try? FileManager.default.removeItem(at: directory)
        session = nil
        super.tearDown()
    }

    private let path = "/api/sync/settings/modelAliases"

    private func client(_ url: String = "http://hub.test:17321") throws -> HubClient {
        HubClient(connection: try HubConnection(userInput: url, secret: "s3cret"), session: session)
    }

    private func requestCount() -> Int {
        StubURLProtocol.recordedRequests.filter { $0.url?.path == path }.count
    }

    private func stats(revision: Int?) -> HubStats {
        HubStats(syncSettingsRevisions: revision.map { ["modelAliases": $0, "customPricing": 1] })
    }

    func testFetchesWhenTheAdvertisedRevisionMoves() async throws {
        StubURLProtocol.stub(path: path, status: 200, body: try PipelineFixture.data("model-aliases.json"))
        let cache = ModelAliasCache(directory: directory)
        let client = try client()
        let key = client.connection.snapshotKey

        // Nothing held: fetch and keep it.
        let first = await SharedSettingsRefresher.modelAliases(stats: stats(revision: 1), client: client, cache: cache)
        XCTAssertEqual(first, try PipelineFixture.aliases())
        XCTAssertEqual(cache.load(hubKey: key), first)
        XCTAssertEqual(requestCount(), 1)

        // Current, or no marker at all: the cache answers.
        let second = await SharedSettingsRefresher.modelAliases(stats: stats(revision: 1), client: client, cache: cache)
        let third = await SharedSettingsRefresher.modelAliases(stats: stats(revision: nil), client: client, cache: cache)
        XCTAssertEqual(second, first)
        XCTAssertEqual(third, first)
        XCTAssertEqual(requestCount(), 1)

        // A new revision, or force: fetch again.
        _ = await SharedSettingsRefresher.modelAliases(stats: stats(revision: 2), client: client, cache: cache)
        XCTAssertEqual(requestCount(), 2)
        _ = await SharedSettingsRefresher.modelAliases(stats: stats(revision: 1), client: client, cache: cache, force: true)
        XCTAssertEqual(requestCount(), 3)

        // Another Hub's cache entry is not this Hub's.
        _ = await SharedSettingsRefresher.modelAliases(stats: stats(revision: 1), client: try self.client("http://other.test:17321"), cache: cache)
        XCTAssertEqual(requestCount(), 4)
        XCTAssertNil(cache.load(hubKey: key), "one entry, now the other Hub's")
    }

    func testAnOlderHubIsRememberedAsUninitialized() async throws {
        let cache = ModelAliasCache(directory: directory)
        let client = try client()
        for status in [404, 405] {
            try cache.clear()
            StubURLProtocol.reset()
            StubURLProtocol.stub(path: path, status: status, body: Data(#"{"error":"not_found"}"#.utf8))
            let document = await SharedSettingsRefresher.modelAliases(stats: stats(revision: nil), client: client, cache: cache, hubKey: "hub-a")
            XCTAssertEqual(document, .uninitialized, "\(status)")
            XCTAssertEqual(cache.load(hubKey: "hub-a"), .uninitialized)
            XCTAssertNil(ModelAliasResolver.forStats(try PipelineFixture.stats(.compact), document: document))
            // Not asked again until the Hub advertises a revision.
            _ = await SharedSettingsRefresher.modelAliases(stats: stats(revision: nil), client: client, cache: cache, hubKey: "hub-a")
            XCTAssertEqual(requestCount(), 1, "\(status)")
            _ = await SharedSettingsRefresher.modelAliases(stats: stats(revision: 1), client: client, cache: cache, hubKey: "hub-a")
            XCTAssertEqual(requestCount(), 2, "\(status)")
        }
    }

    func testOtherFailuresKeepTheCache() async throws {
        let cache = ModelAliasCache(directory: directory)
        let client = try client()
        let key = client.connection.snapshotKey
        StubURLProtocol.stub(path: path, status: 500, body: Data())
        let none = await SharedSettingsRefresher.modelAliases(stats: stats(revision: 1), client: client, cache: cache)
        XCTAssertNil(none, "nothing held, nothing fetched")
        XCTAssertNil(cache.loadEntry())

        let held = try PipelineFixture.aliases()
        try cache.save(held, hubKey: key)
        StubURLProtocol.stub(path: path, status: 200, body: Data(#"{"version":2}"#.utf8))
        let kept = await SharedSettingsRefresher.modelAliases(stats: stats(revision: 5), client: client, cache: cache)
        XCTAssertEqual(kept, held, "an unreadable document keeps the last good one")
        XCTAssertEqual(cache.load(hubKey: key), held)
    }
}

import Foundation
import XCTest
@testable import TokenMonitorKit

/// Round-2 wire decoding against `Fixtures/v2` (captured from a real Node Hub
/// under a frozen clock; see `Fixtures/v2/README.txt`) and its goldens.
final class WireV2Tests: XCTestCase {
    // MARK: - Options

    func testOptionPresets() {
        XCTAssertEqual(HubDecodingOptions.compact, HubDecodingOptions(includeSessions: false, includeProjects: false, deviceDetail: .none))
        XCTAssertEqual(HubDecodingOptions.app, HubDecodingOptions(includeSessions: true, includeProjects: true, deviceDetail: .all))
        XCTAssertEqual(HubDecodingOptions.compact(scopedTo: .all), .compact)
        XCTAssertEqual(HubDecodingOptions.compact(scopedTo: .device("studio-mac")), HubDecodingOptions(deviceDetail: .only("studio-mac")))
        XCTAssertTrue(HubDecodingOptions.DeviceDetail.all.includes("x"))
        XCTAssertFalse(HubDecodingOptions.DeviceDetail.none.includes("x"))
        XCTAssertTrue(HubDecodingOptions.DeviceDetail.only("x").includes("x"))
        XCTAssertFalse(HubDecodingOptions.DeviceDetail.only("x").includes("y"))
        let decoder = HubDecodingOptions.app.makeDecoder()
        XCTAssertEqual(decoder.userInfo[.hubDecodingOptions] as? HubDecodingOptions, .app)
    }

    func testCompactLeavesSessionsProjectsAndDetailsEmpty() throws {
        let stats = try V2.stats(.compact)
        for kind in UsagePeriodKind.allCases {
            XCTAssertEqual(stats[kind].sessions, [], kind.rawValue)
            XCTAssertEqual(stats[kind].projects, [], kind.rawValue)
        }
        XCTAssertEqual(stats.today.sessionCount, 13, "the count does not depend on the options")
        XCTAssertEqual(stats.month.sessionCount, 14)
        XCTAssertEqual(stats.devices.map(\.id), ["build-box", "old-laptop", "studio-mac", "tokyo-mac"])
        for device in stats.devices {
            XCTAssertEqual(device.details, [:], device.id)
            XCTAssertNil(device.detail(.allTime), device.id)
            XCTAssertEqual(device.limits, [], device.id)
            XCTAssertNil(device.limitsUpdatedAt, device.id)
        }
        // Cheap fields are there in every mode.
        XCTAssertFalse(stats.today.clientBreakdown.isEmpty)
        XCTAssertNotNil(stats.today.modelThroughput)
        XCTAssertNotNil(stats.devices.first { $0.id == "studio-mac" }?.clientHealth)
    }

    func testAbsentOptionsDecodeAsCompact() throws {
        let plain = try JSONDecoder().decode(HubStats.self, from: V2.data("stats.json"))
        XCTAssertEqual(plain, try V2.stats(.compact))
        XCTAssertEqual(try HubStats.decode(from: V2.data("stats.json")), plain)

        // A period on its own (as DeviceHistoryRecord decodes `/api/devices`
        // periods) with a plain decoder.
        let period = try JSONDecoder().decode(UsagePeriod.self, from: V2.periodData(["periods", "today"]))
        XCTAssertEqual(period.totalTokens, 73_237_000)
        XCTAssertEqual(period.sessions, [])
        XCTAssertEqual(period.projects, [])
        XCTAssertEqual(period.clientBreakdown, try V2.stats(.compact).today.clientBreakdown)
    }

    func testAppFillsEverything() throws {
        let stats = try V2.stats(.app)
        XCTAssertEqual(stats.today.sessions.count, 13)
        XCTAssertEqual(stats.month.sessions.count, 14)
        XCTAssertEqual(stats.allTime.sessions, [], "the Hub strips all-time sessions")
        XCTAssertEqual(stats.today.projects.map(\.id), ["token-monitor", "docs-site", "infra"])
        XCTAssertEqual(stats.month.projects.count, 3)
        XCTAssertEqual(stats.allTime.projects.count, 3)

        let compact = try V2.stats(.compact)
        // Totals and rows do not depend on the options.
        for kind in UsagePeriodKind.allCases {
            var stripped = stats[kind]
            stripped.sessions = []
            stripped.projects = []
            XCTAssertEqual(stripped, compact[kind], kind.rawValue)
        }

        let studio = try XCTUnwrap(stats.device(id: "studio-mac"))
        XCTAssertEqual(Set(studio.details.keys), [.today, .month, .allTime])
        XCTAssertEqual(studio.detail(.today)?.sessions.count, 11)
        XCTAssertEqual(studio.detail(.month)?.sessions.count, 14)
        XCTAssertEqual(studio.detail(.month)?.projects.map(\.label), ["Token-Monitor", "docs-site", "Infra"])
        XCTAssertEqual(studio.detail(.today)?.totalTokens, studio.today.tokens)
        XCTAssertEqual(studio.detail(.allTime)?.totalTokens, studio.allTime.tokens)
        XCTAssertFalse(studio.limits.isEmpty)
        XCTAssertEqual(studio.limitsUpdatedAt, Fixture.date("2026-10-10T16:29:40.000Z"))
        XCTAssertEqual(studio.limitsRefreshInterval, 300)
        XCTAssertEqual(Set(studio.limits.map(\.id)).count, studio.limits.count)
        XCTAssertFalse(studio.limits.contains(where: \.isStale))

        let tokyo = try XCTUnwrap(stats.device(id: "tokyo-mac"))
        XCTAssertEqual(tokyo.detail(.month)?.projects, [], "projects disabled on this device")
        XCTAssertEqual(tokyo.limits.map(\.provider), ["cursor", "copilot", "zed"])

        let laptop = try XCTUnwrap(stats.device(id: "old-laptop"))
        XCTAssertFalse(laptop.limits.isEmpty)
        XCTAssertTrue(laptop.limits.allSatisfy(\.isStale), "rows of a stale device are stale")
    }

    func testScopedCompactFillsOnlyThatDevice() throws {
        let stats = try V2.stats(.compact(scopedTo: .device("studio-mac")))
        for kind in UsagePeriodKind.allCases {
            XCTAssertEqual(stats[kind].sessions, [])
            XCTAssertEqual(stats[kind].projects, [])
        }
        for device in stats.devices where device.id != "studio-mac" {
            XCTAssertEqual(device.details, [:], device.id)
            XCTAssertEqual(device.limits, [], device.id)
        }
        let studio = try XCTUnwrap(stats.device(id: "studio-mac"))
        XCTAssertEqual(Set(studio.details.keys), [.today, .month, .allTime])
        XCTAssertEqual(studio.detail(.today)?.sessions, [], "scoped compact still skips sessions")
        XCTAssertEqual(studio.detail(.month)?.projects, [])
        XCTAssertEqual(studio.detail(.today)?.sessionCount, 11)
        XCTAssertFalse(studio.limits.isEmpty)

        let app = try XCTUnwrap(try V2.stats(.app).device(id: "studio-mac"))
        var appToday = try XCTUnwrap(app.detail(.today))
        appToday.sessions = []
        appToday.projects = []
        XCTAssertEqual(appToday, studio.detail(.today))

        let missing = try V2.stats(.compact(scopedTo: .device("no-such-device")))
        XCTAssertTrue(missing.devices.allSatisfy { $0.details.isEmpty })
    }

    // MARK: - Hub-level fields

    func testTopLevelV2Fields() throws {
        let stats = try V2.stats(.compact)
        XCTAssertEqual(stats.updatedAt, Fixture.date("2026-10-10T16:30:00.000Z"))
        XCTAssertEqual(stats.historyRevision, "0fa3c82df0af4fa1")
        XCTAssertEqual(stats.deviceHistoryRevision, "266a553b53694d67")
        XCTAssertEqual(stats.subscriptionsUpdatedAt, "2026-10-10T16:29:45.000Z")
        XCTAssertEqual(stats.syncSettingsRevisions, ["modelAliases": 1, "customPricing": 1])
        XCTAssertEqual(stats.sessionDetailsOmitted, [.month: 12])
        XCTAssertEqual(stats.periodProjectsOmitted, [.month: 3])
        XCTAssertTrue(stats.projectsIncomplete)
        XCTAssertEqual(stats.history.count, 30)
        XCTAssertEqual(stats.historyMonths.count, 12)

        // The preview summary is the Hub's summary of the full History.
        let summary = try XCTUnwrap(stats.historyPreviewSummary)
        let history = try V2.object("history.json")
        let wire = try XCTUnwrap(history["summary"] as? [String: Any])
        XCTAssertEqual(summary.totalTokens, wire["totalTokens"] as? Int)
        XCTAssertEqual(summary.totalCost, try XCTUnwrap(wire["totalCost"] as? Double), accuracy: 1e-6)
        XCTAssertEqual(summary.activeDays, 281)
        XCTAssertEqual(summary.currentStreak, 20)
        XCTAssertEqual(summary.longestStreak, 46)
        XCTAssertEqual(summary.peakDayTokens, 69_349_766)
        XCTAssertEqual(summary.favoriteModel, "claude-sonnet-4-5")
        XCTAssertEqual(summary.messages, 284_548)
        XCTAssertEqual(summary.activeTimeMs, 15_402_060_000)
        XCTAssertEqual(summary.unpricedTokens, 2_161_051)
    }

    func testOptionalHubFieldsKeepTheirAbsence() throws {
        let old = try HubStats.decode(from: Data(#"{"periods":{}}"#.utf8))
        XCTAssertNil(old.historyRevision)
        XCTAssertNil(old.deviceHistoryRevision)
        XCTAssertNil(old.subscriptionsUpdatedAt)
        XCTAssertNil(old.syncSettingsRevisions)
        XCTAssertNil(old.historyPreviewSummary)
        XCTAssertEqual(old.sessionDetailsOmitted, [:])

        let json = """
        {"subscriptionsUpdatedAt":"","syncSettingsRevisions":{"modelAliases":"3","bad":"x"},
         "historyRevision":"","sessionDetailsOmitted":{"today":2,"month":0,"week":5,"allTime":-1},
         "historyPreview":{"summary":{"totalTokens":"12","favoriteModel":""}}}
        """
        let fresh = try HubStats.decode(from: Data(json.utf8))
        XCTAssertEqual(fresh.subscriptionsUpdatedAt, "", "empty means the list was never written")
        XCTAssertEqual(fresh.syncSettingsRevisions, ["modelAliases": 3])
        XCTAssertNil(fresh.historyRevision)
        XCTAssertEqual(fresh.sessionDetailsOmitted, [.today: 2])
        XCTAssertEqual(fresh.historyPreviewSummary, HistoryPreviewSummary(totalTokens: 12))
    }

    // MARK: - Breakdown maps

    func testBreakdownMapsMatchTheWireForEveryPeriod() throws {
        let stats = try V2.stats(.app)
        let root = try V2.object("stats.json")
        let periods = try XCTUnwrap(root["periods"] as? [String: Any])
        for kind in UsagePeriodKind.allCases {
            let raw = try XCTUnwrap(periods[kind.rawValue] as? [String: Any])
            try V2.assertPeriod(stats[kind], matches: raw, "aggregate.\(kind.rawValue)")
        }
        let devices = try XCTUnwrap(root["devices"] as? [[String: Any]])
        for rawDevice in devices {
            let id = try XCTUnwrap(rawDevice["deviceId"] as? String)
            let device = try XCTUnwrap(stats.device(id: id))
            let rawPeriods = try XCTUnwrap(rawDevice["periods"] as? [String: Any])
            for kind in UsagePeriodKind.allCases {
                guard let detail = device.detail(kind) else {
                    XCTAssertTrue(id == "old-laptop" && kind == .today, "\(id).\(kind.rawValue) missing")
                    continue
                }
                let raw = try XCTUnwrap(rawPeriods[kind.rawValue] as? [String: Any])
                try V2.assertPeriod(detail, matches: raw, "\(id).\(kind.rawValue)")
            }
        }
    }

    func testBreakdownDetails() throws {
        let today = try V2.stats(.compact).today
        XCTAssertEqual(today.explicitUnclassified, .all)
        XCTAssertTrue(today.hasClientModels)
        XCTAssertFalse(today.hasExactTokenComponents, "tokyo-mac has no components")

        let cursor = try XCTUnwrap(today.clientBreakdown["cursor"])
        XCTAssertEqual(cursor.tokens, 1_350_000)
        XCTAssertEqual(cursor.costUsd, 1.08, accuracy: 1e-9)
        XCTAssertNil(cursor.cacheReadTokens, "absent from clientCacheReads")
        XCTAssertNil(cursor.outputTokens)
        XCTAssertEqual(cursor.unclassifiedTokens, 1_350_000)
        XCTAssertNil(cursor.unpricedTokens)
        XCTAssertEqual(today.clientBreakdown["claude"]?.unclassifiedTokens, 18_200)
        XCTAssertEqual(today.clientBreakdown["opencode"]?.unpricedTokens, 90_000)

        let mystery = try XCTUnwrap(today.modelBreakdown["mystery-model-x"])
        XCTAssertEqual(mystery.tokens, 90_000)
        XCTAssertEqual(mystery.costUsd, 0)
        XCTAssertEqual(mystery.unpricedTokens, 90_000)
        XCTAssertEqual(mystery.cacheReadTokens, 77_400)
        XCTAssertNil(mystery.unclassifiedTokens)
        XCTAssertEqual(today.modelBreakdown["big-pickle"]?.costUsd, 0, "no cost entry is a zero cost")

        let opencode = try XCTUnwrap(today.clientModels["opencode"])
        XCTAssertEqual(Set(opencode.keys), ["big-pickle", "anthropic/claude-sonnet-4.5", "mystery-model-x"])
        XCTAssertEqual(opencode["mystery-model-x"], UsageBreakdownEntry(tokens: 90_000, costUsd: 0, unpricedTokens: 90_000))
        XCTAssertEqual(today.clientModels["codex"]?["unknown"]?.tokens, 650_000)
        XCTAssertEqual(Set(today.clientModels.keys), Set(today.clients.map(\.id)))

        let sonnet = try XCTUnwrap(today.modelThroughput?["claude-sonnet-4-5"])
        XCTAssertEqual(sonnet, ThroughputCounters(timedTokens: 41_220_000, timedOutputTokens: 870_200, timedDurationMs: 13_731_458))
        XCTAssertEqual(sonnet.outputTokensPerSecond ?? 0, 870_200 * 1000 / 13_731_458, accuracy: 1e-9)
        XCTAssertEqual(sonnet.tokensPerMinute ?? 0, 41_220_000 * 60000 / 13_731_458, accuracy: 1e-6)
        XCTAssertNil(try V2.stats(.compact).month.modelThroughput, "absent from the aggregate month")
        XCTAssertEqual(today.throughput.timedDurationMs, 21_649_230)
        XCTAssertNil(ThroughputCounters.zero.outputTokensPerSecond)
    }

    func testOlderPeriodsCarryNoPresenceMarkers() throws {
        let period = try JSONDecoder().decode(UsagePeriod.self, from: Data(#"{"totalTokens":5,"clients":{"a":5}}"#.utf8))
        XCTAssertEqual(period.explicitUnclassified, [])
        XCTAssertFalse(period.hasClientModels)
        XCTAssertNil(period.modelThroughput)
        XCTAssertEqual(period.clientBreakdown, ["a": UsageBreakdownEntry(tokens: 5)])
        XCTAssertEqual(period.clientModels, [:])

        // Presence is hasOwnProperty: null still counts; a cost-only key is a row.
        let json = #"{"unclassifiedTokens":null,"modelUnclassifiedTokens":{},"clientCosts":{"b":0.5},"clientModelCosts":{"b":{"m":0.5}},"clientModels":{"c":3}}"#
        let marked = try JSONDecoder().decode(UsagePeriod.self, from: Data(json.utf8))
        XCTAssertEqual(marked.explicitUnclassified, [.period, .models])
        XCTAssertEqual(marked.clientBreakdown, ["b": UsageBreakdownEntry(tokens: 0, costUsd: 0.5)])
        XCTAssertTrue(marked.hasClientModels)
        XCTAssertEqual(marked.clientModels, ["b": ["m": UsageBreakdownEntry(costUsd: 0.5)]], "a non-object client entry is skipped")
    }

    // MARK: - Sessions

    func testSessionsDecodeWithThreeStateTurnEnded() throws {
        let sessions = try V2.stats(.app).today.sessions
        func session(_ id: String) throws -> HubSession { try XCTUnwrap(sessions.first { $0.id == id }, id) }

        let running = try session("claude:7f3c2a90-1b2c-4d5e-8f90-a1b2c3d4e5f6")
        XCTAssertEqual(running.turnEnded, false)
        XCTAssertEqual(running.client, "claude")
        XCTAssertEqual(running.sessionId, "7f3c2a90-1b2c-4d5e-8f90-a1b2c3d4e5f6")
        XCTAssertEqual(running.title, "Refactor the collector watch loop")
        XCTAssertEqual(running.contextTokens, 190_900)
        XCTAssertEqual(running.contextWindow, 950_000)
        XCTAssertEqual(running.promptCache, PromptCacheObservation(observedAt: Fixture.date("2026-10-10T16:29:00.000Z"), ttlSeconds: 300))
        XCTAssertEqual(running.promptCache?.expiresAt, Fixture.date("2026-10-10T16:34:00.000Z"))
        XCTAssertEqual(running.lastUsedAt, Fixture.date("2026-10-10T16:28:00.000Z"))
        XCTAssertEqual(running.models, ["claude-sonnet-4-5": 3_200_000])
        XCTAssertNil(running.sessionKind)
        XCTAssertFalse(running.isArchived)

        XCTAssertEqual(try session("claude:0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d").turnEnded, true)
        XCTAssertEqual(try session("gemini:gemini-6c5b4a39").turnEnded, false)
        let noBoundary = try session("hermes:hermes-20261010-0815")
        XCTAssertNil(noBoundary.turnEnded, "absent means no boundary information, not false")
        XCTAssertNil(noBoundary.title, "an empty title is no title")
        XCTAssertEqual(noBoundary.projectId, "sha256:fixture-project-infra")
        XCTAssertEqual(noBoundary.projectLabel, "infra")
        XCTAssertEqual(noBoundary.providers, ["moonshotai": 1_000_000])
        XCTAssertEqual(noBoundary.modelCosts["moonshotai/kimi-k2-turbo"] ?? 0, 0.9, accuracy: 1e-9)
        XCTAssertEqual(noBoundary.startedAt, Fixture.date("2026-10-10T08:30:00.000Z"))
        XCTAssertEqual(noBoundary.messageCount, 13)
        XCTAssertEqual(noBoundary.timedOutputTokens, 18_000)
        XCTAssertEqual(noBoundary.timedDurationMs, 310_345)
        XCTAssertNil(noBoundary.promptCache)

        XCTAssertTrue(try session("codex:c4d5e6f7-a8b9-4c0d-8e1f-2a3b4c5d6e7f").isArchived)
        XCTAssertEqual(sessions.filter(\.isArchived).count, 1)
        XCTAssertEqual(sessions.filter(\.isBackgroundReview).count, 3)
        XCTAssertEqual(try session("opencode:ses_7a8b9c0d1e2f").unpricedTokens, 90_000)
        XCTAssertNil(try session("opencode:ses_6f1e2d3c4b5a").unpricedTokens)

        // Newest first, then id.
        let times = sessions.map { $0.activityTime ?? .distantPast }
        XCTAssertEqual(times, times.sorted(by: >))
    }

    func testSessionsMatchTheDesktopRowsGolden() throws {
        let stats = try V2.stats(.app)
        let golden = try V2.goldenObject("sessions.json")
        let scopes = try XCTUnwrap(golden["scopes"] as? [String: Any])
        for (scope, period) in [("aggregate.today", stats.today), ("aggregate.month", stats.month)] {
            let rows = try XCTUnwrap(((scopes[scope] as? [String: Any])?["now"] as? [String: Any])?["rows"] as? [[String: Any]])
            // sessionRowsForPeriod keeps sessions with tokens.
            let decoded = period.sessions.filter { $0.totalTokens > 0 }
            XCTAssertEqual(Set(decoded.map { "session:\($0.id)" }), Set(rows.compactMap { $0["key"] as? String }), scope)
            for row in rows {
                let key = try XCTUnwrap(row["key"] as? String)
                let session = try XCTUnwrap(decoded.first { "session:\($0.id)" == key }, key)
                XCTAssertEqual(session.totalTokens, row["value"] as? Int, key)
                XCTAssertEqual(session.costUsd, try XCTUnwrap(row["cost"] as? Double), accuracy: 1e-6, key)
                XCTAssertEqual(session.client, row["client"] as? String, key)
                XCTAssertEqual(session.unpricedTokens.flatMap { $0 > 0 ? $0 : nil }, row["unpricedTokens"] as? Int, key)
                XCTAssertEqual(session.isArchived, row["archived"] as? Bool ?? false, key)
                XCTAssertEqual(session.isBackgroundReview, row["backgroundReview"] as? Bool ?? false, key)
                XCTAssertEqual(session.activityTime.map(ISODate.string(from:)), row["sortTime"] as? String, key)
                if let snapshot = row["contextSnapshot"] as? [String: Any] {
                    XCTAssertEqual(session.contextTokens, snapshot["contextTokens"] as? Int, key)
                    XCTAssertEqual(session.contextWindow, snapshot["contextWindow"] as? Int, key)
                }
                if let cache = row["promptCache"] as? [String: Any] {
                    XCTAssertEqual(session.promptCache?.ttlSeconds, cache["ttlSeconds"] as? Int, key)
                    XCTAssertEqual(session.promptCache.map { ISODate.string(from: $0.expiresAt) }, cache["expiresAt"] as? String, key)
                }
            }
        }
    }

    func testMalformedSessionAndProjectRowsAreDropped() throws {
        let json = """
        {"periods":{"today":{"totalTokens":10,
          "sessions":{
            "a:1":{"client":"a","sessionId":"1","totalTokens":4,"turnEnded":"true","archived":"true"},
            "a:2":7, "a:3":"x", "a:4":null, "a:5":[1,2],
            "b:9":{"totalTokens":"6","turnEnded":false,"deleted":true,"promptCache":{"observedAt":"nope","ttlSeconds":300},
                   "models":{"m":"5","n":"x"},"title":"  ","sessionKind":"background-review"},
            "c:1":{"client":"c","sourceDeleted":true,"promptCache":{"observedAt":"2026-10-10T16:00:00Z","ttlSeconds":"1800"}}
          },
          "projects":{"p":{"label":"  Café  ","tokens":3,"clients":{"a":3,"b":"x"}},"q":5,"r":{"label":"","tokens":"2"},"s":null}
        }}}
        """
        let stats = try HubStats.decode(from: Data(json.utf8), options: .app)
        let sessions = stats.today.sessions
        XCTAssertEqual(stats.today.sessionCount, 7, "the count is of keys, as before")
        XCTAssertEqual(sessions.map(\.id).sorted(), ["a:1", "b:9", "c:1"])

        let first = try XCTUnwrap(sessions.first { $0.id == "a:1" })
        XCTAssertNil(first.turnEnded, "only a JSON boolean is a turn reading")
        XCTAssertFalse(first.isArchived, "only a JSON true archives")

        let second = try XCTUnwrap(sessions.first { $0.id == "b:9" })
        XCTAssertEqual(second.client, "")
        XCTAssertEqual(second.sessionId, "b:9", "the key stands in for a missing sessionId")
        XCTAssertEqual(second.totalTokens, 6)
        XCTAssertEqual(second.turnEnded, false)
        XCTAssertTrue(second.isArchived)
        XCTAssertNil(second.promptCache)
        XCTAssertEqual(second.models, ["m": 5])
        XCTAssertNil(second.title)
        XCTAssertTrue(second.isBackgroundReview)

        let third = try XCTUnwrap(sessions.first { $0.id == "c:1" })
        XCTAssertTrue(third.isArchived)
        XCTAssertEqual(third.promptCache?.ttlSeconds, 1800)

        XCTAssertEqual(stats.today.projects.map(\.id), ["p", "r"])
        XCTAssertEqual(stats.today.projects[0], ProjectRollup(id: "p", label: "Café", tokens: 3, clients: ["a": 3]))
        XCTAssertEqual(stats.today.projects[1].label, "r", "an empty label falls back to the key")
        XCTAssertEqual(stats.today.projects[1].tokens, 2)
    }

    // MARK: - Projects

    func testProjectsMatchTheDesktopRowsGolden() throws {
        let stats = try V2.stats(.app)
        let golden = try V2.goldenObject("projects.json")
        let scopes = try XCTUnwrap(golden["scopes"] as? [String: Any])
        let cases: [(String, UsagePeriod?)] = [
            ("aggregate.today", stats.today),
            ("aggregate.month", stats.month),
            ("aggregate.allTime", stats.allTime),
            ("device.studio-mac.month", stats.device(id: "studio-mac")?.detail(.month)),
            ("device.tokyo-mac.month", stats.device(id: "tokyo-mac")?.detail(.month))
        ]
        for (scope, period) in cases {
            let period = try XCTUnwrap(period, scope)
            let rows = try XCTUnwrap(scopes[scope] as? [[String: Any]], scope)
            XCTAssertEqual(period.projects.count, rows.count, scope)
            for row in rows {
                let key = try XCTUnwrap(row["key"] as? String)
                let project = try XCTUnwrap(period.projects.first { $0.id == key }, "\(scope) \(key)")
                XCTAssertEqual(project.label, row["name"] as? String, "\(scope) \(key)")
                XCTAssertEqual(project.tokens, row["value"] as? Int, "\(scope) \(key)")
                XCTAssertEqual(project.costUsd, try XCTUnwrap(row["cost"] as? Double), accuracy: 1e-6)
                XCTAssertEqual(project.unpricedTokens, row["unpricedTokens"] as? Int, "\(scope) \(key)")
                var clientTokens = try XCTUnwrap(row["clientTokens"] as? [String: Int])
                clientTokens[""] = nil // the golden's unknown-tool remainder
                XCTAssertEqual(project.clients, clientTokens, "\(scope) \(key)")
            }
        }
    }

    // MARK: - Devices

    func testDeviceV2Fields() throws {
        let stats = try V2.stats(.compact)
        let studio = try XCTUnwrap(stats.device(id: "studio-mac"))
        XCTAssertEqual(studio.agentRuntime, "electron-widget")
        XCTAssertEqual(studio.agentVersion, "0.70.0")
        XCTAssertEqual(studio.syncUploadInterval, 0, "0 uploads live")
        XCTAssertEqual(studio.projectsEnabled, true)
        XCTAssertEqual(studio.clientStatus, [
            "claude": "active", "codex": "active", "opencode": "active",
            "gemini": "waiting", "cursor": "missing", "antigravity": "missing"
        ])
        XCTAssertEqual(studio.sessionDetailsOmitted, [.month: 12])
        XCTAssertEqual(studio.periodProjectsOmitted, [:])
        XCTAssertFalse(studio.allTimeProjectsOmitted)
        XCTAssertFalse(studio.allTimeProjectsIncomplete)
        XCTAssertEqual(studio.periodTimeZone, "America/Los_Angeles")
        XCTAssertEqual(studio.timeZone?.identifier, "America/Los_Angeles")
        XCTAssertEqual(studio.todayWindowKey, "2026-10-10")
        XCTAssertEqual(studio.monthWindowKey, "2026-10")
        XCTAssertEqual(studio.todayEndsAt, Fixture.date("2026-10-11T07:00:00.000Z"))
        XCTAssertEqual(studio.monthEndsAt, Fixture.date("2026-11-01T07:00:00.000Z"))

        let build = try XCTUnwrap(stats.device(id: "build-box"))
        XCTAssertEqual(build.agentRuntime, "headless-agent")
        XCTAssertEqual(build.syncUploadInterval, 600)
        XCTAssertTrue(build.allTimeProjectsIncomplete)
        XCTAssertEqual(build.periodProjectsOmitted, [.month: 3])
        XCTAssertNil(build.clientHealth)
        XCTAssertEqual(build.clientStatus["qwen"], "waiting")

        let tokyo = try XCTUnwrap(stats.device(id: "tokyo-mac"))
        XCTAssertEqual(tokyo.projectsEnabled, false)
        XCTAssertEqual(tokyo.todayWindowKey, "2026-10-11")
        XCTAssertEqual(tokyo.periodTimeZone, "Asia/Tokyo")
        XCTAssertFalse(tokyo.today.isExpired)

        let laptop = try XCTUnwrap(stats.device(id: "old-laptop"))
        XCTAssertNil(laptop.syncUploadInterval, "not reported")
        XCTAssertTrue(laptop.isStale)
        XCTAssertEqual(laptop.periodTimeZone, "Asia/Shanghai")
    }

    func testDeviceUsageThroughputAndUnpriced() throws {
        let stats = try V2.stats(.compact)
        let studio = try XCTUnwrap(stats.device(id: "studio-mac"))
        let raw = try V2.devicePeriod("studio-mac", "today")
        XCTAssertTrue(studio.today.hasThroughput)
        XCTAssertEqual(studio.today.throughput, ThroughputCounters(
            timedTokens: try XCTUnwrap(raw["timedTokens"] as? Double),
            timedOutputTokens: try XCTUnwrap(raw["timedOutputTokens"] as? Double),
            timedDurationMs: try XCTUnwrap(raw["timedDurationMs"] as? Double)
        ))
        XCTAssertEqual(studio.today.modelThroughput?["claude-sonnet-4-5"],
                       ThroughputCounters(timedTokens: 35_100_000, timedOutputTokens: 741_000, timedDurationMs: 11_578_125))
        XCTAssertEqual(studio.today.unpricedTokens, raw["unpricedTokens"] as? Int)
        XCTAssertNil(studio.allTime.modelThroughput)
        XCTAssertFalse(studio.allTime.hasThroughput)
        XCTAssertNil(studio.allTime.throughput, "capabilities.throughput is false")

        let laptopMonth = try XCTUnwrap(stats.device(id: "old-laptop")).month
        XCTAssertFalse(laptopMonth.hasThroughput)

        let json = #"{"devices":[{"deviceId":"x","periods":{"today":{"capabilities":{"throughput":false},"timedTokens":1,"timedOutputTokens":1,"timedDurationMs":1},"month":{"timedTokens":1,"timedOutputTokens":"2","modelThroughput":{"a":{"timedTokens":1,"timedOutputTokens":1,"timedDurationMs":1},"b":{"timedTokens":1},"c":{"timedTokens":-1,"timedOutputTokens":1,"timedDurationMs":1}}},"allTime":{"modelThroughput":"x"}}}]}"#
        let device = try XCTUnwrap(HubStats.decode(from: Data(json.utf8)).devices.first)
        XCTAssertNil(device.today.throughput, "capabilities.throughput === false")
        XCTAssertNil(device.month.throughput, "timedDurationMs missing")
        XCTAssertEqual(device.month.modelThroughput, ["a": ThroughputCounters(timedTokens: 1, timedOutputTokens: 1, timedDurationMs: 1)])
        XCTAssertNil(device.allTime.modelThroughput)
    }

    func testClientHealthDecodes() throws {
        let studio = try XCTUnwrap(try V2.stats(.compact).device(id: "studio-mac"))
        let health = try XCTUnwrap(studio.clientHealth)
        XCTAssertEqual(health.version, 1)
        XCTAssertEqual(health.observedAt, Fixture.date("2026-10-10T16:29:35.000Z"))
        XCTAssertEqual(Set(health.clients.keys), ["claude", "codex", "opencode", "gemini", "cursor", "antigravity"])

        let opencode = try XCTUnwrap(health.entry(for: " OpenCode "))
        XCTAssertEqual(opencode.overall, .attention)
        XCTAssertEqual(opencode.sourceState, "detected")
        XCTAssertEqual(opencode.checks, [ClientHealthCheck(id: "opencode-data", exists: true)])
        XCTAssertEqual(opencode.collectionState, "failed")
        XCTAssertEqual(opencode.syncFailureStage, "timeout")
        XCTAssertEqual(opencode.syncExitCode, 124)
        XCTAssertEqual(opencode.syncDetailCode, "network-timeout")
        XCTAssertEqual(opencode.lastSuccessAt, Fixture.date("2026-10-10T13:30:00.000Z"))
        XCTAssertEqual(opencode.diagnostics, ["sync-timeout"])
        XCTAssertEqual(opencode.liveTokens, 1_090_000)

        let gemini = try XCTUnwrap(health.entry(for: "gemini"))
        XCTAssertEqual(gemini.checks, [], "no checks on the wire")
        XCTAssertEqual(gemini.checkedCount, 2)
        XCTAssertEqual(gemini.lastActivityDay, "2026-10-04")
        XCTAssertEqual(health.entry(for: "antigravity")?.overall, .unknown)
        XCTAssertNil(health.entry(for: "antigravity")?.lastActivityDay)
        XCTAssertNil(health.entry(for: "kimi"))

        // Every entry agrees with the desktop's clientHealthDetail golden.
        let golden = try V2.goldenObject("client-health.json")
        let devices = try XCTUnwrap(golden["devices"] as? [[String: Any]])
        let stats = try V2.stats(.compact)
        for goldenDevice in devices {
            let id = try XCTUnwrap(goldenDevice["deviceId"] as? String)
            let device = try XCTUnwrap(stats.device(id: id))
            XCTAssertEqual(device.clientHealth != nil, goldenDevice["hasHealth"] as? Bool, id)
            XCTAssertEqual(device.clientStatus, goldenDevice["clientStatus"] as? [String: String] ?? [:], id)
            let details = try XCTUnwrap(goldenDevice["details"] as? [String: [String: Any]])
            for (client, entry) in details {
                let decoded = device.clientHealth?.entry(for: client)
                XCTAssertEqual(decoded != nil, entry["has"] as? Bool, "\(id) \(client)")
                guard let decoded, let detail = entry["detail"] as? [String: Any] else { continue }
                XCTAssertEqual(decoded.overall.rawValue, detail["overall"] as? String, "\(id) \(client)")
                let groups = try XCTUnwrap(detail["groups"] as? [[String: Any]])
                let source = groups[0], collection = groups[1], data = groups[2]
                XCTAssertEqual(decoded.sourceState, source["state"] as? String)
                XCTAssertEqual(decoded.detectedCount, source["detectedCount"] as? Int)
                XCTAssertEqual(decoded.checkedCount, source["checkedCount"] as? Int)
                let checks = try XCTUnwrap(source["checks"] as? [[String: Any]])
                XCTAssertEqual(decoded.checks.map(\.id), checks.compactMap { $0["id"] as? String })
                XCTAssertEqual(decoded.checks.map(\.exists), checks.compactMap { $0["exists"] as? Bool })
                XCTAssertEqual(decoded.collectionState, collection["state"] as? String)
                XCTAssertEqual(decoded.lastAttemptAt.map(ISODate.string(from:)) ?? "", collection["lastAttemptAt"] as? String)
                XCTAssertEqual(decoded.lastSuccessAt.map(ISODate.string(from:)) ?? "", collection["lastSuccessAt"] as? String)
                XCTAssertEqual(decoded.liveTokens, data["tokens"] as? Int)
                XCTAssertEqual(decoded.lastActivityDay ?? "", data["lastActivityDay"] as? String)
                let notes = try XCTUnwrap(detail["notes"] as? [[String: Any]]).compactMap { $0["code"] as? String }
                XCTAssertTrue(Set(notes).isSubset(of: decoded.diagnostics), "\(id) \(client)")
                // The data group's per-period usage reads the device totals.
                if let periods = data["periods"] as? [[String: Any]] {
                    for row in periods {
                        let kind = try XCTUnwrap(UsagePeriodKind(rawValue: row["period"] as? String ?? ""))
                        let share = device.usage(kind).clients.first { $0.id == client }
                        XCTAssertEqual(share?.tokens ?? 0, row["tokens"] as? Int, "\(id) \(client) \(kind)")
                    }
                }
            }
        }
    }

    func testMalformedClientHealthIsLenient() throws {
        let json = """
        {"devices":[{"deviceId":"x","clientStatus":{"a":"active","b":3,"c":""},
          "clientHealth":{"version":"1","clients":{
            "a":{"overall":"HEALTHY","source":{"state":"detected","checks":[{"id":"k","exists":"yes"},{"exists":true},7]},
                 "collection":{"syncExitCode":"12"},"diagnostics":[{"code":"sync-failed"},"source-missing",{"nope":1},5,""]},
            "b":"broken","":{}, "c":{"overall":"weird"}}}}]}
        """
        let device = try XCTUnwrap(HubStats.decode(from: Data(json.utf8)).devices.first)
        XCTAssertEqual(device.clientStatus, ["a": "active"])
        let health = try XCTUnwrap(device.clientHealth)
        XCTAssertEqual(health.version, 1)
        XCTAssertEqual(Set(health.clients.keys), ["a", "c"])
        let entry = try XCTUnwrap(health.entry(for: "a"))
        XCTAssertEqual(entry.overall, .healthy)
        XCTAssertEqual(entry.checks, [ClientHealthCheck(id: "k", exists: false)])
        XCTAssertEqual(entry.collectionState, "unknown")
        XCTAssertEqual(entry.syncExitCode, 12)
        XCTAssertEqual(entry.diagnostics, ["sync-failed", "source-missing"])
        XCTAssertEqual(health.entry(for: "c")?.overall, .unknown)
        XCTAssertEqual(health.entry(for: "c")?.sourceState, "unknown")

        let unusable = try XCTUnwrap(HubStats.decode(from: Data(#"{"devices":[{"deviceId":"y","clientHealth":"x"}]}"#.utf8)).devices.first)
        XCTAssertNil(unusable.clientHealth)
    }

    func testExpiryBlanksDetailsToo() throws {
        let stats = try V2.stats(.app)
        let laptop = try XCTUnwrap(stats.device(id: "old-laptop"))
        // Its local day ended at 16:00Z; the Hub built the aggregate at 16:30Z.
        XCTAssertTrue(laptop.today.isExpired)
        XCTAssertEqual(laptop.today.tokens, 0)
        XCTAssertNil(laptop.detail(.today))
        XCTAssertFalse(laptop.month.isExpired)
        XCTAssertNotNil(laptop.detail(.month))
        XCTAssertNotNil(laptop.detail(.allTime))

        // Later, every device's day (and studio's month) has ended.
        var object = try V2.object("stats.json")
        object["updatedAt"] = "2026-11-01T08:00:00.000Z"
        let later = try HubStats.decode(from: JSONSerialization.data(withJSONObject: object), options: .app)
        for device in later.devices {
            XCTAssertNil(device.detail(.today), device.id)
            XCTAssertNil(device.detail(.month), device.id)
            XCTAssertNotNil(device.detail(.allTime), device.id)
            XCTAssertTrue(device.month.isExpired, device.id)
            XCTAssertEqual(device.sessionDetailsOmitted, [:], device.id)
            XCTAssertEqual(device.periodProjectsOmitted, [:], device.id)
        }
    }

    // MARK: - Stream

    func testV2StreamHonoursOptions() throws {
        var parser = ServerSentEventParser()
        let events = parser.consume(try V2.data("stats-stream.txt"))
        XCTAssertEqual(events.map(\.event), ["snapshot", "stats"])

        let compact = HubStreamDecoder()
        let app = HubStreamDecoder(options: .app)
        XCTAssertEqual(compact.options, .compact)
        let snapshot = try XCTUnwrap(compact.update(from: events[0]))
        XCTAssertEqual(snapshot.stats, try V2.stats(.compact), "the snapshot frame is the stats body")
        XCTAssertEqual(snapshot.stats.today.sessions, [])

        let full = try XCTUnwrap(app.update(from: events[1]))
        XCTAssertEqual(full.reason, "ingest")
        XCTAssertEqual(full.stats.today.sessions.count, 13)
        XCTAssertFalse(full.stats.device(id: "build-box")?.details.isEmpty ?? true)
        // build-box re-uploaded today (each component scaled by 1.04).
        XCTAssertEqual(snapshot.stats.device(id: "build-box")?.today.tokens, 9_835_000)
        XCTAssertEqual(full.stats.device(id: "build-box")?.today.tokens, 10_225_400)
        XCTAssertEqual(full.stats.device(id: "build-box")?.detail(.today)?.totalTokens, 10_225_400)
    }
}

// MARK: - Fixture helpers

/// Loads `Fixtures/v2` (the round-1 `Fixture.data` only reads `Fixtures`).
private enum V2 {
    static func data(_ name: String, subdirectory: String = "Fixtures/v2") throws -> Data {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let url = Bundle.module.url(
            forResource: parts[0],
            withExtension: parts.count > 1 ? parts[1] : nil,
            subdirectory: subdirectory
        ) else {
            throw NSError(domain: "V2Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing fixture \(subdirectory)/\(name)"])
        }
        return try Data(contentsOf: url)
    }

    static func stats(_ options: HubDecodingOptions) throws -> HubStats {
        try HubStats.decode(from: data("stats.json"), options: options)
    }

    static func object(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(name)) as? [String: Any])
    }

    static func goldenObject(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(name, subdirectory: "Fixtures/v2/golden")) as? [String: Any])
    }

    /// The JSON of a nested object of `stats.json`, by key path.
    static func periodData(_ path: [String]) throws -> Data {
        var value: Any = try object("stats.json")
        for key in path { value = try XCTUnwrap((value as? [String: Any])?[key], key) }
        return try JSONSerialization.data(withJSONObject: value)
    }

    static func devicePeriod(_ deviceID: String, _ period: String) throws -> [String: Any] {
        let devices = try XCTUnwrap(object("stats.json")["devices"] as? [[String: Any]])
        let device = try XCTUnwrap(devices.first { $0["deviceId"] as? String == deviceID })
        return try XCTUnwrap((device["periods"] as? [String: Any])?[period] as? [String: Any])
    }

    /// Compares every breakdown entry with the raw maps it came from.
    /// Doubles read through JSONSerialization can be an ulp off on Linux, so
    /// costs compare with a tolerance.
    static func assertPeriod(_ period: UsagePeriod, matches raw: [String: Any], _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        func map(_ key: String) -> [String: Double] {
            ((raw[key] as? [String: Any]) ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
        }
        func check(_ breakdown: [String: UsageBreakdownEntry], prefix: String, components: Bool) {
            let tokens = map(prefix + "s"), costs = map(prefix + "Costs"), unpriced = map(prefix + "UnpricedTokens")
            let keys = Set(tokens.keys).union(costs.keys).union(unpriced.keys)
            XCTAssertEqual(Set(breakdown.keys), keys, "\(label) \(prefix) keys", file: file, line: line)
            for key in keys {
                guard let entry = breakdown[key] else { continue }
                XCTAssertEqual(Double(entry.tokens), tokens[key] ?? 0, "\(label) \(prefix) \(key)", file: file, line: line)
                XCTAssertEqual(entry.costUsd, costs[key] ?? 0, accuracy: 1e-9, "\(label) \(prefix) \(key)", file: file, line: line)
                XCTAssertEqual(entry.unpricedTokens.map(Double.init), unpriced[key], "\(label) \(prefix) \(key)", file: file, line: line)
                guard components else { continue }
                XCTAssertEqual(entry.cacheReadTokens.map(Double.init), map(prefix + "CacheReads")[key], "\(label) \(prefix) \(key)", file: file, line: line)
                XCTAssertEqual(entry.cacheWriteTokens.map(Double.init), map(prefix + "CacheWrites")[key], "\(label) \(prefix) \(key)", file: file, line: line)
                XCTAssertEqual(entry.outputTokens.map(Double.init), map(prefix + "Outputs")[key], "\(label) \(prefix) \(key)", file: file, line: line)
                XCTAssertEqual(entry.unclassifiedTokens.map(Double.init), map(prefix + "UnclassifiedTokens")[key], "\(label) \(prefix) \(key)", file: file, line: line)
            }
        }
        check(period.clientBreakdown, prefix: "client", components: true)
        check(period.modelBreakdown, prefix: "model", components: true)

        let clientModels = (raw["clientModels"] as? [String: [String: Any]]) ?? [:]
        let clientModelCosts = (raw["clientModelCosts"] as? [String: [String: Any]]) ?? [:]
        let clientModelUnpriced = (raw["clientModelUnpricedTokens"] as? [String: [String: Any]]) ?? [:]
        XCTAssertEqual(Set(period.clientModels.keys), Set(clientModels.keys).union(clientModelCosts.keys), "\(label) clientModels", file: file, line: line)
        for (client, models) in period.clientModels {
            let tokens = (clientModels[client] ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
            let costs = (clientModelCosts[client] ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
            let unpriced = (clientModelUnpriced[client] ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
            XCTAssertEqual(Set(models.keys), Set(tokens.keys).union(costs.keys).union(unpriced.keys), "\(label) \(client)", file: file, line: line)
            for (model, entry) in models {
                XCTAssertEqual(Double(entry.tokens), tokens[model] ?? 0, "\(label) \(client) \(model)", file: file, line: line)
                XCTAssertEqual(entry.costUsd, costs[model] ?? 0, accuracy: 1e-9, "\(label) \(client) \(model)", file: file, line: line)
                XCTAssertEqual(entry.unpricedTokens.map(Double.init), unpriced[model], "\(label) \(client) \(model)", file: file, line: line)
                XCTAssertNil(entry.cacheReadTokens, file: file, line: line)
            }
        }

        var presence: UnclassifiedPresence = []
        if raw.keys.contains("unclassifiedTokens") { presence.insert(.period) }
        if raw.keys.contains("clientUnclassifiedTokens") { presence.insert(.clients) }
        if raw.keys.contains("modelUnclassifiedTokens") { presence.insert(.models) }
        XCTAssertEqual(period.explicitUnclassified, presence, "\(label) presence", file: file, line: line)
        XCTAssertEqual(period.hasClientModels, raw["clientModels"] is [String: Any] || raw["clientModelCosts"] is [String: Any], file: file, line: line)

        let throughput = raw["modelThroughput"] as? [String: [String: Any]]
        XCTAssertEqual(period.modelThroughput?.count, throughput?.count, "\(label) modelThroughput", file: file, line: line)
        for (model, counters) in throughput ?? [:] {
            let decoded = period.modelThroughput?[model]
            XCTAssertEqual(decoded?.timedTokens, (counters["timedTokens"] as? NSNumber)?.doubleValue, "\(label) \(model)", file: file, line: line)
            XCTAssertEqual(decoded?.timedOutputTokens, (counters["timedOutputTokens"] as? NSNumber)?.doubleValue, "\(label) \(model)", file: file, line: line)
            XCTAssertEqual(decoded?.timedDurationMs, (counters["timedDurationMs"] as? NSNumber)?.doubleValue, "\(label) \(model)", file: file, line: line)
        }

        if let sessions = raw["sessions"] as? [String: Any] {
            XCTAssertEqual(period.sessionCount, sessions.count, "\(label) sessionCount", file: file, line: line)
            XCTAssertEqual(Set(period.sessions.map(\.id)), Set(sessions.keys), "\(label) sessions", file: file, line: line)
            for session in period.sessions {
                let wire = sessions[session.id] as? [String: Any]
                switch wire?["turnEnded"] {
                case let flag as Bool: XCTAssertEqual(session.turnEnded, flag, "\(label) \(session.id)", file: file, line: line)
                default: XCTAssertNil(session.turnEnded, "\(label) \(session.id)", file: file, line: line)
                }
            }
        }
        if let projects = raw["projects"] as? [String: Any] {
            XCTAssertEqual(Set(period.projects.map(\.id)), Set(projects.keys), "\(label) projects", file: file, line: line)
        }
    }
}

import Foundation
import XCTest
@testable import TokenMonitorKit

final class TokenSnapshotTests: XCTestCase {
    private let fetchedAt = Fixture.date("2026-10-09T02:50:00Z")

    private func snapshot() throws -> TokenSnapshot {
        TokenSnapshot(stats: try Fixture.stats(), fetchedAt: fetchedAt, calendar: Fixture.utc)
    }

    func testProjection() throws {
        let snapshot = try snapshot()
        XCTAssertEqual(snapshot.schemaVersion, TokenSnapshot.currentSchemaVersion)
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.sourceUpdatedAt, Fixture.date("2026-10-09T02:47:57.136Z"))
        XCTAssertFalse(snapshot.isSourceStale)
        XCTAssertEqual(snapshot.devices, DeviceCounts(online: 2, total: 3))
        XCTAssertEqual(snapshot.devices.stale, 1)

        let today = snapshot.today
        XCTAssertEqual(today.kind, .today)
        XCTAssertEqual(today.totalTokens, 72_250_000)
        XCTAssertEqual(today.costUsd, 122.825, accuracy: 1e-9)
        XCTAssertEqual(today.outputTokensPerSecond ?? 0, 62, accuracy: 0.1)
        XCTAssertEqual(today.tools.map(\.id), ["claude", "codex", "hermes", "opencode", "cursor", "gemini"])
        XCTAssertEqual(today.tools.first?.label, "Claude", "compact surfaces use the limits name")
        XCTAssertEqual(today.otherToolTokens, 0)
        XCTAssertEqual(today.models.count, TokenSnapshot.maxShares)
        XCTAssertEqual(today.otherModelTokens, 900_000 + 450_000)
        XCTAssertEqual(today.models(otherLabel: "Other").last?.tokens, 1_350_000)
        XCTAssertEqual(today.components.total, 72_250_000)

        let month = snapshot[.month]
        XCTAssertEqual(month.tools.count, TokenSnapshot.maxShares)
        XCTAssertEqual(month.otherToolTokens, 4_200_000 + 990_000)
        XCTAssertEqual(month.tools(otherLabel: "Other").count, TokenSnapshot.maxShares + 1)

        XCTAssertEqual(snapshot.limits.map(\.provider), ["claude", "codex", "opencode", "deepseek", "openrouter", "cursor", "kimi"])
        XCTAssertEqual(snapshot.limits[0].accountEmail, "d***v@example.com", "emails are masked in shared containers")
        XCTAssertEqual(snapshot.limits[1].windows.count, 2, "additional Codex buckets are dropped")
        XCTAssertTrue(snapshot.limits.allSatisfy { $0.windows.count <= TokenSnapshot.maxWindowsPerProvider })

        XCTAssertEqual(snapshot.trend.count, TokenSnapshot.maxTrendDays)
        XCTAssertEqual(snapshot.trend.last?.date, "2026-10-09")
        XCTAssertEqual(snapshot.trend.last?.tokens, 72_250_000)
        XCTAssertEqual(snapshot.trend.first?.date, "2026-09-10")
    }

    func testStaysSmall() throws {
        let data = try snapshot().jsonData()
        XCTAssertLessThan(data.count, 16 * 1024, "snapshot is \(data.count) bytes")
    }

    func testCodableRoundTrip() throws {
        let original = try snapshot()
        XCTAssertEqual(try TokenSnapshot(jsonData: original.jsonData()), original)
        // Dates are encoded by hand, so plain coders round-trip too.
        let plain = try JSONDecoder().decode(TokenSnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(plain, original)
    }

    func testDecodingToleratesMissingParts() throws {
        let snapshot = try TokenSnapshot(jsonData: Data(#"{"schemaVersion":1,"fetchedAt":"2026-10-09T02:50:00Z"}"#.utf8))
        XCTAssertEqual(snapshot.today.totalTokens, 0)
        XCTAssertEqual(snapshot.limits, [])
        XCTAssertThrowsError(try TokenSnapshot(jsonData: Data(#"{"schemaVersion":1}"#.utf8)))
    }

    func testAge() throws {
        let snapshot = try snapshot()
        XCTAssertFalse(snapshot.isOlder(than: 600, at: fetchedAt.addingTimeInterval(300)))
        XCTAssertTrue(snapshot.isOlder(than: 600, at: fetchedAt.addingTimeInterval(601)))
    }

    func testRecordsWhichHubItCameFrom() throws {
        let hub = try HubConnection(userInput: "http://192.168.1.10:17321", secret: "s3cret")
        let other = try HubConnection(userInput: "https://hub.example.com", secret: "s3cret")
        let stamped = TokenSnapshot(stats: try Fixture.stats(), fetchedAt: fetchedAt, hub: hub, calendar: Fixture.utc)
        XCTAssertEqual(stamped.hubKey, hub.snapshotKey)
        XCTAssertTrue(stamped.belongs(to: hub))
        XCTAssertTrue(stamped.belongs(to: HubConnection(baseURL: hub.baseURL, secret: "rotated")), "a new secret keeps the cache")
        XCTAssertFalse(stamped.belongs(to: other), "another Hub's numbers")
        XCTAssertFalse(stamped.belongs(to: nil), "no Hub, nothing to show")
        XCTAssertTrue(stamped.belongs(toHubKey: hub.snapshotKey))
        XCTAssertFalse(stamped.belongs(toHubKey: nil))

        let json = String(decoding: try stamped.jsonData(), as: UTF8.self)
        XCTAssertTrue(json.contains(#""hubKey":"\#(hub.snapshotKey)""#))
        XCTAssertFalse(json.contains("s3cret"))
        XCTAssertFalse(json.contains("192.168.1.10"), "the key, not the address")
        XCTAssertEqual(try TokenSnapshot(jsonData: stamped.jsonData()), stamped)

        var unstamped = stamped
        unstamped.hubKey = nil
        XCTAssertNotEqual(unstamped, stamped)
        XCTAssertEqual(try snapshot(), unstamped, "the hub parameter defaults to nil")
    }

    func testSnapshotsWithoutAHubKeyStayReadable() throws {
        let legacy = try TokenSnapshot(jsonData: Data(#"{"schemaVersion":1,"fetchedAt":"2026-10-09T02:50:00Z"}"#.utf8))
        XCTAssertNil(legacy.hubKey)
        XCTAssertLessThanOrEqual(legacy.schemaVersion, TokenSnapshot.currentSchemaVersion, "no schema bump: older files still load")
        XCTAssertTrue(legacy.belongs(to: try HubConnection(userInput: "https://hub.example.com", secret: "")), "unknown origin is shown, not dropped")
        XCTAssertFalse(legacy.belongs(to: nil))
        XCTAssertFalse(String(decoding: try snapshot().jsonData(), as: UTF8.self).contains("hubKey"), "no key is written without a Hub")
        let blank = try TokenSnapshot(jsonData: Data(#"{"schemaVersion":1,"fetchedAt":"2026-10-09T02:50:00Z","hubKey":"  "}"#.utf8))
        XCTAssertNil(blank.hubKey)
    }

    func testIsCurrentFollowsTheCalendarDayAndMonth() {
        let snapshot = TokenSnapshot(
            fetchedAt: Fixture.date("2026-09-30T23:50:00Z"),
            today: PeriodSummary(kind: .today, totalTokens: 1),
            month: PeriodSummary(kind: .month, totalTokens: 2),
            allTime: PeriodSummary(kind: .allTime, totalTokens: 3)
        )
        let utc = Fixture.utc
        let lateSameDay = Fixture.date("2026-09-30T23:59:59Z")
        let midnight = Fixture.date("2026-10-01T00:00:00Z")
        XCTAssertTrue(snapshot.isCurrent(.today, at: lateSameDay, calendar: utc))
        XCTAssertFalse(snapshot.isCurrent(.today, at: midnight, calendar: utc), "after midnight today is another day")
        XCTAssertTrue(snapshot.isCurrent(.month, at: lateSameDay, calendar: utc))
        XCTAssertFalse(snapshot.isCurrent(.month, at: midnight, calendar: utc), "after the last day this month is another month")
        XCTAssertTrue(snapshot.isCurrent(.month, at: Fixture.date("2026-09-01T00:00:00Z"), calendar: utc))
        XCTAssertFalse(snapshot.isCurrent(.month, at: Fixture.date("2027-09-15T00:00:00Z"), calendar: utc), "same month, next year")
        XCTAssertTrue(snapshot.isCurrent(.allTime, at: Fixture.date("2027-09-15T00:00:00Z"), calendar: utc))

        // The device's calendar decides: 23:50 UTC is already 1 October in Tokyo.
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertTrue(snapshot.isCurrent(.today, at: midnight, calendar: tokyo))
        XCTAssertTrue(snapshot.isCurrent(.month, at: midnight, calendar: tokyo))
        XCTAssertFalse(snapshot.isCurrent(.today, at: lateSameDay.addingTimeInterval(-9 * 3600), calendar: tokyo))
    }
}

final class SnapshotStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenMonitorKitTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTripAndClear() throws {
        let store = SnapshotStore(directory: directory)
        XCTAssertNil(store.load())
        let snapshot = TokenSnapshot(stats: try Fixture.stats(), fetchedAt: Fixture.date("2026-10-09T02:50:00Z"), calendar: Fixture.utc)
        try store.save(snapshot)
        XCTAssertEqual(store.load(), snapshot)
        XCTAssertEqual(store.fileURL.lastPathComponent, SnapshotStore.fileName)

        var newer = snapshot
        newer.today.totalTokens += 1
        try store.save(newer)
        XCTAssertEqual(store.load(), newer)

        try store.clear()
        XCTAssertNil(store.load())
        XCTAssertNoThrow(try store.clear())
    }

    func testIgnoresCorruptAndFutureFiles() throws {
        let store = SnapshotStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.fileURL)
        XCTAssertNil(store.load())

        var future = TokenSnapshot(stats: try Fixture.stats(), fetchedAt: Date(), calendar: Fixture.utc)
        future.schemaVersion = TokenSnapshot.currentSchemaVersion + 1
        try store.save(future)
        XCTAssertNil(store.load(), "a newer schema may mean something else")
    }
}

/// `SnapshotBuilder` over the `Fixtures/v2` capture.
final class SnapshotBuilderTests: XCTestCase {
    private let fetchedAt = PipelineFixture.now

    private func build(_ preferences: DisplayPreferences = .defaults, aliases: ModelAliasDocument? = nil,
                       hub: HubConnection? = nil) throws -> TokenSnapshot {
        SnapshotBuilder(preferences: preferences, aliases: aliases)
            .snapshot(from: try PipelineFixture.stats(.compact), fetchedAt: fetchedAt, hub: hub, calendar: Fixture.utc)
    }

    func testDefaultsProjectAllDevices() throws {
        let stats = try PipelineFixture.stats(.compact)
        let snapshot = try build()
        XCTAssertNil(snapshot.scope)
        XCTAssertEqual(snapshot.requestedScope, .all)
        XCTAssertFalse(snapshot.isDeviceScoped)
        XCTAssertNil(snapshot.aliasRevision)
        XCTAssertEqual(snapshot.projectionKey, SnapshotBuilder().projectionKey)
        XCTAssertEqual(snapshot.today.totalTokens, 73_237_000)
        XCTAssertEqual(snapshot.today.unpricedTokens, 90_000)
        XCTAssertEqual(snapshot.month.unpricedTokens, 965_000)
        XCTAssertEqual(snapshot.today.tools.map(\.id), ["claude", "codex", "hermes", "cursor", "opencode", "gemini"])
        XCTAssertEqual(snapshot.devices, DeviceCounts(online: 3, total: 4))
        XCTAssertEqual(snapshot.sourceUpdatedAt, stats.newestDeviceActivity)
        XCTAssertFalse(snapshot.isSourceStale)
        XCTAssertEqual(snapshot.trend.count, TokenSnapshot.maxTrendDays)
        XCTAssertEqual(snapshot.trend.last?.date, "2026-10-10")
        XCTAssertEqual(snapshot.trend.last?.tokens, 73_237_000)

        // Limits: catalog order (not "ready first"), compacted.
        XCTAssertEqual(snapshot.limits.map(\.provider), [
            "claude", "codex", "cursor", "antigravity", "cline", "kimi", "copilot", "zed", "mimo", "zai",
            "workbuddy", "deepseek", "typesafe", "openrouter", "thirdparty"
        ])
        XCTAssertEqual(snapshot.limits, OrderedIDs.ordered(stats.limits, id: \.provider, order: [], known: VendorCatalog.limitProviders.map(\.id)).map { $0.compacted() })
        for provider in snapshot.limits {
            XCTAssertTrue(provider.windows.allSatisfy { !$0.isAdditional }, provider.provider)
            XCTAssertLessThanOrEqual(provider.windows.count, TokenSnapshot.maxWindowsPerProvider)
            XCTAssertNil(provider.resetCredits)
            XCTAssertNil(provider.usageSummary)
            XCTAssertNil(provider.sourceDeviceId)
            XCTAssertTrue(provider.balance?.tranches.isEmpty ?? true)
            if let email = provider.accountEmail { XCTAssertTrue(email.contains("***"), "\(provider.provider) email stays masked") }
        }
    }

    func testStaysWithinTheBudget() throws {
        var preferences = DisplayPreferences.defaults
        for scope in [DeviceScope.all, .device("studio-mac"), .device("retired-box")] {
            preferences.deviceScope = scope
            let data = try build(preferences, aliases: try PipelineFixture.aliases()).jsonData()
            XCTAssertLessThan(data.count, 16 * 1024, "\(scope.storageValue): \(data.count) bytes")
        }
    }

    func testDeviceScope() throws {
        var preferences = DisplayPreferences.defaults
        preferences.deviceScope = .device("studio-mac")
        let snapshot = try build(preferences)
        XCTAssertEqual(snapshot.scope, SnapshotScope(deviceID: "studio-mac", deviceName: "studio-mac", isStale: false, isMissing: false))
        XCTAssertTrue(snapshot.isDeviceScoped)
        XCTAssertEqual(snapshot.requestedScope, .device("studio-mac"))
        XCTAssertEqual(snapshot.today.totalTokens, 61_792_000)
        XCTAssertEqual(snapshot.today.tools.map(\.id), ["claude", "codex", "opencode"])
        XCTAssertEqual(snapshot.today.unpricedTokens, 90_000)
        XCTAssertEqual(snapshot.allTime.totalTokens, 4_184_233_600)
        XCTAssertEqual(snapshot.trend, [], "a device's History is not part of stats")
        XCTAssertEqual(snapshot.sourceUpdatedAt, Fixture.date("2026-10-10T16:29:40Z"))
        XCTAssertEqual(snapshot.devices, DeviceCounts(online: 3, total: 4), "the device count is the Hub's")
        XCTAssertEqual(snapshot.limits, try build().limits, "limits never follow the scope")

        preferences.deviceScope = .device("old-laptop")
        let stale = try build(preferences)
        XCTAssertEqual(stale.scope?.isStale, true)
        XCTAssertTrue(stale.isSourceStale)
        XCTAssertEqual(stale.today.totalTokens, 0, "its day has ended")
        XCTAssertEqual(stale.month.totalTokens, 10_800_000)

        preferences.deviceScope = .device("retired-box")
        let missing = try build(preferences)
        XCTAssertEqual(missing.scope, SnapshotScope(deviceID: "retired-box", deviceName: "retired-box", isStale: false, isMissing: true))
        XCTAssertFalse(missing.isDeviceScoped)
        XCTAssertEqual(missing.requestedScope, .device("retired-box"))
        XCTAssertEqual(missing.today, try build().today, "a missing device shows all devices")
        XCTAssertEqual(missing.trend, try build().trend)
    }

    func testToolPreferencesShapeTheToolRows() throws {
        var preferences = DisplayPreferences.defaults
        preferences.clientDisplayOrder = ["codex"]
        XCTAssertEqual(try build(preferences).today.tools.map(\.id), ["codex", "claude", "opencode", "hermes", "cursor", "gemini"])

        preferences = .defaults
        preferences.pinnedClients = ["cursor"]
        XCTAssertEqual(try build(preferences).today.tools.map(\.id), ["cursor", "claude", "codex", "hermes", "opencode", "gemini"])

        preferences = .defaults
        preferences.hiddenClients = ["hermes"]
        let hidden = try build(preferences).today
        XCTAssertEqual(hidden.tools.map(\.id), ["claude", "codex", "cursor", "opencode", "gemini"])
        XCTAssertEqual(hidden.otherToolTokens, hidden.totalTokens - hidden.tools.reduce(0) { $0 + $1.tokens })
        XCTAssertGreaterThanOrEqual(hidden.otherToolTokens, 2_510_000, "hidden tools count as other")
        XCTAssertEqual(hidden.tools.first?.label, "Claude", "compact labels")

        // Month has more tools than fit: the order applies before the cut.
        preferences = .defaults
        preferences.clientDisplayOrder = ["qwen", "kimi"]
        let month = try build(preferences).month
        XCTAssertEqual(Array(month.tools.map(\.id).prefix(2)), ["qwen", "kimi"])
        XCTAssertEqual(month.tools.count, TokenSnapshot.maxShares)
    }

    func testLimitPreferencesShapeTheLimitsRows() throws {
        let stats = try PipelineFixture.stats(.compact)
        let claude = try XCTUnwrap(stats.limits.first { $0.provider == "claude" })
        let visible = claude.primaryWindows
        XCTAssertGreaterThan(visible.count, 1)
        let hiddenID = claude.usageItemID(for: visible[0])

        var preferences = DisplayPreferences.defaults
        preferences.limitProviderOrder = ["zed", "deepseek"]
        preferences.limitProviderHiddenItems = ["claude": [hiddenID]]
        let snapshot = try build(preferences)
        XCTAssertEqual(Array(snapshot.limits.map(\.provider).prefix(4)), ["zed", "deepseek", "claude", "codex"])
        let compacted = try XCTUnwrap(snapshot.limits.first { $0.provider == "claude" })
        XCTAssertEqual(compacted.windows.map(\.id), Array(visible.dropFirst().prefix(TokenSnapshot.maxWindowsPerProvider)).map(\.id))
        XCTAssertFalse(compacted.windows.contains { compacted.usageItemID(for: $0) == hiddenID })
    }

    func testAliasesFoldTheModelRows() throws {
        let document = try PipelineFixture.aliases()
        let snapshot = try build(aliases: document)
        XCTAssertEqual(snapshot.aliasRevision, 1)
        let stats = try PipelineFixture.stats(.compact)
        let resolver = try XCTUnwrap(ModelAliasResolver.forStats(stats, document: document))
        for kind in UsagePeriodKind.allCases {
            let expected = Array(stats[kind].projectingModelAliases(resolver).models.prefix(TokenSnapshot.maxShares))
            XCTAssertEqual(snapshot[kind].models, expected, kind.rawValue)
        }
        XCTAssertEqual(snapshot.today.models.first?.id, "claude-sonnet-4-5")
        XCTAssertEqual(snapshot.today.models.first?.tokens, 46_400_000, "anthropic/claude-sonnet-4.5 folded in")
        XCTAssertFalse(snapshot.today.models.contains { $0.id == "gpt-5-codex-high" })
        XCTAssertEqual(snapshot.today.models.first { $0.id == "gpt-5-codex" }?.tokens, 11_750_000)
        XCTAssertNotEqual(snapshot.projectionKey, try build().projectionKey)

        // A group never initialized is no document at all.
        let plain = try build(aliases: .uninitialized)
        XCTAssertEqual(plain, try build())
        XCTAssertNil(plain.aliasRevision)
    }

    func testProjectionKeyIsStable() {
        let base = SnapshotBuilder()
        XCTAssertEqual(base.projectionKey, SnapshotBuilder(preferences: .defaults, aliases: nil).projectionKey)
        XCTAssertEqual(base.projectionKey.count, 16)
        // Pinned: a change here invalidates every cached snapshot once.
        XCTAssertEqual(base.projectionKey, "af1a40c9ed41c84d")

        var preferences = DisplayPreferences.defaults
        preferences.hiddenClients = [" Hermes ", "hermes"]
        preferences.currency = .twd
        preferences.showToolIcons = false
        var normalized = DisplayPreferences.defaults
        normalized.hiddenClients = ["hermes"]
        XCTAssertEqual(SnapshotBuilder(preferences: preferences).projectionKey, SnapshotBuilder(preferences: normalized).projectionKey,
                       "normalized equal settings, and display-only settings, give the same key")
        var assigned = SnapshotBuilder()
        assigned.preferences = preferences
        XCTAssertEqual(assigned.preferences, preferences.normalized(), "assigned preferences are normalized too")
        XCTAssertEqual(assigned.projectionKey, SnapshotBuilder(preferences: normalized).projectionKey)
        XCTAssertEqual(SnapshotBuilder(aliases: .uninitialized).projectionKey, base.projectionKey)

        func key(_ mutate: (inout DisplayPreferences) -> Void, aliases: ModelAliasDocument? = nil) -> String {
            var preferences = DisplayPreferences.defaults
            mutate(&preferences)
            return SnapshotBuilder(preferences: preferences, aliases: aliases).projectionKey
        }
        let keys = [
            base.projectionKey,
            key { $0.deviceScope = .device("studio-mac") },
            key { $0.deviceScope = .device("build-box") },
            key { _ in },
            key({ _ in }, aliases: ModelAliasDocument(revision: 1)),
            key({ _ in }, aliases: ModelAliasDocument(revision: 2)),
            key { $0.clientDisplayOrder = ["codex"] },
            key { $0.hiddenClients = ["codex"] },
            key { $0.pinnedClients = ["codex"] },
            key { $0.limitProviderOrder = ["codex"] },
            key { $0.limitProviderHiddenItems = ["claude": ["credits"]] },
            key { $0.limitProviderHiddenItems = ["claude": ["spend"]] }
        ]
        XCTAssertEqual(keys[0], keys[3])
        XCTAssertEqual(Set(keys).count, keys.count - 1, "every other projection input changes the key")
    }

    func testFreshnessChecks() throws {
        let hub = try HubConnection(userInput: "http://hub.test:17321", secret: "s3cret")
        var preferences = DisplayPreferences.defaults
        preferences.deviceScope = .device("studio-mac")
        let builder = SnapshotBuilder(preferences: preferences)
        let snapshot = builder.snapshot(from: try PipelineFixture.stats(.compact), fetchedAt: fetchedAt, hub: hub, calendar: Fixture.utc)
        XCTAssertTrue(snapshot.matches(projectionKey: builder.projectionKey))
        XCTAssertTrue(builder.isCurrent(snapshot, hubKey: hub.snapshotKey))
        XCTAssertFalse(builder.isCurrent(snapshot, hubKey: "other"))
        XCTAssertFalse(SnapshotBuilder().isCurrent(snapshot, hubKey: hub.snapshotKey), "another scope is due for a refresh")

        let legacy = TokenSnapshot(stats: try Fixture.stats(), fetchedAt: fetchedAt, hub: hub, calendar: Fixture.utc)
        XCTAssertFalse(SnapshotBuilder().isCurrent(legacy, hubKey: hub.snapshotKey), "a snapshot from before projections predates the key")
        XCTAssertTrue(legacy.belongs(to: hub), "but is still shown as a fallback")
    }

    func testNewFieldsRoundTripAndOldSnapshotsStillDecode() throws {
        var preferences = DisplayPreferences.defaults
        preferences.deviceScope = .device("old-laptop")
        let snapshot = try build(preferences, aliases: try PipelineFixture.aliases(), hub: HubConnection(userInput: "http://hub.test:17321", secret: ""))
        XCTAssertEqual(try TokenSnapshot(jsonData: snapshot.jsonData()), snapshot)
        let plain = try JSONDecoder().decode(TokenSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(plain, snapshot)
        let json = String(decoding: try snapshot.jsonData(), as: UTF8.self)
        XCTAssertTrue(json.contains(#""scope":{"deviceID":"old-laptop","deviceName":"old-laptop","isStale":true}"#), json)
        XCTAssertTrue(json.contains(#""aliasRevision":1"#))

        // A file from the first schema: no scope, no aliases, no key, no unpriced tokens.
        let legacyJSON = #"""
        {"allTime":{"cacheReadTokens":0,"cacheWriteTokens":0,"costUsd":3,"kind":"allTime","models":[],"otherModelTokens":0,"otherToolTokens":0,"outputTokens":0,"tools":[],"totalTokens":30,"unclassifiedTokens":0},
         "devices":{"online":1,"total":1},"fetchedAt":"2026-10-09T02:50:00Z","hubKey":"k","isSourceStale":true,"limits":[],
         "month":{"cacheReadTokens":0,"cacheWriteTokens":0,"costUsd":2,"kind":"month","models":[],"otherModelTokens":0,"otherToolTokens":0,"outputTokens":0,"tools":[],"totalTokens":20,"unclassifiedTokens":0},
         "schemaVersion":1,"sourceUpdatedAt":"2026-10-09T02:47:57.136Z",
         "today":{"cacheReadTokens":0,"cacheWriteTokens":0,"costUsd":1,"kind":"today","models":[],"otherModelTokens":0,"otherToolTokens":0,"outputTokens":0,"tools":[],"totalTokens":10,"unclassifiedTokens":0},
         "trend":[{"cost":1,"date":"2026-10-09","tokens":10}]}
        """#
        let legacy = try TokenSnapshot(jsonData: Data(legacyJSON.utf8))
        XCTAssertNil(legacy.scope)
        XCTAssertNil(legacy.aliasRevision)
        XCTAssertNil(legacy.projectionKey)
        XCTAssertNil(legacy.today.unpricedTokens)
        XCTAssertEqual(legacy.requestedScope, .all)
        XCTAssertEqual(legacy.today.totalTokens, 10)
        XCTAssertEqual(legacy.trend.count, 1)
        XCTAssertTrue(legacy.isSourceStale)
        let reencoded = String(decoding: try legacy.jsonData(), as: UTF8.self)
        for key in ["scope", "aliasRevision", "projectionKey", "unpricedTokens"] {
            XCTAssertFalse(reencoded.contains("\"\(key)\""), "\(key) is written only when set")
        }

        // A malformed scope is dropped, not fatal.
        let broken = try TokenSnapshot(jsonData: Data(#"{"schemaVersion":1,"fetchedAt":"2026-10-09T02:50:00Z","scope":{"deviceName":"x"},"aliasRevision":-2}"#.utf8))
        XCTAssertNil(broken.scope)
        XCTAssertNil(broken.aliasRevision)
    }

    func testLoadReadsTheSharedStores() throws {
        let suiteName = "SnapshotBuilderTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SnapshotBuilderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = PreferencesStore(defaults: defaults)
        var preferences = DisplayPreferences.defaults
        preferences.deviceScope = .device("build-box")
        store.save(preferences)
        let cache = ModelAliasCache(directory: directory)
        try cache.save(try PipelineFixture.aliases(), hubKey: "hub-a")

        let builder = SnapshotBuilder.load(preferences: store, aliasCache: cache, hubKey: "hub-a")
        XCTAssertEqual(builder.preferences.deviceScope, .device("build-box"))
        XCTAssertEqual(builder.aliasRevision, 1)
        XCTAssertNil(SnapshotBuilder.load(preferences: store, aliasCache: cache, hubKey: "hub-b").aliases)
        XCTAssertNil(SnapshotBuilder.load(preferences: store, aliasCache: cache, hubKey: nil).aliases)
    }
}

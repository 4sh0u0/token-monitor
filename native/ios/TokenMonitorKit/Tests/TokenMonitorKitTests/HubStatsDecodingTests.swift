import Foundation
import XCTest
@testable import TokenMonitorKit

final class HubStatsDecodingTests: XCTestCase {
    func testDecodesRealStatsFixture() throws {
        let stats = try Fixture.stats()
        XCTAssertEqual(stats.updatedAt, Fixture.date("2026-10-09T02:48:07.695Z"))
        XCTAssertEqual(stats.staleAfter, 600)
        XCTAssertEqual(stats.limitsUpdatedAt, Fixture.date("2026-10-09T02:48:07.695Z"))
        XCTAssertFalse(stats.projectsIncomplete)

        let today = stats.today
        XCTAssertEqual(today.totalTokens, 72_250_000)
        XCTAssertEqual(today.costUsd, 122.825, accuracy: 1e-9)
        XCTAssertEqual(today.outputTokens, 1_445_000)
        XCTAssertEqual(today.cacheReadTokens, 62_135_000)
        XCTAssertEqual(today.cacheWriteTokens, 3_612_500)
        XCTAssertEqual(today.unclassifiedTokens, 0)
        XCTAssertNil(today.inputTokens, "aggregate periods carry no inputTokens")
        XCTAssertTrue(today.hasExactTokenComponents)
        // old-laptop reported no timing, so the aggregate capability is false
        // while the counters from the other devices are still summed.
        XCTAssertFalse(today.hasCompleteThroughput)
        XCTAssertEqual(today.timedOutputTokens, 1_355_650)
        XCTAssertEqual(today.outputTokensPerSecond ?? 0, 1_355_650 * 1000 / 21_865_323, accuracy: 1e-6)
        XCTAssertEqual(today.sessionCount, 1)
        XCTAssertEqual(stats[.month].totalTokens, 715_340_000)
        XCTAssertEqual(stats[.allTime].totalTokens, 4_233_100_000)

        let components = today.components
        XCTAssertEqual(components.cacheRead, 62_135_000)
        XCTAssertEqual(components.output, 1_445_000)
        XCTAssertEqual(components.cacheMiss, 72_250_000 - 62_135_000 - 1_445_000)
        XCTAssertEqual(components.input, components.cacheRead + components.cacheMiss)
        XCTAssertEqual(components.total, 72_250_000)
        XCTAssertEqual(components.cacheHitFraction ?? 0, 62_135_000 / Double(components.input), accuracy: 1e-9)
    }

    func testClientsAndModelsAreSortedLabelledAndColoured() throws {
        let today = try Fixture.stats().today
        XCTAssertEqual(today.clients.map(\.id), ["claude", "codex", "hermes", "opencode", "cursor", "gemini"])
        XCTAssertEqual(today.clients.first?.label, "Claude Code")
        XCTAssertEqual(today.clients.first?.tokens, 55_050_000)
        XCTAssertEqual(today.clients.first?.vendorID, "claude")
        XCTAssertEqual(today.clients.map(\.label).last, "Gemini")
        XCTAssertEqual(today.clients.first(where: { $0.id == "cursor" })?.paint, .ink)
        XCTAssertEqual(today.unattributedClientTokens, 0)
        XCTAssertEqual(today.clients(remainderLabel: "Other").count, today.clients.count)

        XCTAssertEqual(today.models.map(\.id), [
            "claude-sonnet-4-5", "gpt-5-codex", "claude-opus-4-1", "deepseek-chat",
            "big-pickle", "kimi-k2-turbo", "cursor-auto", "gemini-2.5-pro"
        ])
        XCTAssertEqual(today.models.map(\.vendorID), ["claude", "codex", "claude", "deepseek", "opencode", "kimi", "cursor", "gemini"])
        XCTAssertEqual(today.models.first?.paint, .hex("#cc7c5e"))

        let month = try Fixture.stats().month
        let mystery = try XCTUnwrap(month.models.first { $0.id == "mystery-model-x" })
        XCTAssertNil(mystery.vendorID)
        XCTAssertEqual(mystery.paint, .hex("#f0d66a"), "fallback colour must match the desktop's hash")
        XCTAssertEqual(month.clients.count, 8)
        XCTAssertEqual(month.clients.last?.id, "qwen")
    }

    func testRemainderRowWhenRowsDoNotAddUp() {
        let period = UsagePeriod(
            totalTokens: 1000,
            clients: [UsageShare(kind: .client, id: "claude", label: "Claude Code", tokens: 700, vendorID: "claude")]
        )
        let rows = period.clients(remainderLabel: "Unclassified")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.last?.kind, .remainder)
        XCTAssertEqual(rows.last?.tokens, 300)
        XCTAssertEqual(rows.last?.label, "Unclassified")
        XCTAssertEqual(rows.last?.fraction(of: 1000), 0.3)
    }

    func testDevices() throws {
        let stats = try Fixture.stats()
        XCTAssertEqual(stats.devices.map(\.id), ["build-box", "old-laptop", "studio-mac"])
        XCTAssertEqual(stats.devices.map(\.isStale), [false, true, false])
        XCTAssertEqual(stats.onlineDeviceCount, 2)
        XCTAssertFalse(stats.isSourceStale)
        XCTAssertEqual(stats.newestDeviceActivity, Fixture.date("2026-10-09T02:47:57.136Z"))

        let studio = try XCTUnwrap(stats.devices.last)
        XCTAssertEqual(studio.displayName, "studio-mac")
        XCTAssertEqual(studio.hostname, "studio.local")
        XCTAssertEqual(studio.platformFamily, .macOS)
        XCTAssertEqual(studio.operatingSystemDescription, "macOS 26.0")
        XCTAssertEqual(studio.agentRuntime, "electron-widget")
        XCTAssertEqual(studio.today.tokens, 61_800_000)
        XCTAssertFalse(studio.today.isExpired)
        XCTAssertEqual(studio.month.tokens, 587_100_000)
        XCTAssertEqual(studio.today.clients.first?.id, "claude")
        XCTAssertEqual(studio.trackedClients, ["claude", "codex", "opencode"])
        XCTAssertEqual(studio.lastSeen, Fixture.date("2026-10-09T02:47:57.120Z"))
        XCTAssertEqual(studio.usage(.allTime).tokens, studio.allTime.tokens)

        let laptop = stats.devices[1]
        XCTAssertEqual(laptop.platformFamily, .windows)
        XCTAssertEqual(laptop.operatingSystemDescription, "Windows 11 24H2")
        XCTAssertFalse(laptop.isOnline)
        XCTAssertEqual(stats.devices[0].operatingSystemDescription, "Ubuntu 24.04")
    }

    func testDevicePeriodsExpireAtTheirWindowEnd() throws {
        var object = try Fixture.statsObject()
        // The Hub built this aggregate after every device's local midnight.
        object["updatedAt"] = "2026-10-10T00:30:00.000Z"
        let stats = try Fixture.decodeStats(object)
        for device in stats.devices {
            XCTAssertTrue(device.today.isExpired, device.id)
            XCTAssertEqual(device.today.tokens, 0, device.id)
            XCTAssertFalse(device.month.isExpired, device.id)
            XCTAssertGreaterThan(device.month.tokens, 0, device.id)
        }
    }

    func testDeviceWithoutPeriodWindowsFallsBackToUTCDay() throws {
        let json = """
        {"updatedAt":"2026-10-10T08:00:00Z","devices":[
          {"deviceId":"a","updatedAt":"2026-10-09T23:00:00Z","periods":{"today":{"totalTokens":5},"month":{"totalTokens":9}}},
          {"deviceId":"b","updatedAt":"2026-10-10T07:00:00Z","periods":{"today":{"totalTokens":7}}}
        ]}
        """
        let stats = try HubStats.decode(from: Data(json.utf8))
        XCTAssertTrue(stats.devices[0].today.isExpired)
        XCTAssertEqual(stats.devices[0].month.tokens, 9)
        XCTAssertFalse(stats.devices[1].today.isExpired)
        XCTAssertEqual(stats.devices[1].today.tokens, 7)
    }

    func testDeviceNameResolver() throws {
        let json = """
        {"devices":[
          {"displayName":"  Studio  ","deviceId":"studio-mac","hostname":"studio.local"},
          {"displayName":"   ","deviceId":"work","hostname":"work.local"},
          {"deviceId":"","hostname":"only-host"},
          {"platform":"darwin-arm64"}
        ]}
        """
        let names = try HubStats.decode(from: Data(json.utf8)).devices.map(\.displayName)
        XCTAssertEqual(names, ["Studio", "work", "only-host", "device"])
        XCTAssertEqual(DeviceSummary(id: "x", displayName: nil, hostname: "h").displayName, "x")
    }

    func testHistoryPreview() throws {
        let stats = try Fixture.stats()
        XCTAssertEqual(stats.history.count, 30)
        XCTAssertEqual(stats.history.first, HistoryDay(date: "2026-09-10", tokens: 16_998_733, costUsd: 28.8978))
        XCTAssertEqual(stats.history.last?.date, "2026-10-09")
        XCTAssertEqual(stats.historyMonths.map(\.month), ["2026-08", "2026-09", "2026-10"])
        XCTAssertNotNil(stats.history.first?.startOfDay(in: Fixture.utc))
    }

    func testDailyTrendTakesTheGreaterOfHistoryAndLiveToday() throws {
        let stats = try Fixture.stats()
        let trend = stats.dailyTrend(days: 14, endingAt: Fixture.date("2026-10-09T12:00:00Z"), calendar: Fixture.utc)
        XCTAssertEqual(trend.count, 14)
        XCTAssertEqual(trend.first?.date, "2026-09-26")
        XCTAssertEqual(trend.last?.date, "2026-10-09")
        // History holds 45.2M for today; the live period already counts 72.25M.
        XCTAssertEqual(trend.last?.tokens, 72_250_000)
        XCTAssertEqual(trend[12], stats.history.first { $0.date == "2026-10-08" })

        // Days the History preview does not cover are zero, not missing.
        let longer = stats.dailyTrend(days: 35, endingAt: Fixture.date("2026-10-09T12:00:00Z"), calendar: Fixture.utc)
        XCTAssertEqual(longer.count, 35)
        XCTAssertEqual(longer.first?.tokens, 0)

        XCTAssertEqual(HubStats().dailyTrend(days: 14, endingAt: Date(), calendar: Fixture.utc), [])
    }

    func testLimitsDecoding() throws {
        let limits = try Fixture.stats().limits
        XCTAssertEqual(limits.map(\.provider), ["claude", "codex", "cursor", "deepseek", "kimi", "opencode", "openrouter"])
        XCTAssertEqual(Set(limits.map(\.id)).count, limits.count)
        XCTAssertFalse(limits.contains { $0.id.contains("sha256") || $0.id.contains("fixture") }, "ids must not carry the account key")
        // Same derivation as the macOS widget's instanceId.
        XCTAssertEqual(limits[0].id, "claude-527d83d5fcc2")

        let claude = limits[0]
        XCTAssertEqual(claude.displayName, "Claude")
        XCTAssertEqual(claude.planLabel, "Max")
        XCTAssertEqual(claude.accountDisplayName, "dev@example.com")
        XCTAssertEqual(claude.maskedAccountDisplayName, "d***v@example.com")
        XCTAssertEqual(claude.status, .ok)
        XCTAssertTrue(claude.isReady)
        XCTAssertEqual(claude.balance?.amount, 37.5)
        XCTAssertEqual(claude.balance?.currency, "USD")
        XCTAssertNotNil(claude.balance?.expiresAt)

        let cursor = limits[2]
        XCTAssertEqual(cursor.status, .unauthorized)
        XCTAssertEqual(cursor.statusCategory, .needsSignIn)
        XCTAssertTrue(cursor.isStale)
        XCTAssertFalse(cursor.hasData)
        XCTAssertFalse(cursor.isReady)

        XCTAssertEqual(limits[3].displayName, "DeepSeek")
        XCTAssertEqual(limits[3].planLabel, "Pay-as-you-go", "legacy accountLabel is the plan for older producers")
        XCTAssertEqual(limits[4].statusCategory, .rateLimited)
        XCTAssertEqual(limits[6].displayName, "OpenRouter")

        let opencode = limits[5]
        XCTAssertEqual(opencode.balance, LimitBalance(amount: 4.25, currency: "USD"), "balanceUsd predates the balance block")
        XCTAssertEqual(opencode.accountName, "Personal workspace")
        XCTAssertEqual(opencode.windows.first?.boundaryKind, .expiry)
        XCTAssertNotNil(opencode.windows.first?.resetsAt)
    }

    func testSortedForDisplayPutsReadyRowsFirstInDesktopOrder() throws {
        let sorted = LimitProvider.sortedForDisplay(try Fixture.stats().limits)
        XCTAssertEqual(sorted.map(\.provider), ["claude", "codex", "opencode", "deepseek", "openrouter", "cursor", "kimi"])
    }

    func testOriginalFixtureUnderAppOptions() throws {
        let compact = try Fixture.stats()
        let app = try HubStats.decode(from: Fixture.data("stats.json"), options: .app)
        XCTAssertEqual(app.today.sessions.map(\.id), ["claude:7f3c2a90-session"])
        XCTAssertEqual(app.today.sessions.count, app.today.sessionCount)
        XCTAssertEqual(app.today.projects.map(\.id), ["token-monitor"])
        XCTAssertEqual(compact.today.sessions, [])
        XCTAssertEqual(compact.today.projects, [])
        for kind in UsagePeriodKind.allCases {
            var stripped = app[kind]
            stripped.sessions = []
            stripped.projects = []
            XCTAssertEqual(stripped, compact[kind], kind.rawValue)
        }
        XCTAssertEqual(app.devices.map(\.id), compact.devices.map(\.id))
        for (full, plain) in zip(app.devices, compact.devices) {
            XCTAssertEqual(full.today, plain.today, full.id)
            XCTAssertEqual(full.allTime, plain.allTime, full.id)
            XCTAssertEqual(plain.details, [:], plain.id)
            XCTAssertEqual(full.detail(.allTime)?.totalTokens, full.allTime.tokens, full.id)
        }
        XCTAssertEqual(app.device(id: "studio-mac")?.detail(.today)?.sessions.count, 1)
    }

    func testDecodeErrorsMapToHubClientError() {
        XCTAssertThrowsError(try HubStats.decode(from: Data("[1]".utf8), options: .app)) { error in
            guard case HubClientError.decoding = error else { return XCTFail("\(error)") }
        }
    }

    func testStatusMapping() {
        XCTAssertEqual(LimitStatus(wire: "sourceRateLimited").category, .rateLimited)
        XCTAssertEqual(LimitStatus(wire: "notConfigured").category, .inactive)
        XCTAssertEqual(LimitStatus(wire: "somethingNew"), .error)
        XCTAssertEqual(LimitStatus(wire: nil).category, .unavailable)
    }
}

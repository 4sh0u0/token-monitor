import Foundation
import XCTest
@testable import TokenMonitorKit

/// Sessions, projects and tool/model attribution against the `sessions`,
/// `projects` and `attribution` goldens (rendered by the desktop JS on the
/// v2 fixture at its frozen clock, TZ=UTC), plus the live-state edge cases
/// the fixture does not reach.
final class SessionPresentationTests: XCTestCase {
    private let formatter = DisplayFormatter()

    // MARK: - Sessions golden

    func testSessionRowsMatchGolden() throws {
        let golden = try SessionGolden.sessions()
        let stats = try SessionGolden.stats()
        let periods = ["aggregate.today": stats.today, "aggregate.month": stats.month]
        var checkedRows = 0
        for (scopeName, clocks) in golden.scopes {
            let period = try XCTUnwrap(periods[scopeName], scopeName)
            for (clockName, clock) in clocks {
                let context = "\(scopeName) \(clockName)"
                let now = Fixture.date(clock.at)
                let rows = SessionRows.rows(period: period, now: now, calendar: SessionGolden.utc, groupBackgroundReviews: false)
                XCTAssertEqual(rows.map(\.id), clock.rows.map(\.key), context)
                for (row, expected) in zip(rows, clock.rows) {
                    assertRow(row, expected, "\(context) \(expected.key)")
                    checkedRows += 1
                }

                let grouped = SessionRows.rows(period: period, now: now, calendar: SessionGolden.utc)
                XCTAssertEqual(grouped.map(\.id), clock.grouped.map(\.key), context)
                let summaryGolden = try XCTUnwrap(clock.grouped.last { $0.reviewGroup == true }, context)
                let summary = try XCTUnwrap(grouped.last, context)
                XCTAssertTrue(summary.isReviewGroup, context)
                XCTAssertEqual(summary.name, .backgroundReviews, context)
                XCTAssertEqual(summary.client, summaryGolden.client, context)
                XCTAssertEqual(summary.clientLabel, "Codex", context)
                XCTAssertEqual(summary.tokens, summaryGolden.value, context)
                XCTAssertEqual(summary.costUsd, try XCTUnwrap(summaryGolden.cost), accuracy: 1e-9, context)
                XCTAssertEqual(summary.sortTime.map(SessionLive.milliseconds), summaryGolden.sortTime.map { SessionLive.milliseconds(Fixture.date($0)) }, context)
                XCTAssertEqual(summary.reviewRows.map(\.id), summaryGolden.backgroundReviewKeys, context)
                XCTAssertEqual(summary.reviewCount, summaryGolden.backgroundReviewKeys?.count, context)
                XCTAssertEqual(summaryGolden.detail, "\(summary.reviewCount) sessions", "default countLabel")
                XCTAssertNil(summary.unpricedTokens)
                XCTAssertEqual(summary.state, .idle)
                let latest = try XCTUnwrap(summary.reviewRows.first)
                XCTAssertEqual(summary.subtitle, .reviewSummary(latestTime: latest.timeLabel, latestTokens: latest.tokens), context)
                if case let .backgroundReviews(runs) = summary.kind {
                    XCTAssertEqual(runs.map { "session:\($0.id)" }, summaryGolden.backgroundReviewKeys, context)
                } else {
                    XCTFail("group kind")
                }

                XCTAssertEqual(
                    SessionLive.nextPromptCacheChange(sessions: period.sessions, now: now).map(SessionLive.milliseconds),
                    clock.nextPromptCacheChangeAt.map { SessionLive.milliseconds(Fixture.date($0)) }, context
                )
                XCTAssertEqual(
                    SessionLive.nextChange(sessions: period.sessions, now: now).map(SessionLive.milliseconds),
                    clock.nextSessionStatusChangeAt.map { SessionLive.milliseconds(Fixture.date($0)) }, context
                )
            }
        }
        XCTAssertEqual(checkedRows, 12 + 12 + 13)
    }

    func testSessionPrimitivesMatchGolden() throws {
        let golden = try SessionGolden.sessions()
        let stats = try SessionGolden.stats()
        let sessions = Dictionary(uniqueKeysWithValues: stats.today.sessions.map { ($0.id, $0) })
        var checked = 0
        for clock in try XCTUnwrap(golden.scopes["aggregate.today"]).values {
            let now = Fixture.date(clock.at)
            for expected in clock.primitives ?? [] {
                let context = "\(clock.at) \(expected.key)"
                let session = try XCTUnwrap(sessions[expected.key], context)
                XCTAssertEqual(SessionLive.state(session, now: now).rawValue, expected.activityState, context)
                XCTAssertEqual(SessionLive.isRunning(session, now: now), expected.isRunning, context)
                XCTAssertEqual(SessionLive.isArchived(session), expected.isArchived, context)
                assertContext(SessionLive.contextReading(session), expected.contextWindow, toneChecked: false, context)
                assertContext(SessionLive.contextReading(session), expected.contextRow, context)
                assertContext(SessionLive.context(session, now: now), expected.contextForRow, context)
                assertCache(SessionLive.promptCache(session, now: now), expected.promptCache, context)
                XCTAssertEqual(SessionRows.sessionIDLabel(session.sessionId) ?? "", expected.idLabel, context)
                XCTAssertEqual(text(SessionRows.modelLabel(session)), expected.modelLabel, context)
                XCTAssertEqual(SessionRows.tokenRate(session), expected.tokenRate, accuracy: 1e-9, context)
                if let percent = expected.cacheHitPercent {
                    XCTAssertEqual(try XCTUnwrap(SessionRows.cacheHitPercent(session), context), percent, accuracy: 1e-9, context)
                } else {
                    XCTAssertNil(SessionRows.cacheHitPercent(session), context)
                }
                XCTAssertEqual(SessionRows.compactTime(session.activityTime, now: now, calendar: SessionGolden.utc) ?? "", expected.compactTime, context)
                XCTAssertEqual(session.isArchived, expected.activityParts.archived, context)
                XCTAssertEqual(SessionRows.cacheHitLabel(session) ?? "", expected.activityParts.cacheHit, context)
                XCTAssertEqual(SessionRows.roundedTokenRate(session).map { text(.tokensPerSecond($0)) } ?? "", expected.activityParts.tokenRate, context)
                XCTAssertEqual(session.messageCount > 0 ? text(.calls(session.messageCount)) : "", expected.activityParts.calls, context)
                XCTAssertEqual(shareEntries(SessionRows.modelShares(session)), expected.modelTooltipEntries, context)
                checked += 1
            }
        }
        XCTAssertEqual(checked, 2 * 13)
    }

    func testSessionScalarsMatchGolden() throws {
        let golden = try SessionGolden.sessions()
        let stats = try SessionGolden.stats()
        XCTAssertEqual(SessionLive.runningWindow * 1000, Double(golden.runningWindowMs))
        for vector in golden.contextTones {
            XCTAssertEqual(toneText(SessionLive.contextTone(percentLeft: vector.percentLeft)), vector.tone, "\(vector.percentLeft)")
        }
        XCTAssertEqual(SessionRows.isIncomplete(stats: stats, period: .today), golden.incomplete["today"])
        XCTAssertEqual(SessionRows.isIncomplete(stats: stats, period: .month), golden.incomplete["month"])
        XCTAssertEqual(SessionRows.isIncomplete(stats: stats, period: .allTime), golden.incomplete["allTime"])
        XCTAssertTrue(SessionRows.isIncomplete(stats: stats, selection: .month))
        XCTAssertFalse(SessionRows.isIncomplete(stats: stats, selection: .last30))
        XCTAssertEqual(SessionRows.archivedCount(stats: stats), golden.archivedSessionCount)
        for vector in golden.idLabels {
            XCTAssertEqual(SessionRows.sessionIDLabel(vector.id) ?? "", vector.label, vector.id)
        }
    }

    // MARK: - Session live state

    func testActivityStateThreeStateTurnEnded() {
        let now = Fixture.date("2026-10-10T16:30:00.000Z")
        func session(lastUsed: String?, turnEnded: Bool?, archived: Bool = false) -> HubSession {
            HubSession(id: "claude:x", client: "claude", totalTokens: 1, lastUsedAt: lastUsed.map(Fixture.date), turnEnded: turnEnded, isArchived: archived)
        }
        XCTAssertEqual(SessionLive.state(session(lastUsed: "2026-10-10T16:25:00.000Z", turnEnded: nil), now: now), .running)
        XCTAssertEqual(SessionLive.state(session(lastUsed: "2026-10-10T16:25:00.000Z", turnEnded: false), now: now), .running)
        XCTAssertEqual(SessionLive.state(session(lastUsed: "2026-10-10T16:25:00.000Z", turnEnded: true), now: now), .ended)
        // The window is inclusive: exactly 10 minutes is still live.
        XCTAssertEqual(SessionLive.state(session(lastUsed: "2026-10-10T16:20:00.000Z", turnEnded: nil), now: now), .running)
        XCTAssertEqual(SessionLive.state(session(lastUsed: "2026-10-10T16:20:00.000Z", turnEnded: true), now: now), .ended)
        XCTAssertEqual(SessionLive.state(session(lastUsed: "2026-10-10T16:19:59.999Z", turnEnded: nil), now: now), .idle)
        XCTAssertEqual(SessionLive.state(session(lastUsed: "2026-10-10T16:19:59.999Z", turnEnded: true), now: now), .idle)
        // A future timestamp counts as recent, as on the desktop.
        XCTAssertEqual(SessionLive.state(session(lastUsed: "2026-10-10T17:00:00.000Z", turnEnded: nil), now: now), .running)
        XCTAssertEqual(SessionLive.state(session(lastUsed: nil, turnEnded: nil), now: now), .idle)
        XCTAssertEqual(SessionLive.state(session(lastUsed: "2026-10-10T16:29:00.000Z", turnEnded: nil, archived: true), now: now), .idle)
        XCTAssertEqual(SessionLive.state(session(lastUsed: "1970-01-01T00:00:00.000Z", turnEnded: nil), now: now), .idle, "epoch 0 is no timestamp")
    }

    func testContextGauge() throws {
        let now = Fixture.date("2026-10-10T16:30:00.000Z")
        func session(_ tokens: Int, _ window: Int, lastUsed: String = "2026-10-10T16:29:00.000Z") -> HubSession {
            HubSession(id: "codex:x", client: "codex", totalTokens: 1, lastUsedAt: Fixture.date(lastUsed), contextTokens: tokens, contextWindow: window)
        }
        let healthy = try XCTUnwrap(SessionLive.context(session(190_900, 950_000), now: now))
        XCTAssertEqual(healthy, SessionContextGauge(contextTokens: 190_900, contextWindow: 950_000, percentLeft: 80, percentUsed: 20, tone: .neutral))
        XCTAssertEqual(healthy.percent(for: .used), 20)
        XCTAssertEqual(healthy.percent(for: .remaining), 80)
        XCTAssertEqual(SessionLive.context(session(182_000, 200_000), now: now)?.tone, .low)
        XCTAssertEqual(SessionLive.context(session(140_000, 200_000), now: now)?.tone, .caution)
        XCTAssertEqual(SessionLive.context(session(139_000, 200_000), now: now)?.tone, .neutral)
        // Half a point rounds up on percentLeft; used is derived from it.
        XCTAssertEqual(SessionLive.context(session(1, 200), now: now)?.percentLeft, 100)
        XCTAssertEqual(SessionLive.context(session(1, 200), now: now)?.percentUsed, 0)
        XCTAssertEqual(SessionLive.context(session(3, 200), now: now)?.percentLeft, 99, "98.5 rounds half up")
        let overfull = try XCTUnwrap(SessionLive.context(session(300, 200), now: now))
        XCTAssertEqual(overfull.percentLeft, 0)
        XCTAssertEqual(overfull.percentUsed, 100)
        XCTAssertEqual(overfull.tone, .low)
        XCTAssertNil(SessionLive.context(session(0, 200), now: now))
        XCTAssertNil(SessionLive.context(session(10, 0), now: now))
        XCTAssertNil(SessionLive.context(session(10, 200, lastUsed: "2026-10-10T16:00:00.000Z"), now: now), "idle drops the gauge")
        XCTAssertNotNil(SessionLive.contextReading(session(10, 200, lastUsed: "2026-10-10T16:00:00.000Z")))
    }

    func testPromptCacheSuppressionRules() {
        let now = Fixture.date("2026-10-10T16:30:00.000Z")
        func session(client: String = "claude", observed: String = "2026-10-10T16:29:00.000Z", ttl: Int = 300, archived: Bool = false) -> HubSession {
            HubSession(
                id: "\(client):x", client: client, totalTokens: 1,
                lastUsedAt: Fixture.date("2026-10-10T16:29:00.000Z"),
                promptCache: PromptCacheObservation(observedAt: Fixture.date(observed), ttlSeconds: ttl),
                isArchived: archived
            )
        }
        XCTAssertEqual(
            SessionLive.promptCache(session(), now: now),
            PromptCacheCountdown(expiresAt: Fixture.date("2026-10-10T16:34:00.000Z"), ttlSeconds: 300, minutes: 4)
        )
        XCTAssertEqual(SessionLive.promptCache(session(client: "codex", ttl: 1800), now: now)?.minutes, 29)
        XCTAssertEqual(SessionLive.promptCache(session(ttl: 3600), now: now)?.minutes, 59)
        // Minutes round up: 61 s left reads 2 minutes, 1 ms left reads 1.
        XCTAssertEqual(SessionLive.promptCache(session(observed: "2026-10-10T16:26:01.000Z"), now: now)?.minutes, 2)
        XCTAssertEqual(SessionLive.promptCache(session(observed: "2026-10-10T16:25:00.001Z"), now: now)?.minutes, 1)
        XCTAssertNil(SessionLive.promptCache(session(archived: true), now: now), "archived")
        XCTAssertNil(SessionLive.promptCache(session(client: "gemini"), now: now), "client without a cache reading")
        XCTAssertNil(SessionLive.promptCache(session(client: "opencode"), now: now))
        XCTAssertNil(SessionLive.promptCache(session(ttl: 600), now: now), "unknown TTL tier")
        XCTAssertNil(SessionLive.promptCache(session(ttl: 0), now: now))
        XCTAssertNil(SessionLive.promptCache(session(observed: "2026-10-10T16:30:00.001Z"), now: now), "observed in the future")
        XCTAssertNotNil(SessionLive.promptCache(session(observed: "2026-10-10T16:30:00.000Z"), now: now), "observed now is fine")
        XCTAssertNil(SessionLive.promptCache(session(observed: "2026-10-10T16:25:00.000Z"), now: now), "expires exactly now")
        XCTAssertNil(SessionLive.promptCache(session(observed: "2026-10-10T15:00:00.000Z"), now: now), "expired")
        var noCache = session()
        noCache.promptCache = nil
        XCTAssertNil(SessionLive.promptCache(noCache, now: now))

        // The gauge slot shows the countdown only without a context gauge.
        var withContext = session()
        withContext.contextTokens = 10
        withContext.contextWindow = 100
        let gaugeRow = SessionRows.row(for: withContext, now: now, calendar: SessionGolden.utc)
        XCTAssertNotNil(gaugeRow.promptCache)
        XCTAssertFalse(gaugeRow.showsPromptCache)
        XCTAssertTrue(SessionRows.row(for: session(), now: now, calendar: SessionGolden.utc).showsPromptCache)
    }

    func testNextChange() {
        let now = Fixture.date("2026-10-10T16:30:00.000Z")
        func ms(_ date: Date?) -> Int64? { date.map(SessionLive.milliseconds) }
        func ms(_ iso: String) -> Int64? { SessionLive.milliseconds(Fixture.date(iso)) }
        func session(_ id: String, lastUsed: String, observed: String? = nil, ttl: Int = 300, archived: Bool = false) -> HubSession {
            HubSession(
                id: "claude:\(id)", client: "claude", totalTokens: 1,
                lastUsedAt: Fixture.date(lastUsed),
                promptCache: observed.map { PromptCacheObservation(observedAt: Fixture.date($0), ttlSeconds: ttl) },
                isArchived: archived
            )
        }
        XCTAssertNil(SessionLive.nextChange(sessions: [], now: now))
        XCTAssertNil(SessionLive.nextChange(sessions: [session("old", lastUsed: "2026-10-10T15:00:00.000Z")], now: now))
        XCTAssertNil(SessionLive.nextChange(sessions: [session("gone", lastUsed: "2026-10-10T16:29:00.000Z", archived: true)], now: now))
        // A live session changes state the millisecond after its window.
        XCTAssertEqual(ms(SessionLive.nextChange(sessions: [session("a", lastUsed: "2026-10-10T16:25:00.000Z")], now: now)), ms("2026-10-10T16:35:00.001Z"))
        // A cache countdown changes label each minute: 16:34:30 expiry at
        // 16:30 reads 5m until 16:30:30.
        let cached = session("b", lastUsed: "2026-10-10T16:12:00.000Z", observed: "2026-10-10T16:29:30.000Z")
        XCTAssertEqual(ms(SessionLive.nextPromptCacheChange(sessions: [cached], now: now)), ms("2026-10-10T16:30:30.000Z"))
        XCTAssertEqual(ms(SessionLive.nextChange(sessions: [cached, session("a", lastUsed: "2026-10-10T16:25:00.000Z")], now: now)), ms("2026-10-10T16:30:30.000Z"))
        XCTAssertNil(SessionLive.nextPromptCacheChange(sessions: [session("c", lastUsed: "2026-10-10T16:25:00.000Z")], now: now))
    }

    // MARK: - Session rows

    func testRowsDropEmptyAndReasonixSessions() {
        let now = Fixture.date("2026-10-10T16:30:00.000Z")
        let sessions = [
            HubSession(id: "claude:empty", client: "claude", totalTokens: 0, lastUsedAt: now),
            HubSession(id: "reasonix:abc", client: "reasonix", totalTokens: 10, lastUsedAt: now),
            HubSession(id: "codex:x", client: "codex", sessionId: "reasonix-stats:/tmp/x", totalTokens: 10, lastUsedAt: now),
            HubSession(id: "codex:kept", client: "codex", totalTokens: 5, lastUsedAt: now),
        ]
        XCTAssertEqual(SessionRows.rows(sessions: sessions, now: now).map(\.id), ["session:codex:kept"])
    }

    func testTitlesOnlyWhenEnabledAndPresent() throws {
        let now = Fixture.date("2026-10-10T16:30:00.000Z")
        let titled = HubSession(
            id: "claude:t", client: "claude", totalTokens: 10, messageCount: 1,
            lastUsedAt: Fixture.date("2026-10-10T16:28:00.000Z"), title: "Fix the watcher",
            models: ["claude-sonnet-4-5": 10]
        )
        let shown = SessionRows.row(for: titled, titlesEnabled: true, now: now, calendar: SessionGolden.utc)
        XCTAssertEqual(shown.name, .title("Fix the watcher"))
        XCTAssertEqual(shown.subtitle, .tool(clientLabel: "Claude Code", model: .single("claude-sonnet-4-5")))
        XCTAssertEqual(shown.activityLine, [.time("16:28"), .calls(1)])

        let hidden = SessionRows.row(for: titled, titlesEnabled: false, now: now, calendar: SessionGolden.utc)
        XCTAssertEqual(hidden.name, .tool(clientLabel: "Claude Code", model: .single("claude-sonnet-4-5")))
        XCTAssertEqual(hidden.subtitle, .activity([.time("16:28"), .calls(1)]))
        XCTAssertNil(hidden.activityLine)

        var blank = titled
        blank.title = "   "
        XCTAssertEqual(SessionRows.row(for: blank, now: now, calendar: SessionGolden.utc).name, .tool(clientLabel: "Claude Code", model: .single("claude-sonnet-4-5")))

        var clientless = titled
        clientless.client = ""
        clientless.title = nil
        clientless.models = [:]
        let row = SessionRows.row(for: clientless, now: now, calendar: SessionGolden.utc)
        XCTAssertEqual(row.name, .tool(clientLabel: nil, model: .none))
        XCTAssertNil(row.clientLabel)
    }

    func testGroupedRowsWithoutReviewsAreUnchanged() {
        let now = Fixture.date("2026-10-10T16:30:00.000Z")
        let sessions = [HubSession(id: "codex:a", client: "codex", totalTokens: 5, lastUsedAt: now)]
        XCTAssertEqual(SessionRows.rows(sessions: sessions, now: now), SessionRows.rows(sessions: sessions, now: now, groupBackgroundReviews: false))
    }

    func testCompactTimeUsesLocalGregorianDay() {
        var tokyo = Calendar(identifier: .japanese)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let now = Fixture.date("2026-10-10T16:30:00.000Z") // 01:30 on 10/11 in Tokyo
        XCTAssertEqual(SessionRows.compactTime(Fixture.date("2026-10-10T15:05:00.000Z"), now: now, calendar: tokyo), "00:05")
        XCTAssertEqual(SessionRows.compactTime(Fixture.date("2026-10-10T14:59:00.000Z"), now: now, calendar: tokyo), "10/10 23:59")
        XCTAssertEqual(SessionRows.compactTime(Fixture.date("2026-01-02T03:04:00.000Z"), now: now, calendar: SessionGolden.utc), "01/02 03:04")
        XCTAssertNil(SessionRows.compactTime(nil, now: now, calendar: tokyo))
    }

    func testPaging() {
        let now = Fixture.date("2026-10-10T16:30:00.000Z")
        let rows = (0..<250).map { index in
            SessionRows.row(for: HubSession(id: "codex:\(index)", client: "codex", totalTokens: 1, lastUsedAt: now), now: now)
        }
        let first = SessionRows.page(rows, index: 0)
        XCTAssertEqual([first.index, first.pageCount, first.start, first.end, first.total, first.rows.count], [0, 3, 1, 100, 250, 100])
        XCTAssertTrue(first.isPaginated)
        let last = SessionRows.page(rows, index: 9)
        XCTAssertEqual([last.index, last.start, last.end, last.rows.count], [2, 201, 250, 50])
        XCTAssertEqual(last.rows.first?.id, rows[200].id)
        XCTAssertEqual(SessionRows.page(rows, index: -4).index, 0)
        let single = SessionRows.page(Array(rows.prefix(100)), index: 3)
        XCTAssertEqual([single.index, single.pageCount, single.start, single.end], [0, 1, 1, 100])
        XCTAssertFalse(single.isPaginated)
        let empty = SessionRows.page([], index: 0)
        XCTAssertEqual([empty.start, empty.end, empty.total], [0, 0, 0])
    }

    func testRecentSessionsKeepRunningBeyondCap() throws {
        let stats = try SessionGolden.stats()
        let now = Fixture.date("2026-10-10T16:30:00.000Z")
        let recent = SessionRows.recent(month: stats.month, today: stats.today, now: now)
        // Month first, background reviews and duplicates skipped, newest
        // first; the 5-row budget plus every running session.
        XCTAssertEqual(recent.rows.map(\.id), [
            "claude:7f3c2a90-1b2c-4d5e-8f90-a1b2c3d4e5f6",
            "codex:c4d5e6f7-a8b9-4c0d-8e1f-2a3b4c5d6e7f",
            "gemini:gemini-6c5b4a39",
            "claude:0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d",
            "hermes:hermes-20261010-0815",
            "claude:9e8d7c6b-5a49-4382-9170-6f5e4d3c2b1a",
            "claude:empty-0000",
        ])
        XCTAssertEqual(recent.runningCount, 5)
        XCTAssertEqual(recent.nextChange(now: now).map(SessionLive.milliseconds), SessionLive.milliseconds(Fixture.date("2026-10-10T16:30:00.001Z")))
        XCTAssertEqual(recent.rows.first?.name, .title("Refactor the collector watch loop"))
        XCTAssertEqual(recent.rows[1].name, .project("docs-site"))
        XCTAssertEqual(recent.rows.last?.name, .sessionID("empty-0000"))
        XCTAssertEqual(recent.rows.first?.context?.percentLeft, 80)
        XCTAssertFalse(recent.rows.first?.showsPromptCache ?? true)
        XCTAssertNil(recent.rows[1].promptCache, "archived")

        let untitled = SessionRows.recent(month: stats.month, today: stats.today, titlesEnabled: false, now: now)
        XCTAssertEqual(untitled.rows.first?.name, .project("token-monitor"))

        let later = SessionRows.recent(month: stats.month, today: stats.today, now: Fixture.date("2026-10-11T00:00:00.000Z"))
        XCTAssertEqual(later.rows.count, 5)
        XCTAssertEqual(later.runningCount, 0)
        XCTAssertEqual(SessionRows.runningCount(sessions: stats.today.sessions, now: now), 5)

        let long = HubSession(id: "codex:0123456789abcdef", client: "codex", sessionId: "0123456789abcdef", totalTokens: 1, lastUsedAt: now)
        let row = SessionRows.recent(month: UsagePeriod(sessions: [long]), today: nil, now: now).rows.first
        XCTAssertEqual(row?.name, .sessionID("0123456789ab"))
    }

    func testSessionAge() {
        let now = Fixture.date("2026-10-10T16:30:00.000Z")
        func age(_ iso: String) -> SessionAge? { SessionRows.age(of: Fixture.date(iso), now: now) }
        XCTAssertEqual(age("2026-10-10T16:29:31.000Z"), .justNow)
        XCTAssertEqual(age("2026-10-10T16:29:30.000Z"), .minutes(1))
        XCTAssertEqual(age("2026-10-10T15:31:00.000Z"), .minutes(59))
        XCTAssertEqual(age("2026-10-10T15:30:30.000Z"), .hours(1))
        XCTAssertEqual(age("2026-10-09T17:00:00.000Z"), .days(1), "23.5 h rounds to 24 h, which reads as a day")
        XCTAssertEqual(age("2026-10-08T16:30:00.000Z"), .days(2))
        XCTAssertEqual(age("2026-10-10T17:30:00.000Z"), .justNow, "future reads as now")
        XCTAssertNil(SessionRows.age(of: nil, now: now))
    }

    func testModelSharesRemainder() {
        let session = HubSession(id: "opencode:x", client: "opencode", totalTokens: 1000, models: ["a": 500, "b": 300, "": 50, "c": 0])
        XCTAssertEqual(SessionRows.modelLabel(session), .count(3))
        XCTAssertEqual(SessionRows.modelShares(session).map(\.model), ["a", "b", nil])
        XCTAssertEqual(SessionRows.modelShares(session).last?.tokens, 200, "unlabelled 50 plus 150 unattributed")
        XCTAssertEqual(SessionRows.modelShares(HubSession(id: "x", client: "x", models: ["a": 5])), [])
        // More attributed than the total: the denominator is the attributed sum.
        let over = HubSession(id: "x", client: "x", totalTokens: 10, models: ["a": 30, "b": 10])
        XCTAssertEqual(SessionRows.modelShares(over).map(\.percent), [75, 25])
    }

    func testCollationMatchesLocaleCompare() {
        // `list.sort((a, b) => a.localeCompare(b))` in Node 22 (ICU 77).
        let expected = [
            "a1", "A1", "a10", "a2", "big-pickle", "cafe", "Cafe", "café", "Café", "cafes", "claude", "Claude", "CLAUDE",
            "Claude Code · 3 models", "Claude Code · claude-sonnet-4-5", "claude x", "claude_x", "claude-x", "claude:x",
            "claude.x", "Codex", "Codex · gpt-5-codex", "deepseek-chat", "deepseek/deepseek-chat", "E", "é", "ef", "f",
            "gpt-5-codex", "gpt-5-codex-high", "OpenCode", "token-monitor", "Token-Monitor", "unknown", "Unknown tool",
            "x@y", "x#y", "x+y", "x~y", "x$y", "zed", "Zed",
        ]
        for seed in 0..<5 {
            var generator = SeededGenerator(seed: UInt64(seed + 1))
            let shuffled = expected.shuffled(using: &generator)
            XCTAssertEqual(shuffled.sorted { UsageRowCollation.compare($0, $1) < 0 }, expected)
        }
        let pairs: [(String, String, Int)] = [
            ("a", "A", -1), ("aA", "Aa", -1), ("é", "f", -1), ("e", "é", -1), ("E", "é", -1), ("é", "ef", -1),
            ("Café", "cafe", 1), ("a b", "a_b", -1), ("a-b", "ab", -1), ("claude", "claude", 0), ("x·y", "x-y", 1), ("x·y", "x0", -1),
        ]
        for (left, right, order) in pairs {
            XCTAssertEqual(UsageRowCollation.compare(left, right), order, "\(left) vs \(right)")
        }
    }

    // MARK: - Projects golden

    func testProjectRowsMatchGolden() throws {
        let golden = try SessionGolden.projects()
        let stats = try SessionGolden.stats()
        let studio = try XCTUnwrap(stats.device(id: "studio-mac"))
        let tokyo = try XCTUnwrap(stats.device(id: "tokyo-mac"))
        let periods: [String: UsagePeriod] = [
            "aggregate.today": stats.today,
            "aggregate.month": stats.month,
            "aggregate.allTime": stats.allTime,
            "device.studio-mac.month": try XCTUnwrap(studio.detail(.month)),
            "device.tokyo-mac.month": try XCTUnwrap(tokyo.detail(.month)),
        ]
        XCTAssertEqual(Set(golden.scopes.keys), Set(periods.keys))
        for (scope, expectedRows) in golden.scopes {
            let rows = ProjectRows.rows(period: try XCTUnwrap(periods[scope]))
            XCTAssertEqual(rows.map(\.key), expectedRows.map(\.key), scope)
            for (row, expected) in zip(rows, expectedRows) {
                let context = "\(scope) \(expected.key)"
                XCTAssertEqual(row.name, expected.name, context)
                XCTAssertEqual(row.tokens, expected.value, context)
                XCTAssertEqual(row.costUsd, expected.cost, accuracy: 1e-9, context)
                XCTAssertEqual(row.unpricedTokens, expected.unpricedTokens, context)
                XCTAssertEqual(row.clients, expected.clients, context)
                XCTAssertEqual(row.clientTokens, expected.clientTokens, context)
                XCTAssertEqual(row.toolRows.map(\.id), expected.accordionRows.map(\.key), context)
                for (tool, expectedTool) in zip(row.toolRows, expected.accordionRows) {
                    XCTAssertEqual(tool.tokens, expectedTool.value, context)
                    XCTAssertEqual(tool.percent, expectedTool.percent, accuracy: 1e-9, context)
                    XCTAssertEqual(tool.clientID.map { SessionRows.clientLabel($0) ?? $0 } ?? "Unknown tool", expectedTool.name, context)
                }
            }
        }
        XCTAssertEqual(ProjectRows.isIncomplete(stats: stats, period: .today), golden.incomplete["today"])
        XCTAssertEqual(ProjectRows.isIncomplete(stats: stats, period: .month), golden.incomplete["month"])
        XCTAssertEqual(ProjectRows.isIncomplete(stats: stats, period: .allTime), golden.incomplete["allTime"])
        XCTAssertFalse(ProjectRows.isIncomplete(stats: stats, selection: .week))
        XCTAssertTrue(ProjectRows.isIncomplete(device: tokyo, period: .allTime), "projects disabled with usage")
        for vector in golden.canonicalKeys {
            XCTAssertEqual(ProjectRows.canonicalKey(vector.value), vector.key, vector.value)
        }
        for vector in golden.deterministicLabels {
            XCTAssertEqual(ProjectRows.deterministicLabel(vector.left, vector.right), vector.label)
        }
    }

    func testProjectRowsFromSessionsWhenNoRollup() {
        let period = UsagePeriod(totalTokens: 100, sessions: [
            HubSession(id: "claude:a", client: "claude", totalTokens: 60, costUsd: 1, unpricedTokens: 80, projectLabel: "Infra"),
            HubSession(id: "codex:b", client: "codex", totalTokens: 30, costUsd: 2, projectLabel: " infra "),
            HubSession(id: "x:c", client: "", totalTokens: 10, projectLabel: "infra"),
            HubSession(id: "codex:d", client: "codex", totalTokens: 50, projectLabel: "   "),
            HubSession(id: "codex:e", client: "codex", totalTokens: 5),
        ])
        let rows = ProjectRows.rows(period: period)
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.key, "infra")
        XCTAssertEqual(row.name, "Infra")
        XCTAssertEqual(row.tokens, 100)
        XCTAssertEqual(row.costUsd, 3)
        XCTAssertEqual(row.unpricedTokens, 60, "clamped to the session's tokens")
        XCTAssertEqual(row.clients, ["claude", "codex"])
        XCTAssertEqual(row.toolRows.map(\.clientID), ["claude", "codex", nil])
        XCTAssertEqual(row.toolRows.map(\.tokens), [60, 30, 10])
    }

    func testProjectRollupSkipsBlankLabels() {
        let period = UsagePeriod(projects: [
            ProjectRollup(id: "blank", label: "", tokens: 10, clients: ["claude": 10]),
            ProjectRollup(id: "kept", label: "kept", tokens: 10, costUsd: 0.5, clients: ["claude": 4]),
        ])
        let rows = ProjectRows.rows(period: period)
        XCTAssertEqual(rows.map(\.key), ["kept"])
        XCTAssertEqual(rows[0].toolRows.map(\.id), ["unknown", "claude"])
        XCTAssertEqual(rows[0].clientTokens, ["claude": 4, "": 6])
    }

    // MARK: - Attribution golden

    func testAttributionRowsMatchGolden() throws {
        let golden = try SessionGolden.attribution()
        let stats = try SessionGolden.stats()
        let tokyo = try XCTUnwrap(stats.device(id: "tokyo-mac"))
        let periods: [String: UsagePeriod] = [
            "aggregate.today": stats.today,
            "aggregate.month": stats.month,
            "aggregate.allTime": stats.allTime,
            "device.tokyo-mac.today": try XCTUnwrap(tokyo.detail(.today)),
        ]
        XCTAssertEqual(Set(golden.scopes.keys), Set(periods.keys))
        XCTAssertEqual(golden.unattributedKey, AttributionRows.unattributedKey)
        let known = golden.knownClients.map(\.id)
        XCTAssertEqual(known, VendorCatalog.trackedClientIDs)
        for (scope, expected) in golden.scopes {
            let period = try XCTUnwrap(periods[scope])
            assertComponents(period.components, expected.periodComponents, "\(scope) period")
            XCTAssertEqual(AttributionRows.unknownModelSource(period: period), expected.unknownModelSource, scope)

            let tools = AttributionRows.usageToolRows(period: period)
            XCTAssertEqual(tools.map(\.key), expected.toolRows.map(\.key), scope)
            for (row, golden) in zip(tools, expected.toolRows) {
                assertAttribution(row, golden, "\(scope) tool \(golden.key)")
                XCTAssertEqual(row.modelRows, AttributionRows.modelRowsForTool(period: period, client: row.key), scope)
            }
            for (name, scenario) in expected.toolOrder {
                let csv = { (value: String) in value.split(separator: ",").map(String.init) }
                let prefs = DisplayPreferences(
                    clientDisplayOrder: csv(scenario.prefs.order),
                    hiddenClients: csv(scenario.prefs.hidden),
                    pinnedClients: csv(scenario.prefs.pinned)
                )
                XCTAssertEqual(AttributionRows.toolRows(period: period, prefs: prefs, known: known).map(\.key), scenario.keys, "\(scope) \(name)")
            }

            let models = AttributionRows.modelRows(period: period, ranking: .tokens)
            XCTAssertEqual(models.map(\.key), expected.modelRows.map(\.key), scope)
            for (row, golden) in zip(models, expected.modelRows) {
                assertAttribution(row, golden, "\(scope) model \(golden.key)")
                XCTAssertEqual(row.barValue, try XCTUnwrap(golden.barValue), accuracy: 1e-9)
                XCTAssertEqual(row.modelSource, row.key == "unknown" ? expected.unknownModelSource : nil)
            }
            let byCost = AttributionRows.modelRows(period: period, ranking: .cost)
            XCTAssertEqual(byCost.map(\.key), expected.modelCostRanking.map(\.key), scope)
            for (row, golden) in zip(byCost, expected.modelCostRanking) {
                XCTAssertEqual(row.barValue, golden.value, accuracy: 1e-9, "\(scope) \(golden.key)")
            }

            for (client, expectedRows) in expected.modelRowsPerTool {
                let rows = AttributionRows.modelRowsForTool(period: period, client: client)
                XCTAssertEqual(rows.map(\.key), expectedRows.map(\.key), "\(scope) \(client)")
                for (row, golden) in zip(rows, expectedRows) {
                    let context = "\(scope) \(client) \(golden.key)"
                    XCTAssertEqual(row.tokens, golden.value, context)
                    XCTAssertEqual(row.costUsd, golden.cost, accuracy: 1e-9, context)
                    XCTAssertEqual(row.unpricedTokens, golden.unpricedTokens, context)
                    XCTAssertEqual(row.isUnattributed, golden.unattributed ?? false, context)
                    XCTAssertEqual(try XCTUnwrap(row.percent), golden.percent, accuracy: 1e-9, context)
                    XCTAssertEqual(AttributionRows.detailPercentLabel(try XCTUnwrap(row.percent)), golden.percentLabel, context)
                }
            }
        }
        for vector in golden.percentLabels {
            XCTAssertEqual(AttributionRows.detailPercentLabel(vector.value), vector.label, "\(vector.value)")
        }
    }

    func testRemainderRowVisibilityFollowsDisplayCurrency() {
        // 0.00004 USD formats as $0.0000 (hidden); as TWD it is NT$0.0013.
        let period = UsagePeriod(
            totalTokens: 100,
            costUsd: 1.00004,
            clientBreakdown: ["claude": UsageBreakdownEntry(tokens: 100, costUsd: 1)]
        )
        XCTAssertEqual(AttributionRows.usageToolRows(period: period).map(\.key), ["claude"])
        let twd = DisplayFormatter(units: .western, currency: .twd)
        let rows = AttributionRows.usageToolRows(period: period, formatter: twd)
        XCTAssertEqual(rows.map(\.key), ["claude", AttributionRows.unattributedKey])
        XCTAssertEqual(rows.last?.costUsd ?? 0, 0.00004, accuracy: 1e-12)
        XCTAssertTrue(rows.last?.isUnattributed ?? false)
    }

    func testCostRankingNeedsAKnownCost() {
        let period = UsagePeriod(
            totalTokens: 300,
            costUsd: 0.5,
            modelBreakdown: [
                "a": UsageBreakdownEntry(tokens: 200),
                "b": UsageBreakdownEntry(tokens: 100),
            ]
        )
        // Only the remainder has a cost, so ranking falls back to tokens.
        let rows = AttributionRows.modelRows(period: period, ranking: .cost)
        XCTAssertEqual(AttributionRows.effectiveRankingMetric(rows, metric: .cost), .tokens)
        XCTAssertEqual(rows.map(\.key), ["a", "b", AttributionRows.unattributedKey])
        XCTAssertEqual(rows.map(\.barValue), [200, 100, 0])
    }

    // MARK: - Assertions

    private func assertRow(_ row: SessionRow, _ expected: SessionGolden.Row, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(row.client, expected.client, context, file: file, line: line)
        XCTAssertEqual(text(row.name), expected.name, context, file: file, line: line)
        XCTAssertEqual(text(row.modelLabel), expected.modelLabel, context, file: file, line: line)
        XCTAssertEqual(row.subtitle.map(text) ?? "", expected.subtitle ?? "", context, file: file, line: line)
        XCTAssertEqual(row.activityLine.map(text), expected.activity.flatMap { $0.isEmpty ? nil : $0 }, context, file: file, line: line)
        XCTAssertEqual(row.idLabel ?? "", expected.detail, context, file: file, line: line)
        XCTAssertEqual(row.tokens, expected.value, context, file: file, line: line)
        XCTAssertEqual(row.costUsd, expected.cost, accuracy: 1e-12, context, file: file, line: line)
        XCTAssertEqual(row.unpricedTokens, expected.unpricedTokens, context, file: file, line: line)
        XCTAssertEqual(row.isArchived, expected.archived ?? false, context, file: file, line: line)
        XCTAssertEqual(row.isRunning, expected.running ?? false, context, file: file, line: line)
        XCTAssertEqual(row.state.rawValue, expected.activityState, context, file: file, line: line)
        XCTAssertEqual(row.isBackgroundReview, expected.backgroundReview ?? false, context, file: file, line: line)
        assertContext(row.context, expected.context, context, file: file, line: line)
        assertContext(row.contextSnapshot, expected.contextSnapshot, context, file: file, line: line)
        assertCache(row.promptCache, expected.promptCache, context, file: file, line: line)
        XCTAssertEqual(shareEntries(row.modelShares), expected.modelTooltipEntries, context, file: file, line: line)
        XCTAssertEqual(SessionLive.milliseconds(row.sortTime), SessionLive.milliseconds(Fixture.date(expected.sortTime)), context, file: file, line: line)
        XCTAssertEqual(row.timeLabel, row.activity.compactMap { if case let .time(value) = $0 { return value } else { return nil } }.first, context, file: file, line: line)
        if case let .session(session) = row.kind {
            XCTAssertEqual(row.id, "session:\(session.id)", context, file: file, line: line)
        } else {
            XCTFail("session kind \(context)", file: file, line: line)
        }
    }

    private func assertContext(_ actual: SessionContextGauge?, _ expected: SessionGolden.Context?, toneChecked: Bool = true, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let expected else {
            XCTAssertNil(actual, context, file: file, line: line)
            return
        }
        guard let actual else {
            XCTFail("missing context \(context)", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.contextTokens, expected.contextTokens, context, file: file, line: line)
        XCTAssertEqual(actual.contextWindow, expected.contextWindow, context, file: file, line: line)
        XCTAssertEqual(actual.percentLeft, expected.percentLeft, context, file: file, line: line)
        XCTAssertEqual(actual.percentUsed, expected.percentUsed, context, file: file, line: line)
        if toneChecked {
            XCTAssertEqual(toneText(actual.tone), expected.tone, context, file: file, line: line)
        }
    }

    private func assertCache(_ actual: PromptCacheCountdown?, _ expected: SessionGolden.Cache?, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual?.minutes, expected?.minutes, context, file: file, line: line)
        XCTAssertEqual(actual?.ttlSeconds, expected?.ttlSeconds, context, file: file, line: line)
        XCTAssertEqual(
            actual.map { SessionLive.milliseconds($0.expiresAt) },
            expected.map { SessionLive.milliseconds(Fixture.date($0.expiresAt)) },
            context, file: file, line: line
        )
    }

    private func assertAttribution(_ row: AttributionRow, _ expected: SessionGolden.AttributionRowGolden, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(row.tokens, expected.value, context, file: file, line: line)
        XCTAssertEqual(row.costUsd, expected.cost, accuracy: 1e-9, context, file: file, line: line)
        XCTAssertEqual(row.unpricedTokens, expected.unpricedTokens, context, file: file, line: line)
        XCTAssertEqual(row.isUnattributed, expected.unattributed ?? false, context, file: file, line: line)
        XCTAssertEqual(row.cacheRead, expected.cacheReadTokens, context, file: file, line: line)
        XCTAssertEqual(row.cacheWrite, expected.cacheWriteTokens, context, file: file, line: line)
        XCTAssertEqual(row.output, expected.outputTokens, context, file: file, line: line)
        XCTAssertEqual(row.unclassified, expected.unclassifiedTokens, context, file: file, line: line)
        assertComponents(row.components, expected.components, context, file: file, line: line)
        XCTAssertEqual(text(formatter.costLabel(row.costUsd, unpricedTokens: row.unpricedTokens, compact: false)), expected.usageCostLabel, context, file: file, line: line)
        XCTAssertEqual(text(formatter.costLabel(row.costUsd, unpricedTokens: row.unpricedTokens, compact: true)), expected.compactUsageCostLabel, context, file: file, line: line)
    }

    private func assertComponents(_ components: TokenComponents, _ expected: SessionGolden.Components, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(components.cacheRead, expected.cacheRead, context, file: file, line: line)
        XCTAssertEqual(components.cacheMiss, expected.cacheMiss, context, file: file, line: line)
        XCTAssertEqual(components.output, expected.output, context, file: file, line: line)
        XCTAssertEqual(components.unclassified, expected.unclassified, context, file: file, line: line)
        let input = AttributionRows.inputPercentages(components)
        XCTAssertEqual(input.hit, expected.inputHit, accuracy: 1e-9, context, file: file, line: line)
        XCTAssertEqual(input.miss, expected.inputMiss, accuracy: 1e-9, context, file: file, line: line)
        XCTAssertEqual(input.roundedHit, expected.hitPct, context, file: file, line: line)
        XCTAssertEqual(input.roundedMiss, expected.missPct, context, file: file, line: line)
        XCTAssertEqual(AttributionRows.detailPercentLabel(input.hit), expected.hitLabel, context, file: file, line: line)
        XCTAssertEqual(AttributionRows.detailPercentLabel(input.miss), expected.missLabel, context, file: file, line: line)
    }

    // MARK: - Desktop English, for comparing structured values with the goldens

    private func text(_ model: SessionModelLabel) -> String {
        switch model {
        case .none: return ""
        case let .single(id): return id
        case let .count(count): return "\(count) models"
        }
    }

    private func text(_ part: SessionActivityPart) -> String {
        switch part {
        case .archived: return "Archived"
        case let .time(value): return value
        case let .calls(count): return "\(formatter.fullTokens(count)) \(count == 1 ? "call" : "calls")"
        case let .cacheHit(value): return value
        case let .tokensPerSecond(rate): return "\(formatter.fullTokens(rate)) tok/s"
        }
    }

    private func text(_ parts: [SessionActivityPart]) -> String {
        parts.map(text).joined(separator: " · ")
    }

    private func text(_ name: SessionRowName) -> String {
        switch name {
        case let .title(title): return title
        case let .tool(label, model): return [label ?? "Session", text(model)].filter { !$0.isEmpty }.joined(separator: " · ")
        case .backgroundReviews: return "Codex Auto Review"
        }
    }

    private func text(_ subtitle: SessionRowSubtitle) -> String {
        switch subtitle {
        case let .tool(label, model): return [label ?? "Session", text(model)].filter { !$0.isEmpty }.joined(separator: " · ")
        case let .activity(parts): return text(parts)
        case .reviewSummary: return ""
        }
    }

    private func text(_ label: CostLabel) -> String {
        switch label {
        case let .plain(cost): return cost
        case let .partial(cost, unpriced): return "\(cost) + \(unpriced) unpriced tokens"
        case let .unknown(unpriced): return "— (\(unpriced) unpriced tokens)"
        case let .compactPartial(cost): return "\(cost) + ?"
        case .compactUnknown: return "—"
        }
    }

    private func toneText(_ tone: ContextTone) -> String {
        tone == .neutral ? "" : tone.rawValue
    }

    private func shareEntries(_ shares: [SessionModelShare]) -> [[String]] {
        shares.map { [$0.model ?? "Unclassified", formatter.fullTokens($0.tokens), AttributionRows.detailPercentLabel($0.percent)] }
    }
}

// MARK: - Golden loading

private enum SessionGolden {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func data(_ name: String, subdirectory: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: subdirectory) else {
            throw NSError(domain: "SessionGolden", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(subdirectory)/\(name).json"])
        }
        return try Data(contentsOf: url)
    }

    static func stats() throws -> HubStats {
        try HubStats.decode(from: data("stats", subdirectory: "Fixtures/v2"), options: .app)
    }

    static func sessions() throws -> Sessions {
        try JSONDecoder().decode(Sessions.self, from: data("sessions", subdirectory: "Fixtures/v2/golden"))
    }

    static func projects() throws -> Projects {
        try JSONDecoder().decode(Projects.self, from: data("projects", subdirectory: "Fixtures/v2/golden"))
    }

    static func attribution() throws -> Attribution {
        try JSONDecoder().decode(Attribution.self, from: data("attribution", subdirectory: "Fixtures/v2/golden"))
    }

    struct Context: Decodable {
        var contextTokens: Int
        var contextWindow: Int
        var percentLeft: Int
        var percentUsed: Int
        var tone: String?
    }

    struct Cache: Decodable {
        var expiresAt: String
        var ttlSeconds: Int
        var minutes: Int
    }

    struct Row: Decodable {
        var key: String
        var name: String
        var modelLabel: String
        var subtitle: String?
        var activity: String?
        var detail: String
        var value: Int
        var cost: Double
        var unpricedTokens: Int?
        var archived: Bool?
        var running: Bool?
        var activityState: String
        var context: Context?
        var contextSnapshot: Context?
        var promptCache: Cache?
        var client: String
        var backgroundReview: Bool?
        var modelTooltipEntries: [[String]]
        var sortTime: String
    }

    struct Grouped: Decodable {
        var key: String
        var detail: String?
        var value: Int?
        var cost: Double?
        var client: String?
        var sortTime: String?
        var reviewGroup: Bool?
        var backgroundReviewKeys: [String]?
    }

    struct Parts: Decodable {
        var archived: Bool
        var time: String
        var calls: String
        var cacheHit: String
        var tokenRate: String
    }

    struct Primitive: Decodable {
        var key: String
        var activityState: String
        var isRunning: Bool
        var isArchived: Bool
        var contextWindow: Context?
        var contextRow: Context?
        var contextForRow: Context?
        var promptCache: Cache?
        var idLabel: String
        var modelLabel: String
        var tokenRate: Double
        var cacheHitPercent: Double?
        var compactTime: String
        var activityParts: Parts
        var modelTooltipEntries: [[String]]
    }

    struct Clock: Decodable {
        var at: String
        var rows: [Row]
        var grouped: [Grouped]
        var primitives: [Primitive]?
        var nextPromptCacheChangeAt: String?
        var nextSessionStatusChangeAt: String?
    }

    struct Tone: Decodable {
        var percentLeft: Int
        var tone: String
    }

    struct IDLabel: Decodable {
        var id: String
        var label: String
    }

    struct Sessions: Decodable {
        var runningWindowMs: Int
        var contextTones: [Tone]
        var incomplete: [String: Bool]
        var archivedSessionCount: Int
        var idLabels: [IDLabel]
        var scopes: [String: [String: Clock]]
    }

    struct ProjectTool: Decodable {
        var key: String
        var name: String
        var value: Int
        var percent: Double
    }

    struct ProjectRowGolden: Decodable {
        var key: String
        var name: String
        var value: Int
        var cost: Double
        var unpricedTokens: Int?
        var clients: [String]
        var clientTokens: [String: Int]
        var accordionRows: [ProjectTool]
    }

    struct Canonical: Decodable {
        var value: String
        var key: String
    }

    struct Label: Decodable {
        var left: String
        var right: String
        var label: String
    }

    struct Projects: Decodable {
        var incomplete: [String: Bool]
        var canonicalKeys: [Canonical]
        var deterministicLabels: [Label]
        var scopes: [String: [ProjectRowGolden]]
    }

    struct Components: Decodable {
        var cacheRead: Int
        var cacheMiss: Int
        var output: Int
        var unclassified: Int
        var hitPct: Int
        var missPct: Int
        var inputHit: Double
        var inputMiss: Double
        var hitLabel: String
        var missLabel: String
    }

    struct AttributionRowGolden: Decodable {
        var key: String
        var value: Int
        var cost: Double
        var unpricedTokens: Int?
        var unattributed: Bool?
        var cacheReadTokens: Int
        var cacheWriteTokens: Int
        var outputTokens: Int
        var unclassifiedTokens: Int
        var usageCostLabel: String
        var compactUsageCostLabel: String
        var components: Components
        var barValue: Double?
    }

    struct ToolModel: Decodable {
        var key: String
        var value: Int
        var cost: Double
        var unpricedTokens: Int?
        var percent: Double
        var unattributed: Bool?
        var percentLabel: String
    }

    struct Prefs: Decodable {
        var order: String
        var hidden: String
        var pinned: String
    }

    struct Scenario: Decodable {
        var prefs: Prefs
        var keys: [String]
    }

    /// `[key, barValue]`.
    struct RankEntry: Decodable {
        var key: String
        var value: Double

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            key = try container.decode(String.self)
            value = try container.decode(Double.self)
        }
    }

    struct Scope: Decodable {
        var periodComponents: Components
        var unknownModelSource: String?
        var toolRows: [AttributionRowGolden]
        var toolOrder: [String: Scenario]
        var modelRows: [AttributionRowGolden]
        var modelCostRanking: [RankEntry]
        var modelRowsPerTool: [String: [ToolModel]]
    }

    struct KnownClient: Decodable {
        var id: String
    }

    struct PercentLabel: Decodable {
        var value: Double
        var label: String
    }

    struct Attribution: Decodable {
        var unattributedKey: String
        var knownClients: [KnownClient]
        var percentLabels: [PercentLabel]
        var scopes: [String: Scope]
    }
}

/// A deterministic shuffle source (SplitMix64).
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

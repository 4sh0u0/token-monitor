import Foundation
import XCTest
@testable import TokenMonitorKit

final class LimitWindowTests: XCTestCase {
    private func provider(_ id: String) throws -> LimitProvider {
        try XCTUnwrap(Fixture.stats().limits.first { $0.provider == id })
    }

    func testPercentWindows() throws {
        let claude = try provider("claude")
        let session = claude.windows[0]
        XCTAssertEqual(session.kind, .session)
        XCTAssertFalse(session.isMoney)
        XCTAssertEqual(session.usedPercent, 42)
        XCTAssertEqual(session.remainingPercent, 58)
        XCTAssertEqual(session.displayFraction ?? -1, 0.58, accuracy: 1e-9)
        XCTAssertEqual(claude.meterFraction(for: session) ?? -1, 0.58, accuracy: 1e-9)
        XCTAssertEqual(session.windowMinutes, 300)
        XCTAssertEqual(session.boundaryKind, .reset)
        XCTAssertNotNil(session.resetsAt)
        XCTAssertNil(session.label)
        XCTAssertEqual(claude.windows[1].remainingPercent, 79.5)
    }

    func testMoneyWindowsHonourShowMeter() throws {
        let claude = try provider("claude")
        let spend = claude.windows[2]
        XCTAssertTrue(spend.isMoney)
        XCTAssertTrue(spend.isSpend)
        XCTAssertEqual(spend.moneyAmount, 12.4)
        XCTAssertEqual(spend.currency, "USD")
        XCTAssertEqual(spend.label, "Usage credits")
        XCTAssertFalse(spend.showMeter)
        XCTAssertNil(spend.displayFraction)
        XCTAssertNil(claude.meterFraction(for: spend))

        let balance = claude.windows[3]
        XCTAssertTrue(balance.isCredits)
        XCTAssertEqual(balance.moneyAmount, 37.5)
        XCTAssertFalse(balance.showMeter, "Claude's prepaid pool has no denominator")
        XCTAssertNil(claude.meterFraction(for: balance))
        XCTAssertEqual(claude.headlineWindow?.kind, .session, "the percentage window with the least left")
    }

    func testCreditsWithAndWithoutWirePercentage() throws {
        let openRouter = try provider("openrouter")
        let credits = openRouter.windows[0]
        XCTAssertTrue(credits.isCredits)
        XCTAssertEqual(credits.moneyAmount, 13.8)
        XCTAssertEqual(credits.displayFraction ?? -1, 0.69, accuracy: 1e-9)

        // DeepSeek reports money only: the meter is the desktop's display-only
        // derivation balance / (balance + month spend).
        let deepSeek = try provider("deepseek")
        let balance = deepSeek.windows[0]
        XCTAssertNil(balance.usedPercent)
        XCTAssertNil(balance.displayFraction)
        XCTAssertTrue(balance.showMeter)
        XCTAssertEqual(balance.currency, "CNY")
        XCTAssertEqual(deepSeek.meterFraction(for: balance) ?? -1, 86.42 / (86.42 + 23.6), accuracy: 1e-9)
        XCTAssertEqual(deepSeek.headlineWindow, balance)

        var empty = deepSeek
        empty.windows[0].remaining = 0
        XCTAssertEqual(empty.meterFraction(for: empty.windows[0]), 0, "no money left is 0%, not full")
    }

    func testSortedByUrgencyPutsTheTightestReadyQuotaFirst() {
        func percent(_ id: String, left: Double, status: LimitStatus = .ok, stale: Bool = false) -> LimitProvider {
            LimitProvider(id: id, provider: id, status: status, isStale: stale, windows: [
                LimitWindow(kind: .weekly, usedPercent: 100 - left, remainingPercent: left),
                LimitWindow(kind: .session, usedPercent: 0, remainingPercent: 100)
            ])
        }
        let balanceOnly = LimitProvider(id: "claude-credits", provider: "claude", windows: [
            LimitWindow(kind: .billing, metric: .credits, remaining: 37.5, currency: "USD", showMeter: false)
        ])
        let providers = [
            balanceOnly,
            percent("codex", left: 80),
            percent("kimi", left: 12, stale: true),
            percent("cursor", left: 30),
            percent("zai", left: 5, status: .unauthorized),
            percent("openrouter", left: 30)
        ]
        XCTAssertEqual(
            LimitProvider.sortedByUrgency(providers).map(\.id),
            ["cursor", "openrouter", "codex", "claude-credits", "zai", "kimi"],
            "ready before stale or failing; least left first; no meter after every measured one; ties keep their order"
        )
        XCTAssertEqual(LimitProvider.sortedByUrgency(providers.reversed()).map(\.id).prefix(2), ["openrouter", "cursor"])
        XCTAssertEqual(LimitProvider.sortedByUrgency([]), [])
    }

    func testSortedByUrgencyOnTheFixture() throws {
        // Healthy: codex 39% (weekly), claude 58% (session), openrouter 69%,
        // deepseek 79% (derived from its balance), opencode a balance without
        // a meter. Then the failing rows: kimi has a reading, cursor none.
        let sorted = LimitProvider.sortedByUrgency(LimitProvider.sortedForDisplay(try Fixture.stats().limits))
        XCTAssertEqual(sorted.map(\.provider), ["codex", "claude", "openrouter", "deepseek", "opencode", "kimi", "cursor"])
    }

    func testCodexAdditionalBucketsStayOutOfCompactSurfaces() throws {
        let codex = try provider("codex")
        XCTAssertEqual(codex.windows.count, 3)
        XCTAssertTrue(codex.windows[2].isAdditional)
        XCTAssertEqual(codex.windows[2].label, "GPT-5.3-Codex-Spark")
        XCTAssertEqual(codex.windows[2].limitId, "codex_bengalfox")
        XCTAssertEqual(codex.primaryWindows.count, 2)
        XCTAssertEqual(codex.headlineWindow?.remainingPercent, 39)
        XCTAssertEqual(Set(codex.windows.map(\.id)).count, 3)
        XCTAssertEqual(codex.compacted().windows.count, 2)
    }

    func testWireNormalization() throws {
        let json = """
        {"provider":"Kiro","status":"ok","windows":[
          {"kind":"monthly","used":30,"limit":120},
          {"type":"Weekly","used_percent":140,"resets_at":1791936000},
          {"kind":"weekly","utilization":"25","meter":false,"boundary_kind":"MIXED"},
          {"kind":"five_hour","usedPercent":10},
          {"kind":"daily","remainingPercent":12,"currency":"usd","detail":"Unlimited"},
          {"kind":"daily","remainingPercent":12}
        ]}
        """
        let provider = try JSONDecoder().decode(LimitProvider.self, from: Data(json.utf8))
        XCTAssertEqual(provider.provider, "kiro")
        XCTAssertEqual(provider.id, "kiro-anonymous")
        XCTAssertEqual(provider.windows.map(\.kind), [.billing, .weekly, .weekly, .daily, .daily], "unknown kinds are dropped")
        XCTAssertEqual(provider.windows[0].usedPercent, 25, "derived from used/limit")
        XCTAssertEqual(provider.windows[1].usedPercent, 100, "clamped")
        XCTAssertEqual(provider.windows[1].remainingPercent, 0)
        XCTAssertEqual(provider.windows[1].resetsAt, Date(timeIntervalSince1970: 1_791_936_000))
        XCTAssertEqual(provider.windows[2].usedPercent, 25)
        XCTAssertFalse(provider.windows[2].showMeter)
        XCTAssertEqual(provider.windows[2].boundaryKind, .mixed)
        XCTAssertNil(provider.windows[3].usedPercent)
        XCTAssertEqual(provider.windows[3].remainingPercent, 12)
        XCTAssertEqual(provider.windows[3].currency, "USD")
        XCTAssertTrue(provider.windows[3].isUnlimited)
        XCTAssertNotEqual(provider.windows[3].id, provider.windows[4].id, "duplicate windows get distinct ids")
    }

    func testProviderRoundTripsThroughItsOwnEncoding() throws {
        let original = try Fixture.stats().limits
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([LimitProvider].self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testRoundOneFieldsKeepTheirMeaningBesideTheExtras() throws {
        // The legacy plan fallback is unchanged; the raw labels sit beside it.
        let deepSeek = try provider("deepseek")
        XCTAssertEqual(deepSeek.planLabel, "Pay-as-you-go")
        XCTAssertNil(deepSeek.explicitPlanLabel)
        XCTAssertEqual(deepSeek.accountLabel, "Pay-as-you-go")
        XCTAssertEqual(deepSeek.balance?.trackingSince, Fixture.date("2026-08-10T02:47:49.082Z"))
        XCTAssertEqual(deepSeek.sourceDeviceId, "studio-mac")

        let claude = try provider("claude")
        XCTAssertEqual(claude.planLabel, "Max")
        XCTAssertEqual(claude.balance?.amount, 37.5)
        XCTAssertEqual(claude.balance?.tranches.map(\.amount), [25, 12.5])
        XCTAssertEqual(claude.compacted().balance?.tranches, [], "per-grant detail stays out of shared containers")
        XCTAssertEqual(claude.compacted().balance?.amount, 37.5)

        // `balanceUsd` from producers that predate the balance block.
        XCTAssertEqual(try provider("opencode").balance, LimitBalance(amount: 4.25, currency: "USD"))
    }

    func testCompactedMasksIdentity() throws {
        let claude = try provider("claude").compacted()
        XCTAssertEqual(claude.accountEmail, "d***v@example.com")
        XCTAssertEqual(LimitProvider.maskedEmail("a@b.co"), "a***@b.co")
        XCTAssertNil(LimitProvider.maskedEmail("not-an-email"))
        XCTAssertNil(LimitProvider.maskedEmail("x@localhost"))
        XCTAssertEqual(LimitProvider.safeDisplayName("  Team   Plan "), "Team Plan")
        XCTAssertNil(LimitProvider.safeDisplayName("/Users/me/.config"))
        XCTAssertNil(LimitProvider.safeDisplayName("https://example.com"))
        XCTAssertNil(LimitProvider.safeDisplayName("C:\\Users\\me"))
        XCTAssertNil(LimitProvider.safeDisplayName("me@example.com"))
    }
}

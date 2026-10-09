import Foundation
import XCTest
@testable import TokenMonitorKit

final class LenientDecodingTests: XCTestCase {
    func testOddFieldsNeverFailTheResponse() throws {
        let json = """
        {
          "updatedAt": 1791936000000,
          "staleAfterMs": "600000",
          "projectsIncomplete": "true",
          "periods": {
            "today": {
              "capabilities": "yes",
              "totalTokens": "1200",
              "costUsd": 3,
              "outputTokens": 1.5e2,
              "cacheReadTokens": null,
              "timedDurationMs": -5,
              "clients": {"claude": 1000, "codex": "200", "broken": null, "__unattributed": 50, " ": 9, "zero": 0},
              "clientCosts": {"claude": "2.5", "codex": {"nested": 1}},
              "models": ["not", "an", "object"],
              "sessions": {"a": {}, "b": 1}
            },
            "month": "garbage"
          },
          "limits": {
            "providers": [
              42,
              {"status": "ok"},
              {"provider": "claude", "status": "ok", "windows": [{"kind": "nope"}, null, {"kind": "session", "usedPercent": "40"}]},
              {"provider": "claude", "status": "weird", "windows": "none", "balance": {"amount": "12.5", "currency": "usd"}}
            ]
          },
          "devices": [7, {"deviceId": "ok", "stale": 1, "periods": {"today": {"totalTokens": 12.6}}}],
          "historyPreview": {"daily": [{"date": "2026-02-30", "tokens": 1}, {"date": "2026-10-01", "tokens": "5", "cost": null}, "x"]}
        }
        """
        let stats = try HubStats.decode(from: Data(json.utf8))
        XCTAssertEqual(stats.updatedAt, Date(timeIntervalSince1970: 1_791_936_000))
        XCTAssertEqual(stats.staleAfter, 600)
        XCTAssertTrue(stats.projectsIncomplete)

        let today = stats.today
        XCTAssertEqual(today.totalTokens, 1200)
        XCTAssertEqual(today.costUsd, 3)
        XCTAssertEqual(today.outputTokens, 150)
        XCTAssertEqual(today.cacheReadTokens, 0)
        XCTAssertEqual(today.timedDurationMs, 0, "negative counters clamp to zero")
        XCTAssertFalse(today.hasExactTokenComponents)
        XCTAssertEqual(today.clients.map(\.id), ["claude", "codex"])
        XCTAssertEqual(today.clients.map(\.costUsd), [2.5, nil])
        XCTAssertEqual(today.unattributedClientTokens, 0)
        XCTAssertEqual(today.models, [])
        XCTAssertEqual(today.sessionCount, 2)
        XCTAssertEqual(stats.month, .empty)
        XCTAssertEqual(stats.allTime, .empty)

        XCTAssertEqual(stats.limits.count, 2)
        XCTAssertEqual(stats.limits[0].windows.map(\.kind), [.session])
        XCTAssertEqual(stats.limits[0].windows.first?.usedPercent, 40)
        XCTAssertEqual(stats.limits[1].status, .error)
        XCTAssertEqual(stats.limits[1].windows, [])
        XCTAssertEqual(stats.limits[1].balance?.amount, 12.5)
        XCTAssertEqual(stats.limits[1].balance?.currency, "USD")
        XCTAssertEqual(stats.limits.map(\.id), ["claude-anonymous-1", "claude-anonymous-2"])

        XCTAssertEqual(stats.devices.count, 1)
        XCTAssertFalse(stats.devices[0].isStale, "only a JSON boolean (or \"true\") marks a device stale")
        XCTAssertEqual(stats.devices[0].today.tokens, 13)

        XCTAssertEqual(stats.history, [HistoryDay(date: "2026-10-01", tokens: 5, costUsd: 0)])
    }

    func testEmptyObjectIsEmptyStats() throws {
        let stats = try HubStats.decode(from: Data("{}".utf8))
        XCTAssertEqual(stats, HubStats())
        XCTAssertFalse(stats.isSourceStale)
    }

    func testNonObjectBodiesThrowDecodingErrors() {
        for body in ["[]", "<html>captive portal</html>", "", "null"] {
            XCTAssertThrowsError(try HubStats.decode(from: Data(body.utf8)), body) { error in
                guard case HubClientError.decoding = error else { return XCTFail("\(error)") }
            }
        }
    }

    func testDatesAcceptFractionalWholeAndEpochForms() throws {
        struct Probe: Decodable {
            let dates: [Date?]
            enum CodingKeys: String, CodingKey { case a, b, c, d, e }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                dates = [.a, .b, .c, .d, .e].map { container.lenientDate($0) }
            }
        }
        let json = #"{"a":"2026-10-09T02:47:49.082Z","b":"2026-10-09T02:47:49Z","c":1791936000,"d":"not a date","e":"2026-10-09T10:47:49+08:00"}"#
        let dates = try JSONDecoder().decode(Probe.self, from: Data(json.utf8)).dates
        XCTAssertEqual(dates[0]?.timeIntervalSince1970 ?? 0, 1_791_514_069.082, accuracy: 0.0005)
        XCTAssertEqual(dates[1], Date(timeIntervalSince1970: 1_791_514_069))
        XCTAssertEqual(ISODate.string(from: dates[0]!), "2026-10-09T02:47:49.082Z")
        XCTAssertEqual(ISODate.string(from: Date(timeIntervalSince1970: 1_791_514_069.9996)), "2026-10-09T02:47:50.000Z")
        XCTAssertEqual(dates[2], Date(timeIntervalSince1970: 1_791_936_000))
        XCTAssertNil(dates[3])
        XCTAssertEqual(dates[4], dates[1])
    }

    func testHealthFixture() throws {
        let health = try JSONDecoder().decode(HubHealth.self, from: Fixture.data("health.json"))
        XCTAssertTrue(health.ok)
        XCTAssertEqual(health.runtime, "node-hub")
        XCTAssertEqual(health.deviceCount, 3)
        XCTAssertEqual(health.secretRequired, true)
        XCTAssertEqual(health.coreRevision, 74)
        XCTAssertEqual(health.runtimeRevision, 5)
        XCTAssertEqual(health.now, Fixture.date("2026-10-09T02:48:07.688Z"))

        let legacy = try JSONDecoder().decode(HubHealth.self, from: Data(#"{"ok":true}"#.utf8))
        XCTAssertNil(legacy.coreRevision)
    }
}

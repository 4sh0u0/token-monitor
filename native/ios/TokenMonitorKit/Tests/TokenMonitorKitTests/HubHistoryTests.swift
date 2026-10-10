import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TokenMonitorKit

/// Round-2 captures (`Fixtures/v2`, see its README.txt): a real Node Hub's
/// `GET /api/history` and `GET /api/devices` under a frozen clock
/// (now 2026-10-10T16:30:00Z, Hub today 2026-10-10).
private enum HistoryFixtures {
    static let todayKey = "2026-10-10"

    static func data(_ name: String, subdirectory: String = "Fixtures/v2") throws -> Data {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let url = Bundle.module.url(
            forResource: parts[0],
            withExtension: parts.count > 1 ? parts[1] : nil,
            subdirectory: subdirectory
        ) else {
            throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing fixture \(subdirectory)/\(name)"])
        }
        return try Data(contentsOf: url)
    }

    static func json(_ name: String, subdirectory: String = "Fixtures/v2") throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(name, subdirectory: subdirectory)) as? [String: Any])
    }

    static func history() throws -> HubHistory {
        try HubHistory.decode(from: data("history.json"))
    }

    static func records() throws -> [DeviceHistoryRecord] {
        try DeviceHistoryRecord.decodeList(from: data("devices.json"))
    }

    static func rawRecord(_ id: String) throws -> [String: Any] {
        let devices = try XCTUnwrap(json("devices.json")["devices"] as? [[String: Any]])
        return try XCTUnwrap(devices.first { $0["deviceId"] as? String == id })
    }
}

private func number(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue
}

/// Compares a decoded Double with one read through `JSONSerialization`, which
/// on Linux can land a unit or two in the last place away from the correctly
/// rounded value `JSONDecoder` (and JavaScript) produce for long decimals.
private func assertClose(_ decoded: Double?, _ reference: Double?, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    guard let decoded, let reference else {
        return XCTAssertEqual(decoded, reference, message, file: file, line: line)
    }
    XCTAssertEqual(decoded, reference, accuracy: max(1e-9, abs(reference) * 1e-14), message, file: file, line: line)
}

final class HubHistoryTests: XCTestCase {
    // MARK: GET /api/history

    func testHistoryFixtureDecodesEveryRowAndField() throws {
        let history = try HistoryFixtures.history()
        let raw = try HistoryFixtures.json("history.json")
        let rawDaily = try XCTUnwrap(raw["daily"] as? [[String: Any]])
        let rawMonthly = try XCTUnwrap(raw["monthly"] as? [[String: Any]])

        XCTAssertEqual(history.daily.count, 281)
        XCTAssertEqual(history.daily.count, rawDaily.count)
        XCTAssertEqual(history.daily.first?.date, "2025-10-06")
        XCTAssertEqual(history.daily.last?.date, HistoryFixtures.todayKey)
        XCTAssertEqual(history.daily.map(\.date), history.daily.map(\.date).sorted())
        XCTAssertEqual(history.monthly.count, 14)
        XCTAssertEqual(history.monthly.map(\.month), rawMonthly.compactMap { $0["month"] as? String })
        XCTAssertFalse(history.isEmpty)

        for (day, row) in zip(history.daily, rawDaily) {
            XCTAssertEqual(day.date, row["date"] as? String)
            XCTAssertEqual(Double(day.tokens), number(row["tokens"]), day.date)
            assertClose(day.costUsd, number(row["cost"]), day.date)
            XCTAssertEqual(Double(day.messages), number(row["messages"]), day.date)
            assertClose(day.activeTimeMs, number(row["activeTimeMs"]), day.date)
            XCTAssertEqual(Double(day.cacheReadTokens), number(row["cacheReadTokens"]), day.date)
            XCTAssertEqual(Double(day.cacheWriteTokens), number(row["cacheWriteTokens"]), day.date)
            XCTAssertEqual(Double(day.outputTokens), number(row["outputTokens"]), day.date)
            XCTAssertEqual(day.unclassifiedTokens.map(Double.init), number(row["unclassifiedTokens"]), day.date)
            XCTAssertEqual(day.tokenComponentsAvailable, row["tokenComponentsAvailable"] as? Bool, day.date)
            XCTAssertEqual(day.unpricedTokens.map(Double.init), number(row["unpricedTokens"]), day.date)
            try assertBuckets(day.perClient, row["perClient"], context: "\(day.date) perClient")
            try assertBuckets(day.perModel, row["perModel"], context: "\(day.date) perModel")
        }
        for (month, row) in zip(history.monthly, rawMonthly) {
            XCTAssertEqual(Double(month.tokens), number(row["tokens"]), month.month)
            assertClose(month.costUsd, number(row["cost"]), month.month)
            assertClose(month.activeTimeMs, number(row["activeTimeMs"]), month.month)
            XCTAssertEqual(month.unpricedTokens.map(Double.init), number(row["unpricedTokens"]), month.month)
            try assertBuckets(month.perClient, row["perClient"], context: "\(month.month) perClient")
            try assertBuckets(month.perModel, row["perModel"], context: "\(month.month) perModel")
        }
    }

    private func assertBuckets(_ buckets: [String: HistoryBucket], _ raw: Any?, context: String) throws {
        let rows = try XCTUnwrap(raw as? [String: [String: Any]], context)
        XCTAssertEqual(Set(buckets.keys), Set(rows.keys), context)
        for (key, row) in rows {
            let bucket = try XCTUnwrap(buckets[key], "\(context) \(key)")
            XCTAssertEqual(Double(bucket.tokens), number(row["tokens"]), "\(context) \(key)")
            assertClose(bucket.costUsd, number(row["cost"]), "\(context) \(key)")
            XCTAssertEqual(Double(bucket.messages), number(row["messages"]) ?? 0, "\(context) \(key)")
            XCTAssertEqual(bucket.unpricedTokens.map(Double.init), number(row["unpricedTokens"]), "\(context) \(key)")
            XCTAssertEqual(bucket.cacheReadTokens.map(Double.init), number(row["cacheReadTokens"]), "\(context) \(key)")
            XCTAssertEqual(bucket.cacheWriteTokens.map(Double.init), number(row["cacheWriteTokens"]), "\(context) \(key)")
            XCTAssertEqual(bucket.outputTokens.map(Double.init), number(row["outputTokens"]), "\(context) \(key)")
            XCTAssertEqual(bucket.unclassifiedTokens.map(Double.init), number(row["unclassifiedTokens"]), "\(context) \(key)")
        }
    }

    func testHistoryFixtureSpotValues() throws {
        let history = try HistoryFixtures.history()
        let today = try XCTUnwrap(history.daily.last)
        XCTAssertEqual(today.tokens, 60_657_600)
        XCTAssertEqual(today.costUsd, 129.63412)
        XCTAssertEqual(today.messages, 1349)
        XCTAssertEqual(today.unpricedTokens, 72_000)
        XCTAssertTrue(today.tokenComponentsAvailable)
        XCTAssertEqual(today.unclassifiedTokens, 0)
        XCTAssertEqual(today.resolvedUnclassifiedTokens, 0)
        XCTAssertEqual(today.perClient["opencode"]?.unpricedTokens, 72_000)
        // The Hub leaves a tool bucket's zero unclassified count out (model
        // buckets keep it); the desktop then reads the tool as unclassified.
        XCTAssertNil(today.perClient["claude"]?.unclassifiedTokens)
        XCTAssertEqual(today.perClient["claude"]?.resolvedUnclassifiedTokens, today.perClient["claude"]?.tokens)
        XCTAssertEqual(today.perModel["big-pickle"]?.unclassifiedTokens, 0)
        XCTAssertEqual(today.perModel["big-pickle"]?.messages, 0)
        XCTAssertEqual(
            today.historyDay,
            HistoryDay(date: "2026-10-10", tokens: 60_657_600, costUsd: 129.63412, activeTimeMs: 50_640_000, unpricedTokens: 72_000)
        )

        // Older than the producers' 30-day component window: wholly unclassified.
        let first = try XCTUnwrap(history.daily.first)
        XCTAssertFalse(first.tokenComponentsAvailable)
        XCTAssertEqual(first.unclassifiedTokens, first.tokens)
        XCTAssertEqual(first.cacheReadTokens, 0)

        let october = try XCTUnwrap(history.monthly.last)
        XCTAssertEqual(october.month, "2026-10")
        XCTAssertEqual(october.unpricedTokens, 216_319)
        XCTAssertNil(october.perModel["claude-sonnet-4-5"]?.unclassifiedTokens)
        XCTAssertEqual(october.messages, 8801 + 313 + 115 + 1482 + 206)
    }

    func testHubSummaryDecodesAndMatchesTheStatCardsGolden() throws {
        let summary = try XCTUnwrap(HistoryFixtures.history().summary)
        XCTAssertEqual(summary, HistorySummary(
            totalTokens: 12_804_122_030,
            totalCost: 21076.843191,
            activeDays: 281,
            currentStreak: 20,
            longestStreak: 46,
            peakDayTokens: 69_349_766,
            favoriteModel: "claude-sonnet-4-5",
            messages: 284_548,
            activeTimeMs: 15_402_060_000,
            unpricedTokens: 2_161_051
        ))

        let golden = try HistoryFixtures.json("heatmap.json", subdirectory: "Fixtures/v2/golden")
        let aggregate = try XCTUnwrap(golden["aggregate"] as? [String: Any])
        XCTAssertEqual(number(aggregate["summaryActiveDays"]), Double(summary.activeDays))
        try assertStatCards(aggregate["statCards"], equal: summary)

        let device = try XCTUnwrap(golden["device"] as? [String: Any])
        let deviceID = try XCTUnwrap(device["deviceId"] as? String)
        let record = try XCTUnwrap(HistoryFixtures.records().first { $0.id == deviceID })
        try assertStatCards(device["statCards"], equal: XCTUnwrap(record.history?.summary))
    }

    /// `statsCards(summary)` rows: `{key, kind, value}` with the summary's field names.
    private func assertStatCards(_ raw: Any?, equal summary: HistorySummary) throws {
        let cards = try XCTUnwrap(raw as? [[String: Any]])
        XCTAssertEqual(cards.count, 8)
        for card in cards {
            let key = try XCTUnwrap(card["key"] as? String)
            switch key {
            case "totalTokens": XCTAssertEqual(number(card["value"]), Double(summary.totalTokens))
            case "totalCost": assertClose(summary.totalCost, number(card["value"]), key)
            case "activeDays": XCTAssertEqual(number(card["value"]), Double(summary.activeDays))
            case "currentStreak": XCTAssertEqual(number(card["value"]), Double(summary.currentStreak))
            case "activeTimeMs": assertClose(summary.activeTimeMs, number(card["value"]), key)
            case "peakDayTokens": XCTAssertEqual(number(card["value"]), Double(summary.peakDayTokens))
            case "favoriteModel": XCTAssertEqual(card["value"] as? String, summary.favoriteModel)
            case "messages": XCTAssertEqual(number(card["value"]), Double(summary.messages))
            default: XCTFail("unexpected stat card \(key)")
            }
        }
    }

    func testRecomputedSummaryEqualsTheHubSummary() throws {
        let history = try HistoryFixtures.history()
        let computed = HistoryMath.summary(daily: history.daily, monthly: history.monthly, todayKey: HistoryFixtures.todayKey)
        XCTAssertEqual(computed, history.summary)
        // Lifetime messages come from the months' tools, not the capped days.
        XCTAssertEqual(computed.messages, 284_548)
        XCTAssertEqual(history.daily.reduce(0) { $0 + $1.messages }, 268_484)
    }

    /// Expected values: `mergeHistories([record.history], {todayKey: '2026-10-10'}).summary`
    /// from `src/shared/history.js`, run with node on the same fixture.
    func testRecomputedDeviceSummariesMatchMergeHistories() throws {
        let records = try HistoryFixtures.records()
        let studio = try XCTUnwrap(records.first { $0.id == "studio-mac" }?.history)
        XCTAssertEqual(HistoryMath.summary(daily: studio.daily, monthly: studio.monthly, todayKey: "2026-10-10"), HistorySummary(
            totalTokens: 12_368_343_381,
            totalCost: 20469.787788,
            activeDays: 270,
            currentStreak: 4,
            longestStreak: 8,
            peakDayTokens: 63_610_141,
            favoriteModel: "claude-sonnet-4-5",
            messages: 274_854,
            activeTimeMs: 14_945_580_000,
            unpricedTokens: 72_000
        ))
        // The record's own summary covers its uncapped History (288 active days).
        XCTAssertEqual(studio.summary?.activeDays, 288)
        XCTAssertEqual(studio.summary?.totalCost, 20469.78778800001)

        let buildBox = try XCTUnwrap(records.first { $0.id == "build-box" }?.history)
        XCTAssertEqual(HistoryMath.summary(daily: buildBox.daily, monthly: buildBox.monthly, todayKey: "2026-10-10"), HistorySummary(
            totalTokens: 435_778_649,
            totalCost: 607.0554030000001,
            activeDays: 50,
            currentStreak: 2,
            longestStreak: 5,
            peakDayTokens: 12_216_991,
            favoriteModel: "claude-sonnet-4-5",
            messages: 9694,
            activeTimeMs: 456_480_000,
            unpricedTokens: 2_089_051
        ))
    }

    func testSummaryWindowAndEmptyInputs() {
        XCTAssertEqual(HistoryMath.summary(daily: [], monthly: [], todayKey: "2026-10-10"), .empty)
        let days = [
            HubHistoryDay(date: "2026-10-12", tokens: 900, activeTimeMs: 7, perModel: ["future": HistoryBucket(tokens: 900)]),
            HubHistoryDay(date: "2026-10-10", tokens: 10, activeTimeMs: 1),
            HubHistoryDay(date: "2026-10-09", tokens: 20, activeTimeMs: 2, perModel: ["m": HistoryBucket(tokens: 20)]),
            HubHistoryDay(date: "2026-10-01", tokens: 99, activeTimeMs: 4),
        ]
        // capDays 10 ending 2026-10-10 keeps 2026-10-01...2026-10-10; with no
        // months, active time comes from those days.
        let summary = HistoryMath.summary(daily: days, monthly: [], todayKey: "2026-10-10", capDays: 10)
        XCTAssertEqual(summary.activeDays, 3)
        XCTAssertEqual(summary.peakDayTokens, 99)
        XCTAssertEqual(summary.currentStreak, 2)
        XCTAssertEqual(summary.longestStreak, 2)
        XCTAssertEqual(summary.favoriteModel, "m")
        XCTAssertEqual(summary.activeTimeMs, 7)
        XCTAssertEqual(summary.totalTokens, 0, "lifetime totals come from months")
        XCTAssertEqual(HistoryMath.rollingWindow(days, todayKey: "2026-10-10", capDays: 9).map(\.date), ["2026-10-10", "2026-10-09"])
        XCTAssertEqual(HistoryMath.rollingWindow(days, todayKey: "2026-10-10", capDays: 0), [])
        XCTAssertEqual(HistoryMath.rollingWindow(days, todayKey: "nope"), [])
    }

    // MARK: Streaks and favourite model (desktop computeStreaks / favoriteModelOf)

    /// Expected values from `computeStreaks(days, todayKey)` in
    /// `src/shared/history.js`, run with node.
    func testStreaksMatchComputeStreaks() {
        func days(_ rows: [(String, Int)]) -> [HistoryDay] {
            rows.map { HistoryDay(date: $0.0, tokens: $0.1, costUsd: 0) }
        }
        let cases: [([(String, Int)], String, HistoryStreaks)] = [
            ([], "2026-10-10", HistoryStreaks(currentStreak: 0, longestStreak: 0)),
            ([("2026-10-10", 0), ("2026-10-09", 5)], "2026-10-10", HistoryStreaks(currentStreak: 0, longestStreak: 1)),
            ([("2024-02-28", 1), ("2024-02-29", 1), ("2024-03-01", 1), ("2024-03-03", 1)], "2024-03-01", HistoryStreaks(currentStreak: 3, longestStreak: 3)),
            ([("2025-12-31", 1), ("2026-01-01", 2), ("2026-01-02", 0), ("2026-01-03", 3)], "2026-01-03", HistoryStreaks(currentStreak: 1, longestStreak: 2)),
            ([("2026-03-08", 4), ("2026-03-07", 4), ("2026-03-06", 4), ("2026-03-01", 1), ("2026-03-02", 1), ("2026-03-03", 1), ("2026-03-04", 1)], "2026-03-08", HistoryStreaks(currentStreak: 3, longestStreak: 4)),
            ([("2026-10-11", 9), ("2026-10-10", 9)], "2026-10-10", HistoryStreaks(currentStreak: 1, longestStreak: 2)),
        ]
        for (rows, today, expected) in cases {
            XCTAssertEqual(HistoryMath.streaks(daily: days(rows), todayKey: today), expected, "\(rows) @ \(today)")
        }
    }

    func testStreaksOverTheHubDaily() throws {
        let history = try HistoryFixtures.history()
        XCTAssertEqual(HistoryMath.streaks(daily: history.daily, todayKey: "2026-10-10"), HistoryStreaks(currentStreak: 20, longestStreak: 46))
        XCTAssertEqual(HistoryMath.streaks(daily: history.daily, todayKey: "2026-10-11"), HistoryStreaks(currentStreak: 0, longestStreak: 46))
        XCTAssertEqual(HistoryMath.streaks(daily: history.daily, todayKey: "2026-10-09"), HistoryStreaks(currentStreak: 19, longestStreak: 46))
        XCTAssertEqual(
            HistoryMath.streaks(daily: history.daily.map(\.historyDay), todayKey: "2026-10-10"),
            HistoryMath.streaks(daily: history.daily, todayKey: "2026-10-10")
        )
    }

    /// Expected values from `mergeHistories(...).summary.favoriteModel`, run with node.
    func testFavoriteModelMatchesFavoriteModelOf() {
        func day(_ date: String, _ models: [String: Int]) -> HubHistoryDay {
            HubHistoryDay(date: date, perModel: models.mapValues { HistoryBucket(tokens: $0) })
        }
        XCTAssertEqual(HistoryMath.favoriteModel(daily: [day("2026-10-01", ["a": 5, "b": 7]), day("2026-10-02", ["a": 3])]), "a")
        XCTAssertEqual(HistoryMath.favoriteModel(daily: [day("2026-10-01", ["z": 0])]), "z")
        XCTAssertNil(HistoryMath.favoriteModel(daily: []))
        // A tie goes to the model seen first (desktop: first in wire order).
        XCTAssertEqual(HistoryMath.favoriteModel(daily: [day("2026-10-01", ["m2": 5]), day("2026-10-02", ["m1": 5])]), "m2")
        XCTAssertEqual(HistoryMath.favoriteModel(daily: [day("2026-10-01", ["b": 5, "a": 5])]), "a")
    }

    // MARK: Client alias folding

    func testDeviceHistoryFoldsAntigravityCLI() throws {
        let buildBox = try XCTUnwrap(HistoryFixtures.records().first { $0.id == "build-box" }?.history)
        let rawDays = try XCTUnwrap((HistoryFixtures.rawRecord("build-box")["history"] as? [String: Any])?["daily"] as? [[String: Any]])
        let rawDay = try XCTUnwrap(rawDays.first { $0["date"] as? String == "2026-10-07" })
        XCTAssertNotNil((rawDay["perClient"] as? [String: Any])?["antigravity-cli"], "the record keeps the raw Tokscale key")

        let day = try XCTUnwrap(buildBox.daily.first { $0.date == "2026-10-07" })
        XCTAssertNil(day.perClient["antigravity-cli"])
        XCTAssertEqual(day.perClient["antigravity"], HistoryBucket(tokens: 120_000, costUsd: 0.132, messages: 4, unclassifiedTokens: 120_000))
        XCTAssertFalse(buildBox.daily.contains { $0.perClient["antigravity-cli"] != nil })
        XCTAssertFalse(buildBox.monthly.contains { $0.perClient["antigravity-cli"] != nil })
    }

    func testFoldingSumsEveryMetricLikeFoldClientMap() throws {
        let json = """
        {"daily":[{"date":"2026-10-01","tokens":15,"cost":1.5,
          "perClient":{
            "antigravity":{"tokens":10,"cost":1,"messages":2,"cacheReadTokens":3},
            "antigravity-cli":{"tokens":5,"cost":0.5,"messages":1,"unclassifiedTokens":5,"unpricedTokens":2},
            "Antigravity-CLI":{"tokens":1},
            "micode":{"tokens":4}},
          "perModel":{"antigravity-cli":{"tokens":15}}}],
         "monthly":[{"month":"2026-10","tokens":15,"perClient":{"antigravity-cli":{"tokens":5,"messages":1},"antigravity":{"tokens":10,"messages":2}}}]}
        """
        let history = try HubHistory.decode(from: Data(json.utf8))
        let day = try XCTUnwrap(history.daily.first)
        XCTAssertEqual(day.perClient["antigravity"], HistoryBucket(
            tokens: 15, costUsd: 1.5, messages: 3, unpricedTokens: 2, cacheReadTokens: 3, unclassifiedTokens: 5
        ))
        // Only the exact alias the desktop renderers fold; model ids never fold.
        XCTAssertEqual(day.perClient["Antigravity-CLI"]?.tokens, 1)
        XCTAssertEqual(day.perClient["micode"]?.tokens, 4)
        XCTAssertEqual(day.perModel["antigravity-cli"]?.tokens, 15)
        XCTAssertEqual(history.monthly.first?.perClient, ["antigravity": HistoryBucket(tokens: 15, messages: 3)])
        XCTAssertEqual(history.monthly.first?.messages, 3)
    }

    // MARK: Lenient decoding

    func testLenientHistoryDecoding() throws {
        let json = """
        {"daily":[
          {"date":"2026-10-03","tokens":"40","cost":"0.5","unpricedTokens":99.6,"activeTimeMs":-5,"messages":null,"tokenComponentsAvailable":"true"},
          {"date":"2026-02-30","tokens":1},
          {"tokens":1},
          "garbage",
          {"date":"2026-10-01T08:00:00Z","tokens":-3,"cost":-1,"unpricedTokens":2,"unclassifiedTokens":-4,
           "perClient":{"claude":{"tokens":3,"unpricedTokens":0.4},"":{"tokens":1},"bad":"x"},"perModel":[1,2]}
        ],
         "monthly":[{"month":"2026-13","tokens":1},{"month":"2026-10-01","tokens":"7"},{"tokens":2}],
         "summary":{"totalTokens":"12","favoriteModel":"","unpricedTokens":0,"currentStreak":"x"}}
        """
        let history = try HubHistory.decode(from: Data(json.utf8))
        XCTAssertEqual(history.daily.map(\.date), ["2026-10-01", "2026-10-03"])

        let first = history.daily[0]
        XCTAssertEqual(first.tokens, 0)
        XCTAssertEqual(first.costUsd, 0)
        XCTAssertNil(first.unpricedTokens, "unpriced tokens never exceed the day's tokens")
        XCTAssertEqual(first.unclassifiedTokens, 0)
        XCTAssertFalse(first.tokenComponentsAvailable)
        XCTAssertEqual(first.resolvedUnclassifiedTokens, 0)
        XCTAssertEqual(first.perClient, ["claude": HistoryBucket(tokens: 3)])
        XCTAssertEqual(first.perModel, [:])

        let second = history.daily[1]
        XCTAssertEqual(second.tokens, 40)
        XCTAssertEqual(second.costUsd, 0.5)
        XCTAssertEqual(second.unpricedTokens, 40)
        XCTAssertEqual(second.activeTimeMs, 0)
        XCTAssertEqual(second.messages, 0)
        XCTAssertTrue(second.tokenComponentsAvailable)
        XCTAssertNil(second.unclassifiedTokens)
        XCTAssertEqual(second.resolvedUnclassifiedTokens, 0)
        XCTAssertNil(second.historyDay.activeTimeMs)

        XCTAssertEqual(history.monthly.map(\.month), ["2026-10"])
        XCTAssertEqual(history.monthly.first?.tokens, 7)
        XCTAssertEqual(history.summary, HistorySummary(totalTokens: 12))
    }

    func testNonObjectBodiesAndBrokenJSON() throws {
        XCTAssertEqual(try HubHistory.decode(from: Data("[]".utf8)), .empty)
        XCTAssertEqual(try HubHistory.decode(from: Data("null".utf8)), .empty)
        XCTAssertEqual(try HubHistory.decode(from: Data("{}".utf8)), .empty)
        XCTAssertNil(try HubHistory.decode(from: Data(#"{"summary":[]}"#.utf8)).summary)
        XCTAssertEqual(try HubHistory.decode(from: Data(#"{"summary":{}}"#.utf8)).summary, .empty)
        XCTAssertThrowsError(try HubHistory.decode(from: Data("<html>portal</html>".utf8))) { error in
            guard case HubClientError.decoding = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try DeviceHistoryRecord.decodeList(from: Data("<html>".utf8))) { error in
            guard case HubClientError.decoding = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try DeviceHistoryRecord.decodeList(from: Data("{}".utf8)), [])
        XCTAssertEqual(try DeviceHistoryRecord.decodeList(from: Data(#"{"devices":{}}"#.utf8)), [])
    }

    // MARK: GET /api/devices

    func testDeviceRecordsFromTheFixture() throws {
        let records = try HistoryFixtures.records()
        XCTAssertEqual(records.map(\.id), ["old-laptop", "build-box", "tokyo-mac", "studio-mac"])
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })

        // history: null (disabled) and a missing history both read as unavailable.
        let oldLaptop = try XCTUnwrap(byID["old-laptop"])
        XCTAssertFalse(oldLaptop.historyAvailable)
        XCTAssertNil(oldLaptop.history)
        let tokyo = try XCTUnwrap(byID["tokyo-mac"])
        XCTAssertFalse(tokyo.historyAvailable)
        XCTAssertNil(tokyo.history)

        let studio = try XCTUnwrap(byID["studio-mac"])
        XCTAssertTrue(studio.historyAvailable)
        XCTAssertEqual(studio.history?.daily.count, 270)
        XCTAssertEqual(studio.history?.monthly.count, 14)
        XCTAssertEqual(studio.history?.daily.last?.date, "2026-10-10")
        XCTAssertEqual(byID["build-box"]?.history?.daily.count, 50)

        // Day windows as capture.json describes them.
        let capture = try HistoryFixtures.json("capture.json")
        let devices = try XCTUnwrap(capture["devices"] as? [String: [String: Any]])
        for record in records {
            let expected = try XCTUnwrap(devices[record.id], record.id)
            XCTAssertEqual(record.todayWindowKey, expected["todayKey"] as? String, record.id)
            XCTAssertEqual(record.todayEndsAt, (expected["todayEndsAt"] as? String).flatMap(ISODate.parse), record.id)
            XCTAssertEqual(record.timeZone, expected["timeZone"] as? String, record.id)

            let raw = try HistoryFixtures.rawRecord(record.id)
            let rawToday = try XCTUnwrap((raw["periods"] as? [String: Any])?["today"] as? [String: Any])
            let today = try XCTUnwrap(record.today, record.id)
            XCTAssertEqual(Double(today.totalTokens), number(rawToday["totalTokens"]), record.id)
            assertClose(today.costUsd, number(rawToday["costUsd"]), record.id)
        }
        // The stale device's expired today is kept raw; expiry is the reader's call.
        XCTAssertEqual(oldLaptop.today?.totalTokens, 540_000)
        XCTAssertEqual(tokyo.todayWindowKey, "2026-10-11")
    }

    func testDeviceRecordVariants() throws {
        let json = """
        [
          {"id":"legacy","historyAvailable":true,"history":{"daily":[{"date":"2026-10-01","tokens":3}]},
           "today":{"totalTokens":3},"periodWindows":{"today":{"key":"2026-1-01","endsAt":"x"},"timeZone":"  "}},
          {"deviceId":"","id":"fallback","historyAvailable":"true","history":"odd"},
          {"deviceId":"flag-only","history":{"daily":[{"date":"2026-10-01","tokens":3}]}},
          {"hostname":"no-id"},
          7
        ]
        """
        let records = try DeviceHistoryRecord.decodeList(from: Data(json.utf8))
        XCTAssertEqual(records.map(\.id), ["legacy", "fallback", "flag-only"])

        XCTAssertTrue(records[0].historyAvailable)
        XCTAssertEqual(records[0].history?.daily.map(\.tokens), [3])
        XCTAssertEqual(records[0].today?.totalTokens, 3)
        XCTAssertNil(records[0].todayWindowKey)
        XCTAssertNil(records[0].todayEndsAt)
        XCTAssertNil(records[0].timeZone)

        // A History that is not an object is an empty History, as coerceHistory makes it.
        XCTAssertTrue(records[1].historyAvailable)
        XCTAssertEqual(records[1].history, .empty)
        XCTAssertNil(records[1].today)

        // History without the producer's explicit capability fails closed.
        XCTAssertFalse(records[2].historyAvailable)
        XCTAssertNil(records[2].history)
    }

    // MARK: HistoryDay (preview and snapshot rows)

    func testHistoryDayEncodingIsUnchangedWithoutTheNewFields() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plain = HistoryDay(date: "2026-10-01", tokens: 5, costUsd: 1.5)
        XCTAssertEqual(String(decoding: try encoder.encode(plain), as: UTF8.self), #"{"cost":1.5,"date":"2026-10-01","tokens":5}"#)

        let full = HistoryDay(date: "2026-10-01", tokens: 5, costUsd: 1.5, activeTimeMs: 60000, unpricedTokens: 2)
        let encoded = try encoder.encode(full)
        XCTAssertEqual(
            String(decoding: encoded, as: UTF8.self),
            #"{"activeTimeMs":60000,"cost":1.5,"date":"2026-10-01","tokens":5,"unpricedTokens":2}"#
        )
        XCTAssertEqual(try JSONDecoder().decode(HistoryDay.self, from: encoded), full)
        XCTAssertEqual(try JSONDecoder().decode(HistoryDay.self, from: encoder.encode(plain)), plain)
    }

    func testHistoryDayReadsTheNewPreviewFields() throws {
        let decoded = try JSONDecoder().decode([HistoryDay].self, from: Data("""
        [{"date":"2026-10-01","tokens":5,"cost":1,"activeTimeMs":0},
         {"date":"2026-10-02","tokens":5,"cost":0,"activeTimeMs":"1200","unpricedTokens":9}]
        """.utf8))
        XCTAssertEqual(decoded, [
            HistoryDay(date: "2026-10-01", tokens: 5, costUsd: 1),
            HistoryDay(date: "2026-10-02", tokens: 5, costUsd: 0, activeTimeMs: 1200, unpricedTokens: 5),
        ])

        let stats = try HubStats.decode(from: HistoryFixtures.data("stats.json"))
        XCTAssertEqual(
            stats.history.last,
            HistoryDay(date: "2026-10-10", tokens: 60_657_600, costUsd: 129.63412, activeTimeMs: 50_640_000, unpricedTokens: 72_000)
        )
        // The snapshot's trend keeps its compact rows.
        let trend = stats.dailyTrend(days: 14, endingAt: Fixture.date("2026-10-10T12:00:00Z"), calendar: Fixture.utc)
        XCTAssertEqual(trend.count, 14)
        XCTAssertTrue(trend.allSatisfy { $0.activeTimeMs == nil && $0.unpricedTokens == nil })
    }

    func testDayKeyArithmetic() {
        XCTAssertEqual(DayKey.adding(days: 1, to: "2024-02-28"), "2024-02-29")
        XCTAssertEqual(DayKey.adding(days: 1, to: "2024-02-29"), "2024-03-01")
        XCTAssertEqual(DayKey.adding(days: -1, to: "2026-01-01"), "2025-12-31")
        XCTAssertEqual(DayKey.adding(days: -369, to: "2026-10-10"), "2025-10-06")
        XCTAssertEqual(DayKey.adding(days: 0, to: "2026-03-08"), "2026-03-08")
        XCTAssertNil(DayKey.adding(days: 1, to: "2026-02-30"))
        XCTAssertNil(DayKey.adding(days: 1, to: ""))
    }

    // MARK: HubClient

    func testClientFetchesHistoryAndDeviceRecords() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = HubClient(
            connection: try HubConnection(userInput: "http://hub.test:17321", secret: "s3cret"),
            session: URLSession(configuration: configuration)
        )
        StubURLProtocol.stub(path: "/api/history", status: 200, body: try HistoryFixtures.data("history.json"))
        StubURLProtocol.stub(path: "/api/devices", status: 200, body: try HistoryFixtures.data("devices.json"))

        let history = try await client.history()
        XCTAssertEqual(history, try HistoryFixtures.history())
        let raw = try await client.historyData()
        XCTAssertEqual(raw, try HistoryFixtures.data("history.json"))
        let records = try await client.deviceHistoryRecords()
        XCTAssertEqual(records.map(\.id), ["old-laptop", "build-box", "tokyo-mac", "studio-mac"])

        let requests = StubURLProtocol.recordedRequests
        XCTAssertEqual(requests.compactMap(\.url?.path), ["/api/history", "/api/history", "/api/devices"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer s3cret" })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Accept") == "application/json" })

        StubURLProtocol.stub(path: "/api/history", status: 404, body: Data(#"{"error":"not found"}"#.utf8))
        do {
            _ = try await client.history()
            XCTFail("expected a 404")
        } catch {
            XCTAssertEqual(error as? HubClientError, .http(status: 404))
        }
    }
}

import XCTest
@testable import TokenMonitorKit

/// Golden tests for `ExportSerializer` against the desktop's `exportFileSet`
/// output (`Fixtures/v2/golden/export`, produced by `src/shared/exporter.js`),
/// plus a synthetic case run through the same JS for the edge behaviour.
///
/// The goldens keep the Hub's wire order. The iOS export sorts instead, so CSVs are
/// compared header-exact and by row multiset (and checked for the documented
/// order separately), and the JSON structurally, by size, and by line multiset
/// (sorting keys moves lines without changing them).
final class ExportTests: XCTestCase {
    private static let generatedAt = Date(timeIntervalSince1970: 1_791_649_800)  // capture.json "now"
    private static let app = ExportApp(name: "token-monitor", version: "fixture")

    // MARK: Fixtures

    private func fixture(_ name: String, directory: String) throws -> Data {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: parts[0], withExtension: parts[1], subdirectory: directory),
            "missing fixture \(directory)/\(name)"
        )
        return try Data(contentsOf: url)
    }

    private func golden(_ name: String) throws -> Data {
        try fixture(name, directory: "Fixtures/v2/golden/export")
    }

    private func json(_ name: String, directory: String = "Fixtures/v2") throws -> ExportJSONValue {
        try XCTUnwrap(ExportJSONValue.parse(fixture(name, directory: directory)), "\(name) is not JSON")
    }

    /// The export input behind the goldens: the Hub stats `periods` and the
    /// history trimmed to its last 7 daily and 2 monthly rows (manifest.json).
    private func goldenInput() throws -> (periods: ExportJSONValue, history: ExportJSONValue) {
        let stats = try json("stats.json")
        let history = try json("history.json")
        let periods = try XCTUnwrap(stats["periods"])
        let daily = try XCTUnwrap(history["daily"]?.arrayValue)
        let monthly = try XCTUnwrap(history["monthly"]?.arrayValue)
        return (periods, .object(["daily": .array(Array(daily.suffix(7))), "monthly": .array(Array(monthly.suffix(2)))]))
    }

    private func goldenFileSet() throws -> [ExportFile] {
        let input = try goldenInput()
        return ExportSerializer.fileSet(periods: input.periods, history: input.history, generatedAt: Self.generatedAt, app: Self.app)
    }

    private func file(_ name: String, in files: [ExportFile]) throws -> ExportFile {
        try XCTUnwrap(files.first { $0.name == name }, "\(name) was not generated")
    }

    // MARK: Goldens

    func testFileSetNamesAndOrderMatchTheManifest() throws {
        let manifest = try json("manifest.json", directory: "Fixtures/v2/golden/export")
        let expected = try XCTUnwrap(manifest["fileNames"]?.arrayValue).compactMap { value -> String? in
            if case .string(let s) = value { return s } else { return nil }
        }
        XCTAssertEqual(ExportSerializer.fileNames, expected)
        XCTAssertEqual(try goldenFileSet().map(\.name), expected)
    }

    func testSnapshotCSVMatchesTheGolden() throws {
        let output = try file("token-monitor-snapshot.csv", in: goldenFileSet())
        try assertCSV(output, golden: "token-monitor-snapshot.csv", columns: 5)

        // The sorted order: today, month, allTime; tools before models; names ascending.
        let rows = dataRows(output.data).map { parseCSVLine($0) }
        let periodRank = ["today": 0, "month": 1, "allTime": 2]
        let ordered = rows.map { (period: periodRank[$0[0]] ?? 9, dimension: $0[1] == "tool" ? 0 : 1, name: $0[2]) }
        let expectedOrder = ordered.enumerated().sorted { lhs, rhs in
            if lhs.element.period != rhs.element.period { return lhs.element.period < rhs.element.period }
            if lhs.element.dimension != rhs.element.dimension { return lhs.element.dimension < rhs.element.dimension }
            if lhs.element.name != rhs.element.name { return lhs.element.name.utf8.lexicographicallyPrecedes(rhs.element.name.utf8) }
            return lhs.offset < rhs.offset
        }.map(\.offset)
        XCTAssertEqual(expectedOrder, Array(ordered.indices), "snapshot rows: period, tool before model, name")
        XCTAssertTrue(ordered.contains { $0.dimension == 1 } && ordered.contains { $0.period == 2 })
    }

    func testDailyCSVMatchesTheGolden() throws {
        let output = try file("token-monitor-daily.csv", in: goldenFileSet())
        try assertCSV(output, golden: "token-monitor-daily.csv", columns: 4)
        let rows = dataRows(output.data).map { parseCSVLine($0) }
        let keys = rows.map { $0[0] + "\u{0}" + $0[1] }
        XCTAssertEqual(keys, keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }, "daily rows: date, then tool")
    }

    func testDailyModelsCSVMatchesTheGolden() throws {
        let output = try file("token-monitor-daily-models.csv", in: goldenFileSet())
        try assertCSV(output, golden: "token-monitor-daily-models.csv", columns: 9)
        let rows = dataRows(output.data).map { parseCSVLine($0) }
        let keys = rows.map { $0[0] + "\u{0}" + $0[1] }
        XCTAssertEqual(keys, keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }, "daily-models rows: date, then model")
    }

    func testJSONIsStructurallyEqualToTheGolden() throws {
        let output = try file("token-monitor-export.json", in: goldenFileSet())
        let expected = try golden("token-monitor-export.json")

        XCTAssertEqual(ExportJSONValue.parse(output.data), ExportJSONValue.parse(expected))
        XCTAssertNotEqual(output.data.prefix(3), Data([0xEF, 0xBB, 0xBF]), "the JSON has no byte-order mark")
        let text = output.contents
        XCTAssertTrue(text.hasSuffix("}\n") && !text.hasSuffix("\n\n"))
        XCTAssertFalse(text.contains("\r"))

        // Same bytes, same lines: sorting keys only moves lines around. Compared
        // without trailing commas, which follow the position, not the content.
        XCTAssertEqual(output.data.count, expected.count)
        XCTAssertEqual(
            text.split(separator: "\n", omittingEmptySubsequences: false).map(stripComma).sorted(),
            String(decoding: expected, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).map(stripComma).sorted()
        )

        // The authored top level keeps the desktop's order.
        let topLevel = text.split(separator: "\n").filter { $0.hasPrefix("  \"") }.compactMap { $0.split(separator: "\"").dropFirst().first.map(String.init) }
        XCTAssertEqual(topLevel, ["generatedAt", "app", "snapshot", "daily", "monthly"])
        XCTAssertTrue(text.hasPrefix("{\n  \"generatedAt\": \"2026-10-10T16:30:00.000Z\",\n  \"app\": {\n    \"name\": \"token-monitor\",\n    \"version\": \"fixture\"\n  },\n"))
    }

    func testFilesMatchTheManifestSizes() throws {
        let manifest = try json("manifest.json", directory: "Fixtures/v2/golden/export")
        let files = try goldenFileSet()
        for entry in try XCTUnwrap(manifest["files"]?.arrayValue) {
            guard case .string(let name)? = entry["name"], case .number(let bytes)? = entry["bytes"] else {
                return XCTFail("malformed manifest entry")
            }
            XCTAssertEqual(Double(try file(name, in: files).data.count), bytes, name)
        }
    }

    func testSessionTextNeverReachesTheExport() throws {
        let stats = try json("stats.json")
        let input = try goldenInput()
        let output = try file("token-monitor-export.json", in: goldenFileSet())

        // The fixture really carries titles for the strip to remove.
        let titles = ["Refactor the collector watch loop", "Review limits presentation", "Ship the iOS fixtures"]
        let source = String(decoding: try fixture("stats.json", directory: "Fixtures/v2"), as: UTF8.self)
        for title in titles { XCTAssertTrue(source.contains(title), title) }
        XCTAssertNotNil(stats["periods"]?["today"]?["sessions"]?["claude:7f3c2a90-1b2c-4d5e-8f90-a1b2c3d4e5f6"]?["title"])

        for title in titles { XCTAssertFalse(output.contents.contains(title), title) }
        let exported = try XCTUnwrap(ExportJSONValue.parse(output.data))
        for period in ExportSerializer.periodNames {
            let sessions = try XCTUnwrap(exported["snapshot"]?[period]?["sessions"]?.objectValue)
            let original = try XCTUnwrap(input.periods[period]?["sessions"]?.objectValue)
            XCTAssertEqual(Set(sessions.keys), Set(original.keys))
            for (key, session) in sessions {
                let fields = try XCTUnwrap(session.objectValue)
                XCTAssertTrue(ExportSerializer.sessionTextKeys.isDisjoint(with: fields.keys), "\(period) \(key)")
                // Everything that is not session text survives untouched.
                var expected = try XCTUnwrap(original[key]?.objectValue)
                for textKey in ExportSerializer.sessionTextKeys { expected.removeValue(forKey: textKey) }
                XCTAssertEqual(fields, expected, "\(period) \(key)")
            }
        }
        XCTAssertEqual(exported["snapshot"]?["today"]?["sessions"]?["hermes:hermes-20261010-0815"]?["projectLabel"], .string("infra"))
    }

    func testCSVEscapeCasesFromTheManifest() throws {
        let manifest = try json("manifest.json", directory: "Fixtures/v2/golden/export")
        let cases = try XCTUnwrap(manifest["csvEscape"]?.arrayValue)
        XCTAssertFalse(cases.isEmpty)
        for entry in cases {
            guard case .string(let escaped)? = entry["escaped"], let value = entry["value"] else { return XCTFail("malformed case") }
            switch value {
            case .null: XCTAssertEqual(ExportSerializer.csvEscape(nil as String?), escaped)
            case .string(let s): XCTAssertEqual(ExportSerializer.csvEscape(s), escaped, s)
            case .number(let n): XCTAssertEqual(ExportSerializer.csvEscape(n), escaped)
            default: XCTFail("unexpected csvEscape value \(value)")
            }
        }
        // "\r\n" is one Character in Swift; it still needs quotes.
        XCTAssertEqual(ExportSerializer.csvEscape("a\r\nb"), "\"a\r\nb\"")
    }

    // MARK: Hub bytes in

    func testFileSetFromRawHubBodies() throws {
        let stats = try fixture("stats.json", directory: "Fixtures/v2")
        let history = try fixture("history.json", directory: "Fixtures/v2")
        let files = try ExportSerializer.fileSet(statsData: stats, historyData: history, generatedAt: Self.generatedAt, app: Self.app)
        XCTAssertEqual(files.map(\.name), ExportSerializer.fileNames)

        // Equal to the value-level API on the same input.
        let periods = try json("stats.json")["periods"]
        XCTAssertEqual(files, ExportSerializer.fileSet(periods: periods, history: try json("history.json"), generatedAt: Self.generatedAt, app: Self.app))

        // The full (untrimmed) history: every perClient / perModel entry is a row.
        let days = try XCTUnwrap(json("history.json")["daily"]?.arrayValue)
        XCTAssertEqual(days.count, 281)
        let toolRows = days.reduce(0) { $0 + ($1["perClient"]?.objectValue?.count ?? 0) }
        let modelRows = days.reduce(0) { $0 + ($1["perModel"]?.objectValue?.count ?? 0) }
        XCTAssertGreaterThan(toolRows, 0)
        XCTAssertEqual(dataRows(try file("token-monitor-daily.csv", in: files).data).count, toolRows)
        XCTAssertEqual(dataRows(try file("token-monitor-daily-models.csv", in: files).data).count, modelRows)
        let exported = try XCTUnwrap(ExportJSONValue.parse(file("token-monitor-export.json", in: files).data))
        XCTAssertEqual(exported["daily"]?.arrayValue, days)
        XCTAssertEqual(exported["monthly"]?.arrayValue?.count, 14)
    }

    func testMissingHistoryExportsTheSnapshotOnly() throws {
        let stats = try fixture("stats.json", directory: "Fixtures/v2")
        for history in [nil, Data("null".utf8), Data(#"{"daily":[],"monthly":[]}"#.utf8), Data("{}".utf8)] {
            let files = try ExportSerializer.fileSet(statsData: stats, historyData: history, generatedAt: Self.generatedAt)
            XCTAssertEqual(files.map(\.name), ["token-monitor-export.json", "token-monitor-snapshot.csv"])
            let exported = try XCTUnwrap(ExportJSONValue.parse(files[0].data))
            XCTAssertEqual(exported["daily"], .array([]))
            XCTAssertEqual(exported["monthly"], .array([]))
            XCTAssertEqual(exported["app"], .object(["name": .string("token-monitor")]))
        }
    }

    func testDailyFilesAreWrittenOnlyWhenTheyHaveRows() throws {
        let periods = ExportJSONValue.parse(Data(#"{"today":{"clients":{"codex":1}}}"#.utf8))
        let toolsOnly = ExportJSONValue.parse(Data(#"{"daily":[{"date":"2026-07-02","perClient":{"codex":{"tokens":5,"cost":1}}}]}"#.utf8))
        let modelsOnly = ExportJSONValue.parse(Data(#"{"daily":[{"date":"2026-07-02","perModel":{"gpt-5":{"tokens":5}}}]}"#.utf8))
        XCTAssertEqual(
            ExportSerializer.fileSet(periods: periods, history: toolsOnly, generatedAt: Self.generatedAt).map(\.name),
            ["token-monitor-export.json", "token-monitor-snapshot.csv", "token-monitor-daily.csv"]
        )
        XCTAssertEqual(
            ExportSerializer.fileSet(periods: periods, history: modelsOnly, generatedAt: Self.generatedAt).map(\.name),
            ["token-monitor-export.json", "token-monitor-snapshot.csv", "token-monitor-daily-models.csv"]
        )
        // Missing periods are an empty snapshot, as on the desktop.
        let empty = ExportSerializer.fileSet(periods: nil, history: nil, generatedAt: Self.generatedAt)
        XCTAssertEqual(empty[1].contents, "\u{FEFF}period,dimension,name,tokens,cost_usd\r\n")
    }

    func testMalformedBodiesThrow() throws {
        let stats = try fixture("stats.json", directory: "Fixtures/v2")
        let at = Self.generatedAt
        for body in ["", "not json", "[]", "{}", #"{"periods":[]}"#, #"{"periods":null}"#, #"{"error":"unauthorized"}"#] {
            XCTAssertThrowsError(try ExportSerializer.fileSet(statsData: Data(body.utf8), historyData: nil, generatedAt: at), body) {
                XCTAssertEqual($0 as? ExportError, .invalidStats)
            }
        }
        for body in ["", "oops", "[]", "7", "\"x\"", "{\"daily\":"] {
            XCTAssertThrowsError(try ExportSerializer.fileSet(statsData: stats, historyData: Data(body.utf8), generatedAt: at), body) {
                XCTAssertEqual($0 as? ExportError, .invalidHistory)
            }
        }
    }

    // MARK: Synthetic case against the desktop JS

    func testSyntheticInputMatchesTheDesktopSerialization() throws {
        let periods = try XCTUnwrap(ExportJSONValue.parse(Data(syntheticPeriodsJSON.utf8)))
        let history = try XCTUnwrap(ExportJSONValue.parse(Data(syntheticHistoryJSON.utf8)))
        let files = ExportSerializer.fileSet(
            periods: periods,
            history: history,
            generatedAt: Date(timeIntervalSince1970: 1_791_649_800),
            app: ExportApp(name: "token-monitor", version: "1.2.3")
        )
        XCTAssertEqual(files.map(\.name), ExportSerializer.fileNames)
        XCTAssertEqual(files[0].contents, syntheticExpectedJSON + "\n")
        XCTAssertEqual(files[1].contents, syntheticExpectedSnapshotCSV)
        XCTAssertEqual(files[2].contents, syntheticExpectedDailyCSV)
        XCTAssertEqual(files[3].contents, syntheticExpectedDailyModelsCSV)
        XCTAssertEqual(Array(files[1].data.prefix(3)), [0xEF, 0xBB, 0xBF])
    }

    func testDailyModelComponentsFollowTheDesktopRules() {
        func components(_ day: String, _ value: String) -> ExportSerializer.ModelComponents {
            let dayValue = ExportJSONValue.parse(Data(day.utf8))
            let object = ExportJSONValue.parse(Data(value.utf8))?.objectValue ?? [:]
            return ExportSerializer.dailyModelComponents(day: dayValue, value: object)
        }
        typealias C = ExportSerializer.ModelComponents
        // Explicit unclassified, capped at the remainder.
        XCTAssertEqual(
            components("{}", #"{"tokens":100,"outputTokens":10,"cacheReadTokens":20,"cacheWriteTokens":5,"unclassifiedTokens":30}"#),
            C(input: 35, output: 10, cacheRead: 20, cacheWrite: 5, unclassified: 30, total: 100)
        )
        XCTAssertEqual(
            components("{}", #"{"tokens":100,"outputTokens":10,"unclassifiedTokens":500}"#),
            C(input: 0, output: 10, cacheRead: 0, cacheWrite: 0, unclassified: 90, total: 100)
        )
        // No explicit value: classified only when the day says components are available.
        let value = #"{"tokens":100,"outputTokens":10,"cacheReadTokens":20,"cacheWriteTokens":5}"#
        XCTAssertEqual(components(#"{"tokenComponentsAvailable":true}"#, value), C(input: 65, output: 10, cacheRead: 20, cacheWrite: 5, unclassified: 0, total: 100))
        for day in ["{}", #"{"tokenComponentsAvailable":false}"#, #"{"tokenComponentsAvailable":"true"}"#, #"{"tokenComponentsAvailable":1}"#, "null"] {
            XCTAssertEqual(components(day, value), C(input: 0, output: 10, cacheRead: 20, cacheWrite: 5, unclassified: 65, total: 100), day)
        }
        // Known parts above the total: the total is kept, all unclassified.
        XCTAssertEqual(
            components(#"{"tokenComponentsAvailable":true}"#, #"{"tokens":50,"outputTokens":40,"cacheReadTokens":20}"#),
            C(input: 0, output: 0, cacheRead: 0, cacheWrite: 0, unclassified: 50, total: 50)
        )
        // Negative and non-numeric values clamp to zero.
        XCTAssertEqual(components("{}", #"{"tokens":-5,"outputTokens":"x"}"#), C(input: 0, output: 0, cacheRead: 0, cacheWrite: 0, unclassified: 0, total: 0))
    }

    func testNumberCoercionMatchesJavaScriptNumber() {
        let cases: [(String, Double)] = [
            ("12", 12), (" 7 ", 7), ("0x10", 16), ("1e3", 1000), ("abc", 0), ("Infinity", 0), ("", 0), ("12px", 0),
            ("-5", -5), (".5", 0.5), ("5.", 5), ("+3", 3), ("0b101", 5), ("-0x10", 0), ("0o17", 15), ("1_000", 0),
            ("\u{00A0}7\u{00A0}", 7), ("\u{FEFF}8", 8), ("1e", 0), ("e5", 0), ("+.5e1", 5), ("--1", 0), (".", 0), ("0x", 0), ("1 2", 0)
        ]
        for (text, expected) in cases {
            XCTAssertEqual(ExportSerializer.num(.string(text)), expected, "Number(\(text.debugDescription))")
        }
        XCTAssertEqual(ExportSerializer.num(.bool(true)), 1)
        XCTAssertEqual(ExportSerializer.num(.null), 0)
        XCTAssertEqual(ExportSerializer.num(.array([.number(5)])), 0)
        XCTAssertEqual(ExportSerializer.num(.number(.infinity)), 0)
        XCTAssertEqual(ExportSerializer.num(nil), 0)
    }

    // MARK: Session text

    func testStripSessionTextRemovesOnlyTheTextKeys() throws {
        let period = try XCTUnwrap(ExportJSONValue.parse(Data(#"""
        {"totalTokens":5,"sessions":{
          "a":{"sessionId":"a","sessionKind":"background-review","projectLabel":"p","totalTokens":3,"models":{"m":1},
               "title":"t","sessionTitle":"t","session_title":"t","name":"n","preview":"p","firstUserMessage":"f",
               "first_user_message":"f","customTitle":"c","custom_title":"c","aiTitle":"a","ai_title":"a"},
          "b":7,"c":null,"d":[{"title":"kept in arrays"}]}}
        """#.utf8)))
        let stripped = ExportSerializer.stripSessionText(from: period)
        XCTAssertEqual(stripped["totalTokens"], .number(5))
        XCTAssertEqual(stripped["sessions"]?["a"]?.objectValue?.keys.sorted(), ["models", "projectLabel", "sessionId", "sessionKind", "totalTokens"])
        XCTAssertEqual(stripped["sessions"]?["b"], .number(7))
        XCTAssertEqual(stripped["sessions"]?["c"], .null)
        XCTAssertEqual(stripped["sessions"]?["d"], period["sessions"]?["d"], "only the session's own fields are stripped")

        // Periods without a sessions object come back as they are.
        for value in ["{}", #"{"sessions":null}"#, #"{"sessions":"x"}"#, #"{"sessions":0}"#, "[1]", "5"] {
            let parsed = ExportJSONValue.parse(Data(value.utf8))!
            XCTAssertEqual(ExportSerializer.stripSessionText(from: parsed), parsed, value)
        }
        // `Object.entries` on an array yields an index-keyed object.
        let array = ExportJSONValue.parse(Data(#"{"sessions":[{"title":"x","id":1},9]}"#.utf8))!
        XCTAssertEqual(ExportSerializer.stripSessionText(from: array)["sessions"], ExportJSONValue.parse(Data(#"{"0":{"id":1},"1":9}"#.utf8)))
    }

    // MARK: CSV

    func testToCSVOptionsAndMissingCells() {
        let rows: [ExportRow] = [["a": "1", "b": "x,y"], ["a": "2"]]
        XCTAssertEqual(ExportSerializer.toCSV(rows: rows, columns: ["a", "b"], bom: false), "a,b\r\n1,\"x,y\"\r\n2,\r\n")
        XCTAssertEqual(ExportSerializer.toCSV(rows: rows, columns: ["a", "b"]), "\u{FEFF}a,b\r\n1,\"x,y\"\r\n2,\r\n")
        XCTAssertEqual(ExportSerializer.toCSV(rows: [], columns: ["a", "b,c"]), "\u{FEFF}a,\"b,c\"\r\n")
    }

    func testCSVColumnsMatchTheDesktop() {
        XCTAssertEqual(ExportSerializer.snapshotColumns, ["period", "dimension", "name", "tokens", "cost_usd"])
        XCTAssertEqual(ExportSerializer.dailyColumns, ["date", "tool", "tokens", "cost_usd"])
        XCTAssertEqual(
            ExportSerializer.dailyModelColumns,
            ["date", "model", "input_tokens", "output_tokens", "cache_read_tokens", "cache_write_tokens", "unclassified_tokens", "total_tokens", "cost_usd"]
        )
    }

    func testRowOrderIsStableForEqualKeys() throws {
        // Two entries of one date keep their input order for equal tools.
        let history = ExportJSONValue.parse(Data(#"{"daily":[{"date":"2026-01-02","perClient":{"b":{"tokens":1},"a":{"tokens":2}}},{"date":"2026-01-01","perClient":{"a":{"tokens":3}}},{"date":"2026-01-02","perClient":{"a":{"tokens":4}}}]}"#.utf8))
        let rows = ExportSerializer.dailyRows(history: history)
        XCTAssertEqual(rows.map { "\($0["date"]!) \($0["tool"]!) \($0["tokens"]!)" }, ["2026-01-01 a 3", "2026-01-02 a 2", "2026-01-02 a 4", "2026-01-02 b 1"])
    }

    // MARK: generatedAt

    func testGeneratedAtIsAnISOStringWithMilliseconds() throws {
        let cases: [(Double, String)] = [
            (0, "1970-01-01T00:00:00.000Z"),
            (1_791_649_800_000, "2026-10-10T16:30:00.000Z"),
            (1_791_649_800_123, "2026-10-10T16:30:00.123Z"),
            (-1, "1969-12-31T23:59:59.999Z"),
            (951_782_400_000, "2000-02-29T00:00:00.000Z"),
            (253_402_300_799_999, "9999-12-31T23:59:59.999Z"),
            (-62_167_219_200_000, "0000-01-01T00:00:00.000Z"),
            (-62_198_755_200_000, "-000001-01-01T00:00:00.000Z"),
            (253_402_300_800_000, "+010000-01-01T00:00:00.000Z"),
            (1_000_000_000_999, "2001-09-09T01:46:40.999Z"),
            (-86_400_001, "1969-12-30T23:59:59.999Z")
        ]
        for (milliseconds, expected) in cases {
            let output = ExportSerializer.exportJSON(periods: nil, history: nil, generatedAt: Date(timeIntervalSince1970: milliseconds / 1000))
            XCTAssertTrue(output.hasPrefix("{\n  \"generatedAt\": \"\(expected)\",\n"), "\(milliseconds): \(output.prefix(60))")
        }
    }

    func testJSONLiteralsAreWrittenAsJavaScriptWritesThem() {
        let periods = ExportJSONValue.parse(Data(#"{"today":{"a":[],"b":{},"c":-0,"d":1E2,"e":0.1,"f":"\u00e9\u2028\u007f\ud83d\ude00\/","g":true,"h":null,"i":[1,[2]]}}"#.utf8))
        let output = ExportSerializer.exportJSON(periods: periods, history: nil, generatedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(output, """
        {
          "generatedAt": "1970-01-01T00:00:00.000Z",
          "app": {
            "name": "token-monitor"
          },
          "snapshot": {
            "today": {
              "a": [],
              "b": {},
              "c": 0,
              "d": 100,
              "e": 0.1,
              "f": "é\u{2028}\u{7F}😀/",
              "g": true,
              "h": null,
              "i": [
                1,
                [
                  2
                ]
              ]
            },
            "month": {},
            "allTime": {}
          },
          "daily": [],
          "monthly": []
        }

        """)
    }

    // MARK: JSON parser

    func testParserReadsStandardJSON() throws {
        let value = try XCTUnwrap(ExportJSONValue.parse(Data(#"""
         \#t{"s":"a\"b\\c\/d\b\f\n\r\t\u0041\u00e9\ud83d\ude00","n":[0,-0,1.5e2,-12,1E-2],"t":true,"f":false,"z":null,"o":{"k":[]},"dup":1,"dup":2}
        """#.utf8)))
        XCTAssertEqual(value["s"], .string("a\"b\\c/d\u{08}\u{0C}\n\r\tAé😀"))
        XCTAssertEqual(value["n"], .array([.number(0), .number(-0.0), .number(150), .number(-12), .number(0.01)]))
        XCTAssertEqual(value["t"], .bool(true))
        XCTAssertEqual(value["f"], .bool(false))
        XCTAssertEqual(value["z"], .null)
        XCTAssertEqual(value["o"], .object(["k": .array([])]))
        XCTAssertEqual(value["dup"], .number(2), "the last duplicate key wins, as in JSON.parse")
        XCTAssertNotEqual(value["t"], .number(1), "booleans are not numbers")
        XCTAssertEqual(ExportJSONValue.parse(Data([0xEF, 0xBB, 0xBF] + Array("[1]".utf8))), .array([.number(1)]))
        // Lone surrogates become U+FFFD instead of corrupting the string.
        XCTAssertEqual(ExportJSONValue.parse(Data(#""\ud83dx\ude00""#.utf8)), .string("\u{FFFD}x\u{FFFD}"))
    }

    func testParserRejectsMalformedJSON() {
        let bad = [
            "", " ", "{", "[1,]", "{\"a\":1,}", "{\"a\" 1}", "{a:1}", "[01]", "[1.]", "[.5]", "[1e]", "[+1]", "[--1]", "tru", "nulll",
            "\"abc", "\"\\x\"", "\"\\u12\"", "\"\\ud83d\\u0041\"x", "\"a\nb\"", "[1] 2", "{\"a\":1}}", "'a'", "[NaN]", "[Infinity]"
        ]
        for text in bad {
            // A lone-surrogate string followed by junk must still fail as a whole document.
            XCTAssertNil(ExportJSONValue.parse(Data(text.utf8)), text.debugDescription)
        }
        XCTAssertNil(ExportJSONValue.parse(Data(String(repeating: "[", count: 300).utf8)), "depth limit")
        XCTAssertNotNil(ExportJSONValue.parse(Data((String(repeating: "[", count: 200) + String(repeating: "]", count: 200)).utf8)))
    }

    // MARK: Helpers

    /// BOM, CRLF-only line endings, the header, and the golden's rows as a
    /// multiset; the byte count matches too (same rows, any order).
    private func assertCSV(_ output: ExportFile, golden name: String, columns: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let expected = try golden(name)
        XCTAssertEqual(Array(output.data.prefix(3)), [0xEF, 0xBB, 0xBF], "BOM", file: file, line: line)
        XCTAssertEqual(Array(expected.prefix(3)), [0xEF, 0xBB, 0xBF], file: file, line: line)

        let bytes = [UInt8](output.data)
        var bareLineFeeds = 0
        for (index, byte) in bytes.enumerated() where byte == 0x0A && (index == 0 || bytes[index - 1] != 0x0D) { bareLineFeeds += 1 }
        XCTAssertEqual(bareLineFeeds, 0, "every line ends in CRLF", file: file, line: line)
        XCTAssertEqual(Array(bytes.suffix(2)), [0x0D, 0x0A], file: file, line: line)

        let actualLines = recordLines(output.data)
        let expectedLines = recordLines(expected)
        XCTAssertEqual(actualLines.first, expectedLines.first, "header", file: file, line: line)
        XCTAssertEqual(actualLines.dropFirst().sorted(), expectedLines.dropFirst().sorted(), "row multiset", file: file, line: line)
        XCTAssertEqual(output.data.count, expected.count, "size", file: file, line: line)
        XCTAssertEqual(parseCSVLine(actualLines[0]).count, columns, file: file, line: line)
    }

    /// CSV records, split on the CRLF that ends a record (a quoted cell may
    /// hold a line break of its own); the BOM is dropped, the final CRLF too.
    private func recordLines(_ data: Data) -> [String] {
        var text = String(decoding: data, as: UTF8.self).unicodeScalars.map { $0 }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        var records: [String] = []
        var current = String.UnicodeScalarView()
        var inQuotes = false
        var index = 0
        while index < text.count {
            let scalar = text[index]
            if scalar == "\"" { inQuotes.toggle() }
            if !inQuotes, scalar == "\r", index + 1 < text.count, text[index + 1] == "\n" {
                records.append(String(current))
                current = String.UnicodeScalarView()
                index += 2
                continue
            }
            current.append(scalar)
            index += 1
        }
        if !current.isEmpty { records.append(String(current)) }
        return records
    }

    private func dataRows(_ data: Data) -> [String] {
        Array(recordLines(data).dropFirst())
    }

    /// One CSV record into cells (RFC 4180 quoting).
    private func parseCSVLine(_ line: String) -> [String] {
        var cells: [String] = []
        var cell = String.UnicodeScalarView()
        var inQuotes = false
        let scalars = Array(line.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if inQuotes {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        cell.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    cell.append(scalar)
                }
            } else if scalar == "\"" {
                inQuotes = true
            } else if scalar == "," {
                cells.append(String(cell))
                cell = String.UnicodeScalarView()
            } else {
                cell.append(scalar)
            }
            index += 1
        }
        cells.append(String(cell))
        return cells
    }

    private func stripComma(_ line: Substring) -> String {
        line.hasSuffix(",") ? String(line.dropLast()) : String(line)
    }
}

// MARK: - Synthetic case (inputs and expectations generated by running src/shared/exporter.js)

private let syntheticPeriodsJSON = #"""
{
  "today": {
    "totalTokens": 0.30000000000000004,
    "costUsd": 1e+21,
    "big": 123456789012345680000,
    "tiny": 1e-7,
    "negZero": 0,
    "denorm": 5e-324,
    "huge": 1.5e+300,
    "third": 0.3333333333333333,
    "clients": {
      "b,tool": 10,
      "a": "12",
      "say \"hi\"": 5,
      "z": null,
      "m": "abc",
      "line\r\nbreak": 7,
      "costless": 3,
      "é": 2
    },
    "clientCosts": {
      "b,tool": 0.5,
      "a": "0.25",
      "say \"hi\"": 1,
      "ghost": 99,
      "line\r\nbreak": 2.5
    },
    "models": {
      "gpt-5": 20,
      "Claude": 3,
      "claude": 4
    },
    "modelCosts": {
      "gpt-5": 2
    },
    "text": "é/\u0001😀\ttab\\ \"q\"",
    "sessions": {
      "claude:1": {
        "client": "claude",
        "sessionId": "1",
        "totalTokens": 5,
        "title": "secret",
        "sessionTitle": "s",
        "session_title": "s",
        "name": "n",
        "preview": "p",
        "firstUserMessage": "f",
        "first_user_message": "f",
        "customTitle": "c",
        "custom_title": "c",
        "aiTitle": "a",
        "ai_title": "a",
        "sessionKind": "background-review",
        "projectLabel": "infra",
        "models": {
          "x": 1
        }
      },
      "raw": 5,
      "nul": null
    }
  },
  "month": {
    "clients": {},
    "models": {},
    "sessions": [
      {
        "title": "arr",
        "id": 1
      },
      7
    ]
  },
  "allTime": {
    "clients": {
      "codex": 100
    },
    "clientCosts": {
      "codex": 9
    },
    "models": {},
    "sessions": null
  },
  "ignored": {
    "clients": {
      "nope": 1
    }
  }
}
"""#

private let syntheticHistoryJSON = #"""
{
  "daily": [
    {
      "date": "2026-07-03T12:00:00Z",
      "tokenComponentsAvailable": true,
      "perClient": {
        "codex": {
          "tokens": 7,
          "cost": 1
        },
        "claude-code": {
          "tokens": 5,
          "cost": 1
        },
        "junk": 5,
        "nul": null
      },
      "perModel": {
        "m-explicit": {
          "tokens": 100,
          "outputTokens": 10,
          "cacheReadTokens": 20,
          "cacheWriteTokens": 5,
          "unclassifiedTokens": 30,
          "cost": 1.5
        },
        "m-explicit-big": {
          "tokens": 100,
          "outputTokens": 10,
          "unclassifiedTokens": 500,
          "cost": 0
        },
        "m-components": {
          "tokens": 100,
          "outputTokens": 10,
          "cacheReadTokens": 20,
          "cacheWriteTokens": 5,
          "cost": 0.125
        },
        "m-invalid": {
          "tokens": 50,
          "outputTokens": 40,
          "cacheReadTokens": 20,
          "cost": 2
        },
        "m-neg": {
          "tokens": -5,
          "cost": -1
        },
        "m-str": {
          "tokens": "12",
          "cost": "0.5",
          "outputTokens": "abc"
        },
        "m-null-unclassified": {
          "tokens": 10,
          "outputTokens": 2,
          "unclassifiedTokens": null
        },
        "a,b": {
          "tokens": 1
        },
        "say \"hi\"": {
          "tokens": 2
        },
        "line\r\nbreak": {
          "tokens": 3
        },
        "m-empty": {},
        "m-num": 5
      }
    },
    {
      "date": "2026-07-02",
      "perClient": {
        "codex": {
          "tokens": 5,
          "cost": 1
        }
      },
      "perModel": {
        "m-legacy": {
          "tokens": 100,
          "outputTokens": 10
        }
      }
    },
    {
      "date": "2026-07-04",
      "tokenComponentsAvailable": "true",
      "perModel": {
        "m-legacy": {
          "tokens": 100,
          "outputTokens": 10
        }
      }
    },
    {
      "date": "",
      "perClient": {
        "skipped": {
          "tokens": 1
        }
      }
    },
    {
      "tokens": 3,
      "perClient": {
        "skipped": {
          "tokens": 1
        }
      }
    },
    {
      "date": 0,
      "perClient": {
        "skipped": {
          "tokens": 1
        }
      }
    },
    {
      "date": 20260705,
      "perClient": {
        "numdate": {
          "tokens": 1
        }
      }
    },
    {
      "date": "2026-07-03",
      "perClient": {
        "codex": {
          "tokens": 1,
          "cost": 0.5
        }
      }
    }
  ],
  "monthly": [
    {
      "month": "2026-07",
      "tokens": 17,
      "cost": 3
    }
  ]
}
"""#

/// `exportFileSet` with the wire objects key-sorted, as iOS writes them; the final newline
/// is not part of a multi-line literal, so the test appends it.
private let syntheticExpectedJSON = #"""
{
  "generatedAt": "2026-10-10T16:30:00.000Z",
  "app": {
    "name": "token-monitor",
    "version": "1.2.3"
  },
  "snapshot": {
    "today": {
      "big": 123456789012345680000,
      "clientCosts": {
        "a": "0.25",
        "b,tool": 0.5,
        "ghost": 99,
        "line\r\nbreak": 2.5,
        "say \"hi\"": 1
      },
      "clients": {
        "a": "12",
        "b,tool": 10,
        "costless": 3,
        "line\r\nbreak": 7,
        "m": "abc",
        "say \"hi\"": 5,
        "z": null,
        "é": 2
      },
      "costUsd": 1e+21,
      "denorm": 5e-324,
      "huge": 1.5e+300,
      "modelCosts": {
        "gpt-5": 2
      },
      "models": {
        "Claude": 3,
        "claude": 4,
        "gpt-5": 20
      },
      "negZero": 0,
      "sessions": {
        "claude:1": {
          "client": "claude",
          "models": {
            "x": 1
          },
          "projectLabel": "infra",
          "sessionId": "1",
          "sessionKind": "background-review",
          "totalTokens": 5
        },
        "nul": null,
        "raw": 5
      },
      "text": "é/\u0001😀\ttab\\ \"q\"",
      "third": 0.3333333333333333,
      "tiny": 1e-7,
      "totalTokens": 0.30000000000000004
    },
    "month": {
      "clients": {},
      "models": {},
      "sessions": {
        "0": {
          "id": 1
        },
        "1": 7
      }
    },
    "allTime": {
      "clientCosts": {
        "codex": 9
      },
      "clients": {
        "codex": 100
      },
      "models": {},
      "sessions": null
    }
  },
  "daily": [
    {
      "date": "2026-07-03T12:00:00Z",
      "perClient": {
        "claude-code": {
          "cost": 1,
          "tokens": 5
        },
        "codex": {
          "cost": 1,
          "tokens": 7
        },
        "junk": 5,
        "nul": null
      },
      "perModel": {
        "a,b": {
          "tokens": 1
        },
        "line\r\nbreak": {
          "tokens": 3
        },
        "m-components": {
          "cacheReadTokens": 20,
          "cacheWriteTokens": 5,
          "cost": 0.125,
          "outputTokens": 10,
          "tokens": 100
        },
        "m-empty": {},
        "m-explicit": {
          "cacheReadTokens": 20,
          "cacheWriteTokens": 5,
          "cost": 1.5,
          "outputTokens": 10,
          "tokens": 100,
          "unclassifiedTokens": 30
        },
        "m-explicit-big": {
          "cost": 0,
          "outputTokens": 10,
          "tokens": 100,
          "unclassifiedTokens": 500
        },
        "m-invalid": {
          "cacheReadTokens": 20,
          "cost": 2,
          "outputTokens": 40,
          "tokens": 50
        },
        "m-neg": {
          "cost": -1,
          "tokens": -5
        },
        "m-null-unclassified": {
          "outputTokens": 2,
          "tokens": 10,
          "unclassifiedTokens": null
        },
        "m-num": 5,
        "m-str": {
          "cost": "0.5",
          "outputTokens": "abc",
          "tokens": "12"
        },
        "say \"hi\"": {
          "tokens": 2
        }
      },
      "tokenComponentsAvailable": true
    },
    {
      "date": "2026-07-02",
      "perClient": {
        "codex": {
          "cost": 1,
          "tokens": 5
        }
      },
      "perModel": {
        "m-legacy": {
          "outputTokens": 10,
          "tokens": 100
        }
      }
    },
    {
      "date": "2026-07-04",
      "perModel": {
        "m-legacy": {
          "outputTokens": 10,
          "tokens": 100
        }
      },
      "tokenComponentsAvailable": "true"
    },
    {
      "date": "",
      "perClient": {
        "skipped": {
          "tokens": 1
        }
      }
    },
    {
      "perClient": {
        "skipped": {
          "tokens": 1
        }
      },
      "tokens": 3
    },
    {
      "date": 0,
      "perClient": {
        "skipped": {
          "tokens": 1
        }
      }
    },
    {
      "date": 20260705,
      "perClient": {
        "numdate": {
          "tokens": 1
        }
      }
    },
    {
      "date": "2026-07-03",
      "perClient": {
        "codex": {
          "cost": 0.5,
          "tokens": 1
        }
      }
    }
  ],
  "monthly": [
    {
      "cost": 3,
      "month": "2026-07",
      "tokens": 17
    }
  ]
}
"""#

private let syntheticExpectedSnapshotCSV = "\u{FEFF}period,dimension,name,tokens,cost_usd\r\ntoday,tool,a,12,0.25\r\ntoday,tool,\"b,tool\",10,0.5\r\ntoday,tool,costless,3,0\r\ntoday,tool,\"line\r\nbreak\",7,2.5\r\ntoday,tool,m,0,0\r\ntoday,tool,\"say \"\"hi\"\"\",5,1\r\ntoday,tool,z,0,0\r\ntoday,tool,é,2,0\r\ntoday,model,Claude,3,0\r\ntoday,model,claude,4,0\r\ntoday,model,gpt-5,20,2\r\nallTime,tool,codex,100,9\r\n"
private let syntheticExpectedDailyCSV = "\u{FEFF}date,tool,tokens,cost_usd\r\n2026-07-02,codex,5,1\r\n2026-07-03,claude-code,5,1\r\n2026-07-03,codex,7,1\r\n2026-07-03,codex,1,0.5\r\n2026-07-03,junk,0,0\r\n2026-07-03,nul,0,0\r\n20260705,numdate,1,0\r\n"
private let syntheticExpectedDailyModelsCSV = "\u{FEFF}date,model,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,unclassified_tokens,total_tokens,cost_usd\r\n2026-07-02,m-legacy,0,10,0,0,90,100,0\r\n2026-07-03,\"a,b\",1,0,0,0,0,1,0\r\n2026-07-03,\"line\r\nbreak\",3,0,0,0,0,3,0\r\n2026-07-03,m-components,65,10,20,5,0,100,0.125\r\n2026-07-03,m-empty,0,0,0,0,0,0,0\r\n2026-07-03,m-explicit,35,10,20,5,30,100,1.5\r\n2026-07-03,m-explicit-big,0,10,0,0,90,100,0\r\n2026-07-03,m-invalid,0,0,0,0,50,50,2\r\n2026-07-03,m-neg,0,0,0,0,0,0,-1\r\n2026-07-03,m-null-unclassified,8,2,0,0,0,10,0\r\n2026-07-03,m-num,0,0,0,0,0,0,0\r\n2026-07-03,m-str,12,0,0,0,0,12,0.5\r\n2026-07-03,\"say \"\"hi\"\"\",2,0,0,0,0,2,0\r\n2026-07-04,m-legacy,0,10,0,0,90,100,0\r\n"

import Foundation
import XCTest
@testable import TokenMonitorKit

/// Golden parity for the History presentation ports (Activity mosaic, trend
/// bars / candles / area line, fixed ranges, stat cards) against the desktop
/// modules run on the `Fixtures/v2` captures (frozen clock
/// 2026-10-10T16:30:00Z, today 2026-10-10; see `Fixtures/v2/README.txt`).
private enum HistFixtures {
    static let todayKey = "2026-10-10"
    static let now = ISODate.parse("2026-10-10T16:30:00.000Z")!

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

    static func golden(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(name, subdirectory: "Fixtures/v2/golden")) as? [String: Any])
    }

    static func history() throws -> HubHistory {
        try HubHistory.decode(from: data("history.json"))
    }

    static func stats() throws -> HubStats {
        try HubStats.decode(from: data("stats.json"), options: .app)
    }

    static func records() throws -> [DeviceHistoryRecord] {
        try DeviceHistoryRecord.decodeList(from: data("devices.json"))
    }

    static func record(_ id: String) throws -> DeviceHistoryRecord {
        try XCTUnwrap(records().first { $0.id == id })
    }

    /// The aggregate History with the aggregate live today patched in.
    static func patchedAggregate() throws -> [HubHistoryDay] {
        HistorySeries.dailyWithLiveToday(try history().daily, todayKey: todayKey, today: try stats().today)
    }
}

private func number(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue
}

private func int(_ value: Any?) -> Int? {
    number(value).map { Int($0) }
}

/// JSONSerialization on Linux can land an ulp or two away from the correctly
/// rounded value for long decimals, and JS sums maps in wire order: compare
/// doubles with a tight relative tolerance.
private func assertClose(_ actual: Double?, _ expected: Double?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard let actual, let expected else {
        return XCTAssertEqual(actual, expected, message(), file: file, line: line)
    }
    XCTAssertEqual(actual, expected, accuracy: max(1e-9, abs(expected) * 1e-12), message(), file: file, line: line)
}

private func selection(_ raw: String) throws -> PeriodSelection {
    try XCTUnwrap(PeriodSelection(rawValue: raw), raw)
}

/// `Calendar.firstWeekday` for the two locales the goldens use.
private func firstWeekday(_ locale: String) -> Int {
    locale == "en-GB" ? 2 : 1
}

final class HistoryPresentationTests: XCTestCase {
    // MARK: Activity mosaic

    func testAggregateTodayPatchMatchesGolden() throws {
        let golden = try HistFixtures.golden("heatmap.json")
        let aggregate = try XCTUnwrap(golden["aggregate"] as? [String: Any])
        let days = try XCTUnwrap(aggregate["days"] as? [[Any]])
        let patched = try HistFixtures.patchedAggregate()
        XCTAssertEqual(patched.count, days.count)
        for (row, expected) in zip(patched, days) {
            XCTAssertEqual(row.date, expected[0] as? String)
            XCTAssertEqual(row.tokens, int(expected[1]), row.date)
            assertClose(row.costUsd, number(expected[2]), row.date)
            XCTAssertEqual(row.unpricedTokens, expected.count > 3 ? int(expected[3]) : nil, row.date)
        }
        // The live today replaced History's own (smaller) today row.
        XCTAssertEqual(patched.last?.date, HistFixtures.todayKey)
        XCTAssertEqual(patched.last?.tokens, try HistFixtures.stats().today.totalTokens)
    }

    func testAggregateHeatmapMatchesGolden() throws {
        let golden = try HistFixtures.golden("heatmap.json")
        let aggregate = try XCTUnwrap(golden["aggregate"] as? [String: Any])
        let patched = try HistFixtures.patchedAggregate()
        try assertGrid(patched, golden: XCTUnwrap(aggregate["grid"] as? [String: Any]))

        let history = try HistFixtures.history()
        let summary = try XCTUnwrap(history.summary)
        let grid = HeatmapBuilder.rollingYear(daily: patched, metric: .cost, todayKey: HistFixtures.todayKey)
        XCTAssertEqual(ActiveDays.count(window: .all, summary: summary, grid: grid), int(aggregate["summaryActiveDays"]))
        XCTAssertEqual(ActiveDays.count(window: .year, summary: summary, grid: grid), int((aggregate["grid"] as? [String: Any])?["activeDaysInGrid"]))
        XCTAssertEqual(ActiveDays.count(window: .all, summary: nil, grid: grid), grid.activeDayCount)
        try assertStatCards(StatCards.cards(summary: summary), golden: aggregate["statCards"])
    }

    func testDeviceHeatmapMatchesGolden() throws {
        let golden = try HistFixtures.golden("heatmap.json")
        let device = try XCTUnwrap(golden["device"] as? [String: Any])
        let record = try HistFixtures.record(XCTUnwrap(device["deviceId"] as? String))
        let history = try XCTUnwrap(record.history)
        // The record's raw `periods.today` is the stats device's `periods.today`.
        let patched = HistorySeries.dailyWithLiveToday(history.daily, todayKey: HistFixtures.todayKey, today: record.today)
        try assertGrid(patched, golden: XCTUnwrap(device["grid"] as? [String: Any]))
        try assertStatCards(StatCards.cards(summary: XCTUnwrap(history.summary)), golden: device["statCards"])

        // studio-mac's day window is still open: its views end on its key.
        let deviceDaily = try XCTUnwrap(HistorySeries.deviceDaily(record: record, now: HistFixtures.now, fallbackTodayKey: "1999-01-01"))
        XCTAssertEqual(deviceDaily.todayKey, HistFixtures.todayKey)
        XCTAssertEqual(deviceDaily.daily, patched)
        XCTAssertEqual(deviceDaily.summary, history.summary)
        XCTAssertNil(HistorySeries.deviceDaily(record: try HistFixtures.record("old-laptop"), now: HistFixtures.now, fallbackTodayKey: HistFixtures.todayKey))
    }

    func testIntensityLevelsMatchGolden() throws {
        let probe = try XCTUnwrap(HistFixtures.golden("heatmap.json")["intensityProbe"] as? [String: Any])
        let values = try XCTUnwrap(probe["tokens"] as? [Any]).compactMap(number)
        let levels = try XCTUnwrap(probe["levels"] as? [Any]).compactMap(int)
        let maximum = values.max() ?? 0
        XCTAssertEqual(values.map { HeatmapBuilder.intensity(value: $0, max: maximum) }, levels)
        XCTAssertEqual(HeatmapBuilder.intensity(value: 5, max: 0), 0)
        XCTAssertEqual(HeatmapBuilder.intensity(value: .nan, max: 10), 0)
    }

    /// Compares a grid built from `daily` with a golden `heatmapFor` result
    /// (`cells` rows: date, col, row, tokens, cost, levelTokens, levelCost
    /// [, unpricedTokens]).
    private func assertGrid(_ daily: [HubHistoryDay], golden: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws {
        let days = daily.map(HeatmapDay.init)
        let tokens = HeatmapBuilder.rollingYear(days: days, metric: .tokens, todayKey: HistFixtures.todayKey)
        let cost = HeatmapBuilder.rollingYear(days: days, metric: .cost, todayKey: HistFixtures.todayKey)
        let rows = try XCTUnwrap(golden["cells"] as? [[Any]])
        XCTAssertEqual(tokens.cells.count, rows.count, file: file, line: line)
        XCTAssertEqual(tokens.weeks, int(golden["weeks"]), file: file, line: line)
        XCTAssertEqual(tokens.cells.first?.date, golden["startDate"] as? String, file: file, line: line)
        XCTAssertEqual(tokens.startDate, "2025-11-01", file: file, line: line)
        XCTAssertEqual(tokens.endDate, golden["endDate"] as? String, file: file, line: line)
        XCTAssertEqual(tokens.metric, .tokens)
        XCTAssertEqual(cost.metric, .cost)
        XCTAssertEqual(HeatmapBuilder.maximum(of: days, metric: .tokens), number(golden["maxTokens"]), file: file, line: line)
        assertClose(HeatmapBuilder.maximum(of: days, metric: .cost), number(golden["maxCost"]), file: file, line: line)
        XCTAssertEqual(tokens.activeDayCount, int(golden["activeDaysInGrid"]), file: file, line: line)
        let labels = try XCTUnwrap(golden["monthLabels"] as? [[String: Any]])
        XCTAssertEqual(tokens.monthLabels.map(\.column), labels.compactMap { int($0["col"]) }, file: file, line: line)
        XCTAssertEqual(tokens.monthLabels.map(\.month), labels.compactMap { $0["month"] as? String }, file: file, line: line)
        XCTAssertEqual(cost.monthLabels, tokens.monthLabels, file: file, line: line)
        for (index, row) in rows.enumerated() where index < tokens.cells.count {
            let cell = tokens.cells[index]
            let context = "cell \(cell.date)"
            XCTAssertEqual(cell.date, row[0] as? String, context, file: file, line: line)
            XCTAssertEqual(cell.column, int(row[1]), context, file: file, line: line)
            XCTAssertEqual(cell.row, int(row[2]), context, file: file, line: line)
            XCTAssertEqual(cell.tokens, int(row[3]), context, file: file, line: line)
            assertClose(cell.costUsd, number(row[4]), context, file: file, line: line)
            XCTAssertEqual(cell.level, int(row[5]), context, file: file, line: line)
            XCTAssertEqual(cost.cells[index].level, int(row[6]), context, file: file, line: line)
            XCTAssertEqual(cell.unpricedTokens, row.count > 7 ? int(row[7]) : nil, context, file: file, line: line)
            // Row 0 is Sunday whatever the locale.
            XCTAssertEqual(cell.row, (index + 0) % 7, context, file: file, line: line)
        }
    }

    private func assertStatCards(_ cards: [StatCard], golden raw: Any?, file: StaticString = #filePath, line: UInt = #line) throws {
        let rows = try XCTUnwrap(raw as? [[String: Any]])
        XCTAssertEqual(cards.map(\.key.rawValue), rows.compactMap { $0["key"] as? String }, file: file, line: line)
        for (card, row) in zip(cards, rows) {
            let kind = row["kind"] as? String
            switch card.value {
            case .tokens(let value):
                XCTAssertEqual(kind, "tokens")
                XCTAssertEqual(Double(value), number(row["value"]), card.key.rawValue, file: file, line: line)
            case .cost(let usd, _):
                XCTAssertEqual(kind, "cost")
                assertClose(usd, number(row["value"]), card.key.rawValue, file: file, line: line)
            case .days(let value):
                XCTAssertEqual(kind, "days")
                XCTAssertEqual(Double(value), number(row["value"]), card.key.rawValue, file: file, line: line)
            case .duration(let milliseconds):
                XCTAssertEqual(kind, "duration")
                assertClose(milliseconds, number(row["value"]), card.key.rawValue, file: file, line: line)
            case .model(let model):
                XCTAssertEqual(kind, "model")
                XCTAssertEqual(model ?? "", row["value"] as? String, file: file, line: line)
            case .count(let value):
                XCTAssertEqual(kind, "count")
                XCTAssertEqual(Double(value), number(row["value"]), card.key.rawValue, file: file, line: line)
            }
        }
    }

    func testHeatmapCellDetailsAndLookup() throws {
        let grid = HeatmapBuilder.rollingYear(daily: try HistFixtures.patchedAggregate(), metric: .cost, todayKey: HistFixtures.todayKey)
        let today = try XCTUnwrap(grid.cell(on: HistFixtures.todayKey))
        XCTAssertEqual(today.row, 6) // 2026-10-10 is a Saturday.
        XCTAssertEqual(today.excludedFromCostTokens, 90_000)
        XCTAssertTrue(today.showsCost)
        XCTAssertFalse(today.hasUnknownCost)
        XCTAssertNil(grid.cell(on: "2026-10-11"))
        XCTAssertNil(grid.cell(on: "2025-10-25"))
        XCTAssertEqual(grid.cell(on: "2025-10-26")?.column, 0)

        let unknown = HeatmapCell(date: "2026-01-01", column: 0, row: 4, level: 1, tokens: 10, costUsd: 0, unpricedTokens: 10)
        XCTAssertTrue(unknown.hasUnknownCost)
        XCTAssertTrue(unknown.showsCost)
        let empty = HeatmapCell(date: "2026-01-02", column: 0, row: 5, level: 0, tokens: 0, costUsd: 0)
        XCTAssertFalse(empty.showsCost)
        XCTAssertNil(empty.excludedFromCostTokens)

        XCTAssertEqual(HeatmapMonthLabel(column: 3, month: "2026-02").monthNumber, 2)
        XCTAssertEqual(HeatmapMonthLabel(column: 3, month: "2026-02").year, 2026)
        XCTAssertNil(HeatmapMonthLabel(column: 3, month: "2026-13").monthNumber)
    }

    func testHeatmapTrailingWeeks() throws {
        let grid = HeatmapBuilder.rollingYear(daily: try HistFixtures.patchedAggregate(), metric: .tokens, todayKey: HistFixtures.todayKey)
        let recent = grid.trailing(weeks: 20)
        XCTAssertEqual(recent.weeks, 20)
        XCTAssertEqual(recent.cells.first?.column, 0)
        XCTAssertEqual(recent.cells.first?.row, 0)
        XCTAssertEqual(recent.cells.last?.date, HistFixtures.todayKey)
        XCTAssertEqual(recent.cells.last?.column, 19)
        XCTAssertEqual(recent.startDate, recent.cells.first?.date)
        XCTAssertEqual(recent.cells.count, 19 * 7 + 7)
        XCTAssertEqual(recent.cells.map(\.level), grid.cells.suffix(recent.cells.count).map(\.level))
        XCTAssertTrue(recent.monthLabels.allSatisfy { recent.cells[$0.column * 7].date <= "\($0.month)-01" })
        XCTAssertEqual(recent.monthLabels.map(\.month), ["2026-06", "2026-07", "2026-08", "2026-09", "2026-10"])
        XCTAssertEqual(grid.trailing(weeks: 99), grid)
        XCTAssertEqual(grid.trailing(weeks: 0).cells, [])
    }

    func testRollingYearWindowAndEmptyInput() {
        XCTAssertEqual(HeatmapBuilder.rollingYearStart(todayKey: "2026-10-10"), "2025-11-01")
        XCTAssertEqual(HeatmapBuilder.rollingYearStart(todayKey: "2026-12-31"), "2026-01-01")
        XCTAssertEqual(HeatmapBuilder.rollingYearStart(todayKey: "2026-01-15"), "2025-02-01")
        XCTAssertNil(HeatmapBuilder.rollingYearStart(todayKey: "2026-02-30"))

        let empty = HeatmapBuilder.rollingYear(days: [], metric: .cost, todayKey: "2026-10-10")
        XCTAssertEqual(empty.cells.count, 350)
        XCTAssertTrue(empty.cells.allSatisfy { $0.level == 0 && $0.tokens == 0 })
        XCTAssertEqual(empty.monthLabels.count, 12)
        XCTAssertEqual(HeatmapBuilder.rollingYear(days: [], metric: .cost, todayKey: "nope").cells, [])

        // A leap-year window: 2024-12-31 starts on 2024-01-01 (a Monday).
        let leap = HeatmapBuilder.rollingYear(days: [HeatmapDay(date: "2024-02-29", tokens: 4, costUsd: 1)], metric: .tokens, todayKey: "2024-12-31")
        XCTAssertEqual(leap.cells.first?.date, "2023-12-31")
        XCTAssertEqual(leap.cell(on: "2024-02-29")?.level, 4)
        XCTAssertEqual(leap.cells.count, 367)
    }

    func testCivilDayAgreesWithCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 0)
        for offset in stride(from: -40_000, through: 40_000, by: 97) {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let key = DayKey.string(from: date, calendar: calendar)
            XCTAssertEqual(CivilDay.key(offset), key)
            XCTAssertEqual(CivilDay.number(key), offset)
            XCTAssertEqual(CivilDay.weekday(offset), calendar.component(.weekday, from: date) - 1)
        }
        XCTAssertNil(CivilDay.number("2023-02-29"))
        XCTAssertNotNil(CivilDay.number("2000-02-29"))
        XCTAssertNil(CivilDay.number("1900-02-29"))
        XCTAssertNil(CivilDay.number("2026-1-01"))
        XCTAssertEqual(CivilDay.normalized(" 2026-10-10T12:00:00Z"), "2026-10-10")
    }

    // MARK: Trend bars, candles, area line

    func testBarsMatchGolden() throws {
        let golden = try HistFixtures.golden("bars.json")
        let patched = try HistFixtures.patchedAggregate()
        let charts = try XCTUnwrap(golden["charts"] as? [[String: Any]])
        XCTAssertEqual(charts.count, 8)
        for chart in charts {
            let range = try XCTUnwrap(TrendRange(rawValue: XCTUnwrap(chart["range"] as? String)))
            let stack = try XCTUnwrap(TrendStack(rawValue: XCTUnwrap(chart["stackBy"] as? String)))
            let metric = try XCTUnwrap(TrendMetricKind(rawValue: XCTUnwrap(chart["metric"] as? String)))
            let context = "\(range.rawValue)/\(stack.rawValue)/\(metric.rawValue)"
            let days = HistorySeries.range(range, daily: patched, todayKey: HistFixtures.todayKey)
            let model = TrendSeriesBuilder.bars(days: days, stack: stack, metric: metric)
            XCTAssertEqual(model.keys, chart["keys"] as? [String], context)
            assertClose(model.maxTotal, number(chart["maxTotal"]), context)
            let bars = try XCTUnwrap(chart["bars"] as? [[Any]])
            XCTAssertEqual(model.bars.count, bars.count, context)
            for (bar, expected) in zip(model.bars, bars) {
                XCTAssertEqual(bar.date, expected[0] as? String, context)
                assertClose(bar.total, number(expected[1]), "\(context) \(bar.date)")
                let segments = try XCTUnwrap(expected[2] as? [[Any]])
                XCTAssertEqual(bar.segments.map(\.key), segments.compactMap { $0[0] as? String }, "\(context) \(bar.date)")
                for (segment, row) in zip(bar.segments, segments) {
                    assertClose(segment.value, number(row[1]), "\(context) \(bar.date) \(segment.key)")
                }
            }
        }
        XCTAssertEqual(TrendSeriesBuilder.bars(days: [], stack: .client, metric: .tokens), TrendBarsModel(keys: [], bars: [], maxTotal: 1))
    }

    func testCandlesMatchGolden() throws {
        let golden = try HistFixtures.golden("candles.json")
        let patched = try HistFixtures.patchedAggregate()
        for width in try XCTUnwrap(golden["widths"] as? [[String: Any]]) {
            let span = try XCTUnwrap(int(width["span"]))
            let plotWidth = try XCTUnwrap(number(width["plotWidth"]))
            XCTAssertEqual(TrendSeriesBuilder.klineBucketDays(span: span, plotWidth: plotWidth), int(width["bucketDays"]), "\(width)")
        }
        let charts = try XCTUnwrap(golden["charts"] as? [[String: Any]])
        XCTAssertFalse(charts.isEmpty)
        for chart in charts {
            let range = try XCTUnwrap(TrendRange(rawValue: XCTUnwrap(chart["range"] as? String)))
            let metric = try XCTUnwrap(TrendMetricKind(rawValue: XCTUnwrap(chart["metric"] as? String)))
            let bucketDays = try XCTUnwrap(int(chart["bucketDays"]))
            let context = "\(range.rawValue)/\(metric.rawValue)/\(bucketDays)"
            let days = HistorySeries.range(range, daily: patched, todayKey: HistFixtures.todayKey)
            XCTAssertEqual(days.first?.date, chart["firstDate"] as? String, context)
            let points = TrendSeriesBuilder.line(days: days, metric: metric)
            XCTAssertEqual(TrendSeriesBuilder.span(of: points), int(chart["span"]), context)
            let candles = TrendSeriesBuilder.candles(points: points, bucketDays: bucketDays)
            let expected = try XCTUnwrap(chart["candles"] as? [[Any]])
            XCTAssertEqual(candles.count, expected.count, context)
            assertClose(max(1, candles.map(\.high).max() ?? 0), number(chart["maxVal"]), context)
            for (candle, row) in zip(candles, expected) {
                XCTAssertEqual(candle.key, row[0] as? String, context)
                XCTAssertEqual(candle.endKey, row[1] as? String, context)
                XCTAssertEqual(candle.days, int(row[2]), context)
                assertClose(candle.open, number(row[3]), context)
                assertClose(candle.high, number(row[4]), context)
                assertClose(candle.low, number(row[5]), context)
                assertClose(candle.close, number(row[6]), context)
                XCTAssertEqual(candle.up, row[7] as? Bool, "\(context) \(candle.key)")
            }
        }
        // The plot-width entry point picks the same buckets.
        let days = HistorySeries.range(.days90, daily: patched, todayKey: HistFixtures.todayKey)
        let bucketDays = TrendSeriesBuilder.klineBucketDays(span: 90, plotWidth: 390)
        XCTAssertEqual(
            TrendSeriesBuilder.candles(days: days, metric: .tokens, plotWidth: 390),
            TrendSeriesBuilder.candles(points: TrendSeriesBuilder.line(days: days, metric: .tokens), bucketDays: bucketDays)
        )
        XCTAssertEqual(TrendSeriesBuilder.candles(points: [], bucketDays: 3), [])
    }

    func testAreaLineMatchesGolden() throws {
        let golden = try HistFixtures.golden("area-line.json")
        let patched = try HistFixtures.patchedAggregate()
        for chart in try XCTUnwrap(golden["charts"] as? [[String: Any]]) {
            let name = try XCTUnwrap(chart["name"] as? String)
            let options = try XCTUnwrap(chart["options"] as? [String: Any])
            let goldenPoints = try XCTUnwrap(chart["points"] as? [[String: Any]])
            let points = goldenPoints.map { TrendLinePoint(date: $0["date"] as? String ?? "", value: number($0["value"]) ?? 0) }
            let defaults = TrendPlotInsets.areaLine
            let insets = TrendPlotInsets(
                top: number(options["padTop"]) ?? defaults.top,
                right: number(options["padRight"]) ?? defaults.right,
                bottom: number(options["padBottom"]) ?? defaults.bottom,
                left: number(options["padLeft"]) ?? defaults.left
            )
            let geometry = TrendSeriesBuilder.areaLine(
                points: points,
                width: try XCTUnwrap(number(options["width"])),
                height: try XCTUnwrap(number(options["height"])),
                insets: insets,
                curve: options["curve"] as? Bool ?? false
            )
            assertClose(geometry.maxValue, number(chart["maxVal"]), name)
            let plot = try XCTUnwrap(chart["plot"] as? [String: Any])
            XCTAssertEqual(geometry.plotOrigin, TrendPlotPoint(x: number(plot["x"]) ?? -1, y: number(plot["y"]) ?? -1), name)
            XCTAssertEqual(geometry.plotWidth, number(plot["w"]), name)
            XCTAssertEqual(geometry.plotHeight, number(plot["h"]), name)
            for (point, expected) in zip(geometry.points, goldenPoints) {
                assertClose(point.x, number(expected["x"]), "\(name) \(point.date)")
                assertClose(point.y, number(expected["y"]), "\(name) \(point.date)")
            }
            XCTAssertEqual(AreaLineGeometry.svgPath(geometry.line), chart["linePath"] as? String, name)
            XCTAssertEqual(AreaLineGeometry.svgPath(geometry.area), chart["areaPath"] as? String, name)

            // `homeTrendSummary` always reads the rows' tokens, whatever the
            // chart's metric.
            let summary = try XCTUnwrap(chart["trendSummary"] as? [String: Any])
            let tokenPoints = options["metric"] as? String == "cost"
                ? TrendSeriesBuilder.line(days: HistorySeries.range(.days30, daily: patched, todayKey: HistFixtures.todayKey), metric: .tokens)
                : points
            let trend = HistoryInsights.trendSummary(points: tokenPoints)
            XCTAssertEqual(trend.peak, int(summary["peak"]), name)
            XCTAssertEqual(trend.axisDates, summary["dates"] as? [String], name)

            // The calendar ranges feed the same points.
            if name == "range7" || name == "range30cost" {
                let range: TrendRange = name == "range7" ? .days7 : .days30
                let metric: TrendMetricKind = name == "range7" ? .tokens : .cost
                let mine = TrendSeriesBuilder.line(days: HistorySeries.range(range, daily: patched, todayKey: HistFixtures.todayKey), metric: metric)
                XCTAssertEqual(mine.map(\.date), points.map(\.date), name)
                for (left, right) in zip(mine, points) { assertClose(left.value, right.value, name) }
            }
        }
        let empty = TrendSeriesBuilder.areaLine(points: [])
        XCTAssertEqual(empty.line, [])
        XCTAssertEqual(empty.area, [])
        XCTAssertEqual(empty.maxValue, 1)
        let single = TrendSeriesBuilder.areaLine(points: [TrendLinePoint(date: "2026-10-10", value: 5)], width: 100, height: 50, insets: TrendPlotInsets(top: 0, right: 0, bottom: 0, left: 0))
        XCTAssertEqual(single.points.first?.x, 50)
        XCTAssertEqual(single.points.first?.y, 0)
    }

    func testHomeTrendFillsCalendarDays() throws {
        let golden = try HistFixtures.golden("area-line.json")
        let home = try XCTUnwrap((golden["charts"] as? [[String: Any]])?.first { $0["name"] as? String == "home45" })
        let goldenPoints = try XCTUnwrap(home["points"] as? [[String: Any]])
        let patched = try HistFixtures.patchedAggregate()
        let summary = try HistFixtures.history().summary
        let trend = HistoryInsights.homeTrend(daily: patched, todayKey: HistFixtures.todayKey, summary: summary)
        XCTAssertEqual(trend.points.count, 45)
        XCTAssertEqual(trend.points.first?.date, "2026-08-27")
        XCTAssertEqual(trend.points.last?.date, HistFixtures.todayKey)
        // Every History row the desktop plots is on the iOS line with the same
        // value; the days History omits are zeros instead of being skipped.
        let byDate = Dictionary(uniqueKeysWithValues: trend.points.map { ($0.date, $0.value) })
        for point in goldenPoints {
            guard let date = point["date"] as? String, date >= "2026-08-27" else { continue }
            XCTAssertEqual(byDate[date], number(point["value"]), date)
        }
        XCTAssertEqual(trend.points.filter { $0.value == 0 }.count, 45 - goldenPoints.filter { ($0["date"] as? String ?? "") >= "2026-08-27" }.count)
        XCTAssertEqual(trend.longRangePeak, int(golden["longRangePeakDayTokens"]))
        XCTAssertEqual(trend.peak, 73_237_000)
        XCTAssertEqual(trend.axisDates, ["2026-08-27", "2026-09-18", "2026-10-10"])
        XCTAssertEqual(HistoryInsights.longRangePeakDayTokens(summary: nil, daily: []), 0)
    }

    // MARK: Fixed ranges

    func testRangesForSelectionMatchGolden() throws {
        let golden = try HistFixtures.golden("fixed-range.json")
        let ranges = try XCTUnwrap(golden["ranges"] as? [[String: Any]])
        XCTAssertEqual(ranges.count, 50)
        for entry in ranges {
            let todayKey = try XCTUnwrap(entry["todayKey"] as? String)
            let locale = try XCTUnwrap(entry["locale"] as? String)
            let selection = try selection(XCTUnwrap(entry["selection"] as? String))
            let range = FixedRanges.range(for: selection, todayKey: todayKey, firstWeekday: firstWeekday(locale))
            let expected = entry["range"] as? [String: Any]
            XCTAssertEqual(range?.start, expected?["start"] as? String, "\(todayKey) \(locale) \(selection)")
            XCTAssertEqual(range?.end, expected?["end"] as? String, "\(todayKey) \(locale) \(selection)")
        }
        XCTAssertNil(FixedRanges.range(for: .week, todayKey: "bad", firstWeekday: 1))
        XCTAssertEqual(FixedRanges.range(for: .last30, todayKey: "2026-10-10", firstWeekday: 1)?.dayCount, 30)
        // Saturday-first locales (ar-EG): a Saturday is its own week start.
        XCTAssertEqual(FixedRanges.range(for: .week, todayKey: "2026-10-10", firstWeekday: 7)?.start, "2026-10-10")
    }

    func testWeekStartFollowsTheLocaleCalendar() throws {
        let golden = try HistFixtures.golden("fixed-range.json")
        for entry in try XCTUnwrap(golden["weekStarts"] as? [[String: Any]]) {
            let locale = try XCTUnwrap(entry["locale"] as? String)
            // CLDR changed China's first day to Monday (ICU 77 in the goldens);
            // older platform data still says Sunday. The app takes whatever
            // the device's calendar says.
            guard locale != "zh-CN" else { continue }
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: locale)
            XCTAssertEqual(FixedRanges.weekStart(firstWeekday: calendar.firstWeekday), int(entry["weekStartsOn"]), locale)
        }
        XCTAssertEqual(FixedRanges.weekStart(firstWeekday: 1), 0)
        XCTAssertEqual(FixedRanges.weekStart(firstWeekday: 2), 1)
        XCTAssertEqual(FixedRanges.weekStart(firstWeekday: 7), 6)
    }

    func testAggregateFixedRangesMatchGolden() throws {
        let golden = try HistFixtures.golden("fixed-range.json")
        let history = try HistFixtures.history()
        let stats = try HistFixtures.stats()
        for entry in try XCTUnwrap(golden["aggregate"] as? [[String: Any]]) {
            let selection = try selection(XCTUnwrap(entry["selection"] as? String))
            let locale = try XCTUnwrap(entry["locale"] as? String)
            let snapshot = FixedRanges.snapshot(
                selection: selection,
                daily: history.daily,
                todayKey: HistFixtures.todayKey,
                today: stats.today,
                historyAvailable: true,
                firstWeekday: firstWeekday(locale)
            )
            try assertSnapshot(snapshot, golden: XCTUnwrap(entry["snapshot"] as? [String: Any]), context: "\(selection) \(locale)")
        }
    }

    func testFixedRangeUnavailableStates() throws {
        let golden = try HistFixtures.golden("fixed-range.json")
        let rows = try XCTUnwrap(golden["unavailable"] as? [[String: Any]])
        let byName = Dictionary(uniqueKeysWithValues: rows.compactMap { row in (row["name"] as? String).map { ($0, row["snapshot"] as? [String: Any] ?? [:]) } })
        let disabled = FixedRanges.snapshot(selection: .last7, daily: [], todayKey: HistFixtures.todayKey, today: nil, historyAvailable: true, historyEnabled: false, firstWeekday: 1)
        XCTAssertEqual(disabled.status, .unavailable(.historyDisabled))
        XCTAssertEqual(byName["historyDisabled"]?["reason"] as? String, FixedRangeUnavailableReason.historyDisabled.rawValue)
        let unavailable = FixedRanges.snapshot(selection: .last7, daily: [], todayKey: HistFixtures.todayKey, today: nil, historyAvailable: false, firstWeekday: 1)
        XCTAssertEqual(unavailable.status, .unavailable(.historyUnavailable))
        XCTAssertEqual(byName["historyUnavailable"]?["reason"] as? String, FixedRangeUnavailableReason.historyUnavailable.rawValue)
        for snapshot in [disabled, unavailable] {
            XCTAssertNil(snapshot.range)
            XCTAssertNil(snapshot.period)
            XCTAssertEqual(snapshot.selection, .last7)
        }
        let native = FixedRanges.snapshot(selection: .month, daily: [], todayKey: HistFixtures.todayKey, today: nil, historyAvailable: true, firstWeekday: 1)
        XCTAssertEqual(native.status, .native)
        XCTAssertEqual(byName["nativeMonth"]?["status"] as? String, "native")
        XCTAssertNil(native.period)

        XCTAssertFalse(FixedRanges.supports(.session, selection: .week))
        XCTAssertFalse(FixedRanges.supports(.project, selection: .last30))
        XCTAssertTrue(FixedRanges.supports(.tool, selection: .last7))
        XCTAssertFalse(FixedRanges.supports(.device, selection: .last7))
        XCTAssertTrue(FixedRanges.supports(.device, selection: .last7, deviceHistoriesAvailable: true))
        XCTAssertTrue(FixedRanges.supports(.session, selection: .month))
    }

    func testDeviceDayStatesMatchGolden() throws {
        let golden = try HistFixtures.golden("fixed-range.json")
        let stats = try HistFixtures.stats()
        for entry in try XCTUnwrap(golden["deviceDayStates"] as? [[String: Any]]) {
            let id = try XCTUnwrap(entry["deviceId"] as? String)
            let record = try HistFixtures.record(id)
            let device = try XCTUnwrap(stats.devices.first { $0.id == id })
            for (now, raw) in [
                (HistFixtures.now, entry["dayState"]),
                (HistFixtures.now.addingTimeInterval(8 * 3600), (entry["atPlus8h"] as? [String: Any])?["dayState"])
            ] {
                let expected = try XCTUnwrap(raw as? [String: Any])
                let state = DeviceDayState(
                    currentKey: try XCTUnwrap(expected["currentKey"] as? String),
                    snapshotKey: try XCTUnwrap(expected["snapshotKey"] as? String)
                )
                XCTAssertEqual(FixedRanges.deviceDayState(record: record, now: now), state, "\(id) \(now)")
                XCTAssertEqual(FixedRanges.deviceDayState(device: device, now: now), state, "\(id) \(now) (stats)")
            }
        }
        // An ended window without a usable time zone cannot be placed.
        let ended = ISODate.parse("2026-10-10T00:00:00Z")
        XCTAssertNil(FixedRanges.deviceDayState(todayWindowKey: "2026-10-09", todayEndsAt: ended, timeZone: nil, now: HistFixtures.now))
        XCTAssertNil(FixedRanges.deviceDayState(todayWindowKey: "2026-10-09", todayEndsAt: ended, timeZone: "Mars/Olympus", now: HistFixtures.now))
        XCTAssertNil(FixedRanges.deviceDayState(todayWindowKey: nil, todayEndsAt: ended, timeZone: "UTC", now: HistFixtures.now))
    }

    func testPerDeviceFixedRangesMatchGolden() throws {
        let golden = try HistFixtures.golden("fixed-range.json")
        let stats = try HistFixtures.stats()
        for entry in try XCTUnwrap(golden["perDevice"] as? [[String: Any]]) {
            let id = try XCTUnwrap(entry["deviceId"] as? String)
            let selection = try selection(XCTUnwrap(entry["selection"] as? String))
            let locale = try XCTUnwrap(entry["locale"] as? String)
            let snapshot = FixedRanges.deviceSnapshot(
                selection: selection,
                record: try HistFixtures.record(id),
                device: stats.devices.first { $0.id == id },
                now: HistFixtures.now,
                firstWeekday: firstWeekday(locale)
            )
            try assertSnapshot(snapshot, golden: XCTUnwrap(entry["snapshot"] as? [String: Any]), context: "\(id) \(selection) \(locale)")
        }
    }

    func testDeviceWithoutUsageGetsAnEmptyRange() throws {
        var record = try HistFixtures.record("build-box")
        record.history = HubHistory(daily: [], monthly: [], summary: nil)
        record.today = UsagePeriod()
        record.todayEndsAt = nil
        let snapshot = FixedRanges.deviceSnapshot(selection: .last7, record: record, now: HistFixtures.now, firstWeekday: 1, calendar: DayKey.utcCalendar)
        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertEqual(snapshot.range, DayKeyRange(start: "2026-10-04", end: "2026-10-10"))
        XCTAssertEqual(snapshot.daily.count, 7)
        XCTAssertEqual(snapshot.period?.totalTokens, 0)
        XCTAssertEqual(snapshot.summary, .empty)

        // With usage but no day window, the device cannot be placed.
        var unplaced = try HistFixtures.record("build-box")
        unplaced.todayWindowKey = nil
        XCTAssertEqual(
            FixedRanges.deviceSnapshot(selection: .last7, record: unplaced, now: HistFixtures.now, firstWeekday: 1).status,
            .unavailable(.historyUnavailable)
        )
        XCTAssertEqual(
            FixedRanges.deviceSnapshot(selection: .allTime, record: unplaced, now: HistFixtures.now, firstWeekday: 1).status,
            .native
        )
    }

    /// Compares a snapshot with `slimFixedSnapshot` output.
    private func assertSnapshot(_ snapshot: FixedRangeSnapshot, golden: [String: Any], context: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let status = try XCTUnwrap(golden["status"] as? String)
        switch snapshot.status {
        case .ready: XCTAssertEqual(status, "ready", context, file: file, line: line)
        case .native: XCTAssertEqual(status, "native", context, file: file, line: line)
        case .unavailable(let reason):
            XCTAssertEqual(status, "unavailable", context, file: file, line: line)
            XCTAssertEqual(golden["reason"] as? String, reason.rawValue, context, file: file, line: line)
        }
        // `fixedPeriodSnapshotFromDevices` leaves `selection` out of its
        // unavailable results.
        if let selection = golden["selection"] as? String {
            XCTAssertEqual(snapshot.selection.rawValue, selection, context, file: file, line: line)
        }
        let range = golden["range"] as? [String: Any]
        XCTAssertEqual(snapshot.range?.start, range?["start"] as? String, context, file: file, line: line)
        XCTAssertEqual(snapshot.range?.end, range?["end"] as? String, context, file: file, line: line)
        guard status == "ready" else {
            XCTAssertNil(snapshot.period, context, file: file, line: line)
            return
        }
        let daily = try XCTUnwrap(golden["daily"] as? [[String: Any]])
        XCTAssertEqual(snapshot.daily.map(\.date), daily.compactMap { $0["date"] as? String }, context, file: file, line: line)
        for (row, expected) in zip(snapshot.daily, daily) {
            let rowContext = "\(context) \(row.date)"
            XCTAssertEqual(row.tokens, int(expected["tokens"]), rowContext, file: file, line: line)
            assertClose(row.costUsd, number(expected["cost"]), rowContext, file: file, line: line)
            XCTAssertEqual(row.unpricedTokens, int(expected["unpricedTokens"]), rowContext, file: file, line: line)
            assertClose(row.activeTimeMs, number(expected["activeTimeMs"]) ?? 0, rowContext, file: file, line: line)
        }
        let summary = try XCTUnwrap(golden["summary"] as? [String: Any])
        XCTAssertEqual(snapshot.summary.activeDays, int(summary["activeDays"]), context, file: file, line: line)
        XCTAssertEqual(snapshot.summary.currentStreak, int(summary["currentStreak"]), context, file: file, line: line)
        assertClose(snapshot.summary.activeTimeMs, number(summary["activeTimeMs"]), context, file: file, line: line)
        XCTAssertEqual(snapshot.summary.peakDayTokens, int(summary["peakDayTokens"]), context, file: file, line: line)

        let period = try XCTUnwrap(snapshot.period, context, file: file, line: line)
        let expected = try XCTUnwrap(golden["period"] as? [String: Any])
        XCTAssertEqual(period.totalTokens, int(expected["totalTokens"]), context, file: file, line: line)
        assertClose(period.costUsd, number(expected["costUsd"]), context, file: file, line: line)
        XCTAssertEqual(period.unpricedTokens, int(expected["unpricedTokens"]), context, file: file, line: line)
        XCTAssertEqual(period.cacheReadTokens, int(expected["cacheReadTokens"]), context, file: file, line: line)
        XCTAssertEqual(period.cacheWriteTokens, int(expected["cacheWriteTokens"]), context, file: file, line: line)
        XCTAssertEqual(period.outputTokens, int(expected["outputTokens"]), context, file: file, line: line)
        XCTAssertEqual(period.unclassifiedTokens, int(expected["unclassifiedTokens"]), context, file: file, line: line)
        let capabilities = try XCTUnwrap(expected["capabilities"] as? [String: Any])
        XCTAssertEqual(period.hasExactTokenComponents, capabilities["tokenComponents"] as? Bool, context, file: file, line: line)
        for (prefix, breakdown) in [("client", period.clientBreakdown), ("model", period.modelBreakdown)] {
            let maps = prefix == "client"
                ? ["clients", "clientCosts", "clientUnpricedTokens", "clientCacheReads", "clientCacheWrites", "clientOutputs", "clientUnclassifiedTokens"]
                : ["models", "modelCosts", "modelUnpricedTokens", "modelCacheReads", "modelCacheWrites", "modelOutputs", "modelUnclassifiedTokens"]
            let tokens = try XCTUnwrap(expected[maps[0]] as? [String: Any], context, file: file, line: line)
            XCTAssertEqual(Set(breakdown.keys), Set(tokens.keys), "\(context) \(prefix) keys", file: file, line: line)
            let unpriced = expected[maps[2]] as? [String: Any] ?? [:]
            for (key, entry) in breakdown {
                let keyContext = "\(context) \(prefix) \(key)"
                XCTAssertEqual(entry.tokens, int(tokens[key]), keyContext, file: file, line: line)
                assertClose(entry.costUsd, number((expected[maps[1]] as? [String: Any])?[key]), keyContext, file: file, line: line)
                XCTAssertEqual(entry.unpricedTokens, int(unpriced[key]), keyContext, file: file, line: line)
                XCTAssertEqual(entry.cacheReadTokens, int((expected[maps[3]] as? [String: Any])?[key]), keyContext, file: file, line: line)
                XCTAssertEqual(entry.cacheWriteTokens, int((expected[maps[4]] as? [String: Any])?[key]), keyContext, file: file, line: line)
                XCTAssertEqual(entry.outputTokens, int((expected[maps[5]] as? [String: Any])?[key]), keyContext, file: file, line: line)
                XCTAssertEqual(entry.unclassifiedTokens, int((expected[maps[6]] as? [String: Any])?[key]), keyContext, file: file, line: line)
            }
        }
        let components = try XCTUnwrap(golden["components"] as? [String: Any])
        let mine = period.components
        XCTAssertEqual(mine.cacheRead, int(components["cacheRead"]), context, file: file, line: line)
        XCTAssertEqual(mine.cacheMiss, int(components["cacheMiss"]), context, file: file, line: line)
        XCTAssertEqual(mine.output, int(components["output"]), context, file: file, line: line)
        XCTAssertEqual(mine.unclassified, int(components["unclassified"]), context, file: file, line: line)
        // Shares are the breakdown's non-empty, non-internal rows.
        XCTAssertEqual(Set(period.clients.map(\.id)), Set(period.clientBreakdown.filter { ($0.value.tokens > 0 || $0.value.costUsd > 0) && !$0.key.hasPrefix("__") }.keys), context, file: file, line: line)
        XCTAssertEqual(period.sessions, [])
        XCTAssertEqual(period.projects, [])
    }

    // MARK: Today patch and calendar fill

    func testLiveTodayReplacesOnlyWhenNotSmaller() {
        let stored = HubHistoryDay(
            date: "2026-10-10", tokens: 100, costUsd: 2, messages: 7, activeTimeMs: 60_000,
            perClient: ["claude": HistoryBucket(tokens: 100, costUsd: 2, messages: 7)]
        )
        let older = HubHistoryDay(date: "2026-10-08", tokens: 5, costUsd: 0.1)
        var live = UsagePeriod(totalTokens: 150, costUsd: 3, unpricedTokens: 400)
        live.clientBreakdown = ["claude": UsageBreakdownEntry(tokens: 150, costUsd: 3)]
        let patched = HistorySeries.dailyWithLiveToday([stored, older], todayKey: "2026-10-10", today: live)
        XCTAssertEqual(patched.map(\.date), ["2026-10-08", "2026-10-10"])
        let today = patched[1]
        XCTAssertEqual(today.tokens, 150)
        XCTAssertEqual(today.costUsd, 3)
        XCTAssertEqual(today.unpricedTokens, 150) // clamped to the day's tokens
        XCTAssertEqual(today.messages, 7)
        XCTAssertEqual(today.activeTimeMs, 60_000)
        XCTAssertEqual(today.perClient["claude"]?.messages, 7)
        XCTAssertEqual(today.perClient["claude"]?.tokens, 150)

        var smaller = UsagePeriod(totalTokens: 90, costUsd: 9)
        smaller.clientBreakdown = [:]
        XCTAssertEqual(HistorySeries.dailyWithLiveToday([stored], todayKey: "2026-10-10", today: smaller), [stored])
        XCTAssertEqual(HistorySeries.dailyWithLiveToday([stored], todayKey: "2026-10-10", today: nil), [stored])
        XCTAssertEqual(HistorySeries.dailyWithLiveToday([stored], todayKey: "bad", today: live), [stored])

        let appended = HistorySeries.dailyWithLiveToday([older], todayKey: "2026-10-11", today: live)
        XCTAssertEqual(appended.map(\.date), ["2026-10-08", "2026-10-11"])
        XCTAssertEqual(appended.last?.messages, 0)

        let compact = HistorySeries.dailyWithLiveToday(
            [HistoryDay(date: "2026-10-10", tokens: 100, costUsd: 2, activeTimeMs: 5)],
            todayKey: "2026-10-10",
            today: live
        )
        XCTAssertEqual(compact, [HistoryDay(date: "2026-10-10", tokens: 150, costUsd: 3, activeTimeMs: 5, unpricedTokens: 150)])
    }

    func testLiveRowComponents() {
        // Exact: the remainder is input that missed the cache, never unclassified.
        var exact = UsagePeriod(totalTokens: 100, outputTokens: 10, cacheReadTokens: 60, cacheWriteTokens: 5, hasExactTokenComponents: true)
        exact.modelBreakdown = ["m": UsageBreakdownEntry(tokens: 100, cacheReadTokens: 60, outputTokens: 10)]
        let exactRow = HistorySeries.liveRow(exact, date: "2026-10-10", previous: nil)
        XCTAssertEqual(exactRow.unclassifiedTokens, 0)
        XCTAssertTrue(exactRow.tokenComponentsAvailable)
        XCTAssertEqual(exactRow.perModel["m"]?.unclassifiedTokens, 0)

        // Not exact, no explicit map: the remainder is unclassified.
        var loose = UsagePeriod(totalTokens: 100, outputTokens: 10, cacheReadTokens: 60, cacheWriteTokens: 5, hasExactTokenComponents: false)
        loose.clientBreakdown = ["claude": UsageBreakdownEntry(tokens: 40, cacheReadTokens: 30)]
        let looseRow = HistorySeries.liveRow(loose, date: "2026-10-10", previous: nil)
        XCTAssertEqual(looseRow.unclassifiedTokens, 25)
        XCTAssertEqual(looseRow.perClient["claude"]?.unclassifiedTokens, 10)

        // Explicit unclassified maps are clamped into the remainder.
        var explicit = loose
        explicit.unclassifiedTokens = 999
        explicit.clientBreakdown = ["claude": UsageBreakdownEntry(tokens: 40, cacheReadTokens: 30, unclassifiedTokens: 4), "codex": UsageBreakdownEntry(tokens: 20)]
        explicit.explicitUnclassified = [.period, .clients]
        let explicitRow = HistorySeries.liveRow(explicit, date: "2026-10-10", previous: nil)
        XCTAssertEqual(explicitRow.unclassifiedTokens, 25)
        XCTAssertEqual(explicitRow.perClient["claude"]?.unclassifiedTokens, 4)
        XCTAssertEqual(explicitRow.perClient["codex"]?.unclassifiedTokens, 0)

        // The Tokscale alias folds into its parent.
        var aliased = UsagePeriod(totalTokens: 30)
        aliased.clientBreakdown = ["antigravity": UsageBreakdownEntry(tokens: 10), "antigravity-cli": UsageBreakdownEntry(tokens: 20)]
        XCTAssertEqual(HistorySeries.liveRow(aliased, date: "2026-10-10", previous: nil).perClient["antigravity"]?.tokens, 30)
    }

    func testRangesFillCalendarDays() {
        let daily = [
            HubHistoryDay(date: "2026-10-01", tokens: 1),
            HubHistoryDay(date: "2026-10-05", tokens: 5),
            HubHistoryDay(date: "2026-10-10", tokens: 10)
        ]
        let week = HistorySeries.range(.days7, daily: daily, todayKey: "2026-10-10")
        XCTAssertEqual(week.map(\.date), ["2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10"])
        XCTAssertEqual(week.map(\.tokens), [0, 5, 0, 0, 0, 0, 10])
        XCTAssertEqual(week[0], HubHistoryDay(date: "2026-10-04", unclassifiedTokens: 0, tokenComponentsAvailable: true))
        XCTAssertEqual(HistorySeries.range(.all, daily: daily, todayKey: "2026-10-10").count, 10)
        XCTAssertEqual(HistorySeries.range(.all, daily: [HubHistoryDay](), todayKey: "2026-10-10").map(\.date), ["2026-10-10"])
        XCTAssertEqual(HistorySeries.range(.days365, daily: daily, todayKey: "2026-10-10").count, 365)
        XCTAssertEqual(HistorySeries.range(.days7, daily: daily, todayKey: "bad"), [])

        let compact = daily.map(\.historyDay)
        XCTAssertEqual(HistorySeries.range(.days30, daily: compact, todayKey: "2026-10-10").count, 30)
        XCTAssertEqual(HistorySeries.range(.days7, daily: compact, todayKey: "2026-10-10").map(\.tokens), [0, 5, 0, 0, 0, 0, 10])
        XCTAssertEqual(TrendSeriesBuilder.line(days: HistorySeries.range(.days7, daily: compact, todayKey: "2026-10-10"), metric: .tokens).map(\.value), [0, 5, 0, 0, 0, 0, 10])
    }

    func testPreviewFallback() throws {
        let stats = try HistFixtures.stats()
        let preview = HistorySeries.previewFallback(stats: stats)
        XCTAssertEqual(preview.daily.map(\.date), stats.history.map(\.date))
        XCTAssertEqual(preview.daily.map(\.tokens), stats.history.map(\.tokens))
        XCTAssertTrue(preview.daily.allSatisfy { $0.perClient.isEmpty && $0.perModel.isEmpty })
        XCTAssertEqual(preview.monthly.map(\.month), stats.historyMonths.map(\.month))
        XCTAssertEqual(preview.summary?.activeDays, stats.historyPreviewSummary?.activeDays)
        XCTAssertEqual(preview.summary?.favoriteModel, stats.historyPreviewSummary?.favoriteModel)
        // Bars from the preview cannot stack.
        let bars = TrendSeriesBuilder.bars(days: HistorySeries.range(.days7, daily: preview.daily, todayKey: HistFixtures.todayKey), stack: .client, metric: .tokens)
        XCTAssertEqual(bars.keys, [])
    }

    /// The Hub omits a tool bucket's `unclassifiedTokens` when it is 0,
    /// and the desktop then counts the whole bucket as unclassified.
    func testDerivedPeriodReadsBucketsWithoutUnclassifiedAsWhollyUnclassified() {
        let row = HubHistoryDay(
            date: "2026-10-10", tokens: 100, costUsd: 1.0000004, cacheReadTokens: 60, cacheWriteTokens: 0, outputTokens: 10,
            unclassifiedTokens: 30, tokenComponentsAvailable: false,
            perClient: [
                "claude": HistoryBucket(tokens: 70, costUsd: 0.7000004, cacheReadTokens: 60, outputTokens: 10),
                "antigravity-cli": HistoryBucket(tokens: 30, costUsd: 0.3, unclassifiedTokens: 30)
            ],
            perModel: ["m": HistoryBucket(tokens: 100, costUsd: 1, cacheReadTokens: 60, outputTokens: 10, unclassifiedTokens: 30)]
        )
        let period = FixedRanges.derivePeriod(daily: [row], range: DayKeyRange(start: "2026-10-09", end: "2026-10-10"))
        XCTAssertEqual(period.totalTokens, 100)
        XCTAssertEqual(period.costUsd, 1)
        XCTAssertEqual(period.unclassifiedTokens, 30)
        XCTAssertEqual(period.clientBreakdown["claude"]?.unclassifiedTokens, 70)
        XCTAssertEqual(period.clientBreakdown["claude"]?.costUsd, 0.7)
        XCTAssertEqual(period.clientBreakdown["antigravity"]?.unclassifiedTokens, 30)
        XCTAssertNil(period.clientBreakdown["antigravity-cli"])
        XCTAssertEqual(period.modelBreakdown["m"]?.unclassifiedTokens, 30)
        // The zero-filled 2026-10-09 is exact, the real row is not.
        XCTAssertFalse(period.hasExactTokenComponents)
        XCTAssertEqual(period.explicitUnclassified, .all)
        XCTAssertEqual(period.clients.map(\.id), ["claude", "antigravity"])
        XCTAssertNil(period.unpricedTokens)
    }

    // MARK: Stat cards, breakdowns, insights

    func testStatCardsOrderAndKinds() {
        let summary = HistorySummary(totalTokens: 1, totalCost: 2, activeDays: 3, currentStreak: 4, longestStreak: 9, peakDayTokens: 5, favoriteModel: nil, messages: 6, activeTimeMs: 7_500_000, unpricedTokens: 8)
        XCTAssertEqual(StatCards.cards(summary: summary).map(\.value), [
            .tokens(1), .cost(usd: 2, unpricedTokens: 8), .days(3), .days(4), .duration(milliseconds: 7_500_000), .tokens(5), .model(nil), .count(6)
        ])
        XCTAssertTrue(StatCards.durationParts(milliseconds: 15_402_060_000) == (4278, 21))
        XCTAssertTrue(StatCards.durationParts(milliseconds: 29_999) == (0, 0))
        XCTAssertTrue(StatCards.durationParts(milliseconds: 30_000) == (0, 1))
        XCTAssertTrue(StatCards.durationParts(milliseconds: -5) == (0, 0))
    }

    /// Expected rows computed with `dashboard.js` `renderBreakdown`'s logic in
    /// node over `history.json` (grand total 12,081,352,697).
    func testHistoryBreakdownMatchesDashboard() throws {
        let daily = try HistFixtures.history().daily
        let clients = HistoryBreakdown.topClients(daily: daily)
        XCTAssertEqual(clients.map(\.key), ["claude", "codex", "hermes", "gemini", "opencode"])
        XCTAssertEqual(clients.map(\.tokens), [10_650_101_494, 1_296_613_986, 80_994_045, 32_012_692, 21_510_480])
        XCTAssertEqual(clients.map(\.percentLabel), ["88.2", "10.7", "0.7", "0.3", "0.2"])
        XCTAssertEqual(clients[1].fractionOfMax, 0.1217466318729901, accuracy: 1e-15)
        XCTAssertEqual(clients[0].fractionOfMax, 1)
        let models = HistoryBreakdown.topModels(daily: daily)
        XCTAssertEqual(models.map(\.key), ["claude-sonnet-4-5", "claude-sonnet-4", "gpt-5-codex", "claude-opus-4-1", "deepseek-chat"])
        XCTAssertEqual(models.map(\.percentLabel), ["51.6", "35.5", "10.7", "1.1", "0.6"])
        XCTAssertEqual(models[1].fractionOfMax, 0.6873590365286044, accuracy: 1e-15)
        XCTAssertEqual(HistoryBreakdown.topModels(daily: daily, limit: 2).count, 2)
        XCTAssertEqual(HistoryBreakdown.topClients(daily: []), [])
    }

    func testActivityStatsFollowTheSelection() throws {
        let patched = try HistFixtures.patchedAggregate()
        let summary = try XCTUnwrap(HistFixtures.history().summary)
        let today = HistoryInsights.activityStats(selection: .today, fixedRange: nil, daily: patched, summary: summary, todayKey: HistFixtures.todayKey)
        XCTAssertEqual(today.activeDays, summary.activeDays)
        XCTAssertEqual(today.currentStreak, summary.currentStreak)
        XCTAssertEqual(today.peakDayTokens, patched.last?.tokens)
        let all = HistoryInsights.activityStats(selection: .allTime, fixedRange: nil, daily: patched, summary: summary, todayKey: HistFixtures.todayKey)
        XCTAssertEqual(all.peakDayTokens, summary.peakDayTokens)
        XCTAssertEqual(all.activeTimeMs, summary.activeTimeMs)
        let month = HistoryInsights.activityStats(selection: .month, fixedRange: nil, daily: patched, summary: summary, todayKey: HistFixtures.todayKey)
        XCTAssertEqual(month.activeTimeMs, patched.filter { $0.date.hasPrefix("2026-10") }.reduce(0) { $0 + $1.activeTimeMs })
        let range = FixedRanges.snapshot(selection: .last7, daily: patched, todayKey: HistFixtures.todayKey, today: nil, historyAvailable: true, firstWeekday: 1)
        let fixed = HistoryInsights.activityStats(selection: .last7, fixedRange: range, daily: patched, summary: summary, todayKey: HistFixtures.todayKey)
        XCTAssertEqual(fixed.activeTimeMs, range.summary.activeTimeMs)
        XCTAssertEqual(fixed.peakDayTokens, range.summary.peakDayTokens)
    }

    func testLocaleCompareTieBreak() {
        let ids = ["gpt-5", "GPT-5", "gpt5", "gpt-5-codex", "gpt_5", "gpt.5", "claude-sonnet-4-5", "claude-sonnet-4.5", "claude/sonnet", "Claude", "claude", "a1", "a10", "a2", "ab", "a-b", "b", "z"]
        // `ids.sort((a, b) => a.localeCompare(b))` in node 22 (ICU root).
        XCTAssertEqual(ids.sorted { TrendKeyCollation.compare($0, $1) < 0 }, [
            "a-b", "a1", "a10", "a2", "ab", "b", "claude", "Claude", "claude-sonnet-4-5", "claude-sonnet-4.5", "claude/sonnet",
            "gpt_5", "gpt-5", "GPT-5", "gpt-5-codex", "gpt.5", "gpt5", "z"
        ])
        XCTAssertEqual(TrendKeyCollation.compare("same", "same"), 0)
    }

    // MARK: Activity snapshot (App Group, Activity widget)

    func testActivitySnapshotReproducesTheAppHeatmap() throws {
        let patched = try HistFixtures.patchedAggregate()
        let summary = try HistFixtures.history().summary
        let generatedAt = HistFixtures.now
        let snapshot = ActivitySnapshot(
            daily: patched.map(\.historyDay),
            todayKey: HistFixtures.todayKey,
            hubKey: "hub",
            scopeDeviceID: nil,
            generatedAt: generatedAt,
            summary: summary
        )
        // Every History row (370-day cap) fits, so the scale is the app's.
        XCTAssertEqual(snapshot.startDay, "2025-10-06")
        XCTAssertEqual(snapshot.endDay, HistFixtures.todayKey)
        XCTAssertEqual(snapshot.tokens.count, 370)
        XCTAssertEqual(snapshot.costMicros.count, 370)
        XCTAssertEqual(snapshot.tokens.last, 73_237_000)
        XCTAssertEqual(snapshot.costMicros.last, 157_411_400)

        for metric in HeatmapMetric.allCases {
            let app = HeatmapBuilder.rollingYear(daily: patched, metric: metric, todayKey: HistFixtures.todayKey)
            let widget = snapshot.heatmap(metric: metric, todayKey: HistFixtures.todayKey)
            XCTAssertEqual(widget.cells.map(\.date), app.cells.map(\.date))
            XCTAssertEqual(widget.cells.map(\.level), app.cells.map(\.level), "\(metric)")
            XCTAssertEqual(widget.cells.map(\.tokens), app.cells.map(\.tokens))
            XCTAssertEqual(widget.monthLabels, app.monthLabels)
            XCTAssertEqual(widget.weeks, app.weeks)
            for (left, right) in zip(widget.cells, app.cells) {
                XCTAssertEqual(left.costUsd, right.costUsd, accuracy: 1e-6)
            }
        }
        let grid = snapshot.heatmap(metric: .cost, today: generatedAt, calendar: DayKey.utcCalendar)
        XCTAssertEqual(grid.endDate, HistFixtures.todayKey)
        XCTAssertEqual(snapshot.activeDays(window: .all, grid: grid), summary?.activeDays)
        XCTAssertEqual(snapshot.activeDays(window: .year, grid: grid), grid.activeDayCount)
        XCTAssertEqual(snapshot.peakDayTokens, 73_237_000)

        // A day later the grid moves on and today reads empty.
        let tomorrow = snapshot.heatmap(metric: .cost, today: generatedAt.addingTimeInterval(86_400), calendar: DayKey.utcCalendar)
        XCTAssertEqual(tomorrow.cells.last?.date, "2026-10-11")
        XCTAssertEqual(tomorrow.cells.last?.level, 0)
        XCTAssertEqual(tomorrow.cell(on: HistFixtures.todayKey)?.tokens, 73_237_000)
        // A device whose own day is ahead of the phone's keeps its last day.
        let ahead = ActivitySnapshot(daily: [HistoryDay(date: "2026-10-11", tokens: 5, costUsd: 1)], todayKey: "2026-10-11", hubKey: "hub", scopeDeviceID: "tokyo-mac", generatedAt: generatedAt)
        XCTAssertEqual(ahead.heatmap(metric: .tokens, today: generatedAt, calendar: DayKey.utcCalendar).cells.last?.level, 4)
    }

    func testActivitySnapshotFitsItsBudget() throws {
        let patched = try HistFixtures.patchedAggregate()
        let snapshot = ActivitySnapshot(daily: patched.map(\.historyDay), hubKey: String(repeating: "h", count: 64), scopeDeviceID: "studio-mac", generatedAt: HistFixtures.now, calendar: DayKey.utcCalendar)
        XCTAssertLessThanOrEqual(try snapshot.jsonData().count, ActivitySnapshot.maxEncodedBytes)

        // A heavy fleet: 100 billion tokens and $100,000 every day for the
        // longest possible window.
        let heavy = (0..<400).map { offset in
            HistoryDay(date: CivilDay.key(CivilDay.number("2026-12-31")! - offset), tokens: 99_999_999_999, costUsd: 99_999.999999)
        }
        let worst = ActivitySnapshot(daily: heavy, todayKey: "2026-12-31", hubKey: String(repeating: "h", count: 64), scopeDeviceID: String(repeating: "d", count: 64), generatedAt: HistFixtures.now, summary: HistorySummary(activeDays: 9999, peakDayTokens: 99_999_999_999))
        XCTAssertEqual(worst.tokens.count, ActivitySnapshot.maxDays)
        XCTAssertEqual(worst.startDay, "2025-12-25")
        XCTAssertLessThanOrEqual(try worst.jsonData().count, ActivitySnapshot.maxEncodedBytes)
    }

    func testActivitySnapshotWindowAndZeroFill() {
        let snapshot = ActivitySnapshot(
            daily: [
                HistoryDay(date: "2026-10-08", tokens: 12, costUsd: 1.25),
                HistoryDay(date: "2026-10-12", tokens: 99, costUsd: 9) // after today: dropped
            ],
            todayKey: "2026-10-10",
            hubKey: "hub",
            scopeDeviceID: nil,
            generatedAt: HistFixtures.now
        )
        // No older rows: the window is the grid's (the Sunday before 2025-11-01).
        XCTAssertEqual(snapshot.startDay, "2025-10-26")
        XCTAssertEqual(snapshot.tokens.count, 350)
        XCTAssertEqual(Array(snapshot.tokens.suffix(3)), [12, 0, 0])
        XCTAssertEqual(Array(snapshot.costMicros.suffix(3)), [1_250_000, 0, 0])
        XCTAssertEqual(snapshot.days.last, HistoryDay(date: "2026-10-10", tokens: 0, costUsd: 0))
        XCTAssertNil(snapshot.summaryActiveDays)
        XCTAssertEqual(snapshot.peakDayTokens, 12)

        // The calendar initializer reads today from the generation date.
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let ahead = ActivitySnapshot(daily: [], hubKey: nil, scopeDeviceID: nil, generatedAt: HistFixtures.now, calendar: tokyo)
        XCTAssertEqual(ahead.endDay, "2026-10-11")
    }

    func testActivitySnapshotCodableAndOwnership() throws {
        let snapshot = ActivitySnapshot(
            hubKey: "hub-a", scopeDeviceID: "studio-mac", generatedAt: HistFixtures.now,
            startDay: "2026-10-08", tokens: [0, 12, 3], costMicros: [0, 1_250_000, 7],
            summaryActiveDays: 3, summaryPeakDayTokens: 40
        )
        let data = try snapshot.jsonData()
        XCTAssertEqual(try ActivitySnapshot(jsonData: data), snapshot)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"generatedAt\":\"2026-10-10T16:30:00"), text)

        XCTAssertTrue(snapshot.belongs(toHubKey: "hub-a", scope: .device("studio-mac")))
        XCTAssertFalse(snapshot.belongs(toHubKey: "hub-a", scope: .all))
        XCTAssertFalse(snapshot.belongs(toHubKey: "hub-b", scope: .device("studio-mac")))
        XCTAssertFalse(snapshot.belongs(toHubKey: nil, scope: .device("studio-mac")))
        var legacy = snapshot
        legacy.hubKey = nil
        legacy.scopeDeviceID = nil
        XCTAssertTrue(legacy.belongs(toHubKey: "hub-b", scope: .all))
        XCTAssertFalse(snapshot.isOlder(than: 86_400, at: HistFixtures.now.addingTimeInterval(3_600)))
        XCTAssertTrue(snapshot.isOlder(than: 86_400, at: HistFixtures.now.addingTimeInterval(90_000)))

        // Lenient: mismatched arrays are padded, a bad start day is refused.
        let padded = try ActivitySnapshot(jsonData: Data(#"{"schemaVersion":1,"generatedAt":"2026-10-10T16:30:00Z","startDay":"2026-10-09","tokens":[1,2],"costMicros":[5]}"#.utf8))
        XCTAssertEqual(padded.costMicros, [5, 0])
        XCTAssertEqual(padded.endDay, "2026-10-10")
        XCTAssertThrowsError(try ActivitySnapshot(jsonData: Data(#"{"generatedAt":"2026-10-10T16:30:00Z","startDay":"soon","tokens":[],"costMicros":[]}"#.utf8)))
    }

    func testActivitySnapshotStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("activity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActivitySnapshotStore(directory: directory)
        XCTAssertNil(store.load())
        XCTAssertEqual(store.fileURL.lastPathComponent, "activity.json")
        let snapshot = ActivitySnapshot(hubKey: "hub", scopeDeviceID: nil, generatedAt: HistFixtures.now, startDay: "2026-10-10", tokens: [5], costMicros: [9])
        try store.save(snapshot)
        XCTAssertEqual(store.load(), snapshot)
        XCTAssertEqual(store.load(hubKey: "hub", scope: .all), snapshot)
        XCTAssertNil(store.load(hubKey: "other", scope: .all))
        XCTAssertNil(store.load(hubKey: "hub", scope: .device("x")))

        var newer = snapshot
        newer.schemaVersion = ActivitySnapshot.currentSchemaVersion + 1
        try store.save(newer)
        XCTAssertNil(store.load())
        try store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        try store.clear()
        XCTAssertEqual(ActivitySnapshot.widgetKind, "TokenMonitorActivityWidget")
    }
}

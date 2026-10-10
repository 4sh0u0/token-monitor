import Foundation

// Port of `src/shared/exporter.js` (the desktop "Data export" file set) for the
// iOS share sheet. Pure and Foundation-only: Hub bytes in, file bytes out, so it
// is testable on Linux and never touches the file system.
//
// The desktop writes its objects in insertion order. Swift dictionaries cannot
// keep wire order, so by decision D-EXPORT the output is content-equivalent but
// deterministic instead: nested JSON object keys are sorted, and CSV rows are
// sorted (snapshot by period, then tool before model, then name; daily files by
// date, then name). Everything else - headers, column order, BOM, CRLF, number
// text, which files exist - matches the desktop byte for byte.

// MARK: - Public types

/// One generated file of the export set.
public struct ExportFile: Sendable, Equatable {
    /// One of ``ExportSerializer/fileNames``.
    public let name: String
    /// UTF-8 bytes; the CSV files start with a byte-order mark.
    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }

    /// The file text (a CSV keeps its leading U+FEFF).
    public var contents: String { String(decoding: data, as: UTF8.self) }
}

/// The `app` object of the JSON export, the desktop's `meta.app`.
public struct ExportApp: Sendable, Equatable {
    public var name: String
    public var version: String?

    public init(name: String = "token-monitor", version: String? = nil) {
        self.name = name
        self.version = version
    }

    /// The desktop default, `{ "name": "token-monitor" }`.
    public static let tokenMonitor = ExportApp()
}

public enum ExportError: Error, Equatable {
    /// The `/api/stats` body is not a JSON object with an object `periods`.
    case invalidStats
    /// The `/api/history` body is not a JSON object (or `null`).
    case invalidHistory
}

/// Parsed JSON for the serializer. Unlike `JSONSerialization` it distinguishes
/// booleans from numbers on every platform and keeps numbers as the `Double`
/// JavaScript would have read, so they print exactly as the desktop prints them.
public enum ExportJSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ExportJSONValue])
    case object([String: ExportJSONValue])

    /// `nil` for malformed JSON (a UTF-8 byte-order mark is tolerated).
    public static func parse(_ data: Data) -> ExportJSONValue? {
        var parser = ExportJSONParser(bytes: [UInt8](data))
        return parser.parseDocument()
    }

    public var objectValue: [String: ExportJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [ExportJSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public subscript(key: String) -> ExportJSONValue? {
        objectValue?[key]
    }
}

/// A CSV row: column name to already formatted cell text.
public typealias ExportRow = [String: String]

// MARK: - Serializer

public enum ExportSerializer {
    public static let bom = "\u{FEFF}"
    public static let periodNames = ["today", "month", "allTime"]

    public static let snapshotColumns = ["period", "dimension", "name", "tokens", "cost_usd"]
    public static let dailyColumns = ["date", "tool", "tokens", "cost_usd"]
    public static let dailyModelColumns = [
        "date",
        "model",
        "input_tokens",
        "output_tokens",
        "cache_read_tokens",
        "cache_write_tokens",
        "unclassified_tokens",
        "total_tokens",
        "cost_usd"
    ]

    /// Every file name the export can produce, in `exportFileSet` order. The
    /// daily files exist only when their history has rows.
    public static let fileNames = [
        "token-monitor-export.json",
        "token-monitor-snapshot.csv",
        "token-monitor-daily.csv",
        "token-monitor-daily-models.csv"
    ]

    /// Session fields that quote conversation text; `SESSION_TEXT_KEYS` in
    /// `src/shared/usage.js`. They never reach the export.
    public static let sessionTextKeys: Set<String> = [
        "title", "sessionTitle", "session_title",
        "name", "preview", "firstUserMessage", "first_user_message",
        "customTitle", "custom_title", "aiTitle", "ai_title"
    ]

    // MARK: File set

    /// `exportFileSet` over the raw `/api/stats` and `/api/history` bodies. The
    /// history body is optional: without it the export is snapshot only.
    ///
    /// Throws when the stats body has no `periods` object or the history body is
    /// not a JSON object, rather than writing an empty file the user would share.
    public static func fileSet(
        statsData: Data,
        historyData: Data?,
        generatedAt: Date,
        app: ExportApp = .tokenMonitor
    ) throws -> [ExportFile] {
        guard let stats = ExportJSONValue.parse(statsData),
              let periods = stats["periods"],
              case .object = periods else {
            throw ExportError.invalidStats
        }
        var history: ExportJSONValue?
        if let historyData {
            guard let parsed = ExportJSONValue.parse(historyData) else { throw ExportError.invalidHistory }
            switch parsed {
            case .object: history = parsed
            case .null: history = nil
            default: throw ExportError.invalidHistory
            }
        }
        return fileSet(periods: periods, history: history, generatedAt: generatedAt, app: app)
    }

    /// `exportFileSet({ periods, history, meta })`. `periods` is the stats
    /// `periods` object, `history` the `/api/history` object.
    public static func fileSet(
        periods: ExportJSONValue?,
        history: ExportJSONValue?,
        generatedAt: Date,
        app: ExportApp = .tokenMonitor
    ) -> [ExportFile] {
        var files = [
            ExportFile(
                name: fileNames[0],
                data: utf8(exportJSON(periods: periods, history: history, generatedAt: generatedAt, app: app))
            ),
            ExportFile(
                name: fileNames[1],
                data: utf8(toCSV(rows: snapshotRows(periods: periods), columns: snapshotColumns))
            )
        ]
        let dailyRows = self.dailyRows(history: history)
        if !dailyRows.isEmpty {
            files.append(ExportFile(name: fileNames[2], data: utf8(toCSV(rows: dailyRows, columns: dailyColumns))))
        }
        let modelRows = dailyModelRows(history: history)
        if !modelRows.isEmpty {
            files.append(ExportFile(name: fileNames[3], data: utf8(toCSV(rows: modelRows, columns: dailyModelColumns))))
        }
        return files
    }

    // MARK: CSV

    /// `csvEscape`: quotes a cell holding a comma, a quote or a line break
    /// (`"` doubled); `nil` is an empty cell.
    public static func csvEscape(_ value: String?) -> String {
        guard let value else { return "" }
        // Scalars, not Characters: "\r\n" is a single Character that equals
        // neither "\r" nor "\n".
        let needsQuotes = value.unicodeScalars.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// `csvEscape(number)`: a number is written as JavaScript prints it.
    public static func csvEscape(_ value: Double) -> String {
        csvEscape(JSCompat.numberString(value))
    }

    /// `toCsv`: RFC 4180 with CRLF line endings, a header row and, by default,
    /// a leading UTF-8 byte-order mark for Excel. A missing cell is empty.
    public static func toCSV(rows: [ExportRow], columns: [String], bom: Bool = true) -> String {
        let header = columns.map { csvEscape($0) }.joined(separator: ",")
        let body = rows.map { row in columns.map { csvEscape(row[$0]) }.joined(separator: ",") }
        return (bom ? Self.bom : "") + ([header] + body).joined(separator: "\r\n") + "\r\n"
    }

    // MARK: Rows

    /// `buildSnapshotRows`: per period (today, month, allTime) the tool rows
    /// (`clients`, `clientCosts`) then the model rows (`models`, `modelCosts`),
    /// each sorted by name. A name present only in the cost map is not a row.
    public static func snapshotRows(periods: ExportJSONValue?) -> [ExportRow] {
        guard let source = periods?.objectValue else { return [] }
        var rows: [ExportRow] = []
        for period in periodNames {
            guard let p = source[period]?.objectValue else { continue }
            for (dimension, tokensKey, costsKey) in [("tool", "clients", "clientCosts"), ("model", "models", "modelCosts")] {
                let tokens = p[tokensKey]?.objectValue ?? [:]
                let costs = p[costsKey]?.objectValue ?? [:]
                for name in tokens.keys.sorted(by: ascending) {
                    rows.append([
                        "period": period,
                        "dimension": dimension,
                        "name": name,
                        "tokens": JSCompat.numberString(num(tokens[name])),
                        "cost_usd": JSCompat.numberString(num(costs[name]))
                    ])
                }
            }
        }
        return rows
    }

    /// `buildDailyRows`: one row per day and tool from `history.daily[].perClient`,
    /// sorted by date, then tool. A day without a date is skipped.
    public static func dailyRows(history: ExportJSONValue?) -> [ExportRow] {
        var keyed: [(date: String, name: String, row: ExportRow)] = []
        for day in dailyEntries(history) {
            let date = dateKey(day)
            if date.isEmpty { continue }
            let perClient = day["perClient"]?.objectValue ?? [:]
            for tool in perClient.keys {
                let value = perClient[tool]?.objectValue ?? [:]
                keyed.append((date, tool, [
                    "date": date,
                    "tool": tool,
                    "tokens": JSCompat.numberString(num(value["tokens"])),
                    "cost_usd": JSCompat.numberString(num(value["cost"]))
                ]))
            }
        }
        return sortedRows(keyed)
    }

    /// `buildDailyModelRows`: one row per day and model from
    /// `history.daily[].perModel`, with the token component split of
    /// ``dailyModelComponents(day:value:)``, sorted by date, then model.
    public static func dailyModelRows(history: ExportJSONValue?) -> [ExportRow] {
        var keyed: [(date: String, name: String, row: ExportRow)] = []
        for day in dailyEntries(history) {
            let date = dateKey(day)
            if date.isEmpty { continue }
            let perModel = day["perModel"]?.objectValue ?? [:]
            for model in perModel.keys {
                let value = perModel[model]?.objectValue ?? [:]
                let c = dailyModelComponents(day: day, value: value)
                keyed.append((date, model, [
                    "date": date,
                    "model": model,
                    "input_tokens": JSCompat.numberString(c.input),
                    "output_tokens": JSCompat.numberString(c.output),
                    "cache_read_tokens": JSCompat.numberString(c.cacheRead),
                    "cache_write_tokens": JSCompat.numberString(c.cacheWrite),
                    "unclassified_tokens": JSCompat.numberString(c.unclassified),
                    "total_tokens": JSCompat.numberString(c.total),
                    "cost_usd": JSCompat.numberString(num(value["cost"]))
                ]))
            }
        }
        return sortedRows(keyed)
    }

    /// The token components of one day-model entry, in tokens.
    public struct ModelComponents: Sendable, Equatable {
        public var input: Double
        public var output: Double
        public var cacheRead: Double
        public var cacheWrite: Double
        public var unclassified: Double
        public var total: Double
    }

    /// `dailyModelComponents`. A row whose known parts exceed its total keeps
    /// the trusted total and reports it all as unclassified. Otherwise the
    /// remainder is input, less an explicit `unclassifiedTokens`; without one,
    /// the remainder is unclassified unless the day says its components are
    /// available (`tokenComponentsAvailable === true`).
    public static func dailyModelComponents(day: ExportJSONValue?, value: [String: ExportJSONValue]) -> ModelComponents {
        let total = max(0, num(value["tokens"]))
        let output = max(0, num(value["outputTokens"]))
        let cacheRead = max(0, num(value["cacheReadTokens"]))
        let cacheWrite = max(0, num(value["cacheWriteTokens"]))
        let known = output + cacheRead + cacheWrite
        if known > total {
            return ModelComponents(input: 0, output: 0, cacheRead: 0, cacheWrite: 0, unclassified: total, total: total)
        }
        let remaining = total - known
        let unclassified: Double
        if let explicit = value["unclassifiedTokens"] {
            unclassified = min(remaining, max(0, num(explicit)))
        } else if day?["tokenComponentsAvailable"] == .bool(true) {
            unclassified = 0
        } else {
            unclassified = remaining
        }
        return ModelComponents(
            input: max(0, remaining - unclassified),
            output: output,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            unclassified: unclassified,
            total: total
        )
    }

    // MARK: JSON

    /// `renderExportJson`: `JSON.stringify(payload, null, 2)` plus a newline.
    /// The top level keeps the desktop's order (`generatedAt`, `app`,
    /// `snapshot`, `daily`, `monthly`); every wire object below is key-sorted.
    /// The snapshot periods are lossless except for ``sessionTextKeys``.
    public static func exportJSON(
        periods: ExportJSONValue?,
        history: ExportJSONValue?,
        generatedAt: Date,
        app: ExportApp = .tokenMonitor
    ) -> String {
        var appFields: [(String, ExportDocument)] = [("name", .value(.string(app.name)))]
        if let version = app.version { appFields.append(("version", .value(.string(version)))) }
        let document = ExportDocument.fields([
            ("generatedAt", .value(.string(isoString(generatedAt)))),
            ("app", .fields(appFields)),
            ("snapshot", .fields(periodNames.map { ($0, .value(periodSnapshot(periods, $0))) })),
            ("daily", .value(.array(history?["daily"]?.arrayValue ?? []))),
            ("monthly", .value(.array(history?["monthly"]?.arrayValue ?? [])))
        ])
        var out = ""
        render(document, depth: 0, into: &out)
        return out + "\n"
    }

    /// `stripSessionTextFromPeriod` with `preserveSessionTitles: false`:
    /// removes every ``sessionTextKeys`` field from each session of a period
    /// and keeps everything else (ids, counters, `sessionKind`).
    public static func stripSessionText(from period: ExportJSONValue) -> ExportJSONValue {
        guard case .object(var fields) = period, let sessions = fields["sessions"] else { return period }
        func strip(_ session: ExportJSONValue) -> ExportJSONValue {
            guard case .object(var f) = session else { return session }
            for key in sessionTextKeys { f.removeValue(forKey: key) }
            return .object(f)
        }
        switch sessions {
        case .object(let map):
            fields["sessions"] = .object(map.mapValues(strip))
        case .array(let items):
            // `Object.entries` on an array: an object keyed by index.
            fields["sessions"] = .object(Dictionary(uniqueKeysWithValues: items.enumerated().map { (String($0.offset), strip($0.element)) }))
        default: return period
        }
        return .object(fields)
    }

    // MARK: - Internals

    private static func periodSnapshot(_ periods: ExportJSONValue?, _ key: String) -> ExportJSONValue {
        guard let p = periods?[key], case .object = p else { return .object([:]) }
        return stripSessionText(from: p)
    }

    private static func utf8(_ text: String) -> Data { Data(text.utf8) }

    /// Code point order, the same on every platform and locale.
    private static func ascending(_ a: String, _ b: String) -> Bool {
        a.utf8.lexicographicallyPrecedes(b.utf8)
    }

    private static func sortedRows(_ keyed: [(date: String, name: String, row: ExportRow)]) -> [ExportRow] {
        keyed.enumerated().sorted { lhs, rhs in
            if lhs.element.date != rhs.element.date { return ascending(lhs.element.date, rhs.element.date) }
            if lhs.element.name != rhs.element.name { return ascending(lhs.element.name, rhs.element.name) }
            return lhs.offset < rhs.offset
        }.map { $0.element.row }
    }

    private static func dailyEntries(_ history: ExportJSONValue?) -> [ExportJSONValue] {
        (history?["daily"]?.arrayValue ?? []).filter { $0.objectValue != nil }
    }

    /// `String(day.date || '').slice(0, 10)`.
    private static func dateKey(_ day: ExportJSONValue) -> String {
        let text = jsString(day["date"])
        return String(decoding: Array(text.utf16.prefix(10)), as: UTF16.self)
    }

    /// `String(value || '')`.
    private static func jsString(_ value: ExportJSONValue?) -> String {
        switch value {
        case .string(let s)?: return s
        case .number(let n)?: return n == 0 || n.isNaN ? "" : JSCompat.numberString(n)
        case .bool(let b)?: return b ? "true" : ""
        case .array(let items)?: return items.map { item in
            if case .null = item { return "" }
            return jsString(item)
        }.joined(separator: ",")
        case .object?: return "[object Object]"
        case .null?, nil: return ""
        }
    }

    /// `num`: a finite number as is, anything else through `Number(value)`,
    /// and 0 when that is not finite.
    static func num(_ value: ExportJSONValue?) -> Double {
        switch value {
        case .number(let n)?: return n.isFinite ? n : 0
        case .bool(let b)?: return b ? 1 : 0
        case .string(let s)?:
            let n = jsNumber(s)
            return n.isFinite ? n : 0
        default: return 0
        }
    }

    /// `Number(string)`: trimmed decimal, `0x`/`0o`/`0b` literals, empty is 0,
    /// anything else NaN (which `num` then maps to 0 like an infinity).
    private static func jsNumber(_ raw: String) -> Double {
        var scalars = Array(raw.unicodeScalars)
        func isSpace(_ s: Unicode.Scalar) -> Bool {
            s == "\u{FEFF}" || CharacterSet.whitespacesAndNewlines.contains(s)
        }
        while let first = scalars.first, isSpace(first) { scalars.removeFirst() }
        while let last = scalars.last, isSpace(last) { scalars.removeLast() }
        if scalars.isEmpty { return 0 }
        let text = String(String.UnicodeScalarView(scalars))

        if scalars.count > 2, scalars[0] == "0" {
            let radix: Int?
            switch scalars[1] {
            case "x", "X": radix = 16
            case "o", "O": radix = 8
            case "b", "B": radix = 2
            default: radix = nil
            }
            if let radix {
                var result = 0.0
                for digit in scalars.dropFirst(2) {
                    guard let d = Int(String(digit), radix: radix) else { return .nan }
                    result = result * Double(radix) + Double(d)
                }
                return result
            }
        }

        // StrDecimalLiteral: sign? (digits [. digits?] | . digits) exponent?
        var i = 0
        func digits() -> Int {
            let start = i
            while i < scalars.count, ("0"..."9").contains(scalars[i]) { i += 1 }
            return i - start
        }
        if i < scalars.count, scalars[i] == "+" || scalars[i] == "-" { i += 1 }
        let whole = digits()
        var fraction = 0
        if i < scalars.count, scalars[i] == "." {
            i += 1
            fraction = digits()
        }
        guard whole + fraction > 0 else { return .nan }
        if i < scalars.count, scalars[i] == "e" || scalars[i] == "E" {
            i += 1
            if i < scalars.count, scalars[i] == "+" || scalars[i] == "-" { i += 1 }
            guard digits() > 0 else { return .nan }
        }
        guard i == scalars.count else { return .nan }
        return Double(text) ?? .nan
    }

    // MARK: JSON rendering

    private static func render(_ document: ExportDocument, depth: Int, into out: inout String) {
        switch document {
        case .value(let value):
            render(value, depth: depth, into: &out)
        case .fields(let fields):
            renderObject(fields.map { ($0.0, $0.1) }, depth: depth, into: &out)
        }
    }

    private static func renderObject(_ fields: [(String, ExportDocument)], depth: Int, into out: inout String) {
        if fields.isEmpty {
            out += "{}"
            return
        }
        let inner = String(repeating: "  ", count: depth + 1)
        out += "{\n"
        for (index, field) in fields.enumerated() {
            out += inner + JSCompat.jsonQuoted(field.0) + ": "
            render(field.1, depth: depth + 1, into: &out)
            out += index == fields.count - 1 ? "\n" : ",\n"
        }
        out += String(repeating: "  ", count: depth) + "}"
    }

    private static func render(_ value: ExportJSONValue, depth: Int, into out: inout String) {
        switch value {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n.isFinite ? JSCompat.numberString(n) : "null"
        case .string(let s): out += JSCompat.jsonQuoted(s)
        case .array(let items):
            if items.isEmpty {
                out += "[]"
                return
            }
            let inner = String(repeating: "  ", count: depth + 1)
            out += "[\n"
            for (index, item) in items.enumerated() {
                out += inner
                render(item, depth: depth + 1, into: &out)
                out += index == items.count - 1 ? "\n" : ",\n"
            }
            out += String(repeating: "  ", count: depth) + "]"
        case .object(let map):
            renderObject(map.keys.sorted(by: ascending).map { ($0, .value(map[$0]!)) }, depth: depth, into: &out)
        }
    }

    /// `Date.prototype.toISOString`: UTC, millisecond precision.
    private static func isoString(_ date: Date) -> String {
        let seconds = date.timeIntervalSince1970
        let rounded = seconds.isFinite ? (seconds * 1000).rounded() : 0
        let clamped = min(max(rounded, -8.64e15), 8.64e15)
        let totalMilliseconds = Int64(clamped)
        let day = Int64((Double(totalMilliseconds) / 86_400_000).rounded(.down))
        let millisecondOfDay = Int(totalMilliseconds - day * 86_400_000)

        // Days since 1970-01-01 to a proleptic Gregorian date (H. Hinnant).
        let z = day + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let dayOfMonth = Int(dayOfYear - (153 * monthIndex + 2) / 5 + 1)
        let month = Int(monthIndex < 10 ? monthIndex + 3 : monthIndex - 9)
        let year = Int(yearOfEra + era * 400) + (month <= 2 ? 1 : 0)

        func pad(_ value: Int, _ width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        let yearText = (0...9999).contains(year)
            ? pad(year, 4)
            : (year < 0 ? "-" : "+") + pad(abs(year), 6)
        let hours = millisecondOfDay / 3_600_000
        let minutes = millisecondOfDay / 60_000 % 60
        let secondsOfMinute = millisecondOfDay / 1000 % 60
        let milliseconds = millisecondOfDay % 1000
        return "\(yearText)-\(pad(month, 2))-\(pad(dayOfMonth, 2))T\(pad(hours, 2)):\(pad(minutes, 2)):\(pad(secondsOfMinute, 2)).\(pad(milliseconds, 3))Z"
    }
}

// MARK: - Rendering document

/// What the JSON renderer writes: objects the exporter authors itself keep their
/// field order, while parsed wire values are rendered with sorted keys.
private indirect enum ExportDocument {
    case fields([(String, ExportDocument)])
    case value(ExportJSONValue)
}

// MARK: - Parser

/// A strict JSON parser (RFC 8259) with a depth limit. Duplicate keys: the
/// last one wins, as in `JSON.parse`.
private struct ExportJSONParser {
    let bytes: [UInt8]
    var index = 0
    static let maxDepth = 256

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func parseDocument() -> ExportJSONValue? {
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { index = 3 }
        skipWhitespace()
        guard let value = parseValue(depth: 0) else { return nil }
        skipWhitespace()
        return index == bytes.count ? value : nil
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0A || bytes[index] == 0x0D {
            index += 1
        }
    }

    private mutating func parseValue(depth: Int) -> ExportJSONValue? {
        guard index < bytes.count, depth <= Self.maxDepth else { return nil }
        switch bytes[index] {
        case UInt8(ascii: "{"): return parseObject(depth: depth)
        case UInt8(ascii: "["): return parseArray(depth: depth)
        case UInt8(ascii: "\""): return parseString().map { .string($0) }
        case UInt8(ascii: "t"): return literal("true", .bool(true))
        case UInt8(ascii: "f"): return literal("false", .bool(false))
        case UInt8(ascii: "n"): return literal("null", .null)
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return parseNumber()
        default: return nil
        }
    }

    private mutating func literal(_ word: String, _ value: ExportJSONValue) -> ExportJSONValue? {
        let expected = Array(word.utf8)
        guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else { return nil }
        index += expected.count
        return value
    }

    private mutating func parseObject(depth: Int) -> ExportJSONValue? {
        index += 1
        var map: [String: ExportJSONValue] = [:]
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .object(map)
        }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\""), let key = parseString() else { return nil }
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
            index += 1
            skipWhitespace()
            guard let value = parseValue(depth: depth + 1) else { return nil }
            map[key] = value
            skipWhitespace()
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
            } else if bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object(map)
            } else {
                return nil
            }
        }
    }

    private mutating func parseArray(depth: Int) -> ExportJSONValue? {
        index += 1
        var items: [ExportJSONValue] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return .array(items)
        }
        while true {
            skipWhitespace()
            guard let value = parseValue(depth: depth + 1) else { return nil }
            items.append(value)
            skipWhitespace()
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
            } else if bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array(items)
            } else {
                return nil
            }
        }
    }

    private mutating func parseNumber() -> ExportJSONValue? {
        let start = index
        func digits() -> Int {
            let first = index
            while index < bytes.count, bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9") { index += 1 }
            return index - first
        }
        if bytes[index] == UInt8(ascii: "-") { index += 1 }
        guard index < bytes.count else { return nil }
        if bytes[index] == UInt8(ascii: "0") {
            index += 1
        } else if digits() == 0 {
            return nil
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            guard digits() > 0 else { return nil }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard digits() > 0 else { return nil }
        }
        guard let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else { return nil }
        return .number(value)
    }

    private mutating func parseString() -> String? {
        index += 1
        var buffer: [UInt8] = []
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                return String(decoding: buffer, as: UTF8.self)
            case 0x00..<0x20:
                return nil
            case UInt8(ascii: "\\"):
                guard index < bytes.count else { return nil }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""): buffer.append(UInt8(ascii: "\""))
                case UInt8(ascii: "\\"): buffer.append(UInt8(ascii: "\\"))
                case UInt8(ascii: "/"): buffer.append(UInt8(ascii: "/"))
                case UInt8(ascii: "b"): buffer.append(0x08)
                case UInt8(ascii: "f"): buffer.append(0x0C)
                case UInt8(ascii: "n"): buffer.append(0x0A)
                case UInt8(ascii: "r"): buffer.append(0x0D)
                case UInt8(ascii: "t"): buffer.append(0x09)
                case UInt8(ascii: "u"):
                    guard let unit = hexUnit() else { return nil }
                    var scalar = UInt32(unit)
                    if (0xD800...0xDBFF).contains(unit) {
                        // A high surrogate needs the low half that follows it.
                        if index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
                            let saved = index
                            index += 2
                            if let low = hexUnit(), (0xDC00...0xDFFF).contains(low) {
                                scalar = 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(low) - 0xDC00)
                            } else {
                                index = saved
                                scalar = 0xFFFD
                            }
                        } else {
                            scalar = 0xFFFD
                        }
                    } else if (0xDC00...0xDFFF).contains(unit) {
                        scalar = 0xFFFD
                    }
                    buffer.append(contentsOf: Array(String(Unicode.Scalar(scalar) ?? "\u{FFFD}").utf8))
                default:
                    return nil
                }
            default:
                buffer.append(byte)
            }
        }
        return nil
    }

    private mutating func hexUnit() -> UInt16? {
        guard index + 4 <= bytes.count else { return nil }
        var value: UInt16 = 0
        for offset in 0..<4 {
            let byte = bytes[index + offset]
            let digit: UInt16
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt16(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt16(byte - UInt8(ascii: "a")) + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt16(byte - UInt8(ascii: "A")) + 10
            default: return nil
            }
            value = value << 4 | digit
        }
        index += 4
        return value
    }
}

import Foundation

/// One day of the Hub's History preview (`historyPreview.daily`, the latest
/// 30 days across all devices) or of a trend built from it.
public struct HistoryDay: Sendable, Hashable, Identifiable {
    /// Calendar day key `yyyy-MM-dd`. Producers key days by their own local
    /// calendar, so treat it as a calendar date, not an instant.
    public var date: String
    public var tokens: Int
    public var costUsd: Double

    public var id: String { date }

    public init(date: String, tokens: Int, costUsd: Double) {
        self.date = date
        self.tokens = tokens
        self.costUsd = costUsd
    }

    /// The start of this day in `calendar` (for chart axes), nil when the key
    /// is not a valid `yyyy-MM-dd` date.
    public func startOfDay(in calendar: Calendar = .current) -> Date? {
        DayKey.date(from: date, calendar: calendar)
    }
}

extension HistoryDay: Codable {
    private enum CodingKeys: String, CodingKey {
        case date, tokens, cost
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let date = container.lenientString(.date), DayKey.isValid(date) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: container, debugDescription: "invalid day key")
        }
        self.init(
            date: date,
            tokens: nonNegative(container.lenientInt(.tokens) ?? 0),
            costUsd: nonNegative(container.lenientDouble(.cost) ?? 0)
        )
    }

    /// Wire field names (`cost`, not `costUsd`), like the History preview.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(tokens, forKey: .tokens)
        try container.encode(costUsd, forKey: .cost)
    }
}

/// One month of `historyPreview.monthly` (latest 12 months).
public struct HistoryMonth: Sendable, Hashable, Identifiable {
    /// `yyyy-MM`.
    public var month: String
    public var tokens: Int
    public var costUsd: Double

    public var id: String { month }

    public init(month: String, tokens: Int, costUsd: Double) {
        self.month = month
        self.tokens = tokens
        self.costUsd = costUsd
    }
}

extension HistoryMonth: Decodable {
    private enum CodingKeys: String, CodingKey {
        case month, tokens, cost
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let month = container.lenientString(.month),
              month.count == 7, DayKey.isValid("\(month)-01") else {
            throw DecodingError.dataCorruptedError(forKey: .month, in: container, debugDescription: "invalid month key")
        }
        self.init(
            month: month,
            tokens: nonNegative(container.lenientInt(.tokens) ?? 0),
            costUsd: nonNegative(container.lenientDouble(.cost) ?? 0)
        )
    }
}

/// `yyyy-MM-dd` day keys in an explicit calendar.
public enum DayKey {
    public static func string(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(padded(parts.year ?? 0, 4))-\(padded(parts.month ?? 0, 2))-\(padded(parts.day ?? 0, 2))"
    }

    private static func padded(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    public static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              string(from: date, calendar: calendar) == key else { return nil }
        return date
    }

    static func isValid(_ key: String) -> Bool {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? utc.timeZone
        return date(from: key, calendar: utc) != nil
    }
}

enum TrendBuilder {
    /// The last `days` calendar days ending at `endingAt`'s day, with missing
    /// days as zero and today as the greater of History and the live `today`
    /// period — the macOS widget's rule, because History may already hold
    /// part or all of today and adding the two would double count.
    static func daily(
        history: [HistoryDay],
        liveToday: UsagePeriod,
        days: Int,
        endingAt: Date,
        calendar: Calendar
    ) -> [HistoryDay] {
        let count = max(0, days)
        guard count > 0 else { return [] }
        let liveTokens = liveToday.totalTokens
        let liveCost = liveToday.costUsd
        guard !history.isEmpty || liveTokens > 0 || liveCost > 0 else { return [] }
        let byDate = Dictionary(history.map { ($0.date, $0) }, uniquingKeysWith: { first, second in
            HistoryDay(date: first.date, tokens: max(first.tokens, second.tokens), costUsd: max(first.costUsd, second.costUsd))
        })
        let today = calendar.startOfDay(for: endingAt)
        let todayKey = DayKey.string(from: today, calendar: calendar)
        var points: [HistoryDay] = []
        points.reserveCapacity(count)
        for offset in stride(from: -(count - 1), through: 0, by: 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let key = DayKey.string(from: day, calendar: calendar)
            let stored = byDate[key]
            if key == todayKey {
                points.append(HistoryDay(
                    date: key,
                    tokens: max(stored?.tokens ?? 0, liveTokens),
                    costUsd: max(stored?.costUsd ?? 0, liveCost)
                ))
            } else {
                points.append(stored ?? HistoryDay(date: key, tokens: 0, costUsd: 0))
            }
        }
        return points
    }
}

import Foundation

/// One day of the Hub's History preview (`historyPreview.daily`, the latest
/// 30 days across all devices) or of a trend built from it.
public struct HistoryDay: Sendable, Hashable, Identifiable {
    /// Calendar day key `yyyy-MM-dd`. Producers key days by their own local
    /// calendar, so treat it as a calendar date, not an instant.
    public var date: String
    public var tokens: Int
    /// The known (priced) subtotal in USD.
    public var costUsd: Double
    /// Active time in milliseconds; nil when the wire says 0 or nothing
    /// (the desktop reads both as 0).
    public var activeTimeMs: Double?
    /// Tokens with no price (`costUsd` excludes them), clamped to `tokens`
    /// like the desktop's `unpricedTokensFor`; nil when there are none.
    public var unpricedTokens: Int?

    public var id: String { date }

    public init(date: String, tokens: Int, costUsd: Double, activeTimeMs: Double? = nil, unpricedTokens: Int? = nil) {
        self.date = date
        self.tokens = tokens
        self.costUsd = costUsd
        self.activeTimeMs = activeTimeMs
        self.unpricedTokens = unpricedTokens
    }

    /// The start of this day in `calendar` (for chart axes), nil when the key
    /// is not a valid `yyyy-MM-dd` date.
    public func startOfDay(in calendar: Calendar = .current) -> Date? {
        DayKey.date(from: date, calendar: calendar)
    }
}

extension HistoryDay: Codable {
    private enum CodingKeys: String, CodingKey {
        case date, tokens, cost, activeTimeMs, unpricedTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let date = container.lenientString(.date), DayKey.isValid(date) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: container, debugDescription: "invalid day key")
        }
        let tokens = nonNegative(container.lenientInt(.tokens) ?? 0)
        self.init(
            date: date,
            tokens: tokens,
            costUsd: nonNegative(container.lenientDouble(.cost) ?? 0),
            activeTimeMs: HistoryWire.positive(container.lenientDouble(.activeTimeMs)),
            unpricedTokens: HistoryWire.unpriced(container.lenientDouble(.unpricedTokens), tokens: tokens)
        )
    }

    /// Wire field names (`cost`, not `costUsd`), like the History preview.
    /// The optional fields are written only when present, so a day without
    /// them encodes exactly as it did before they existed (cached snapshots).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(tokens, forKey: .tokens)
        try container.encode(costUsd, forKey: .cost)
        try container.encodeIfPresent(activeTimeMs, forKey: .activeTimeMs)
        try container.encodeIfPresent(unpricedTokens, forKey: .unpricedTokens)
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

    /// A strict `yyyy-MM-dd` key of a real date. Integer arithmetic
    /// (`CivilDay`) rather than `Calendar`: History decoding validates every
    /// row, and streaks step through every active day.
    static func isValid(_ key: String) -> Bool {
        CivilDay.parts(key) != nil
    }

    /// The key `days` calendar days after `key` (negative: before), stepped
    /// in UTC like the desktop's `dayKeyAddDays` (proleptic Gregorian, as
    /// JavaScript dates are); nil for an invalid key or a result outside
    /// years 0000–9999.
    public static func adding(days: Int, to key: String) -> String? {
        CivilDay.adding(days, to: key)
    }

    /// The valid `yyyy-MM-dd` prefix of `value` (the desktop's
    /// `String(date).slice(0, 10)` plus validation), else nil.
    static func normalized(_ value: String) -> String? {
        CivilDay.normalized(value)
    }

    static let utcCalendar: Calendar = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? utc.timeZone
        return utc
    }()
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
        // Rows carry date, tokens and cost only, as they always have: this
        // series feeds the snapshot's sparkline, which has a size budget.
        let byDate = Dictionary(history.map { ($0.date, HistoryDay(date: $0.date, tokens: $0.tokens, costUsd: $0.costUsd)) }, uniquingKeysWith: { first, second in
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

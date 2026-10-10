import Foundation

/// One point of the smooth area line (the Home "Trend").
public struct TrendLinePoint: Sendable, Hashable, Identifiable {
    /// `yyyy-MM-dd`.
    public var date: String
    public var value: Double

    public var id: String { date }

    public init(date: String, value: Double) {
        self.date = date
        self.value = value
    }
}

/// One stacked segment of a trend bar: a tool or model and its value.
public struct TrendBarSegment: Sendable, Hashable, Identifiable {
    /// Client id or model name.
    public var key: String
    public var value: Double

    public var id: String { key }

    public init(key: String, value: Double) {
        self.key = key
        self.value = value
    }
}

/// One day's stacked bar.
public struct TrendBar: Sendable, Hashable, Identifiable {
    /// `yyyy-MM-dd`.
    public var date: String
    public var total: Double
    public var segments: [TrendBarSegment]

    public var id: String { date }

    public init(date: String, total: Double, segments: [TrendBarSegment]) {
        self.date = date
        self.total = total
        self.segments = segments
    }
}

/// The stacked-bars chart.
public struct TrendBarsModel: Sendable, Hashable {
    /// Stack keys in legend and stacking order.
    public var keys: [String]
    public var bars: [TrendBar]
    public var maxTotal: Double

    public init(keys: [String], bars: [TrendBar], maxTotal: Double) {
        self.keys = keys
        self.bars = bars
        self.maxTotal = maxTotal
    }

    public static let empty = TrendBarsModel(keys: [], bars: [], maxTotal: 0)
}

/// One K-line candle: `days` consecutive calendar days aggregated to OHLC
/// (open = first day, close = last day, high/low = busiest/quietest day).
public struct TrendCandle: Sendable, Hashable, Identifiable {
    /// First day of the bucket, `yyyy-MM-dd`.
    public var key: String
    /// Last day of the bucket.
    public var endKey: String
    /// Days with data in the bucket.
    public var days: Int
    public var open: Double
    public var high: Double
    public var low: Double
    public var close: Double
    /// `close >= open`.
    public var up: Bool

    public var id: String { key }

    public init(key: String, endKey: String, days: Int, open: Double, high: Double, low: Double, close: Double, up: Bool) {
        self.key = key
        self.endKey = endKey
        self.days = days
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.up = up
    }
}

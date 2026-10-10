import Foundation

/// One day of input to the Activity mosaic.
public struct HeatmapDay: Sendable, Hashable, Identifiable {
    /// `yyyy-MM-dd`.
    public var date: String
    public var tokens: Int
    /// The known (priced) subtotal in USD.
    public var costUsd: Double
    /// Tokens with no price, nil when the source does not say.
    public var unpricedTokens: Int?

    public var id: String { date }

    public init(date: String, tokens: Int, costUsd: Double, unpricedTokens: Int? = nil) {
        self.date = date
        self.tokens = tokens
        self.costUsd = costUsd
        self.unpricedTokens = unpricedTokens
    }
}

/// One cell of the mosaic: a calendar day in a Sunday-first week column.
public struct HeatmapCell: Sendable, Hashable, Identifiable {
    /// `yyyy-MM-dd`.
    public var date: String
    /// Week column, 0 = the leftmost (oldest) week.
    public var column: Int
    /// Day of the week, 0 = Sunday … 6 = Saturday, whatever the locale.
    public var row: Int
    /// Intensity 0–4 (0 = no usage).
    public var level: Int
    public var tokens: Int
    public var costUsd: Double
    public var unpricedTokens: Int?

    public var id: String { date }

    public init(date: String, column: Int, row: Int, level: Int, tokens: Int, costUsd: Double, unpricedTokens: Int? = nil) {
        self.date = date
        self.column = column
        self.row = row
        self.level = level
        self.tokens = tokens
        self.costUsd = costUsd
        self.unpricedTokens = unpricedTokens
    }
}

/// A month label, placed on the column that contains the month's 1st.
public struct HeatmapMonthLabel: Sendable, Hashable, Identifiable {
    public var column: Int
    /// `yyyy-MM`; the target formats it as a localized short month.
    public var month: String

    public var id: String { month }

    public init(column: Int, month: String) {
        self.column = column
        self.month = month
    }
}

/// The laid-out Activity mosaic.
public struct HeatmapGrid: Sendable, Hashable {
    /// Every day from the Sunday on or before `startDate` through `endDate`,
    /// oldest first.
    public var cells: [HeatmapCell]
    /// The number of week columns.
    public var weeks: Int
    public var monthLabels: [HeatmapMonthLabel]
    /// The window's first day (`yyyy-MM-dd`), "" for `.empty`.
    public var startDate: String
    /// The window's last day, normally today (`yyyy-MM-dd`), "" for `.empty`.
    public var endDate: String
    /// What `level` was computed from.
    public var metric: HeatmapMetric

    public init(cells: [HeatmapCell], weeks: Int, monthLabels: [HeatmapMonthLabel], startDate: String, endDate: String, metric: HeatmapMetric) {
        self.cells = cells
        self.weeks = weeks
        self.monthLabels = monthLabels
        self.startDate = startDate
        self.endDate = endDate
        self.metric = metric
    }

    public static let empty = HeatmapGrid(cells: [], weeks: 0, monthLabels: [], startDate: "", endDate: "", metric: .cost)
}

/// The name the Activity widget's contract (`ActivitySnapshot`) uses for the
/// mosaic; the same type as `HeatmapGrid`.
public typealias HeatmapModel = HeatmapGrid

/// The compact daily activity the app writes to the App Group for the
/// Activity widget, which never decodes `/api/history` itself.
///
/// One entry per calendar day from `startDay` through the day it was
/// generated (at most 372), zero-filled and already patched with live today.
public struct ActivitySnapshot: Codable, Sendable, Equatable {
    /// The format version this build writes.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// `HubConnection.snapshotKey` of the Hub it came from.
    public var hubKey: String?
    /// The scoped device, nil for all devices.
    public var scopeDeviceID: String?
    public var generatedAt: Date
    /// `yyyy-MM-dd` of `tokens[0]` / `costMicros[0]`.
    public var startDay: String
    public var tokens: [Int]
    /// USD × 1_000_000, rounded.
    public var costMicros: [Int]

    public init(
        schemaVersion: Int = ActivitySnapshot.currentSchemaVersion,
        hubKey: String?,
        scopeDeviceID: String?,
        generatedAt: Date,
        startDay: String,
        tokens: [Int],
        costMicros: [Int]
    ) {
        self.schemaVersion = schemaVersion
        self.hubKey = hubKey
        self.scopeDeviceID = scopeDeviceID
        self.generatedAt = generatedAt
        self.startDay = startDay
        self.tokens = tokens
        self.costMicros = costMicros
    }
}

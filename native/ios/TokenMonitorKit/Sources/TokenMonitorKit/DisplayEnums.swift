import Foundation

// The closed value sets behind the display preferences (`DisplayPreferences`)
// and the views that read them. String raw values are the desktop settings
// values where the desktop has the setting, so a stored preference reads the
// same on both. Int raw values are the stored numbers themselves.
//
// Nothing here is user-facing text: the targets localize each case.

/// `compactTokenUnits`: K/M/B everywhere, or the UI language's own
/// myriad units (万/亿, 萬/億, 万/億, 만/억) where it has them.
public enum CompactTokenUnits: String, Sendable, Codable, CaseIterable, Identifiable {
    case western
    case localized

    public var id: String { rawValue }
}

/// `currency`: what costs are shown in. Costs are always converted from USD.
public enum DisplayCurrency: String, Sendable, Codable, CaseIterable, Identifiable {
    case usd = "USD"
    case twd = "TWD"
    case hkd = "HKD"
    case cny = "CNY"

    public var id: String { rawValue }

    /// The ISO 4217 code (`"USD"`).
    public var code: String { rawValue }

    /// The desktop's symbol (`currency.js` `CURRENCY_RATES`), written directly
    /// before the amount with no space: `$`, `NT$`, `HK$`, `¥`.
    public var symbol: String {
        switch self {
        case .usd: return "$"
        case .twd: return "NT$"
        case .hkd: return "HK$"
        case .cny: return "¥"
        }
    }
}

/// `periodMonthMode`: what the middle period segment shows.
public enum PeriodMonthMode: String, Sendable, Codable, CaseIterable, Identifiable {
    case month
    case week
    case last7
    case last30

    public var id: String { rawValue }
}

/// A period a view can show: the Hub's three native periods plus the fixed
/// ranges derived from history. Raw values are also the `period` values of
/// the `tokenmonitor://dashboard?period=` deep link.
public enum PeriodSelection: String, Sendable, Codable, CaseIterable, Identifiable {
    case today
    case month
    case week
    case last7
    case last30
    case allTime

    public var id: String { rawValue }

    public init(_ kind: UsagePeriodKind) {
        switch kind {
        case .today: self = .today
        case .month: self = .month
        case .allTime: self = .allTime
        }
    }

    /// The Hub period this selection reads directly, nil for a fixed range.
    public var nativeKind: UsagePeriodKind? {
        switch self {
        case .today: return .today
        case .month: return .month
        case .allTime: return .allTime
        case .week, .last7, .last30: return nil
        }
    }

    /// Derived from history rather than read from a Hub period.
    public var isDerived: Bool { nativeKind == nil }

    /// The middle segment for a `periodMonthMode`.
    public static func middle(for mode: PeriodMonthMode) -> PeriodSelection {
        switch mode {
        case .month: return .month
        case .week: return .week
        case .last7: return .last7
        case .last30: return .last30
        }
    }
}

/// `deviceScope`: every device (the Hub aggregate) or one device.
///
/// Codable as a single string, `"all"` or `"device:<id>"`; anything else
/// fails to decode (lenient readers fall back to `.all`).
public enum DeviceScope: Sendable, Hashable {
    case all
    case device(String)

    private static let devicePrefix = "device:"

    /// The scoped device's Hub id, nil for `.all`.
    public var deviceID: String? {
        switch self {
        case .all: return nil
        case .device(let id): return id
        }
    }

    public var isAll: Bool { deviceID == nil }

    /// The stored form. A `.device` with a blank id stores as `"all"`.
    public var storageValue: String {
        switch self {
        case .all: return "all"
        case .device(let id):
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "all" : Self.devicePrefix + trimmed
        }
    }

    /// Parses the stored form; nil when it is neither `"all"` nor
    /// `"device:<non-blank id>"`.
    public init?(storageValue: String) {
        let value = storageValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "all" {
            self = .all
            return
        }
        guard value.hasPrefix(Self.devicePrefix) else { return nil }
        let id = value.dropFirst(Self.devicePrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        self = .device(id)
    }
}

extension DeviceScope: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let scope = DeviceScope(storageValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid device scope \"\(raw)\"")
        }
        self = scope
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageValue)
    }
}

/// `heatmapMetric`: what the Activity mosaic's intensity follows.
public enum HeatmapMetric: String, Sendable, Codable, CaseIterable, Identifiable {
    case tokens
    case cost

    public var id: String { rawValue }
}

/// `homeActiveDaysWindow`: whether the active-days chip counts all history or
/// the rolling year.
public enum ActiveDaysWindow: String, Sendable, Codable, CaseIterable, Identifiable {
    case all
    case year

    public var id: String { rawValue }
}

/// `modelRankingMetric`: what model rows are ranked by.
public enum RankingMetric: String, Sendable, Codable, CaseIterable, Identifiable {
    case tokens
    case cost

    public var id: String { rawValue }
}

/// `sessionContextMetric`: whether a session's context gauge reads used or
/// remaining.
public enum ContextMetric: String, Sendable, Codable, CaseIterable, Identifiable {
    case used
    case remaining

    public var id: String { rawValue }
}

/// `tokenRateMode`: the live rate as output speed (tok/s) or burn (TPM).
public enum TokenRateMode: String, Sendable, Codable, CaseIterable, Identifiable {
    case speed
    case burn

    public var id: String { rawValue }
}

/// `liveTokenRateScope`: every device, or the device chosen by the device
/// scope (`.all` behaviour while no device is scoped).
public enum LiveRateScope: String, Sendable, Codable, CaseIterable, Identifiable {
    case all
    case device

    public var id: String { rawValue }
}

/// Overview (Home) modules: the desktop's Home modules plus the iOS-only
/// `components` card.
public enum HomeModule: String, Sendable, Codable, CaseIterable, Identifiable {
    case components
    case limits
    case tool
    case model
    case session
    case device
    case trends

    public var id: String { rawValue }

    /// `homeModuleOrder` default: the desktop's order with `components` first.
    public static let defaultOrder: [HomeModule] = [.components, .limits, .tool, .model, .session, .device, .trends]

    /// `hiddenHomeModules` default, as on the desktop.
    public static let defaultHidden: [HomeModule] = [.tool, .device]
}

/// `homeLimitDisplayMode`: the Home limits module as text or bars.
public enum HomeLimitDisplayMode: String, Sendable, Codable, CaseIterable, Identifiable {
    case text
    case bars

    public var id: String { rawValue }
}

/// `appRefreshSeconds`: live SSE updates, or polling every N seconds while the
/// app is active.
public enum AppRefreshMode: Int, Sendable, Codable, CaseIterable, Identifiable {
    case live = 0
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    public var id: Int { rawValue }

    public static let defaultValue: AppRefreshMode = .live
}

/// `widgetRefreshMinutes`: the iOS widgets' reload interval in minutes.
public enum WidgetRefreshInterval: Int, Sendable, Codable, CaseIterable, Identifiable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60

    public var id: Int { rawValue }

    public static let defaultValue: WidgetRefreshInterval = .fifteenMinutes
}

/// `watchRefreshSeconds`: how often the watch app polls while on screen, in
/// seconds.
public enum WatchRefreshInterval: Int, Sendable, Codable, CaseIterable, Identifiable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case fifteenMinutes = 900

    public var id: Int { rawValue }

    public static let defaultValue: WatchRefreshInterval = .oneMinute
}

/// `complicationRefreshMinutes`: the watch complications' reload interval in
/// minutes.
public enum ComplicationRefreshInterval: Int, Sendable, Codable, CaseIterable, Identifiable {
    case twentyMinutes = 20
    case thirtyMinutes = 30
    case oneHour = 60

    public var id: Int { rawValue }

    public static let defaultValue: ComplicationRefreshInterval = .twentyMinutes
}

/// `serviceStatusRefreshMs`: the Status tab's re-check interval in
/// milliseconds (the desktop's unit), 0 for manual.
public enum ServiceStatusRefresh: Int, Sendable, Codable, CaseIterable, Identifiable {
    case manual = 0
    case oneMinute = 60_000
    case twoMinutes = 120_000
    case fiveMinutes = 300_000
    case fifteenMinutes = 900_000
    case thirtyMinutes = 1_800_000

    public var id: Int { rawValue }

    public static let defaultValue: ServiceStatusRefresh = .oneMinute
}

/// The Trends view's chart style (app-local, not a shared preference).
public enum TrendChartMode: String, Sendable, Codable, CaseIterable, Identifiable {
    case bars
    case line
    case kline

    public var id: String { rawValue }
}

/// The Trends view's range: the last N calendar days ending today, or all
/// history.
public enum TrendRange: String, Sendable, Codable, CaseIterable, Identifiable {
    case days7 = "7"
    case days30 = "30"
    case days90 = "90"
    case days365 = "365"
    case all

    public var id: String { rawValue }

    /// The number of calendar days, nil for `.all`.
    public var dayCount: Int? { Int(rawValue) }
}

/// What the Trends bars are stacked by.
public enum TrendStack: String, Sendable, Codable, CaseIterable, Identifiable {
    case client
    case model

    public var id: String { rawValue }
}

/// The value a trend chart plots.
public enum TrendMetricKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case tokens
    case cost

    public var id: String { rawValue }
}

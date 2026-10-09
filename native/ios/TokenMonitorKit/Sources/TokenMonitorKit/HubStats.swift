import Foundation

/// The decoded `GET /api/stats` response (also the `stats` of every
/// `snapshot`/`stats` SSE event).
///
/// Decoding is lenient: a missing or malformed field becomes its empty value
/// instead of failing the response. Only a body that is not a JSON object
/// throws. Session, project and per-device History detail on the wire is not
/// decoded.
public struct HubStats: Sendable, Equatable {
    /// When the Hub built this aggregate (Hub clock).
    public var updatedAt: Date?
    /// The Hub's stale threshold (`staleAfterMs`), in seconds.
    public var staleAfter: TimeInterval?
    public var today: UsagePeriod
    public var month: UsagePeriod
    public var allTime: UsagePeriod
    /// Provider accounts in the Hub's order (provider id, then account); use
    /// `LimitProvider.sortedForDisplay(_:)` for presentation order.
    public var limits: [LimitProvider]
    public var limitsUpdatedAt: Date?
    /// Sorted by device id, like the Hub.
    public var devices: [DeviceSummary]
    /// The History preview's daily rows (latest 30 days, ascending). Empty
    /// when no device shares History.
    public var history: [HistoryDay]
    /// The History preview's monthly rows (latest 12 months, ascending).
    public var historyMonths: [HistoryMonth]
    /// Some device omitted or could not attribute its project rollup.
    public var projectsIncomplete: Bool

    public init(
        updatedAt: Date? = nil,
        staleAfter: TimeInterval? = nil,
        today: UsagePeriod = .empty,
        month: UsagePeriod = .empty,
        allTime: UsagePeriod = .empty,
        limits: [LimitProvider] = [],
        limitsUpdatedAt: Date? = nil,
        devices: [DeviceSummary] = [],
        history: [HistoryDay] = [],
        historyMonths: [HistoryMonth] = [],
        projectsIncomplete: Bool = false
    ) {
        self.updatedAt = updatedAt
        self.staleAfter = staleAfter
        self.today = today
        self.month = month
        self.allTime = allTime
        self.limits = limits
        self.limitsUpdatedAt = limitsUpdatedAt
        self.devices = devices
        self.history = history
        self.historyMonths = historyMonths
        self.projectsIncomplete = projectsIncomplete
    }

    public subscript(period: UsagePeriodKind) -> UsagePeriod {
        get {
            switch period {
            case .today: return today
            case .month: return month
            case .allTime: return allTime
            }
        }
        set {
            switch period {
            case .today: today = newValue
            case .month: month = newValue
            case .allTime: allTime = newValue
            }
        }
    }

    public var onlineDeviceCount: Int { devices.filter(\.isOnline).count }

    /// The newest time the Hub heard from any device — how fresh the data
    /// is, as opposed to when it was fetched.
    public var newestDeviceActivity: Date? { devices.compactMap(\.lastSeen).max() }

    /// Every device is stale, so the numbers describe the past (the macOS
    /// widget's `sourceStale`). False when there are no devices.
    public var isSourceStale: Bool { !devices.isEmpty && devices.allSatisfy(\.isStale) }

    /// A daily series for the last `days` days ending at `endingAt`, missing
    /// days as zero and today as the greater of History and the live `today`
    /// period. Empty when there is neither History nor usage today.
    public func dailyTrend(days: Int = 14, endingAt: Date = Date(), calendar: Calendar = .current) -> [HistoryDay] {
        TrendBuilder.daily(history: history, liveToday: today, days: days, endingAt: endingAt, calendar: calendar)
    }

    /// Decodes a stats body, mapping failures to `HubClientError.decoding`.
    public static func decode(from data: Data) throws -> HubStats {
        do {
            return try JSONDecoder().decode(HubStats.self, from: data)
        } catch {
            throw HubClientError.decoding(String(describing: error))
        }
    }
}

extension HubStats: Decodable {
    private enum CodingKeys: String, CodingKey {
        case updatedAt, staleAfterMs, periods, limits, devices, historyPreview, projectsIncomplete
    }

    private enum PeriodKeys: String, CodingKey {
        case today, month, allTime
    }

    private enum LimitsKeys: String, CodingKey {
        case updatedAt, providers
    }

    private enum HistoryKeys: String, CodingKey {
        case daily, monthly
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let periods = try? container.nestedContainer(keyedBy: PeriodKeys.self, forKey: .periods)
        let limits = try? container.nestedContainer(keyedBy: LimitsKeys.self, forKey: .limits)
        let history = try? container.nestedContainer(keyedBy: HistoryKeys.self, forKey: .historyPreview)
        let updatedAt = container.lenientDate(.updatedAt)

        var providers = limits?.lenientArray(.providers, of: LimitProvider.self) ?? []
        // Rows without an account key (or sharing one) get ordinals, so ids
        // stay unique and stable in Hub order.
        var seen: [String: Int] = [:]
        for index in providers.indices {
            let base = providers[index].id
            let count = (seen[base] ?? 0) + 1
            seen[base] = count
            if base.hasSuffix("-anonymous") || count > 1 {
                providers[index].id = "\(base)-\(count)"
            }
        }

        var devices = container.lenientArray(.devices, of: DeviceSummary.self)
        let reference = updatedAt ?? Date()
        for index in devices.indices { devices[index].applyPeriodExpiry(now: reference) }

        self.init(
            updatedAt: updatedAt,
            staleAfter: container.lenientDouble(.staleAfterMs).map { $0 / 1000 },
            today: periods?.lenientObject(.today, as: UsagePeriod.self) ?? .empty,
            month: periods?.lenientObject(.month, as: UsagePeriod.self) ?? .empty,
            allTime: periods?.lenientObject(.allTime, as: UsagePeriod.self) ?? .empty,
            limits: providers,
            limitsUpdatedAt: limits?.lenientDate(.updatedAt),
            devices: devices,
            history: (history?.lenientArray(.daily, of: HistoryDay.self) ?? []).sorted { $0.date < $1.date },
            historyMonths: (history?.lenientArray(.monthly, of: HistoryMonth.self) ?? []).sorted { $0.month < $1.month },
            projectsIncomplete: container.lenientBool(.projectsIncomplete) ?? false
        )
    }
}

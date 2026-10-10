import Foundation

/// The operating-system family of a device's `platform` (`darwin-arm64` →
/// `.macOS`).
public enum DevicePlatformFamily: String, Sendable, Codable {
    case macOS
    case windows
    case linux
    case other

    init(platform: String?) {
        switch platform?.lowercased().split(separator: "-").first.map(String.init) {
        case "darwin": self = .macOS
        case "win32": self = .windows
        case "linux": self = .linux
        default: self = .other
        }
    }
}

/// One device's contribution to one period.
public struct DeviceUsage: Sendable, Equatable {
    public var tokens: Int
    public var costUsd: Double
    /// Tools on this device, tokens descending.
    public var clients: [UsageShare]
    /// The device's `today`/`month` window has ended (it went offline before
    /// midnight / month end). The Hub no longer counts it in the aggregate,
    /// so the Kit reports zero instead of yesterday's numbers.
    public var isExpired: Bool
    /// Tokens the cost excludes; nil when absent.
    public var unpricedTokens: Int?
    /// The period's throughput counters, nil when the device marked its
    /// throughput incomplete (`capabilities.throughput === false`) or did not
    /// send all three (`usageCounters()` in `tokenRatePresentation.js`).
    public var throughput: ThroughputCounters?
    /// `capabilities.throughput`.
    public var hasThroughput: Bool
    /// Per-model counters; nil when the wire has no `modelThroughput`.
    public var modelThroughput: [String: ThroughputCounters]?

    public init(
        tokens: Int = 0,
        costUsd: Double = 0,
        clients: [UsageShare] = [],
        isExpired: Bool = false,
        unpricedTokens: Int? = nil,
        throughput: ThroughputCounters? = nil,
        hasThroughput: Bool = false,
        modelThroughput: [String: ThroughputCounters]? = nil
    ) {
        self.tokens = tokens
        self.costUsd = costUsd
        self.clients = clients
        self.isExpired = isExpired
        self.unpricedTokens = unpricedTokens
        self.throughput = throughput
        self.hasThroughput = hasThroughput
        self.modelThroughput = modelThroughput
    }

    public static let empty = DeviceUsage()
}

/// One entry of `devices[]` in `GET /api/stats`.
public struct DeviceSummary: Sendable, Equatable, Identifiable {
    /// The device id: the stable key for lists and grouping.
    public var id: String
    /// The Devices-view name: first nonblank `displayName`, `deviceId` or
    /// `hostname`, then `device` (docs/API.md). Presentation only.
    public var displayName: String
    public var hostname: String?
    /// Node-style platform (`darwin-arm64`, `win32-x64`, `linux-x64`).
    public var platform: String?
    public var osName: String?
    public var osVersion: String?
    /// `electron-widget`, `headless-agent`, …
    public var agentRuntime: String?
    public var agentVersion: String?
    /// The Hub's freshness verdict (`staleAfterMs`, stretched for devices that
    /// upload on an interval). Stale devices stay listed, greyed out.
    public var isStale: Bool
    /// When the Hub last received from the device (`receivedAt`, else
    /// `updatedAt`).
    public var lastSeen: Date?
    /// When the device's own snapshot was taken.
    public var updatedAt: Date?
    public var trackedClients: [String]
    public var today: DeviceUsage
    public var month: DeviceUsage
    public var allTime: DeviceUsage

    /// `syncUploadIntervalMs` in seconds: 0 uploads live, otherwise the
    /// interval between uploads. Nil when the device does not say.
    public var syncUploadInterval: TimeInterval?
    /// `projectsEnabled`; nil when the device does not say (treated as on).
    public var projectsEnabled: Bool?
    /// Per-client diagnostics, when the device sends them.
    public var clientHealth: ClientHealthReport?
    /// `clientStatus`: `active`, `waiting` or `missing` per client id.
    public var clientStatus: [String: String]
    /// Session rows the device dropped to fit its upload budget, per live
    /// period. Expired periods are removed.
    public var sessionDetailsOmitted: [UsagePeriodKind: Int]
    /// Project rows the device dropped, per live period. Expired periods are
    /// removed.
    public var periodProjectsOmitted: [UsagePeriodKind: Int]
    /// The device omitted its all-time project rollup (a wire boolean).
    public var allTimeProjectsOmitted: Bool
    /// The device's all-time project rollup is known to be partial.
    public var allTimeProjectsIncomplete: Bool
    /// `periodWindows.timeZone`: the device's IANA time zone.
    public var periodTimeZone: String?
    /// `periodWindows.today.key`: the device-local day (`yyyy-MM-dd`).
    public var todayWindowKey: String?
    /// `periodWindows.month.key`: the device-local month (`yyyy-MM`).
    public var monthWindowKey: String?
    /// `periodWindows.today.endsAt`: the device's next local midnight.
    public var todayEndsAt: Date?
    /// `periodWindows.month.endsAt`: the device's next local month start.
    public var monthEndsAt: Date?
    /// The device's full periods, only for devices `HubDecodingOptions`
    /// selects (`deviceDetail`), with sessions and projects per the same
    /// options. Expired periods are removed.
    public var details: [UsagePeriodKind: UsagePeriod]
    /// The device's own limits rows (`limits.providers`), only for devices
    /// with details. A row is marked stale when the device is stale.
    public var limits: [LimitProvider]
    /// `limits.updatedAt`, only for devices with details.
    public var limitsUpdatedAt: Date?
    /// `limits.refreshMs` in seconds, only for devices with details.
    public var limitsRefreshInterval: TimeInterval?

    public init(
        id: String,
        displayName: String? = nil,
        hostname: String? = nil,
        platform: String? = nil,
        osName: String? = nil,
        osVersion: String? = nil,
        agentRuntime: String? = nil,
        agentVersion: String? = nil,
        isStale: Bool = false,
        lastSeen: Date? = nil,
        updatedAt: Date? = nil,
        trackedClients: [String] = [],
        today: DeviceUsage = .empty,
        month: DeviceUsage = .empty,
        allTime: DeviceUsage = .empty,
        syncUploadInterval: TimeInterval? = nil,
        projectsEnabled: Bool? = nil,
        clientHealth: ClientHealthReport? = nil,
        clientStatus: [String: String] = [:],
        sessionDetailsOmitted: [UsagePeriodKind: Int] = [:],
        periodProjectsOmitted: [UsagePeriodKind: Int] = [:],
        allTimeProjectsOmitted: Bool = false,
        allTimeProjectsIncomplete: Bool = false,
        periodTimeZone: String? = nil,
        todayWindowKey: String? = nil,
        monthWindowKey: String? = nil,
        todayEndsAt: Date? = nil,
        monthEndsAt: Date? = nil,
        details: [UsagePeriodKind: UsagePeriod] = [:],
        limits: [LimitProvider] = [],
        limitsUpdatedAt: Date? = nil,
        limitsRefreshInterval: TimeInterval? = nil
    ) {
        self.id = id
        self.displayName = Self.resolveName(displayName: displayName, deviceId: id, hostname: hostname)
        self.hostname = hostname
        self.platform = platform
        self.osName = osName
        self.osVersion = osVersion
        self.agentRuntime = agentRuntime
        self.agentVersion = agentVersion
        self.isStale = isStale
        self.lastSeen = lastSeen
        self.updatedAt = updatedAt
        self.trackedClients = trackedClients
        self.today = today
        self.month = month
        self.allTime = allTime
        self.syncUploadInterval = syncUploadInterval
        self.projectsEnabled = projectsEnabled
        self.clientHealth = clientHealth
        self.clientStatus = clientStatus
        self.sessionDetailsOmitted = sessionDetailsOmitted
        self.periodProjectsOmitted = periodProjectsOmitted
        self.allTimeProjectsOmitted = allTimeProjectsOmitted
        self.allTimeProjectsIncomplete = allTimeProjectsIncomplete
        self.periodTimeZone = periodTimeZone
        self.todayWindowKey = todayWindowKey
        self.monthWindowKey = monthWindowKey
        self.todayEndsAt = todayEndsAt
        self.monthEndsAt = monthEndsAt
        self.details = details
        self.limits = limits
        self.limitsUpdatedAt = limitsUpdatedAt
        self.limitsRefreshInterval = limitsRefreshInterval
    }

    /// The device's full period, nil when it was not decoded (see
    /// `HubDecodingOptions.deviceDetail`) or has expired.
    public func detail(_ period: UsagePeriodKind) -> UsagePeriod? {
        details[period]
    }

    /// `periodTimeZone` as a `TimeZone`, nil when absent or unknown.
    public var timeZone: TimeZone? { periodTimeZone.flatMap(TimeZone.init(identifier:)) }

    public var isOnline: Bool { !isStale }

    public var platformFamily: DevicePlatformFamily { DevicePlatformFamily(platform: platform) }

    /// "macOS 26.0", "Windows 11 24H2", "Ubuntu 24.04" — the desktop's
    /// `devicePlatformLabel`. Product names, so not localized.
    public var operatingSystemDescription: String? {
        let family: String?
        switch platformFamily {
        case .macOS: family = "macOS"
        case .windows: family = "Windows"
        case .linux: family = "Linux"
        case .other: family = platform
        }
        let name = osName ?? family
        let parts = [name, osVersion].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    public func usage(_ period: UsagePeriodKind) -> DeviceUsage {
        switch period {
        case .today: return today
        case .month: return month
        case .allTime: return allTime
        }
    }

    static func resolveName(displayName: String?, deviceId: String?, hostname: String?) -> String {
        for candidate in [displayName, deviceId, hostname] {
            if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return "device"
    }

    /// Port of the Hub's `isPeriodExpired()`: a `today`/`month` snapshot whose
    /// device-local window has ended is not live any more. Without
    /// `periodWindows` the Hub compares UTC day/month of `updatedAt`. An
    /// expired period is zeroed in the totals and removed from `details` and
    /// the omission counts.
    mutating func applyPeriodExpiry(now: Date) {
        if Self.isExpired(endsAt: todayEndsAt, recordedAt: updatedAt ?? lastSeen, now: now, components: [.year, .month, .day]) {
            expire(.today)
        }
        if Self.isExpired(endsAt: monthEndsAt, recordedAt: updatedAt ?? lastSeen, now: now, components: [.year, .month]) {
            expire(.month)
        }
    }

    private mutating func expire(_ period: UsagePeriodKind) {
        switch period {
        case .today: today = DeviceUsage(isExpired: true)
        case .month: month = DeviceUsage(isExpired: true)
        case .allTime: return
        }
        details[period] = nil
        sessionDetailsOmitted[period] = nil
        periodProjectsOmitted[period] = nil
    }

    private static func isExpired(endsAt: Date?, recordedAt: Date?, now: Date, components: Set<Calendar.Component>) -> Bool {
        if let endsAt { return now >= endsAt }
        guard let recordedAt else { return false }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? utc.timeZone
        return utc.dateComponents(components, from: recordedAt) != utc.dateComponents(components, from: now)
    }
}

extension DeviceSummary: Decodable {
    private enum CodingKeys: String, CodingKey {
        case deviceId, id, displayName, hostname, platform, osName, osVersion, agentRuntime, agentVersion
        case stale, receivedAt, updatedAt, trackedClients, periods, periodWindows
        case today, month, allTime
        case syncUploadIntervalMs, projectsEnabled, clientHealth, clientStatus
        case sessionDetailsOmitted, periodProjectsOmitted, allTimeProjectsOmitted, allTimeProjectsIncomplete
        case limits
    }

    private enum PeriodKeys: String, CodingKey {
        case today, month, allTime
    }

    private enum WindowKeys: String, CodingKey {
        case today, month, timeZone
    }

    private enum WindowFieldKeys: String, CodingKey {
        case endsAt, key
    }

    private enum LimitsKeys: String, CodingKey {
        case updatedAt, refreshMs, providers
    }

    private struct PeriodTotals: Decodable {
        let usage: DeviceUsage

        private enum Keys: String, CodingKey {
            case capabilities, totalTokens, costUsd, clients, clientCosts, unpricedTokens
            case timedTokens, timedOutputTokens, timedDurationMs, modelThroughput
        }

        private enum CapabilityKeys: String, CodingKey {
            case throughput
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            let capabilities = try? container.nestedContainer(keyedBy: CapabilityKeys.self, forKey: .capabilities)
            let throughputFlag = capabilities?.strictBool(.throughput)
            let counters = (try? decoder.container(keyedBy: ThroughputCounters.WireKeys.self))
                .flatMap(ThroughputCounters.init(wire:))
            usage = DeviceUsage(
                tokens: nonNegative(container.lenientInt(.totalTokens) ?? 0),
                costUsd: nonNegative(container.lenientDouble(.costUsd) ?? 0),
                clients: UsagePeriod.shares(
                    tokens: container.lenientNumberMap(.clients),
                    costs: container.lenientNumberMap(.clientCosts)
                ) { id, tokens, cost in UsageShare.client(id, tokens: tokens, costUsd: cost) },
                unpricedTokens: container.lenientInt(.unpricedTokens).map(nonNegative),
                throughput: throughputFlag == false ? nil : counters,
                hasThroughput: capabilities?.lenientBool(.throughput) ?? false,
                modelThroughput: ThroughputCounters.modelMap(in: container, forKey: .modelThroughput)
            )
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let deviceId = container.lenientString(.deviceId) ?? container.lenientString(.id)
        let hostname = container.lenientString(.hostname)
        let id = deviceId ?? hostname ?? "device"
        let periods = try? container.nestedContainer(keyedBy: PeriodKeys.self, forKey: .periods)
        func usage(_ key: PeriodKeys, legacy: CodingKeys) -> DeviceUsage {
            periods?.lenientObject(key, as: PeriodTotals.self)?.usage
                ?? container.lenientObject(legacy, as: PeriodTotals.self)?.usage
                ?? .empty
        }
        let receivedAt = container.lenientDate(.receivedAt)
        let updatedAt = container.lenientDate(.updatedAt)
        let isStale = container.lenientBool(.stale) ?? false
        let windows = try? container.nestedContainer(keyedBy: WindowKeys.self, forKey: .periodWindows)
        let todayWindow = try? windows?.nestedContainer(keyedBy: WindowFieldKeys.self, forKey: .today)
        let monthWindow = try? windows?.nestedContainer(keyedBy: WindowFieldKeys.self, forKey: .month)

        var details: [UsagePeriodKind: UsagePeriod] = [:]
        var limits: [LimitProvider] = []
        var limitsUpdatedAt: Date?
        var limitsRefreshInterval: TimeInterval?
        if decoder.hubDecodingOptions.deviceDetail.includes(id) {
            let pairs: [(UsagePeriodKind, PeriodKeys, CodingKeys)] = [
                (.today, .today, .today), (.month, .month, .month), (.allTime, .allTime, .allTime)
            ]
            for (kind, key, legacy) in pairs {
                if let period = periods?.lenientObject(key, as: UsagePeriod.self)
                    ?? container.lenientObject(legacy, as: UsagePeriod.self) {
                    details[kind] = period
                }
            }
            if let limitsContainer = try? container.nestedContainer(keyedBy: LimitsKeys.self, forKey: .limits) {
                limits = limitsContainer.lenientArray(.providers, of: LimitProvider.self)
                HubStats.assignUniqueIDs(&limits)
                if isStale {
                    for index in limits.indices { limits[index].isStale = true }
                }
                limitsUpdatedAt = limitsContainer.lenientDate(.updatedAt)
                limitsRefreshInterval = limitsContainer.lenientDouble(.refreshMs).map { max(0, $0) / 1000 }
            }
        }

        self.init(
            id: id,
            displayName: Self.resolveName(
                displayName: container.lenientString(.displayName),
                deviceId: deviceId,
                hostname: hostname
            ),
            hostname: hostname,
            platform: container.lenientString(.platform),
            osName: container.lenientString(.osName),
            osVersion: container.lenientString(.osVersion),
            agentRuntime: container.lenientString(.agentRuntime),
            agentVersion: container.lenientString(.agentVersion),
            isStale: isStale,
            lastSeen: receivedAt ?? updatedAt,
            updatedAt: updatedAt,
            trackedClients: container.lenientStringArray(.trackedClients),
            today: usage(.today, legacy: .today),
            month: usage(.month, legacy: .month),
            allTime: usage(.allTime, legacy: .allTime),
            syncUploadInterval: container.lenientDouble(.syncUploadIntervalMs).map { max(0, $0) / 1000 },
            projectsEnabled: container.strictBool(.projectsEnabled),
            clientHealth: container.lenientObject(.clientHealth, as: ClientHealthReport.self),
            clientStatus: container.lenientStringMap(.clientStatus),
            sessionDetailsOmitted: container.lenientPeriodCounts(.sessionDetailsOmitted),
            periodProjectsOmitted: container.lenientPeriodCounts(.periodProjectsOmitted),
            allTimeProjectsOmitted: container.strictBool(.allTimeProjectsOmitted) == true,
            allTimeProjectsIncomplete: container.strictBool(.allTimeProjectsIncomplete) == true,
            periodTimeZone: windows?.lenientString(.timeZone),
            todayWindowKey: todayWindow?.lenientString(.key),
            monthWindowKey: monthWindow?.lenientString(.key),
            todayEndsAt: todayWindow?.lenientDate(.endsAt),
            monthEndsAt: monthWindow?.lenientDate(.endsAt),
            details: details,
            limits: limits,
            limitsUpdatedAt: limitsUpdatedAt,
            limitsRefreshInterval: limitsRefreshInterval
        )
    }
}

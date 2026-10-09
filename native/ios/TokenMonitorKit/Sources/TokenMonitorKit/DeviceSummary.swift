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

    public init(tokens: Int = 0, costUsd: Double = 0, clients: [UsageShare] = [], isExpired: Bool = false) {
        self.tokens = tokens
        self.costUsd = costUsd
        self.clients = clients
        self.isExpired = isExpired
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
        allTime: DeviceUsage = .empty
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
    }

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

    // Raw period windows, kept only until `HubStats` applies the expiry.
    var todayEndsAt: Date?
    var monthEndsAt: Date?

    /// Port of the Hub's `isPeriodExpired()`: a `today`/`month` snapshot whose
    /// device-local window has ended is not live any more. Without
    /// `periodWindows` the Hub compares UTC day/month of `updatedAt`.
    mutating func applyPeriodExpiry(now: Date) {
        if Self.isExpired(endsAt: todayEndsAt, recordedAt: updatedAt ?? lastSeen, now: now, components: [.year, .month, .day]) {
            today = DeviceUsage(isExpired: true)
        }
        if Self.isExpired(endsAt: monthEndsAt, recordedAt: updatedAt ?? lastSeen, now: now, components: [.year, .month]) {
            month = DeviceUsage(isExpired: true)
        }
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
    }

    private enum PeriodKeys: String, CodingKey {
        case today, month, allTime
    }

    private enum WindowKeys: String, CodingKey {
        case today, month
    }

    private enum WindowFieldKeys: String, CodingKey {
        case endsAt
    }

    private struct PeriodTotals: Decodable {
        let usage: DeviceUsage

        private enum Keys: String, CodingKey {
            case totalTokens, costUsd, clients, clientCosts
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            usage = DeviceUsage(
                tokens: nonNegative(container.lenientInt(.totalTokens) ?? 0),
                costUsd: nonNegative(container.lenientDouble(.costUsd) ?? 0),
                clients: UsagePeriod.shares(
                    tokens: container.lenientNumberMap(.clients),
                    costs: container.lenientNumberMap(.clientCosts)
                ) { id, tokens, cost in UsageShare.client(id, tokens: tokens, costUsd: cost) }
            )
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let deviceId = container.lenientString(.deviceId) ?? container.lenientString(.id)
        let hostname = container.lenientString(.hostname)
        let periods = try? container.nestedContainer(keyedBy: PeriodKeys.self, forKey: .periods)
        func usage(_ key: PeriodKeys, legacy: CodingKeys) -> DeviceUsage {
            periods?.lenientObject(key, as: PeriodTotals.self)?.usage
                ?? container.lenientObject(legacy, as: PeriodTotals.self)?.usage
                ?? .empty
        }
        let receivedAt = container.lenientDate(.receivedAt)
        let updatedAt = container.lenientDate(.updatedAt)
        self.init(
            id: deviceId ?? hostname ?? "device",
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
            isStale: container.lenientBool(.stale) ?? false,
            lastSeen: receivedAt ?? updatedAt,
            updatedAt: updatedAt,
            trackedClients: container.lenientStringArray(.trackedClients),
            today: usage(.today, legacy: .today),
            month: usage(.month, legacy: .month),
            allTime: usage(.allTime, legacy: .allTime)
        )
        if let windows = try? container.nestedContainer(keyedBy: WindowKeys.self, forKey: .periodWindows) {
            todayEndsAt = (try? windows.nestedContainer(keyedBy: WindowFieldKeys.self, forKey: .today))?.lenientDate(.endsAt)
            monthEndsAt = (try? windows.nestedContainer(keyedBy: WindowFieldKeys.self, forKey: .month))?.lenientDate(.endsAt)
        }
    }
}

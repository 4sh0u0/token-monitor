import Foundation

// Port of the desktop's device presentation: `deviceBreakdown.js` (tool and
// model split, platform label), `app.js` `deviceRowsForPeriod` /
// `deviceRuntimeLabel` / `relativeAgeLabel` / `osIconFor`,
// `homeOverview.js` `homeDeviceRows` and `syncDevicePanel.js` `deviceRows`
// (ordering, online count). No user-facing strings: targets localize the
// enums (`devices.runtime.*`, `devices.synced`, `settings.age.*`,
// `devices.detailsUnavailable`, `home.noTools`, `dashboard.tooltip.unclassified`).

/// The collector a device runs (`agentRuntime`): `devices.runtime.widget`
/// / `devices.runtime.agent`, else the raw value as the desktop prints it.
public enum DeviceRuntime: Sendable, Hashable {
    /// `electron-widget`, the desktop app.
    case widget
    /// `headless-agent`, `npm run agent`.
    case agent
    case other(String)

    /// Nil for an absent or blank runtime.
    public init?(wire: String?) {
        guard let raw = wire?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        switch raw {
        case "electron-widget": self = .widget
        case "headless-agent": self = .agent
        default: self = .other(raw)
        }
    }
}

/// How often a device uploads (`syncUploadIntervalMs`; the Hub normalizes
/// it to live / 10 / 20 / 30 minutes). Targets reuse
/// `settings.sync.uploadInterval.*`.
public enum DeviceUploadInterval: Sendable, Hashable {
    case live
    case minutes(Int)
    /// The device does not say (older producers, local-only hubs).
    case unknown
}

/// A relative age in the desktop's `relativeAgeLabel` steps: under 45 s
/// "just now", then `Math.round`ed minutes (< 60), hours (< 24), days.
/// Targets localize `settings.age.*`.
public enum DeviceSyncedAge: Sendable, Hashable {
    case justNow
    case minutes(Int)
    case hours(Int)
    case days(Int)
}

/// The meta line under a device's breakdown: platform label, runtime and
/// version, "Synced {age}" (joined with " · " on the desktop), plus the
/// iOS-only upload interval.
public struct DeviceMeta: Sendable, Hashable {
    /// `devicePlatformLabel` ("macOS 26.0", "Ubuntu 24.04"); a product name,
    /// not localized. Nil when the device sends nothing.
    public var operatingSystem: String?
    public var runtime: DeviceRuntime?
    /// `agentVersion` without the "v" the desktop prefixes.
    public var agentVersion: String?
    /// The desktop Devices view's "Synced" time (`device.updatedAt`).
    public var syncedAt: Date?
    public var uploadInterval: DeviceUploadInterval

    public init(
        operatingSystem: String?,
        runtime: DeviceRuntime?,
        agentVersion: String?,
        syncedAt: Date?,
        uploadInterval: DeviceUploadInterval
    ) {
        self.operatingSystem = operatingSystem
        self.runtime = runtime
        self.agentVersion = agentVersion
        self.syncedAt = syncedAt
        self.uploadInterval = uploadInterval
    }

    /// The "Synced {age}" bucket at `now`; nil without a timestamp.
    public func syncedAge(now: Date) -> DeviceSyncedAge? {
        DevicePresentation.syncedAge(since: syncedAt, now: now)
    }
}

/// One model under a device's tool (`clientModels[client]`).
public struct DeviceToolModelRow: Sendable, Hashable, Identifiable {
    public var model: String
    public var tokens: Int

    public var id: String { model }

    public init(model: String, tokens: Int) {
        self.model = model
        self.tokens = tokens
    }
}

/// One tool of a device's breakdown (`deviceBreakdownForPeriod().tools[]`).
public struct DeviceToolRow: Sendable, Hashable, Identifiable {
    /// The desktop's key for the synthetic row (`UNATTRIBUTED_KEY`).
    public static let unattributedID = "__unattributed"

    /// The client id, or `unattributedID`.
    public var id: String
    public var tokens: Int
    /// Share of the period total, 0–100 (the desktop prints `Math.round`).
    public var percent: Double
    /// Tokens descending, then name; empty when the device sent no
    /// per-tool models (see `DeviceToolBreakdown.modelsAvailable`).
    public var models: [DeviceToolModelRow]

    public init(id: String, tokens: Int, percent: Double, models: [DeviceToolModelRow]) {
        self.id = id
        self.tokens = tokens
        self.percent = percent
        self.models = models
    }

    /// The synthetic "Unclassified" row: period tokens no tool accounts for
    /// (`dashboard.tooltip.unclassified`).
    public var isUnattributed: Bool { id == Self.unattributedID }

    /// The client id; nil for the Unclassified row.
    public var clientID: String? { isUnattributed ? nil : id }
}

/// Why a breakdown has no tool rows (the desktop's `emptyText`).
public enum DeviceBreakdownEmptyState: String, Sendable, Codable, CaseIterable {
    /// `home.noTools`: nothing was used in the period.
    case noTools
    /// `devices.detailsUnavailable`: tokens without any tool split.
    case detailsUnavailable
}

/// A device's tool / model split for one period.
public struct DeviceToolBreakdown: Sendable, Hashable {
    public var totalTokens: Int
    /// Tokens descending, then name; the Unclassified row carries the
    /// remainder when the tools do not add up to the total.
    public var tools: [DeviceToolRow]
    /// The period carried `clientModels` (and was decoded, see
    /// `HubDecodingOptions.deviceDetail`), so tools can list their models.
    /// When false and the device has tokens, targets can say
    /// `devices.detailsUnavailable` under the tool list.
    public var modelsAvailable: Bool

    public init(totalTokens: Int, tools: [DeviceToolRow], modelsAvailable: Bool) {
        self.totalTokens = totalTokens
        self.tools = tools
        self.modelsAvailable = modelsAvailable
    }

    public static let empty = DeviceToolBreakdown(totalTokens: 0, tools: [], modelsAvailable: false)

    /// Set exactly when `tools` is empty, as on the desktop.
    public var emptyState: DeviceBreakdownEmptyState? {
        guard tools.isEmpty else { return nil }
        return totalTokens > 0 ? .detailsUnavailable : .noTools
    }
}

/// One row of the Devices view (`deviceRowsForPeriod()`) or the Overview
/// Devices module (`homeDeviceRows()`).
public struct DeviceRow: Sendable, Hashable, Identifiable {
    /// The Hub device id.
    public var id: String
    /// `deviceLabel()`: display name, device id, hostname, then "device".
    public var name: String
    public var tokens: Int
    public var costUsd: Double
    public var unpricedTokens: Int?
    /// The Hub's verdict; stale rows are dimmed (`home.staleDevice`).
    public var isStale: Bool
    /// The device's `today`/`month` window ended before it uploaded again,
    /// so the Kit shows it as 0 (the Hub aggregate rule; the desktop list
    /// would still show the old numbers).
    public var isExpired: Bool
    /// The raw `platform` (`darwin-arm64`).
    public var platform: String?
    /// The device mark (`osIconAssetName(platform:)`); nil draws a dot.
    public var osIconAssetName: String?
    public var breakdown: DeviceToolBreakdown
    public var meta: DeviceMeta

    public init(
        id: String,
        name: String,
        tokens: Int,
        costUsd: Double,
        unpricedTokens: Int?,
        isStale: Bool,
        isExpired: Bool,
        platform: String?,
        osIconAssetName: String?,
        breakdown: DeviceToolBreakdown,
        meta: DeviceMeta
    ) {
        self.id = id
        self.name = name
        self.tokens = tokens
        self.costUsd = costUsd
        self.unpricedTokens = unpricedTokens
        self.isStale = isStale
        self.isExpired = isExpired
        self.platform = platform
        self.osIconAssetName = osIconAssetName
        self.breakdown = breakdown
        self.meta = meta
    }
}

public enum DevicePresentation {
    /// `syncedAge` steps (milliseconds in the desktop source).
    static let justNowThreshold: TimeInterval = 45

    // MARK: - Runtime, platform, interval, age

    /// `deviceRuntimeLabel()`: nil for a blank runtime.
    public static func runtime(_ raw: String?) -> DeviceRuntime? {
        DeviceRuntime(wire: raw)
    }

    public static func runtime(_ device: DeviceSummary) -> DeviceRuntime? {
        DeviceRuntime(wire: device.agentRuntime)
    }

    /// `devicePlatformLabel(platform, osName, osVersion)`, exactly: the OS
    /// name (else `darwin` → macOS, `win32` → Windows, `linux` → Linux, else
    /// the raw platform) and the version, joined with a space; `""` when
    /// there is nothing to say. Product names, not localized.
    public static func platformLabel(platform: String?, osName: String?, osVersion: String?) -> String {
        let raw = platform ?? ""
        let prefix = raw.lowercased().split(separator: "-", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        var label = raw
        switch prefix {
        case "darwin": label = "macOS"
        case "win32": label = "Windows"
        case "linux": label = "Linux"
        default: break
        }
        let trimmedName = (osName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? label : trimmedName
        let version = (osVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return [name, version].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The device's platform label; nil when empty.
    public static func platformLabel(_ device: DeviceSummary) -> String? {
        let label = platformLabel(platform: device.platform, osName: device.osName, osVersion: device.osVersion)
        return label.isEmpty ? nil : label
    }

    /// The asset-catalog image of a device's OS mark, mirroring the desktop's
    /// `osIconFor()`: `darwin` → Apple, `win32` → Windows, `linux`, `freebsd`
    /// and `openbsd` → Linux; nil (draw a dot) otherwise. Matched on the
    /// lower-cased text before the first "-".
    public static func osIconAssetName(platform: String?) -> String? {
        let prefix = (platform ?? "").lowercased()
            .split(separator: "-", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        switch prefix {
        case "darwin": return VendorCatalog.osIconAssetNames[.macOS]
        case "win32": return VendorCatalog.osIconAssetNames[.windows]
        case "linux", "freebsd", "openbsd": return VendorCatalog.osIconAssetNames[.linux]
        default: return nil
        }
    }

    /// `syncUploadIntervalMs` as a choice: 0 is live, otherwise whole
    /// minutes (at least 1).
    public static func uploadInterval(seconds: TimeInterval?) -> DeviceUploadInterval {
        guard let seconds, seconds.isFinite else { return .unknown }
        guard seconds > 0 else { return .live }
        let minutes = (seconds / 60).rounded()
        return .minutes(minutes >= Double(Int.max) ? Int.max : max(1, Int(minutes)))
    }

    public static func uploadInterval(_ device: DeviceSummary) -> DeviceUploadInterval {
        uploadInterval(seconds: device.syncUploadInterval)
    }

    /// `relativeAgeLabel()`: nil without a date; a future date reads as
    /// "just now".
    public static func syncedAge(since date: Date?, now: Date) -> DeviceSyncedAge? {
        guard let date else { return nil }
        let elapsedMs = max(0, now.timeIntervalSince(date) * 1000)
        if elapsedMs < justNowThreshold * 1000 { return .justNow }
        let minutes = JSCompat.round(elapsedMs / 60000)
        if minutes < 60 { return .minutes(Int(minutes)) }
        let hours = JSCompat.round(minutes / 60)
        if hours < 24 { return .hours(Int(hours)) }
        return .days(saturatingInt(JSCompat.round(hours / 24)))
    }

    /// The device's meta line.
    public static func meta(_ device: DeviceSummary) -> DeviceMeta {
        let version = device.agentVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        return DeviceMeta(
            operatingSystem: platformLabel(device),
            runtime: runtime(device),
            agentVersion: (version?.isEmpty ?? true) ? nil : version,
            syncedAt: device.updatedAt,
            uploadInterval: uploadInterval(device)
        )
    }

    // MARK: - Tool / model split

    /// `deviceBreakdownForPeriod(device, period)`: the device's tools with
    /// positive tokens plus an Unclassified row for the remainder, models
    /// from the decoded period's `clientModels`.
    public static func toolBreakdown(device: DeviceSummary, period: UsagePeriodKind) -> DeviceToolBreakdown {
        let usage = device.usage(period)
        let detail = device.detail(period)
        return toolBreakdown(
            totalTokens: usage.tokens,
            clients: usage.clients,
            clientModels: detail?.clientModels ?? [:],
            modelsAvailable: detail?.hasClientModels ?? false
        )
    }

    /// The same split for any period, e.g. a device's derived fixed range.
    public static func toolBreakdown(period: UsagePeriod) -> DeviceToolBreakdown {
        toolBreakdown(
            totalTokens: period.totalTokens,
            clients: period.clients,
            clientModels: period.clientModels,
            modelsAvailable: period.hasClientModels
        )
    }

    /// The tool rows alone (the plan's `toolRows(device:period:)`).
    public static func toolRows(device: DeviceSummary, period: UsagePeriodKind) -> [DeviceToolRow] {
        toolBreakdown(device: device, period: period).tools
    }

    /// The core of `deviceBreakdownForPeriod()`. Ties sort by the tool's
    /// catalog name (the desktop's `clientLabels`; the Unclassified row by
    /// its English label), as `localeCompare` would.
    public static func toolBreakdown(
        totalTokens rawTotal: Int,
        clients: [UsageShare],
        clientModels: [String: [String: UsageBreakdownEntry]],
        modelsAvailable: Bool
    ) -> DeviceToolBreakdown {
        let totalTokens = max(0, rawTotal)
        var entries: [(id: String, tokens: Int)] = []
        var attributed = 0
        for share in clients where share.kind == .client && share.tokens > 0 {
            entries.append((share.id, share.tokens))
            attributed = attributed.addingReportingOverflow(share.tokens).overflow ? Int.max : attributed + share.tokens
        }
        let unattributed = max(0, totalTokens - attributed)
        if unattributed > 0 { entries.append((DeviceToolRow.unattributedID, unattributed)) }

        let rows = entries.map { entry -> (row: DeviceToolRow, sortName: String) in
            let models = (clientModels[entry.id] ?? [:])
                .compactMap { model, value -> DeviceToolModelRow? in
                    value.tokens > 0 ? DeviceToolModelRow(model: model, tokens: value.tokens) : nil
                }
                .sorted { left, right in
                    if left.tokens != right.tokens { return left.tokens > right.tokens }
                    return localeAscending(left.model, right.model)
                }
            let percent = totalTokens > 0 ? Double(entry.tokens) / Double(totalTokens) * 100 : 0
            let sortName = entry.id == DeviceToolRow.unattributedID ? "Unclassified" : VendorCatalog.clientLabel(entry.id)
            return (DeviceToolRow(id: entry.id, tokens: entry.tokens, percent: percent, models: models), sortName)
        }
        let tools = rows.sorted { left, right in
            if left.row.tokens != right.row.tokens { return left.row.tokens > right.row.tokens }
            return localeAscending(left.sortName, right.sortName)
        }.map(\.row)
        return DeviceToolBreakdown(
            totalTokens: totalTokens,
            tools: tools,
            modelsAvailable: modelsAvailable && totalTokens > 0
        )
    }

    // MARK: - Rows and ordering

    /// One device's row for a period.
    public static func row(_ device: DeviceSummary, period: UsagePeriodKind) -> DeviceRow {
        let usage = device.usage(period)
        let breakdown = toolBreakdown(device: device, period: period)
        return DeviceRow(
            id: device.id,
            name: device.displayName,
            tokens: breakdown.totalTokens,
            costUsd: usage.costUsd.isFinite ? max(0, usage.costUsd) : 0,
            unpricedTokens: usage.unpricedTokens,
            isStale: device.isStale,
            isExpired: usage.isExpired,
            platform: device.platform,
            osIconAssetName: osIconAssetName(platform: device.platform),
            breakdown: breakdown,
            meta: meta(device)
        )
    }

    /// The Devices view (`deviceRowsForPeriod()`): every device, tokens
    /// descending; ties keep the Hub's order (by device id).
    public static func rows(devices: [DeviceSummary], period: UsagePeriodKind) -> [DeviceRow] {
        devices.enumerated()
            .map { (index: $0.offset, row: row($0.element, period: period)) }
            .sorted { left, right in
                if left.row.tokens != right.row.tokens { return left.row.tokens > right.row.tokens }
                return left.index < right.index
            }
            .map(\.row)
    }

    public static func rows(stats: HubStats, period: UsagePeriodKind) -> [DeviceRow] {
        rows(devices: stats.devices, period: period)
    }

    /// The Overview Devices module (`homeDeviceRows()`): devices with tokens
    /// in the period, tokens descending, then online before stale, then Hub
    /// order; at most `limit`. A phone has no "this device", so the desktop's
    /// local-first rule never applies.
    public static func homeDevices(stats: HubStats, period: UsagePeriodKind, limit: Int = 4) -> [DeviceRow] {
        homeDevices(devices: stats.devices, period: period, limit: limit)
    }

    public static func homeDevices(devices: [DeviceSummary], period: UsagePeriodKind, limit: Int = 4) -> [DeviceRow] {
        let count = max(0, limit)
        guard count > 0 else { return [] }
        return devices.enumerated()
            .filter { $0.element.usage(period).tokens > 0 }
            .sorted { left, right in
                let leftTokens = left.element.usage(period).tokens
                let rightTokens = right.element.usage(period).tokens
                if leftTokens != rightTokens { return leftTokens > rightTokens }
                if left.element.isStale != right.element.isStale { return !left.element.isStale }
                return left.offset < right.offset
            }
            .prefix(count)
            .map { row($0.element, period: period) }
    }

    /// The device list order of the desktop's sync panel
    /// (`syncDevicePanel.js` `deviceRows`): online devices by most recent
    /// upload (`receivedAt`, else `updatedAt`), then offline ones the same
    /// way, then by id.
    public static func ordered(_ devices: [DeviceSummary]) -> [DeviceSummary] {
        devices.sorted { left, right in
            if left.isStale != right.isStale { return !left.isStale }
            let leftTime = left.lastSeen?.timeIntervalSince1970 ?? 0
            let rightTime = right.lastSeen?.timeIntervalSince1970 ?? 0
            if leftTime != rightTime { return leftTime > rightTime }
            return localeAscending(left.id, right.id)
        }
    }

    /// `{online}/{total} online` (`settings.sync.panel.onlineCount`).
    public static func onlineCount(_ devices: [DeviceSummary]) -> DeviceCounts {
        DeviceCounts(online: devices.filter { !$0.isStale }.count, total: devices.count)
    }

    public static func onlineCount(stats: HubStats) -> DeviceCounts {
        onlineCount(stats.devices)
    }

    // MARK: - Ordering helper

    /// An approximation of JavaScript's default `localeCompare` (ICU root
    /// collation) for the tie-breaks the desktop sorts with: case and
    /// accents are ignored first, punctuation and symbols sort before
    /// digits, digits before letters; then lower case before upper case;
    /// then code points, so the order is total.
    static func localeAscending(_ left: String, _ right: String) -> Bool {
        let leftKey = collationKey(left)
        let rightKey = collationKey(right)
        if leftKey != rightKey { return leftKey.lexicographicallyPrecedes(rightKey) }
        let leftCase = left.unicodeScalars.map { $0.properties.isUppercase ? 1 : 0 }
        let rightCase = right.unicodeScalars.map { $0.properties.isUppercase ? 1 : 0 }
        if leftCase != rightCase { return leftCase.lexicographicallyPrecedes(rightCase) }
        return left.unicodeScalars.map(\.value).lexicographicallyPrecedes(right.unicodeScalars.map(\.value))
    }

    private static func collationKey(_ value: String) -> [UInt64] {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars
            .map { scalar -> UInt64 in
                let group: UInt64
                if scalar.properties.numericType != nil && scalar.properties.generalCategory == .decimalNumber {
                    group = 1
                } else if scalar.properties.isAlphabetic {
                    group = 2
                } else {
                    group = 0
                }
                return group << 32 | UInt64(scalar.value)
            }
    }

    private static func saturatingInt(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        if value >= Double(Int.max) { return Int.max }
        return Int(value)
    }
}

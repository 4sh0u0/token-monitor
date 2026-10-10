import Foundation

// Port of `src/electron/renderer/clientHealthPresentation.js` and
// `clientStatusPresentation.js`: turns a device's `clientHealth` entry and
// `clientStatus` map into the groups, notes, counts and tags the desktop's
// per-tool panel shows. Everything is structured (enums and numbers); the
// targets localize it with the desktop keys named on each case.

/// The colour family of a tool-health chip, note or status tag (the
/// desktop's `tone-*` classes). `OVERALL_TONES` and `DIAGNOSTIC_TONES` use
/// `ok`, `neutral`, `warn` and `muted`; `clientStatusTag` adds `setup`.
public enum ClientHealthTone: String, Sendable, Codable, CaseIterable {
    case ok
    case neutral
    case warn
    case setup
    case muted
}

extension ClientHealthOverall {
    /// `OVERALL_TONES[overall] || 'muted'`.
    public var tone: ClientHealthTone {
        switch self {
        case .healthy: return .ok
        case .waiting: return .neutral
        case .attention: return .warn
        case .unavailable, .unknown: return .muted
        }
    }

    /// The overalls the three-way summary counts (`SUMMARY_OVERALLS`).
    public var isSummarized: Bool { self != .unknown }
}

/// The three groups of a tool's health panel, in display order.
public enum ClientHealthGroupID: String, Sendable, Codable, CaseIterable {
    /// `settings.tools.health.source`
    case source
    /// `settings.tools.health.sync` ("Collection")
    case collection
    /// `settings.tools.health.usage`
    case data
}

/// `source.state`. Targets localize `settings.tools.health.source.<rawValue>`
/// (`detected` takes the detected and checked counts).
public enum ClientHealthSourceState: String, Sendable, Codable, CaseIterable {
    case detected
    case missing
    case unknown

    /// A value this build does not know reads as `.unknown`.
    public init(wire: String?) {
        let raw = wire?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self = ClientHealthSourceState(rawValue: raw) ?? .unknown
    }
}

/// `collection.state`. Targets localize `settings.tools.health.sync.<rawValue>`.
/// The Hub sends the first six; `notTracked` and `waiting` complete the
/// desktop's key set.
public enum ClientHealthCollectionState: String, Sendable, Codable, CaseIterable {
    case direct
    case idle
    case pending
    case ok
    case failed
    case unknown
    case notTracked
    case waiting

    /// A value this build does not know reads as `.unknown`.
    public init(wire: String?) {
        let raw = wire?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self = ClientHealthCollectionState(rawValue: raw) ?? .unknown
    }
}

/// A diagnostic code the desktop renders (`DIAGNOSTIC_TONES`). Targets
/// localize `settings.tools.health.code.<rawValue>`. Codes outside this set
/// are not shown, as on the desktop.
public enum ClientHealthDiagnostic: String, Sendable, Codable, CaseIterable {
    case sourceMissing = "source-missing"
    case noUsageObserved = "no-usage-observed"
    case wslDetectedNoData = "wsl-detected-no-data"
    case syncFailed = "sync-failed"
    case syncTimeout = "sync-timeout"
    case syncSpawnFailed = "sync-spawn-failed"
    case syncExitError = "sync-exit-error"
    case syncLockPresent = "sync-lock-present"

    /// `DIAGNOSTIC_TONES`.
    public var tone: ClientHealthTone {
        switch self {
        case .sourceMissing, .noUsageObserved: return .muted
        case .wslDetectedNoData: return .neutral
        case .syncFailed, .syncTimeout, .syncSpawnFailed, .syncExitError, .syncLockPresent: return .warn
        }
    }

    /// `DIAGNOSTIC_GROUPS`: the group the note is printed under.
    public var group: ClientHealthGroupID {
        switch self {
        case .sourceMissing: return .source
        case .syncFailed, .syncTimeout, .syncSpawnFailed, .syncExitError, .syncLockPresent: return .collection
        case .noUsageObserved, .wslDetectedNoData: return .data
        }
    }

    /// `QUIET_WHEN_UNAVAILABLE`: notes that only restate an `unavailable`
    /// overall and are dropped then.
    public var isQuietWhenUnavailable: Bool {
        self == .sourceMissing || self == .noUsageObserved
    }
}

/// One rendered diagnostic line (`clientHealthNotes()`).
public struct ClientHealthNote: Sendable, Hashable {
    public var code: ClientHealthDiagnostic
    public var group: ClientHealthGroupID
    public var tone: ClientHealthTone

    public init(code: ClientHealthDiagnostic) {
        self.code = code
        self.group = code.group
        self.tone = code.tone
    }
}

/// The `source` group: whether the tool's data roots exist on the device.
public struct ClientHealthSourceGroup: Sendable, Hashable {
    public var state: ClientHealthSourceState
    public var detectedCount: Int
    public var checkedCount: Int
    /// The logical checks by stable id (never a path), first occurrence of
    /// each id in wire order (`mergeSourceChecks()` without local sources:
    /// a phone has no local paths).
    public var checks: [ClientHealthCheck]

    public init(state: ClientHealthSourceState, detectedCount: Int, checkedCount: Int, checks: [ClientHealthCheck]) {
        self.state = state
        self.detectedCount = detectedCount
        self.checkedCount = checkedCount
        self.checks = checks
    }
}

/// The `collection` group. Targets show `settings.tools.health.lastAttempt`
/// / `lastSuccess` ("Last tried {time}") for each present stamp.
public struct ClientHealthCollectionGroup: Sendable, Hashable {
    public var state: ClientHealthCollectionState
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    /// Raw failure details (`syncFailureStage`, `syncDetailCode`,
    /// `syncExitCode`). The desktop panel does not print them; they are
    /// here for an iOS diagnostics row.
    public var failureStage: String?
    public var detailCode: String?
    public var exitCode: Int?

    public init(
        state: ClientHealthCollectionState,
        lastAttemptAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        failureStage: String? = nil,
        detailCode: String? = nil,
        exitCode: Int? = nil
    ) {
        self.state = state
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.failureStage = failureStage
        self.detailCode = detailCode
        self.exitCode = exitCode
    }
}

/// One period cell of the `data` group: the tool's tokens and cost on the
/// device (`clientPeriodUsage()`).
public struct ClientHealthPeriodUsage: Sendable, Hashable, Identifiable {
    public var period: UsagePeriodKind
    public var tokens: Int
    public var costUsd: Double

    public var id: UsagePeriodKind { period }

    public init(period: UsagePeriodKind, tokens: Int, costUsd: Double) {
        self.period = period
        self.tokens = tokens
        self.costUsd = costUsd
    }
}

/// The `data` group.
public struct ClientHealthDataGroup: Sendable, Hashable {
    /// Today / month / all time, in that order; nil when no usage was
    /// supplied (the panel then prints `liveTokens` with
    /// `settings.tools.health.tokensValue`). Cost is shown only when > 0.
    public var periods: [ClientHealthPeriodUsage]?
    /// `data.liveTokens`: everything counted for the tool.
    public var liveTokens: Int
    /// `data.lastActivityDay` (`yyyy-MM-dd`, device-local); nil when absent.
    /// See `ClientHealthPresentation.relativeDay(_:todayKey:)`.
    public var lastActivityDay: String?

    public init(periods: [ClientHealthPeriodUsage]?, liveTokens: Int, lastActivityDay: String?) {
        self.periods = periods
        self.liveTokens = liveTokens
        self.lastActivityDay = lastActivityDay
    }
}

/// A tool's expanded health panel (`clientHealthDetail()`).
public struct ClientHealthDetail: Sendable, Hashable {
    public var overall: ClientHealthOverall
    public var tone: ClientHealthTone
    public var source: ClientHealthSourceGroup
    public var collection: ClientHealthCollectionGroup
    public var data: ClientHealthDataGroup
    /// Diagnostic lines in wire order; each belongs to one group.
    public var notes: [ClientHealthNote]

    public init(
        overall: ClientHealthOverall,
        source: ClientHealthSourceGroup,
        collection: ClientHealthCollectionGroup,
        data: ClientHealthDataGroup,
        notes: [ClientHealthNote]
    ) {
        self.overall = overall
        self.tone = overall.tone
        self.source = source
        self.collection = collection
        self.data = data
        self.notes = notes
    }

    /// The group ids in display order (`clientHealthGroups()`).
    public var groups: [ClientHealthGroupID] { ClientHealthGroupID.allCases }

    /// The notes printed under one group (`clientHealthPanel()`).
    public func notes(in group: ClientHealthGroupID) -> [ClientHealthNote] {
        notes.filter { $0.group == group }
    }
}

/// The settings summary counts (`clientHealthCountsForTracked()`): `waiting`
/// and `attention` share the "needs review" bucket. Targets localize
/// `settings.summary.toolsHealth`.
public struct ClientHealthCounts: Sendable, Hashable {
    public var healthy: Int
    public var review: Int
    public var unavailable: Int

    public init(healthy: Int, review: Int, unavailable: Int) {
        self.healthy = healthy
        self.review = review
        self.unavailable = unavailable
    }

    public var total: Int { healthy + review + unavailable }
}

/// How the "Last output" line names `lastActivityDay` (`relativeDayLabel()`):
/// `settings.tools.health.day.today` / `.yesterday` / `.daysAgo`, or the
/// plain date for a future or unreadable day.
public enum ClientHealthRelativeDay: Sendable, Hashable {
    case today
    case yesterday
    case daysAgo(Int)
    case date(String)
}

/// A tool's tag in a device's tool list (`clientStatusTag()`): the desktop
/// keys are `settings.tools.status.<rawValue>`. `missing` is
/// "Not installed"; Cursor and Antigravity read tokscale caches that appear
/// only after sign-in / opening the app, so their `missing` reads `signIn`
/// and `openApp`.
public enum ClientStatusTag: String, Sendable, Codable, CaseIterable {
    case active
    case waiting
    case missing
    case signIn
    case openApp

    /// The tag for a `clientStatus` value, nil for an unknown status (no tag
    /// renders). The status is matched exactly, as on the desktop.
    public static func tag(client: String, status: String?) -> ClientStatusTag? {
        switch status {
        case "active": return .active
        case "waiting": return .waiting
        case "missing":
            switch client.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "cursor": return .signIn
            case "antigravity": return .openApp
            default: return .missing
            }
        default: return nil
        }
    }

    /// Every tagged client of a device (`device.clientStatus`).
    public static func tags(for device: DeviceSummary) -> [String: ClientStatusTag] {
        var result: [String: ClientStatusTag] = [:]
        for (client, status) in device.clientStatus {
            if let tag = tag(client: client, status: status) { result[client] = tag }
        }
        return result
    }

    public var tone: ClientHealthTone {
        switch self {
        case .active: return .ok
        case .waiting: return .neutral
        case .missing: return .muted
        case .signIn, .openApp: return .setup
        }
    }
}

/// One tool in a device's tool list: its status tag and health panel.
public struct ClientToolStatus: Sendable, Hashable, Identifiable {
    public var clientID: String
    /// The device lists the tool in `trackedClients`.
    public var isTracked: Bool
    public var tag: ClientStatusTag?
    public var health: ClientHealthDetail?

    public var id: String { clientID }

    public init(clientID: String, isTracked: Bool, tag: ClientStatusTag?, health: ClientHealthDetail?) {
        self.clientID = clientID
        self.isTracked = isTracked
        self.tag = tag
        self.health = health
    }
}

public enum ClientHealthPresentation {
    /// `hasClientHealth()`: the report has an entry for the client.
    public static func hasHealth(report: ClientHealthReport?, clientID: String) -> Bool {
        report?.entry(for: clientID) != nil
    }

    /// `clientHealthDetail(health, clientId, { usage })`: nil when the report
    /// has no entry for the client. Pass `usage` (see `periodUsage`) to fill
    /// the data group's period cells, as the desktop panel does.
    public static func detail(
        report: ClientHealthReport?,
        clientID: String,
        usage: [ClientHealthPeriodUsage]? = nil
    ) -> ClientHealthDetail? {
        guard let entry = report?.entry(for: clientID) else { return nil }
        return detail(entry: entry, usage: usage)
    }

    /// The detail for one of a device's tools, with that device's usage of
    /// the tool. Nil when the device sent no health entry for it.
    public static func detail(device: DeviceSummary, clientID: String) -> ClientHealthDetail? {
        detail(report: device.clientHealth, clientID: clientID, usage: periodUsage(device: device, clientID: clientID))
    }

    /// `clientHealthDetailFromEntry()`.
    public static func detail(entry: ClientHealthEntry, usage: [ClientHealthPeriodUsage]? = nil) -> ClientHealthDetail {
        ClientHealthDetail(
            overall: entry.overall,
            source: ClientHealthSourceGroup(
                state: ClientHealthSourceState(wire: entry.sourceState),
                detectedCount: max(0, entry.detectedCount),
                checkedCount: max(0, entry.checkedCount),
                checks: uniqueChecks(entry.checks)
            ),
            collection: ClientHealthCollectionGroup(
                state: ClientHealthCollectionState(wire: entry.collectionState),
                lastAttemptAt: entry.lastAttemptAt,
                lastSuccessAt: entry.lastSuccessAt,
                failureStage: entry.syncFailureStage,
                detailCode: entry.syncDetailCode,
                exitCode: entry.syncExitCode
            ),
            data: ClientHealthDataGroup(
                periods: usage.map(orderedUsage),
                liveTokens: max(0, entry.liveTokens),
                lastActivityDay: nonEmpty(entry.lastActivityDay)
            ),
            notes: notes(entry: entry)
        )
    }

    /// `clientHealthNotes()`: known codes in wire order; `source-missing` and
    /// `no-usage-observed` are dropped when the overall is `unavailable`.
    public static func notes(entry: ClientHealthEntry) -> [ClientHealthNote] {
        let quiet = entry.overall == .unavailable
        return entry.diagnostics.compactMap { raw in
            guard let code = ClientHealthDiagnostic(rawValue: raw) else { return nil }
            if quiet && code.isQuietWhenUnavailable { return nil }
            return ClientHealthNote(code: code)
        }
    }

    /// `clientPeriodUsage(device, clientId)`: the tool's tokens and cost on
    /// the device per period, 0 when absent. The client id is matched
    /// exactly. An expired `today`/`month` (see `DeviceSummary`) reads 0,
    /// where the desktop would show the stale numbers.
    public static func periodUsage(device: DeviceSummary, clientID: String) -> [ClientHealthPeriodUsage] {
        UsagePeriodKind.allCases.map { kind in
            let share = device.usage(kind).clients.first { $0.id == clientID }
            return ClientHealthPeriodUsage(
                period: kind,
                tokens: max(0, share?.tokens ?? 0),
                costUsd: max(0, share?.costUsd ?? 0)
            )
        }
    }

    /// `clientHealthCountsForTracked(health, tracked)`: nil when there is no
    /// report, or when any tracked tool has no entry or an `unknown` overall
    /// (the three counts must partition every tracked tool). Tracked ids are
    /// trimmed, lower-cased and de-duplicated; blanks are ignored.
    public static func counts(report: ClientHealthReport?, tracked: [String]) -> ClientHealthCounts? {
        guard let report else { return nil }
        var seen = Set<String>()
        var counts = ClientHealthCounts(healthy: 0, review: 0, unavailable: 0)
        for raw in tracked {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            guard let overall = report.entry(for: id)?.overall else { return nil }
            switch overall {
            case .healthy: counts.healthy += 1
            case .waiting, .attention: counts.review += 1
            case .unavailable: counts.unavailable += 1
            case .unknown: return nil
            }
        }
        return counts
    }

    /// The counts for a device's own tracked tools.
    public static func counts(device: DeviceSummary) -> ClientHealthCounts? {
        counts(report: device.clientHealth, tracked: device.trackedClients)
    }

    /// `relativeDayLabel(day)` with an explicit "today" (the desktop uses
    /// its own local day; for a remote device pass its `todayWindowKey`).
    /// Days are counted as calendar days between the two keys.
    public static func relativeDay(_ day: String, todayKey: String) -> ClientHealthRelativeDay {
        if day == todayKey { return .today }
        guard let dayDate = DayKey.date(from: day, calendar: DayKey.utcCalendar),
              let todayDate = DayKey.date(from: todayKey, calendar: DayKey.utcCalendar),
              let days = DayKey.utcCalendar.dateComponents([.day], from: dayDate, to: todayDate).day else {
            return .date(day)
        }
        if days == 1 { return .yesterday }
        if days > 1 { return .daysAgo(days) }
        return .date(day)
    }

    /// Every tool a device reports on, with its tag and health panel:
    /// tracked tools plus any tool that has a status or a health entry, in
    /// the catalog's client order (unknown ids last, by id).
    public static func toolStatuses(device: DeviceSummary) -> [ClientToolStatus] {
        func normalized(_ id: String) -> String { id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let tracked = Set(device.trackedClients.map(normalized).filter { !$0.isEmpty })
        var statusByID: [String: String] = [:]
        for (client, status) in device.clientStatus {
            let id = normalized(client)
            guard !id.isEmpty, statusByID[id] == nil || client == id else { continue }
            statusByID[id] = status
        }
        var ids = tracked.union(statusByID.keys)
        if let clients = device.clientHealth?.clients {
            ids.formUnion(clients.keys.map(normalized).filter { !$0.isEmpty })
        }
        let catalogOrder = Dictionary(
            VendorCatalog.trackedClientIDs.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let ordered = ids.sorted { left, right in
            let leftRank = catalogOrder[left] ?? Int.max
            let rightRank = catalogOrder[right] ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            return left < right
        }
        return ordered.map { id in
            ClientToolStatus(
                clientID: id,
                isTracked: tracked.contains(id),
                tag: ClientStatusTag.tag(client: id, status: statusByID[id]),
                health: detail(device: device, clientID: id)
            )
        }
    }

    // MARK: - Helpers

    private static func uniqueChecks(_ checks: [ClientHealthCheck]) -> [ClientHealthCheck] {
        var seen = Set<String>()
        return checks.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }

    /// One cell per period in today / month / all-time order; a missing
    /// period reads 0, a repeated one keeps its first value.
    private static func orderedUsage(_ usage: [ClientHealthPeriodUsage]) -> [ClientHealthPeriodUsage] {
        UsagePeriodKind.allCases.map { kind in
            let cell = usage.first { $0.period == kind }
            return ClientHealthPeriodUsage(
                period: kind,
                tokens: max(0, cell?.tokens ?? 0),
                costUsd: cell.map { $0.costUsd.isFinite ? max(0, $0.costUsd) : 0 } ?? 0
            )
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

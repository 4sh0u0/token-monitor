import Foundation

// Port of `src/electron/renderer/projectRows.js` and
// `src/shared/projectKey.js`: the Projects view rows and their per-tool split.

/// One tool's share of a project (the expanded row).
public struct ProjectToolRow: Sendable, Hashable, Identifiable {
    /// Nil for the tokens no tool claimed ("Unknown tool",
    /// `projects.unknownTool`).
    public var clientID: String?
    public var tokens: Int
    /// Share of the project's tokens, 0–100 (the desktop prints it rounded).
    public var percent: Double

    public init(clientID: String?, tokens: Int, percent: Double) {
        self.clientID = clientID
        self.tokens = tokens
        self.percent = percent
    }

    /// The desktop key: the client id, or `unknown`.
    public var id: String { clientID ?? "unknown" }
}

/// A row of the Projects view: one project folder for the period, merged
/// case-insensitively by label.
public struct ProjectRow: Sendable, Hashable, Identifiable {
    /// `canonicalProjectKey`: the lower-cased, NFC label.
    public var key: String
    /// The display label (`deterministicProjectLabel` across merged spellings).
    public var name: String
    public var tokens: Int
    public var costUsd: Double
    public var unpricedTokens: Int?
    /// Client ids with tokens, sorted.
    public var clients: [String]
    /// Tokens per client id; `""` holds the remainder no tool claimed.
    public var clientTokens: [String: Int]
    /// The per-tool split, heaviest first, the unknown remainder included.
    public var toolRows: [ProjectToolRow]

    public init(key: String, name: String, tokens: Int, costUsd: Double, unpricedTokens: Int? = nil, clients: [String], clientTokens: [String: Int], toolRows: [ProjectToolRow]) {
        self.key = key
        self.name = name
        self.tokens = tokens
        self.costUsd = costUsd
        self.unpricedTokens = unpricedTokens
        self.clients = clients
        self.clientTokens = clientTokens
        self.toolRows = toolRows
    }

    public var id: String { key }
}

public enum ProjectRows {
    /// `projectRowsForPeriod`: the period's project rollup — or, when a Hub
    /// sent none, its sessions grouped by project label — merged by
    /// canonical key, by cost, then tokens, then name. Each row's tool split
    /// adds an unknown-tool remainder when its tools do not cover its total.
    public static func rows(period: UsagePeriod) -> [ProjectRow] {
        var projects: [String: Accumulator] = [:]
        var order: [String] = []
        func accumulator(key: String, name: String) -> Accumulator {
            if let existing = projects[key] { return existing }
            order.append(key)
            return Accumulator(key: key, name: name)
        }
        if !period.projects.isEmpty {
            for rollup in period.projects {
                // `ProjectRollup.label` is already `label || key`; a blank
                // label stays blank and is skipped, as on the desktop.
                let name = normalizedLabel(rollup.label)
                let key = canonicalKey(name.isEmpty ? rollup.id : name)
                guard !key.isEmpty, !name.isEmpty else { continue }
                var project = accumulator(key: key, name: name)
                project.name = deterministicLabel(project.name, name)
                project.tokens += max(0, rollup.tokens)
                project.cost += rollup.costUsd
                let unpriced = unpricedTokens(rollup.unpricedTokens, total: rollup.tokens)
                if unpriced > 0 { project.unpriced = (project.unpriced ?? 0) + unpriced }
                for (client, tokens) in rollup.clients where tokens > 0 {
                    project.clients.insert(client)
                    project.clientTokens[client, default: 0] += tokens
                }
                projects[key] = project
            }
        } else {
            for session in period.sessions {
                let label = normalizedLabel(session.projectLabel ?? "")
                let key = canonicalKey(label)
                guard !key.isEmpty, !label.isEmpty else { continue }
                var project = accumulator(key: key, name: label)
                project.name = deterministicLabel(project.name, label)
                let tokens = max(0, session.totalTokens)
                project.tokens += tokens
                project.cost += session.costUsd
                let unpriced = unpricedTokens(session.unpricedTokens, total: tokens)
                if unpriced > 0 { project.unpriced = (project.unpriced ?? 0) + unpriced }
                if !session.client.isEmpty {
                    project.clients.insert(session.client)
                    project.clientTokens[session.client, default: 0] += tokens
                }
                projects[key] = project
            }
        }
        let rows = order.compactMap { projects[$0] }.map(\.row)
        return rows.enumerated().sorted { left, right in
            let a = left.element
            let b = right.element
            if a.costUsd != b.costUsd { return a.costUsd > b.costUsd }
            if a.tokens != b.tokens { return a.tokens > b.tokens }
            let names = UsageRowCollation.compare(a.name, b.name)
            return names != 0 ? names < 0 : left.offset < right.offset
        }.map(\.element)
    }

    /// `projectBreakdownIncomplete`: all time is incomplete when any device
    /// left projects out; today and month when the Hub counted omissions.
    public static func isIncomplete(stats: HubStats, period: UsagePeriodKind) -> Bool {
        switch period {
        case .allTime: return stats.projectsIncomplete
        case .today, .month: return (stats.periodProjectsOmitted[period] ?? 0) > 0
        }
    }

    /// `isIncomplete(stats:period:)` for a period selection; fixed ranges
    /// carry no projects, so never.
    public static func isIncomplete(stats: HubStats, selection: PeriodSelection) -> Bool {
        guard let kind = selection.nativeKind else { return false }
        return isIncomplete(stats: stats, period: kind)
    }

    /// The same hint for one device, following the Hub's own rule for
    /// folding a device into `projectsIncomplete`.
    public static func isIncomplete(device: DeviceSummary, period: UsagePeriodKind) -> Bool {
        switch period {
        case .allTime:
            return device.allTimeProjectsOmitted
                || device.allTimeProjectsIncomplete
                || (device.projectsEnabled == false && device.allTime.tokens > 0)
        case .today, .month:
            return (device.periodProjectsOmitted[period] ?? 0) > 0
        }
    }

    /// `canonicalProjectKey`: trimmed, NFC, lower-cased; `""` for a blank label.
    public static func canonicalKey(_ value: String) -> String {
        let label = normalizedLabel(value)
        guard !label.isEmpty else { return "" }
        return ModelAliasResolver.jsLowercased(label).precomposedStringWithCanonicalMapping
    }

    /// `deterministicProjectLabel`: of two spellings of one project, the one
    /// that sorts first by UTF-16 code units, so every client picks the same.
    public static func deterministicLabel(_ left: String, _ right: String) -> String {
        let a = normalizedLabel(left)
        let b = normalizedLabel(right)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a.utf16.lexicographicallyPrecedes(b.utf16) ? a : b
    }

    // MARK: Helpers

    /// The sort key the desktop's English "Unknown tool" label gives the
    /// remainder row when it ties with a tool (never displayed).
    static let unknownToolSortKey = "Unknown tool"

    static func normalizedLabel(_ value: String) -> String {
        ModelAliasResolver.jsTrimmed(value).precomposedStringWithCanonicalMapping
    }

    /// `unpricedTokensFor`: never more than the row's own tokens.
    static func unpricedTokens(_ value: Int?, total: Int) -> Int {
        guard let value else { return 0 }
        return min(max(0, total), max(0, value))
    }

    struct Accumulator {
        var key: String
        var name: String
        var tokens = 0
        var cost = 0.0
        var unpriced: Int?
        var clients = Set<String>()
        var clientTokens: [String: Int] = [:]

        init(key: String, name: String) {
            self.key = key
            self.name = name
        }

        var row: ProjectRow {
            var clientTokens = self.clientTokens
            let attributed = clientTokens.values.reduce(0, +)
            if tokens > attributed { clientTokens["", default: 0] = tokens - attributed }
            let toolRows = clientTokens
                .filter { $0.value > 0 }
                .map { client, value in
                    (
                        row: ProjectToolRow(
                            clientID: client.isEmpty ? nil : client,
                            tokens: value,
                            percent: tokens > 0 ? Double(value) / Double(tokens) * 100 : 0
                        ),
                        sortName: client.isEmpty ? ProjectRows.unknownToolSortKey : (SessionRows.clientLabel(client) ?? client)
                    )
                }
                .sorted { left, right in
                    if left.row.tokens != right.row.tokens { return left.row.tokens > right.row.tokens }
                    let names = UsageRowCollation.compare(left.sortName, right.sortName)
                    if names != 0 { return names < 0 }
                    return left.row.id.utf16.lexicographicallyPrecedes(right.row.id.utf16)
                }
                .map(\.row)
            return ProjectRow(
                key: key,
                name: name,
                tokens: tokens,
                costUsd: cost,
                unpricedTokens: unpriced,
                clients: clients.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) },
                clientTokens: clientTokens,
                toolRows: toolRows
            )
        }
    }
}

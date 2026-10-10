import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The project folders of the Overview's period (`projectRowsForPeriod`): by
/// cost, then tokens, then name, each bar blended from its tools' colours. A
/// project expands to its per-tool split, with an "Unknown tool" row for
/// tokens no tool claimed. Fixed ranges have no projects
/// (`periodRange.projectUnavailable`); `projects.incomplete` shows when a
/// device left project details out.
struct ProjectsView: View {
    @State private var expanded: Set<String> = []

    var body: some View {
        BreakdownsScreen("Projects", breakdown: .project) { usage in
            ProjectsList(usage: usage, expanded: $expanded)
        }
    }
}

private struct ProjectsList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmPresentation) private var presentation
    @ScaledMetric(relativeTo: .subheadline) private var markSize: CGFloat = 16

    let usage: UsagePeriod
    @Binding var expanded: Set<String>

    var body: some View {
        let rows = ProjectRows.rows(period: usage)
        if isIncomplete {
            IncompleteNotice(text: "Project breakdown may be incomplete because one or more devices omitted project details.")
        }
        if rows.isEmpty {
            BreakdownsEmptyNote(text: "No project usage in this period")
        } else {
            let maximum = rows.map { Double($0.tokens) }.max() ?? 0
            LazyVStack(spacing: 8) {
                ForEach(rows) { row in
                    projectRow(row, maximum: maximum)
                }
            }
        }
    }

    /// `projectBreakdownIncomplete` for the scope's stats (a scoped device's
    /// own omission counts, `ScopedStats`).
    private var isIncomplete: Bool {
        guard let stats = model.presented?.stats else { return false }
        return ProjectRows.isIncomplete(stats: stats, selection: model.selectedPeriod)
    }

    private func projectRow(_ row: ProjectRow, maximum: Double) -> some View {
        let projectColor = Self.projectColor(row)
        return BreakdownsRow(
            name: row.name,
            tokens: row.tokens,
            costUsd: row.costUsd,
            unpricedTokens: row.unpricedTokens,
            barFraction: BreakdownsBar.fraction(Double(row.tokens), max: maximum),
            barFill: barFill(row, projectColor: projectColor),
            isExpanded: expanded.contains(row.key),
            onToggle: row.toolRows.isEmpty ? nil : { toggle(row.key) }
        ) {
            VendorMark(.project, size: markSize, dotColor: projectColor)
        } detail: {
            ProjectDetail(row: row, color: { clientColor($0, projectColor: projectColor) })
        }
    }

    private func toggle(_ key: String) {
        if expanded.contains(key) {
            expanded.remove(key)
        } else {
            expanded.insert(key)
        }
    }

    // MARK: Colours

    /// `stableColor(project.key, fallbackModelColors)`: the desktop hashes
    /// the key into the same palette as unknown models.
    static func projectColor(_ row: ProjectRow) -> Color {
        Color(hex: VendorCatalog.fallbackModelColorHex(for: row.key))
    }

    /// A tool's colour in the split (`clientColor`): its mark colour with
    /// overrides, or the project's colour for an unknown or unclaimed tool.
    private func clientColor(_ clientID: String?, projectColor: Color) -> Color {
        guard let clientID, !clientID.isEmpty, VendorCatalog.mark(for: clientID) != nil else { return projectColor }
        return VendorColor.color(for: clientID, palette: presentation.palette)
    }

    /// `clientGradient`: one colour for a single tool, else the tools'
    /// colours heaviest first, each boundary blended over at most 1.5 % of
    /// the bar either side.
    private func barFill(_ row: ProjectRow, projectColor: Color) -> AnyShapeStyle {
        let entries = row.clientTokens
            .filter { $0.value > 0 }
            .sorted { left, right in
                left.value != right.value ? left.value > right.value : left.key < right.key
            }
        guard let first = entries.first else { return AnyShapeStyle(projectColor) }
        let colors = entries.map { clientColor($0.key, projectColor: projectColor) }
        guard entries.count > 1 else { return AnyShapeStyle(clientColor(first.key, projectColor: projectColor)) }
        let total = Double(entries.reduce(0) { $0 + $1.value })
        var stops = [Gradient.Stop(color: colors[0], location: 0)]
        var cumulative = 0.0
        for index in 0..<(entries.count - 1) {
            let current = Double(entries[index].value) / total * 100
            let next = Double(entries[index + 1].value) / total * 100
            cumulative += current
            let blend = min(1.5, current / 2, next / 2)
            stops.append(Gradient.Stop(color: colors[index], location: max(0, cumulative - blend) / 100))
            stops.append(Gradient.Stop(color: colors[index + 1], location: min(100, cumulative + blend) / 100))
        }
        stops.append(Gradient.Stop(color: colors[colors.count - 1], location: 1))
        return AnyShapeStyle(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
    }
}

/// An expanded project: each tool's tokens and share of the project, then
/// the full cost label.
private struct ProjectDetail: View {
    @Environment(\.tmFormatter) private var formatter
    @ScaledMetric(relativeTo: .footnote) private var markSize: CGFloat = 12
    let row: ProjectRow
    let color: (String?) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(row.toolRows) { tool in
                BreakdownsDetailRow(
                    title: Text(verbatim: tool.clientID.map(VendorCatalog.clientLabel) ?? String(localized: "Unknown tool")),
                    percent: formatter.percent(tool.percent),
                    value: formatter.fullTokens(tool.tokens)
                ) {
                    VendorMark(.client(tool.clientID ?? ""), size: markSize, dotColor: color(tool.clientID))
                }
            }
            BreakdownsCostRow(costUsd: row.costUsd, unpricedTokens: row.unpricedTokens)
        }
    }
}

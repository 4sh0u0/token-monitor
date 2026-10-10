import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// What an expanded tool shows (the desktop's tool-detail footer toggle,
/// `state.toolDetailMode`): its token components or its models. Shared by
/// every expanded tool and kept for the screen's lifetime, as on the desktop.
private enum ToolDetailMode: Hashable {
    case tokens
    case models
}

/// Every tool of the Overview's period (`toolRowsForPeriod`), with the
/// Unclassified remainder, hidden / pinned / ordered by the Tools-list
/// preferences. A tool expands to its token components or, with the
/// Tokens / Models toggle, its models.
struct ToolsView: View {
    @State private var expanded: Set<String> = []
    @State private var detailMode: ToolDetailMode = .tokens

    var body: some View {
        BreakdownsScreen("Tools", breakdown: .tool) { usage in
            ToolsList(usage: usage, expanded: $expanded, detailMode: $detailMode)
        }
    }
}

private struct ToolsList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmPresentation) private var presentation
    @Environment(\.tmFormatter) private var formatter
    @ScaledMetric(relativeTo: .subheadline) private var markSize: CGFloat = 16

    let usage: UsagePeriod
    @Binding var expanded: Set<String>
    @Binding var detailMode: ToolDetailMode

    private var known: [String] { VendorCatalog.trackedClientIDs }

    var body: some View {
        let preferences = model.preferences
        let rows = AttributionRows.toolRows(period: usage, prefs: preferences, known: known, formatter: formatter)
        let hidden = hiddenTools(preferences)
        if rows.isEmpty {
            BreakdownsEmptyNote(text: "No tool usage in this period")
        } else {
            UsageBar(
                segments: rows.map { UsageBar.Segment(id: $0.key, value: Double($0.tokens), color: color(of: $0)) },
                total: Double(usage.totalTokens),
                height: 8
            )
            let maximum = rows.map(\.barValue).max() ?? 0
            let pinsApply = !ClientDisplayOrder.hasCustomOrder(preferences.clientDisplayOrder)
            LazyVStack(spacing: 8) {
                ForEach(rows) { row in
                    toolRow(row, maximum: maximum, isPinned: pinsApply && preferences.pinnedClients.contains(row.key))
                        .contextMenu {
                            menu(for: row, pinsApply: pinsApply, preferences: preferences)
                        }
                }
            }
        }
        if !hidden.isEmpty {
            hiddenToolsMenu(hidden)
        }
    }

    // MARK: Rows

    private func toolRow(_ row: AttributionRow, maximum: Double, isPinned: Bool) -> some View {
        let name = Self.name(of: row)
        let isExpanded = expanded.contains(row.key)
        return BreakdownsRow(
            name: name,
            tokens: row.tokens,
            costUsd: row.costUsd,
            unpricedTokens: row.unpricedTokens,
            barFraction: BreakdownsBar.fraction(row.barValue, max: maximum),
            barFill: AnyShapeStyle(color(of: row)),
            share: breakdownsShareLabel(Double(row.tokens), of: Double(usage.totalTokens)),
            isPinned: isPinned,
            isExpanded: isExpanded,
            onToggle: row.tokens > 0 ? { toggle(row.key) } : nil
        ) {
            VendorMark(.client(row.key), size: markSize)
        } detail: {
            ToolDetail(row: row, name: name, mode: $detailMode)
        }
    }

    private func toggle(_ key: String) {
        if expanded.contains(key) {
            expanded.remove(key)
        } else {
            expanded.insert(key)
        }
    }

    /// The tool's bar and dot colour (overrides applied); the remainder
    /// takes the default mark colour, as the desktop's `clientColors.default`.
    private func color(of row: AttributionRow) -> Color {
        VendorColor.color(for: row.key, palette: presentation.palette)
    }

    static func name(of row: AttributionRow) -> String {
        row.isUnattributed ? String(localized: "Unclassified") : VendorCatalog.clientLabel(row.key)
    }

    // MARK: Hide and pin

    /// Pin / unpin (only while no explicit order exists: an explicit order
    /// ignores pins, `applyClientDisplayPreferences`) and hide, for tracked
    /// tools; the remainder and unknown ids have no preferences.
    @ViewBuilder
    private func menu(for row: AttributionRow, pinsApply: Bool, preferences: DisplayPreferences) -> some View {
        if !row.isUnattributed, known.contains(row.key) {
            let name = VendorCatalog.clientLabel(row.key)
            if pinsApply {
                if preferences.pinnedClients.contains(row.key) {
                    Button {
                        togglePin(row.key)
                    } label: {
                        Label(String(localized: "Unpin \(name)"), systemImage: "pin.slash")
                    }
                } else {
                    Button {
                        togglePin(row.key)
                    } label: {
                        Label(String(localized: "Pin \(name) to top"), systemImage: "pin")
                    }
                }
            }
            Button {
                setHidden(row.key, true)
            } label: {
                Label(String(localized: "Hide \(name) from the Tools list"), systemImage: "eye.slash")
            }
        }
    }

    /// Tools of this period the Tools-list preferences hide, so they can be
    /// shown again from here.
    private func hiddenTools(_ preferences: DisplayPreferences) -> [String] {
        guard !preferences.hiddenClients.isEmpty else { return [] }
        return AttributionRows.usageToolRows(period: usage, formatter: formatter)
            .map(\.key)
            .filter { preferences.hiddenClients.contains($0) && known.contains($0) }
    }

    private func hiddenToolsMenu(_ hidden: [String]) -> some View {
        Menu {
            ForEach(hidden, id: \.self) { id in
                let name = VendorCatalog.clientLabel(id)
                Button {
                    setHidden(id, false)
                } label: {
                    Label(String(localized: "Show \(name) in the Tools list"), systemImage: "eye")
                }
            }
        } label: {
            Label {
                Text("Hidden tools: \(hidden.count)")
            } icon: {
                Image(systemName: "eye.slash")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(TMTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    private func togglePin(_ id: String) {
        let known = known
        model.updatePreferences { preferences in
            preferences.pinnedClients = ClientDisplayOrder.togglePinned(preferences.pinnedClients, id: id, known: known)
        }
    }

    private func setHidden(_ id: String, _ hidden: Bool) {
        model.updatePreferences { preferences in
            if hidden {
                if !preferences.hiddenClients.contains(id) { preferences.hiddenClients.append(id) }
            } else {
                preferences.hiddenClients.removeAll { $0 == id }
            }
        }
        if hidden { expanded.remove(id) }
    }
}

/// An expanded tool (`renderToolDetailAccordion`): token components, or its
/// models with their share of the tool when the Hub sent them; then the full
/// cost label.
private struct ToolDetail: View {
    @Environment(\.tmFormatter) private var formatter
    @ScaledMetric(relativeTo: .footnote) private var markSize: CGFloat = 12
    let row: AttributionRow
    let name: String
    @Binding var mode: ToolDetailMode

    var body: some View {
        let hasModels = !row.modelRows.isEmpty
        let shown: ToolDetailMode = mode == .models && hasModels ? .models : .tokens
        VStack(alignment: .leading, spacing: 8) {
            if hasModels {
                Picker(selection: $mode) {
                    Text("Tokens").tag(ToolDetailMode.tokens)
                    Text("Models").tag(ToolDetailMode.models)
                } label: {
                    Text(verbatim: name)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            switch shown {
            case .tokens:
                BreakdownsComponentRows(components: row.components)
            case .models:
                ForEach(row.modelRows) { model in
                    BreakdownsDetailRow(
                        title: Text(verbatim: model.isUnattributed ? String(localized: "Unclassified") : model.key),
                        percent: model.tokens > 0 ? AttributionRows.detailPercentLabel(model.percent ?? 0) : nil,
                        value: model.tokens > 0 ? formatter.fullTokens(model.tokens) : formatter.cost(model.costUsd)
                    ) {
                        VendorMark(.model(model.key), size: markSize)
                    }
                }
            }
            BreakdownsCostRow(costUsd: row.costUsd, unpricedTokens: row.unpricedTokens)
        }
    }
}

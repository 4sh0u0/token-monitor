import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Every model of the Overview's period (`modelRowsForPeriod`), with the
/// Unclassified remainder, ranked by tokens or cost (`modelRankingMetric`,
/// shared with Settings). A model expands to its token components.
struct ModelsView: View {
    @State private var expanded: Set<String> = []

    var body: some View {
        BreakdownsScreen("Models", breakdown: .model) { usage in
            ModelsList(usage: usage, expanded: $expanded)
        }
    }
}

private struct ModelsList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmPresentation) private var presentation
    @Environment(\.tmFormatter) private var formatter
    @ScaledMetric(relativeTo: .subheadline) private var markSize: CGFloat = 16

    let usage: UsagePeriod
    @Binding var expanded: Set<String>

    var body: some View {
        let requested = model.preferences.modelRankingMetric
        let rows = AttributionRows.modelRows(period: usage, ranking: requested, formatter: formatter)
        // Cost ranking needs a known cost; otherwise the desktop ranks by
        // tokens (`effectiveRankingMetric`).
        let metric = AttributionRows.effectiveRankingMetric(rows, metric: requested)
        rankingPicker(requested)
        if requested == .cost, metric == .tokens, !rows.isEmpty {
            Text("No model has a known cost in this period, so models are ranked by tokens.")
                .font(.footnote)
                .foregroundStyle(TMTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        if rows.isEmpty {
            BreakdownsEmptyNote(text: "No model usage in this period")
        } else {
            let total = metric == .cost ? usage.costUsd : Double(usage.totalTokens)
            UsageBar(
                segments: rows.map { UsageBar.Segment(id: $0.key, value: value(of: $0, metric: metric), color: color(of: $0)) },
                total: total,
                height: 8
            )
            let maximum = rows.map(\.barValue).max() ?? 0
            LazyVStack(spacing: 8) {
                ForEach(rows) { row in
                    modelRow(row, metric: metric, total: total, maximum: maximum)
                }
            }
        }
    }

    private func rankingPicker(_ requested: RankingMetric) -> some View {
        let ranking = Binding(
            get: { requested },
            set: { metric in model.updatePreferences { $0.modelRankingMetric = metric } }
        )
        return HStack(spacing: 12) {
            Text("Model ranking")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(TMTheme.muted)
            Spacer(minLength: 8)
            Picker("Model ranking", selection: ranking) {
                Text("Tokens").tag(RankingMetric.tokens)
                Text("Cost").tag(RankingMetric.cost)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    private func modelRow(_ row: AttributionRow, metric: RankingMetric, total: Double, maximum: Double) -> some View {
        let color = color(of: row)
        let name = row.isUnattributed ? String(localized: "Unclassified") : row.key
        return BreakdownsRow(
            name: name,
            tokens: row.tokens,
            costUsd: row.costUsd,
            unpricedTokens: row.unpricedTokens,
            barFraction: BreakdownsBar.fraction(row.barValue, max: maximum),
            barFill: AnyShapeStyle(color),
            share: breakdownsShareLabel(value(of: row, metric: metric), of: total),
            isExpanded: expanded.contains(row.key),
            onToggle: row.tokens > 0 ? { toggle(row.key) } : nil
        ) {
            VendorMark(.model(row.key, source: row.modelSource), size: markSize, dotColor: color)
        } detail: {
            VStack(alignment: .leading, spacing: 8) {
                BreakdownsComponentRows(components: row.components)
                BreakdownsCostRow(costUsd: row.costUsd, unpricedTokens: row.unpricedTokens)
            }
        }
    }

    private func value(of row: AttributionRow, metric: RankingMetric) -> Double {
        metric == .cost ? row.costUsd : Double(row.tokens)
    }

    /// The model's vendor colour (overrides applied) or its stable fallback;
    /// the `unknown` model takes Codex's colour when Codex accounts for all
    /// of it, else the muted colour (`modelRowsForPeriod`).
    private func color(of row: AttributionRow) -> Color {
        if row.key == "unknown" {
            return row.modelSource.map { VendorColor.color(for: $0, palette: presentation.palette) } ?? TMTheme.muted
        }
        return VendorColor.model(row.key, palette: presentation.palette)
    }

    private func toggle(_ key: String) {
        if expanded.contains(key) {
            expanded.remove(key)
        } else {
            expanded.insert(key)
        }
    }
}

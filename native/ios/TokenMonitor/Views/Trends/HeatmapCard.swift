import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The Activity mosaic block shared by the Overview module and the Trends
/// screen: the rolling-year grid (Sunday on top, localized month labels),
/// the selected day's detail, the Tokens/Cost metric toggle (the shared
/// `heatmapMetric` preference, which the Activity widget also follows) and
/// the Less/More legend. It draws no card of its own.
///
/// Cells grow to fill a wide screen (iPad); on a phone the grid keeps its
/// minimum cell size and scrolls sideways, opening on the newest week, as the
/// desktop Home's scroller does.
struct HeatmapCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmFormatter) private var formatter
    @ScaledMetric(relativeTo: .caption2) private var monthLabelSize: CGFloat = 9

    /// The mosaic (`HistoryStore.heatmap(metric:)` for the preference).
    let grid: HeatmapGrid
    /// Cell sizes: the smallest keeps cells tappable, the largest stops a
    /// wide window from stretching them.
    var cellSizes: ClosedRange<CGFloat> = 10...16

    @State private var selectedDate: String?
    @State private var width: CGFloat = 0

    private let spacing: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            mosaic
            if let selectedDate, let cell = grid.cell(on: selectedDate) {
                HeatmapCellDetail(cell: cell)
                    .transition(.opacity)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    metricPicker
                    Spacer(minLength: 0)
                    legend
                }
                VStack(alignment: .leading, spacing: 8) {
                    metricPicker
                    legend
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: selectedDate)
        .onChange(of: grid.endDate) { _, _ in
            // A new day (or scope) can drop the selected cell.
            if let selectedDate, grid.cell(on: selectedDate) == nil { self.selectedDate = nil }
        }
    }

    private var cellSize: CGFloat {
        ActivityHeatmapView.fittedCellSize(width: width, weeks: grid.weeks, spacing: spacing, range: cellSizes)
    }

    private var mosaic: some View {
        let size = cellSize
        return ScrollView(.horizontal, showsIndicators: false) {
            ActivityHeatmapView(
                grid: grid,
                cellSize: size,
                spacing: spacing,
                cornerRadius: size >= 12 ? 3 : 2,
                monthLabelSize: monthLabelSize,
                selectedDate: $selectedDate,
                monthLabel: TrendsFormat.monthLabel,
                cellLabel: cellLabel
            )
            .accessibilityLabel(Text("Activity heatmap"))
        }
        .defaultScrollAnchor(.trailing)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .trendsMeasuringWidth($width)
    }

    /// A cell's VoiceOver label: "Mon, Nov 3, 2025, 1.2M tokens".
    private func cellLabel(_ cell: HeatmapCell) -> String {
        let day = TrendsFormat.longDate(cell.date)
        let tokens = formatter.compactTokens(cell.tokens)
        return String(localized: "\(day), \(tokens) tokens")
    }

    private var metricPicker: some View {
        Picker("Heatmap color", selection: metricBinding) {
            Text("Tokens").tag(HeatmapMetric.tokens)
            Text("Cost").tag(HeatmapMetric.cost)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private var metricBinding: Binding<HeatmapMetric> {
        Binding(
            get: { model.preferences.heatmapMetric },
            set: { metric in
                guard metric != model.preferences.heatmapMetric else { return }
                model.updatePreferences { $0.heatmapMetric = metric }
            }
        )
    }

    private var legend: some View {
        HeatmapLegend(
            less: String(localized: "Less"),
            more: String(localized: "More"),
            cellSize: 10,
            spacing: spacing,
            cornerRadius: 2
        )
    }
}

/// A tapped day: its date, tokens and, when some cost is known or tokens are
/// unpriced, its cost ("—" when nothing is priced), plus the
/// `usage.excludedFromCost` note (the dashboard's heat tooltip).
private struct HeatmapCellDetail: View {
    @Environment(\.tmFormatter) private var formatter
    let cell: HeatmapCell

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: TrendsFormat.longDate(cell.date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(TMTheme.text)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                figure(title: "Tokens", value: formatter.compactTokens(cell.tokens))
                if cell.showsCost {
                    figure(title: "Cost", value: cell.hasUnknownCost ? "—" : formatter.cost(cell.costUsd))
                }
            }
            if let excluded = cell.excludedFromCostTokens {
                Text(verbatim: TrendsFormat.excludedFromCost(excluded, formatter: formatter))
                    .font(.caption2)
                    .foregroundStyle(TMTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func figure(title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(TMTheme.muted)
            Text(verbatim: value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(TMTheme.number)
        }
    }
}

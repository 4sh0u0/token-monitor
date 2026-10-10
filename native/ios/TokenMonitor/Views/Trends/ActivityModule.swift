import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The Overview "Activity" module (desktop Home `renderHomeTrendsModule`):
/// the rolling-year mosaic, then the 45-day "Trend" line of tokens with the
/// long-range "Peak {value}" and its first, middle and last dates. The header
/// links to Trends and carries the active-days chip (`homeActiveDaysWindow`).
///
/// It reads the current device scope's History from `model.history` (live
/// today patched in) and asks for it on appear. Like the desktop Home it
/// falls back silently to the stats' 30-day preview when `/api/history` is
/// unavailable. It draws its own card; the Overview places it as is.
struct ActivityModule: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.history
        let state = store.trendsLoadState
        let grid = state == .ready ? store.heatmap(metric: model.preferences.heatmapMetric) : .empty
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                ModuleHeader(title: "Activity", route: .trends) {
                    if state == .ready {
                        let window = model.preferences.homeActiveDaysWindow
                        Text(verbatim: TrendsFormat.activeDays(store.activeDays(window: window, grid: grid), window: window))
                            .font(.caption)
                            .foregroundStyle(TMTheme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                if state == .ready {
                    HeatmapCard(grid: grid, cellSizes: 10...14)
                    ActivityTrendLine(trend: store.homeTrend())
                } else {
                    TrendsStateView(state: state, compact: true)
                }
            }
        }
        .onAppear {
            model.history.ensureLoaded()
        }
    }
}

/// "TREND · Peak 48.2M" over the 45-day smooth area line and its three dates
/// (`homeTrendSummary`, `trendShortLabel`).
private struct ActivityTrendLine: View {
    @Environment(\.tmFormatter) private var formatter
    let trend: HomeTrend

    var body: some View {
        let peak = formatter.compactTokens(trend.longRangePeak)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Trend")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(TMTheme.text)
                Spacer(minLength: 8)
                Text(verbatim: String(localized: "Peak \(peak)"))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(1)
            }
            TrendsAreaLinePlot(points: trend.points)
                .frame(height: 70)
            HStack(spacing: 4) {
                ForEach(Array(trend.axisDates.enumerated()), id: \.offset) { index, date in
                    Text(verbatim: TrendsFormat.axisDate(date))
                        .frame(maxWidth: .infinity, alignment: alignment(index))
                }
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(TMTheme.muted)
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Trend"))
        .accessibilityValue(Text(verbatim: [
            TrendsFormat.lastDays(trend.points.count),
            String(localized: "Peak \(peak)")
        ].joined(separator: ", ")))
    }

    private func alignment(_ index: Int) -> Alignment {
        switch index {
        case 0: return .leading
        case trend.axisDates.count - 1: return .trailing
        default: return .center
        }
    }
}

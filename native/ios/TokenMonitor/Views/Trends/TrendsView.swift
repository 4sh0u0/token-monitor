import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The Trends screen (`AppRoute.trends`), the desktop's usage dashboard on
/// one page: the History stat cards, the Activity mosaic, the trend chart
/// (Bars / Line / K-line over 7 / 30 / 90 / 365 days or all History, stacked
/// by tool or model, in tokens or cost) and the top five tools and models
/// over the chart's range.
///
/// Everything follows the device scope through `model.history`. Chart
/// choices are app-local `@AppStorage` (the desktop keeps them in memory,
/// so they are not shared preferences). On the stats' 30-day preview (a
/// Hub without `/api/history`, or while a first load fails) only 7 and 30
/// days are offered and bars do not stack.
struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("trends.mode") private var mode: TrendChartMode = .bars
    @AppStorage("trends.range") private var range: TrendRange = .days30
    @AppStorage("trends.stack") private var stack: TrendStack = .client
    @AppStorage("trends.metric") private var metric: TrendMetricKind = .tokens

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .background {
            TMBackground().ignoresSafeArea()
        }
        .refreshable {
            model.history.refresh()
            await model.refresh()
        }
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.history.ensureLoaded()
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.presented == nil {
            DataPlaceholder()
        } else {
            let store = model.history
            let state = store.trendsLoadState
            ScopeBadge()
            if state == .ready {
                ready(store)
            } else {
                CardContainer {
                    TrendsStateView(state: state)
                }
            }
        }
    }

    @ViewBuilder
    private func ready(_ store: HistoryStore) -> some View {
        let ranges = store.isPreviewFallback ? [TrendRange.days7, .days30] : TrendRange.allCases
        let shownRange = ranges.contains(range) ? range : .days30
        let days = store.trendDays(shownRange)
        if let reason = store.trendsPreviewReason {
            previewNote(reason)
        }
        if let summary = store.summary {
            StatCardsGrid(summary: summary)
        }
        activity(store)
        TrendChartSection(
            days: days,
            canStack: store.canStack,
            ranges: ranges,
            mode: $mode,
            range: Binding(get: { shownRange }, set: { range = $0 }),
            stack: $stack,
            metric: $metric
        )
        TrendTopLists(days: days, range: shownRange)
    }

    private func activity(_ store: HistoryStore) -> some View {
        let grid = store.heatmap(metric: model.preferences.heatmapMetric)
        let window = model.preferences.homeActiveDaysWindow
        return CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                ModuleHeader(title: "Activity") {
                    Text(verbatim: TrendsFormat.activeDays(store.activeDays(window: window, grid: grid), window: window))
                        .font(.caption)
                        .foregroundStyle(TMTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                HeatmapCard(grid: grid)
            }
        }
    }

    private func previewNote(_ reason: TrendsPreviewReason) -> some View {
        switch reason {
        case .unsupported:
            return TrendsNote(
                systemImage: "info.circle",
                text: String(localized: "This Hub doesn’t provide full usage history, so Trends shows the last 30 days without tool or model detail.")
            )
        case .loadFailed:
            return TrendsNote(
                systemImage: "exclamationmark.triangle",
                text: String(localized: "Full usage history couldn’t be loaded, so Trends shows the last 30 days without tool or model detail."),
                actionTitle: "Try Again",
                action: { model.history.refresh() }
            )
        }
    }
}

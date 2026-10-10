import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Page 1: the period's total tokens, cost, output speed and a 14-day trend,
/// for the device scope the iPhone chose.
struct WatchUsagePage: View {
    static let trendDays = 14

    let store: WatchStore
    let snapshot: TokenSnapshot
    @Binding var period: UsagePeriodKind

    @Environment(\.tmFormatter) private var format

    var body: some View {
        // Empty for a scoped device: its daily history is not part of stats.
        let trend = Array(snapshot.trend.suffix(Self.trendDays))
        ScrollView {
            // At midnight (on the 1st for the month) the cached figures stop
            // being this period's; they read "—" until the next fetch, as on
            // the widgets and complications.
            TimelineView(.everyMinute) { timeline in
                let summary = snapshot.isCurrent(period, at: timeline.date) ? snapshot[period] : nil
                VStack(alignment: .leading, spacing: 4) {
                    WatchScopeLabel(scope: snapshot.scope)
                    Text("Tokens")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(TMTheme.muted)
                    Text(verbatim: summary.map { format.compactTokens($0.totalTokens) } ?? Self.noValue)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(TMTheme.number)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                    HStack(spacing: 6) {
                        Text(verbatim: summary.map(costText) ?? Self.noValue)
                        if let rate = summary?.outputTokensPerSecond, rate > 0 {
                            Text("\(format.liveTokenRate(rate)) tok/s")
                        }
                    }
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    if trend.count > 1 {
                        Sparkline(days: trend, color: TMTheme.chartBlue, lineWidth: 2, fillOpacity: 0.25)
                            .frame(height: 30)
                            .padding(.vertical, 4)
                    }
                    WatchFreshnessLine(store: store, snapshot: snapshot)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(WatchText.periodTitle(period))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    period = period.next
                } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("Period")
                .accessibilityValue(WatchText.periodTitle(period))
            }
        }
        .containerBackground(for: .tabView) { TMBackground() }
    }

    /// In place of a figure the cache no longer holds.
    static let noValue = "—"

    /// The compact cost: "$1.23 + ?" when some tokens had no price.
    private func costText(_ summary: PeriodSummary) -> String {
        WatchText.cost(format.costLabel(summary.costUsd, unpricedTokens: summary.unpricedTokens, compact: true, compactAmount: true))
    }
}

#Preview {
    NavigationStack {
        WatchUsagePage(store: WatchStore(), snapshot: .watchSample, period: .constant(.today))
    }
}

#Preview("Scoped, localized units") {
    NavigationStack {
        WatchUsagePage(store: WatchStore(), snapshot: .watchScopedSample, period: .constant(.month))
    }
    .tmPresentation(.watchSample)
}

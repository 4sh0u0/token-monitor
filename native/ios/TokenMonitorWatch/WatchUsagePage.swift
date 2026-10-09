import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Page 1: the period's total tokens, cost, output speed and a 14-day trend.
struct WatchUsagePage: View {
    static let trendDays = 14

    let store: WatchStore
    let snapshot: TokenSnapshot
    @Binding var period: UsagePeriodKind

    var body: some View {
        let summary = snapshot[period]
        let trend = Array(snapshot.trend.suffix(Self.trendDays))
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tokens")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(TMTheme.muted)
                Text(TokenFormat.compactTokens(summary.totalTokens))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.number)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    Text(TokenFormat.usd(summary.costUsd))
                    if let rate = summary.outputTokensPerSecond {
                        Text("\(TokenFormat.tokensPerSecond(rate)) tok/s")
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
}

#Preview {
    NavigationStack {
        WatchUsagePage(store: WatchStore(), snapshot: .watchSample, period: .constant(.today))
    }
}

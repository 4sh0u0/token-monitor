import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Page 2: the period's top tools with their share of its tokens.
struct WatchToolsPage: View {
    let snapshot: TokenSnapshot
    let period: UsagePeriodKind

    var body: some View {
        let summary = snapshot[period]
        let rows = summary.tools(otherLabel: String(localized: "Other"))
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(WatchText.periodTitle(period))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(TMTheme.accent)
                if rows.isEmpty || summary.totalTokens <= 0 {
                    Text("No data")
                        .font(.footnote)
                        .foregroundStyle(TMTheme.muted)
                } else {
                    UsageBar(shares: rows, total: summary.totalTokens, height: 6)
                        .padding(.bottom, 2)
                    ForEach(rows) { share in
                        WatchToolRow(share: share, total: summary.totalTokens)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Tools")
        .containerBackground(for: .tabView) { TMBackground() }
    }
}

struct WatchToolRow: View {
    let share: UsageShare
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(share.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(share.label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TMTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            Text(TokenFormat.compactTokens(share.tokens))
                .font(.caption2)
                .foregroundStyle(TMTheme.muted)
            Text(TokenFormat.percent(share.fraction(of: total) * 100))
                .font(.caption2.weight(.medium))
                .foregroundStyle(TMTheme.text)
                .frame(minWidth: 30, alignment: .trailing)
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        WatchToolsPage(snapshot: .watchSample, period: .today)
    }
}

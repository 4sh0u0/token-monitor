import SwiftUI
import TokenMonitorKit
import TokenMonitorUI
import WidgetKit

/// Today's tokens and cost.
struct UsageComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ComplicationKind.usage, provider: ComplicationProvider()) { entry in
            UsageComplicationView(entry: entry)
                .containerBackground(for: .widget) { TMBackground() }
        }
        .configurationDisplayName("Token Monitor Summary")
        .description("Tokens, cost, and a compact trend.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct UsageComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            ComplicationPlaceholderView(isConfigured: entry.isConfigured)
        }
    }

    @ViewBuilder
    private func content(_ snapshot: TokenSnapshot) -> some View {
        let isCurrentDay = ComplicationContent.isCurrentDay(snapshot, at: entry.date)
        let tokens = isCurrentDay ? TokenFormat.compactTokens(snapshot.today.totalTokens) : "—"
        let cost = isCurrentDay ? TokenFormat.usd(snapshot.today.costUsd) : "—"
        switch family {
        case .accessoryRectangular:
            AccessorySummaryView(
                title: title(snapshot),
                value: tokens,
                detail: isCurrentDay ? detail(snapshot, cost: cost) : nil,
                trend: ComplicationContent.trend(snapshot)
            )
        case .accessoryInline:
            Label {
                Text(verbatim: "\(tokens) · \(cost)")
            } icon: {
                Image(systemName: "chart.bar.fill")
            }
        case .accessoryCorner:
            Text(verbatim: tokens)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .widgetAccentable()
                .widgetLabel {
                    Text(verbatim: cost)
                }
        default:
            AccessoryTokensGauge(
                valueText: tokens,
                label: String(localized: "Today"),
                fraction: isCurrentDay ? ComplicationContent.busiestDayFraction(snapshot) : nil
            )
        }
    }

    /// "Today", or "Today · 2 hr. ago" once the numbers are old.
    private func title(_ snapshot: TokenSnapshot) -> String {
        let today = String(localized: "Today")
        guard snapshot.isOlder(than: ComplicationContent.staleAge, at: entry.date) else { return today }
        return "\(today) · \(TokenFormat.relative(snapshot.fetchedAt, to: entry.date))"
    }

    /// "$122.83 · Claude 57%".
    private func detail(_ snapshot: TokenSnapshot, cost: String) -> String {
        let total = snapshot.today.totalTokens
        guard let top = snapshot.today.tools.first, total > 0 else { return cost }
        return "\(cost) · \(top.label) \(TokenFormat.percent(top.fraction(of: total) * 100))"
    }
}

#Preview(as: .accessoryRectangular) {
    UsageComplication()
} timeline: {
    ComplicationEntry.sample
    ComplicationEntry(date: .now, snapshot: nil, isConfigured: false)
}

#Preview(as: .accessoryCircular) {
    UsageComplication()
} timeline: {
    ComplicationEntry.sample
}

#Preview(as: .accessoryCorner) {
    UsageComplication()
} timeline: {
    ComplicationEntry.sample
}

#Preview(as: .accessoryInline) {
    UsageComplication()
} timeline: {
    ComplicationEntry.sample
}

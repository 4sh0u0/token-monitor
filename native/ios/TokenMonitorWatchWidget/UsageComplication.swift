import SwiftUI
import TokenMonitorKit
import TokenMonitorUI
import WidgetKit

/// Today's tokens and cost, for the device scope the iPhone chose.
struct UsageComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ComplicationKind.usage, provider: ComplicationProvider()) { entry in
            UsageComplicationView(entry: entry)
                .tmPresentation(entry.context)
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
        let format = entry.context.formatter
        let today = snapshot.today
        // A snapshot fetched yesterday says nothing about today's usage.
        let isCurrentDay = snapshot.isCurrent(.today, at: entry.date)
        let tokens = isCurrentDay ? format.compactTokens(today.totalTokens) : "—"
        let cost = isCurrentDay
            ? ComplicationText.cost(format.costLabel(today.costUsd, unpricedTokens: today.unpricedTokens, compact: true, compactAmount: true))
            : "—"
        switch family {
        case .accessoryRectangular:
            AccessorySummaryView(
                title: title(snapshot),
                value: tokens,
                detail: isCurrentDay ? detail(snapshot, cost: cost, format: format) : nil,
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

    /// "Today", "Today · Studio Mac" for a scoped device, then "· 2h ago"
    /// once the numbers are old.
    private func title(_ snapshot: TokenSnapshot) -> String {
        var parts = [String(localized: "Today")]
        if let scope = snapshot.scope, !scope.isMissing {
            parts.append(scope.deviceName)
        }
        if snapshot.isOlder(than: entry.timing.staleAge, at: entry.date) {
            parts.append(ComplicationText.age(of: snapshot.fetchedAt, at: entry.date))
        }
        return parts.joined(separator: " · ")
    }

    /// "$122.83 · Claude 57%": the cost, then today's biggest visible tool.
    private func detail(_ snapshot: TokenSnapshot, cost: String, format: DisplayFormatter) -> String {
        let total = snapshot.today.totalTokens
        guard total > 0, let top = ComplicationContent.topTool(snapshot.today, preferences: entry.context.preferences) else {
            return cost
        }
        return "\(cost) · \(top.label) \(format.percent(top.fraction(of: total) * 100))"
    }
}

#Preview(as: .accessoryRectangular) {
    UsageComplication()
} timeline: {
    ComplicationEntry.sample
    ComplicationEntry.sample(context: .complicationSample, snapshot: .complicationScopedSample)
    ComplicationEntry(date: .now, snapshot: nil, isConfigured: false)
}

#Preview(as: .accessoryCircular) {
    UsageComplication()
} timeline: {
    ComplicationEntry.sample
    ComplicationEntry.sample(context: .complicationSample)
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
    ComplicationEntry.sample(context: .complicationSample)
}

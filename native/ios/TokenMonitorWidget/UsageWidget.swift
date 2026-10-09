import SwiftUI
import TokenMonitorKit
import TokenMonitorUI
import WidgetKit

/// Usage: tokens and cost of a period, on the Home Screen and the Lock Screen.
struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetKind.usage,
            intent: UsageWidgetIntent.self,
            provider: UsageTimelineProvider()
        ) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Usage")
        .description("Tokens, cost, trend, and top tools for a period.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TokenEntry

    var body: some View {
        WidgetChrome(url: url) {
            content
        }
    }

    private var url: URL {
        if case .notConfigured = entry.state { return WidgetLink.settings }
        return WidgetLink.dashboard(entry.period)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case .notConfigured:
            WidgetMessageView(message: .notConfigured)
        case .unavailable:
            WidgetMessageView(message: .unavailable)
        case .ready(let snapshot):
            ready(snapshot)
        }
    }

    @ViewBuilder
    private func ready(_ snapshot: TokenSnapshot) -> some View {
        switch family {
        case .systemMedium:
            UsageMediumView(entry: entry, snapshot: snapshot)
        case .systemLarge:
            UsageLargeView(entry: entry, snapshot: snapshot)
        case .accessoryCircular:
            UsageCircularView(entry: entry, snapshot: snapshot)
        case .accessoryRectangular:
            UsageRectangularView(entry: entry, snapshot: snapshot)
        case .accessoryInline:
            UsageInlineView(entry: entry, snapshot: snapshot)
        default:
            UsageSmallView(entry: entry, snapshot: snapshot)
        }
    }
}

#Preview(as: .systemSmall) {
    UsageWidget()
} timeline: {
    TokenEntry.preview()
    TokenEntry.preview(period: .month, fetchedMinutesAgo: 45)
    TokenEntry.previewState(.notConfigured)
}

#Preview(as: .systemMedium) {
    UsageWidget()
} timeline: {
    TokenEntry.preview()
    TokenEntry.preview(period: .allTime, breakdown: .models)
    TokenEntry.previewState(.unavailable)
}

#Preview(as: .systemLarge) {
    UsageWidget()
} timeline: {
    TokenEntry.preview()
    TokenEntry.preview(period: .month, breakdown: .models, fetchedMinutesAgo: 45)
}

#Preview(as: .accessoryCircular) {
    UsageWidget()
} timeline: {
    TokenEntry.preview()
    TokenEntry.preview(period: .month)
}

#Preview(as: .accessoryRectangular) {
    UsageWidget()
} timeline: {
    TokenEntry.preview()
    TokenEntry.preview(period: .allTime, fetchedMinutesAgo: 45)
}

#Preview(as: .accessoryInline) {
    UsageWidget()
} timeline: {
    TokenEntry.preview()
    TokenEntry.previewState(.notConfigured)
}

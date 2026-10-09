import SwiftUI
import TokenMonitorKit
import TokenMonitorUI
import WidgetKit

/// AI Tool Limits: quota windows and when they reset, most constrained first
/// unless one provider is pinned.
struct LimitsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetKind.limits,
            intent: LimitsWidgetIntent.self,
            provider: LimitsTimelineProvider()
        ) { entry in
            LimitsWidgetView(entry: entry)
        }
        .configurationDisplayName("AI Tool Limits")
        .description("Subscription windows and reset times.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct LimitsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TokenEntry

    var body: some View {
        WidgetChrome(url: url) {
            content
        }
    }

    private var url: URL {
        if case .notConfigured = entry.state { return WidgetLink.settings }
        return WidgetLink.limits
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
        if let lead = LimitSelection.providers(in: snapshot, pinnedID: entry.pinnedLimitID, limit: 1).first {
            switch family {
            case .systemMedium:
                LimitsMediumView(entry: entry, snapshot: snapshot)
            case .accessoryCircular:
                LimitsCircularView(provider: lead)
            case .accessoryRectangular:
                LimitsRectangularView(provider: lead, now: entry.date)
            default:
                LimitsSmallView(entry: entry, provider: lead)
            }
        } else {
            WidgetMessageView(message: .noLimits)
        }
    }
}

#Preview(as: .systemSmall) {
    LimitsWidget()
} timeline: {
    TokenEntry.preview()
    TokenEntry.preview(pinnedLimitID: "deepseek-sample")
    TokenEntry.previewState(.notConfigured)
}

#Preview(as: .systemMedium) {
    LimitsWidget()
} timeline: {
    TokenEntry.preview()
    TokenEntry.preview(pinnedLimitID: "claude-sample", fetchedMinutesAgo: 45)
}

#Preview(as: .accessoryCircular) {
    LimitsWidget()
} timeline: {
    TokenEntry.preview()
    TokenEntry.preview(pinnedLimitID: "openrouter-sample")
}

#Preview(as: .accessoryRectangular) {
    LimitsWidget()
} timeline: {
    TokenEntry.preview()
    TokenEntry.previewState(.unavailable)
}

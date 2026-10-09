import AppIntents
import SwiftUI
import TokenMonitorKit
import TokenMonitorUI
import WidgetKit

/// Small uppercase section label ("TODAY", "TOOLS").
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(TMTheme.muted)
            .lineLimit(1)
    }
}

/// The subtle "data may be stale" mark next to a header.
struct StaleBadge: View {
    var body: some View {
        Image(systemName: "clock.badge.exclamationmark")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(TMTheme.caution)
            .accessibilityLabel(Text("Data may be stale"))
    }
}

/// Period label plus the stale mark, as the top line of the usage widgets.
struct PeriodHeader: View {
    let period: UsagePeriodKind
    let isStale: Bool

    var body: some View {
        HStack(spacing: 4) {
            SectionLabel(text: WidgetText.shortPeriod(period))
            if isStale { StaleBadge() }
        }
    }
}

/// "Updated 14:05" — when this phone last read the Hub.
struct UpdatedFootnote: View {
    let snapshot: TokenSnapshot
    let now: Date
    let isStale: Bool

    var body: some View {
        Text(WidgetText.updated(snapshot.fetchedAt, now: now))
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(isStale ? TMTheme.caution : TMTheme.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityHint(isStale ? Text("Data may be stale") : Text(verbatim: ""))
    }
}

/// The interactive refresh button (iOS 17) of medium and large widgets.
struct RefreshButton: View {
    var body: some View {
        Button(intent: RefreshUsageIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TMTheme.muted)
                .frame(width: 24, height: 20, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Refresh"))
    }
}

/// The headline token count; `WidgetText.noValue` when it is unknown.
struct TotalTokensText: View {
    let tokens: Int?
    let size: CGFloat

    var body: some View {
        Text(tokens.map(WidgetText.tokens) ?? WidgetText.noValue)
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(TMTheme.number)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
            .widgetAccentable()
    }
}

/// The smooth trend line. The area fill only reads in full colour; tinted
/// and vibrant modes flatten it into a solid block.
struct TrendLine: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let values: [Double]

    var body: some View {
        if values.count > 1 {
            Sparkline(
                values: values,
                color: TMTheme.chartBlue,
                lineWidth: 1.8,
                fillOpacity: renderingMode == .fullColor ? 0.22 : 0
            )
            .widgetAccentable()
        } else {
            Color.clear
        }
    }
}

struct VendorDot: View {
    let color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(TMTheme.divider)
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

/// A full-widget message: not connected, Hub unreachable, nothing to show.
struct WidgetMessage {
    let symbol: String
    let title: String
    let detail: String?
    /// The one line an inline (and rectangular) Lock Screen widget shows.
    let short: String
    /// Offer the refresh button (medium/large) — when trying again can help.
    var offersRefresh: Bool = false

    static var notConfigured: WidgetMessage {
        WidgetMessage(
            symbol: "link",
            title: String(localized: "Not connected"),
            detail: String(localized: "Open Token Monitor to connect a Hub"),
            short: String(localized: "Connect a Hub")
        )
    }

    static var unavailable: WidgetMessage {
        WidgetMessage(
            symbol: "wifi.exclamationmark",
            title: String(localized: "Waiting for data"),
            detail: String(localized: "Can't reach the Hub"),
            short: String(localized: "Can't reach the Hub"),
            offersRefresh: true
        )
    }

    static var noLimits: WidgetMessage {
        WidgetMessage(
            symbol: "gauge",
            title: String(localized: "No limits yet"),
            detail: nil,
            short: String(localized: "No limits yet")
        )
    }
}

struct WidgetMessageView: View {
    @Environment(\.widgetFamily) private var family
    let message: WidgetMessage

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: message.symbol)
                    .font(.title3.weight(.semibold))
                    .widgetAccentable()
            }
            .accessibilityLabel(Text(message.short))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Token Monitor")
                    .font(.headline)
                    .widgetAccentable()
                Text(message.short)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Text(message.short)
        default:
            systemBody
        }
    }

    private var systemBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Image(systemName: message.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(TMTheme.accent)
                    .widgetAccentable()
                Spacer(minLength: 0)
                if message.offersRefresh && family != .systemSmall {
                    RefreshButton()
                }
            }
            Spacer(minLength: 0)
            Text(message.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TMTheme.text)
                .lineLimit(2)
            if let detail = message.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

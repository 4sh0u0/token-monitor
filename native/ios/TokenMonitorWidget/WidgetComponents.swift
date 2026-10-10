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

/// The device the numbers follow (`deviceScope`), shown while one device is
/// scoped. The name is the Hub's, shown as is.
struct ScopeLabel: View {
    let name: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 8, weight: .semibold))
                .accessibilityHidden(true)
            Text(verbatim: name)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(TMTheme.muted)
        .layoutPriority(-1)
    }
}

/// Period label, the scoped device and the stale mark, as the top line of
/// the usage widgets.
struct PeriodHeader: View {
    let period: UsagePeriodKind
    let isStale: Bool
    var scopeName: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            SectionLabel(text: WidgetText.shortPeriod(period))
            if let scopeName { ScopeLabel(name: scopeName) }
            if isStale { StaleBadge() }
        }
    }
}

/// "Updated 14:05" — when this phone last read the Hub.
struct UpdatedFootnote: View {
    let fetchedAt: Date
    let now: Date
    let isStale: Bool

    var body: some View {
        Text(WidgetText.updated(fetchedAt, now: now))
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

/// The headline token count in the user's units; `WidgetText.noValue` when
/// it is unknown.
struct TotalTokensText: View {
    @Environment(\.tmFormatter) private var format
    let tokens: Int?
    let size: CGFloat

    var body: some View {
        Text(tokens.map { format.compactTokens($0) } ?? WidgetText.noValue)
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

/// The neutral dot of a breakdown's "Other" row, which stands for no vendor.
struct RemainderDot: View {
    var size: CGFloat = 12

    var body: some View {
        Circle()
            .fill(ShareStyle.remainderColor)
            .frame(width: size * 0.7, height: size * 0.7)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The leading mark of a Tools/Models row: the vendor icon or, with tool
/// icons off, the vendor-colour dot (`VendorMark`).
struct ShareMark: View {
    let share: UsageShare
    var size: CGFloat = 12

    var body: some View {
        switch share.kind {
        case .client:
            VendorMark(.client(share.vendorID ?? share.id), size: size)
        case .model:
            VendorMark(.model(share.id), size: size)
        case .remainder:
            RemainderDot(size: size)
        }
    }
}

/// The colours of breakdown rows, with the user's vendor-colour overrides.
enum ShareStyle {
    /// The remainder is drawn neutral so it never reads as one more vendor.
    static let remainderColor = TMTheme.muted.opacity(0.55)

    static func color(_ share: UsageShare, palette: VendorPalette) -> Color {
        switch share.kind {
        case .client: return VendorColor.color(for: share.vendorID ?? share.id, palette: palette)
        case .model: return VendorColor.model(share.id, palette: palette)
        case .remainder: return remainderColor
        }
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
            detail: String(localized: "Can’t reach the Hub"),
            short: String(localized: "Can’t reach the Hub"),
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

    /// The app has not written the Activity file for this Hub and scope yet:
    /// it does after loading History, which the widget never decodes itself.
    static var noActivity: WidgetMessage {
        WidgetMessage(
            symbol: "square.grid.3x3.fill",
            title: String(localized: "No activity yet"),
            detail: String(localized: "Open Token Monitor to load activity"),
            short: String(localized: "Open Token Monitor to load activity")
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

import SwiftUI
import TokenMonitorKit
import TokenMonitorUI
import WidgetKit

enum ComplicationContent {
    static let trendDays = 14

    static func trend(_ snapshot: TokenSnapshot) -> [Double] {
        snapshot.trend.suffix(trendDays).map { Double($0.tokens) }
    }

    /// Today against the busiest day of the trend (today included), for the
    /// circular gauge; nil when there is nothing to compare (a scoped device
    /// has no trend).
    static func busiestDayFraction(_ snapshot: TokenSnapshot) -> Double? {
        let today = snapshot.today.totalTokens
        let trend = snapshot.trend.suffix(trendDays).map(\.tokens)
        guard !trend.isEmpty else { return nil }
        let peak = max(today, trend.max() ?? 0)
        guard peak > 0 else { return nil }
        return Double(today) / Double(peak)
    }

    /// Today's biggest tool among those the user did not hide.
    static func topTool(_ summary: PeriodSummary, preferences: DisplayPreferences) -> UsageShare? {
        let visible = ClientDisplayOrder.apply(summary.tools, id: \.id, preferences: preferences, known: VendorCatalog.trackedClientIDs)
        return visible.max { $0.tokens < $1.tokens }
    }
}

/// One line of the Quota complication: a provider's headline window, one
/// window of a single provider, or a provider whose reading needs attention
/// (its status label instead of a value).
struct ComplicationQuotaRow: Identifiable {
    let id: String
    let title: String
    let provider: LimitProvider
    /// Nil for a status row.
    let window: LimitWindow?
    let context: PresentationContext

    private var showUsed: Bool { context.preferences.showLimitUsed }

    /// The localized status chip of a reading that is not healthy.
    var status: String? {
        guard provider.status != .ok else { return nil }
        return ComplicationText.statusLabel(LimitPresentation.statusChip(provider).label)
    }

    /// What is left, 0...1, whatever the used/remaining choice (gauges
    /// always fill by what is left); nil when the window draws no meter.
    var fraction: Double? {
        guard status == nil, let window else { return nil }
        return LimitPresentation.gaugeFill(window: window, provider: provider, showUsed: showUsed).remainingFraction
    }

    private var headline: LimitPresentation.Headline? {
        window.map { LimitPresentation.headline(window: $0, provider: provider, showUsed: showUsed) }
    }

    /// "58%" (used or left, as the user chose) or a compact amount; the
    /// status for a row that needs attention.
    var value: String {
        if let status { return status }
        return headline.map { ComplicationText.shortValue($0, format: context.formatter) } ?? "—"
    }

    /// "58% left" / "42% used" where there is room (inline).
    var longValue: String {
        if let status { return status }
        return headline.map { ComplicationText.longValue($0, format: context.formatter) } ?? "—"
    }

    /// Calm while there is room, amber then red as it runs out; stale
    /// readings and status rows are muted.
    var tint: Color {
        guard status == nil, !provider.isStale else { return TMTheme.muted }
        return TMTheme.quotaColor(remainingFraction: fraction)
    }

    /// The providers the Quota complication considers: every reading but the
    /// providers hidden from Home (`hiddenHomeLimitProviders`), each narrowed
    /// to the windows the user left visible.
    static func providers(in snapshot: TokenSnapshot, preferences: DisplayPreferences) -> [LimitProvider] {
        let hidden = Set(preferences.hiddenHomeLimitProviders.map(OrderedIDs.normalizeID))
        return snapshot.limits
            .filter { !hidden.contains(OrderedIDs.normalizeID($0.provider)) }
            .map { provider in
                var visible = provider
                visible.windows = LimitPresentation.visibleWindows(provider, prefs: preferences)
                return visible
            }
    }

    /// Tightest first (`LimitProvider.sortedByUrgency`, the iOS Limits
    /// widget's automatic order while no Home provider order is set; the
    /// complication always leads with the tightest window): healthy readings
    /// by what is left of their headline window, stale ones after them, then
    /// the providers that need attention (signed out, limited, failing) with
    /// their status. Providers the user turned off or never set up are left
    /// out.
    static func headlines(in snapshot: TokenSnapshot, context: PresentationContext, limit: Int) -> [ComplicationQuotaRow] {
        let sorted = LimitProvider.sortedByUrgency(providers(in: snapshot, preferences: context.preferences))
        let healthy = sorted.filter { $0.status == .ok }.compactMap { provider -> ComplicationQuotaRow? in
            guard let window = provider.headlineWindow else { return nil }
            return ComplicationQuotaRow(id: provider.id, title: provider.displayName, provider: provider, window: window, context: context)
        }
        let attention = sorted.filter { needsAttention($0.status) }.map { provider in
            ComplicationQuotaRow(id: provider.id, title: provider.displayName, provider: provider, window: nil, context: context)
        }
        return Array((healthy + attention).prefix(max(0, limit)))
    }

    private static func needsAttention(_ status: LimitStatus) -> Bool {
        switch status {
        case .ok, .disabled, .notConfigured: return false
        case .unauthorized, .rateLimited, .sourceRateLimited, .unavailable, .error: return true
        }
    }

    /// The rectangular family's rows: one per provider, or, when only one
    /// provider reports, its windows.
    static func rectangularRows(in snapshot: TokenSnapshot, context: PresentationContext, limit: Int) -> (header: String?, rows: [ComplicationQuotaRow]) {
        let headlines = headlines(in: snapshot, context: context, limit: limit)
        guard headlines.count == 1, let only = headlines.first, only.status == nil else { return (nil, headlines) }
        let windows = only.provider.windows.prefix(max(1, limit - 1)).map { window in
            ComplicationQuotaRow(
                id: "\(only.provider.id)|\(window.id)",
                title: ComplicationText.windowName(LimitPresentation.windowName(window, provider: only.provider)),
                provider: only.provider,
                window: window,
                context: context
            )
        }
        return (only.provider.displayName, windows)
    }
}

/// Before the first snapshot: where to go, or that data is on its way.
struct ComplicationPlaceholderView: View {
    @Environment(\.widgetFamily) private var family
    let isConfigured: Bool

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Token Monitor")
                    .font(.headline)
                    .widgetAccentable()
                if isConfigured {
                    Text("Waiting for data")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Open Token Monitor on your iPhone")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Text(verbatim: "Token Monitor")
        case .accessoryCorner:
            Image(systemName: symbol)
                .font(.title3)
                .widgetAccentable()
                .widgetLabel {
                    Text(verbatim: "Token Monitor")
                }
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: symbol)
                    .font(.title3)
                    .widgetAccentable()
            }
        }
    }

    private var symbol: String { isConfigured ? "hourglass" : "iphone" }
}

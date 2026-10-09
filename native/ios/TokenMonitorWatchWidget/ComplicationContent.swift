import SwiftUI
import TokenMonitorKit
import TokenMonitorUI
import WidgetKit

enum ComplicationContent {
    static let trendDays = 14
    /// Older than this, the rectangular usage complication says how old.
    static let staleAge: TimeInterval = 60 * 60

    static func trend(_ snapshot: TokenSnapshot) -> [Double] {
        snapshot.trend.suffix(trendDays).map { Double($0.tokens) }
    }

    /// Today against the busiest day of the trend (today included), for the
    /// circular gauge; nil when there is nothing to compare.
    static func busiestDayFraction(_ snapshot: TokenSnapshot) -> Double? {
        let today = snapshot.today.totalTokens
        let peak = max(today, snapshot.trend.suffix(trendDays).map(\.tokens).max() ?? 0)
        guard peak > 0 else { return nil }
        return Double(today) / Double(peak)
    }

    static func windowTitle(_ window: LimitWindow) -> String {
        if let label = window.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        switch window.metric {
        case .credits: return String(localized: "Balance")
        case .spend: return String(localized: "Spend")
        case nil: break
        }
        switch window.kind {
        case .session: return String(localized: "Session")
        case .daily: return String(localized: "Daily")
        case .weekly: return String(localized: "Weekly")
        case .billing: return String(localized: "Billing")
        }
    }

    /// "58%" or a compact amount: complications have no room for "left".
    static func shortValue(_ window: LimitWindow, in provider: LimitProvider) -> String {
        if window.isMoney {
            if window.isUnlimited { return "∞" }
            let amount = window.isCredits ? (window.remaining ?? provider.balance?.amount) : window.used
            return amount.map { TokenFormat.compactMoney($0, currency: window.currency ?? provider.balance?.currency) } ?? "—"
        }
        return window.remainingPercent.map { TokenFormat.percent($0) } ?? "—"
    }
}

/// One quota meter on a complication: a provider's headline window, or one
/// window of a single provider.
struct ComplicationQuotaRow: Identifiable {
    let id: String
    let title: String
    let provider: LimitProvider
    let window: LimitWindow

    /// What is left, 0...1; nil when the window must not draw a meter.
    var fraction: Double? { provider.meterFraction(for: window) }
    var value: String { ComplicationContent.shortValue(window, in: provider) }
    var tint: Color { TMTheme.quotaColor(remainingFraction: fraction) }

    /// Providers worth a complication: healthy readings with a headline
    /// window, tightest first (`LimitProvider.sortedByUrgency`, the iOS
    /// Limits widget's order): fresh readings before stale ones, then the
    /// least left, then windows without a meter.
    static func headlines(in snapshot: TokenSnapshot, limit: Int) -> [ComplicationQuotaRow] {
        let rows = LimitProvider.sortedByUrgency(snapshot.limits)
            .filter { $0.status == .ok }
            .compactMap { provider -> ComplicationQuotaRow? in
                guard let window = provider.headlineWindow else { return nil }
                return ComplicationQuotaRow(id: provider.id, title: provider.displayName, provider: provider, window: window)
            }
        return Array(rows.prefix(limit))
    }

    /// The rectangular family's rows: one per provider, or, when only one
    /// provider reports, its windows.
    static func rectangularRows(in snapshot: TokenSnapshot, limit: Int) -> (header: String?, rows: [ComplicationQuotaRow]) {
        let headlines = headlines(in: snapshot, limit: limit)
        guard headlines.count == 1, let only = headlines.first else { return (nil, headlines) }
        let windows = only.provider.primaryWindows.prefix(max(1, limit - 1)).map { window in
            ComplicationQuotaRow(id: "\(only.provider.id)|\(window.id)", title: ComplicationContent.windowTitle(window), provider: only.provider, window: window)
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

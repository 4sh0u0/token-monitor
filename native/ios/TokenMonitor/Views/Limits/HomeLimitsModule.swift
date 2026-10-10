import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The Overview's Limits module (desktop Home `renderHomeLimitModule`): the
/// accounts with the least left first (or in the user's Home provider order),
/// at most `homeLimitAccountCount`, each with up to two windows as text or
/// progress bars.
///
/// A self-contained card, like the other Overview modules; its title opens
/// the Limits tab (a tab, not an `AppRoute`). It draws nothing while there is
/// no account to show (no stats yet, or no account with a window left after
/// the user's hidden providers and items).
///
/// Values follow the used/remaining choice; the low-limit highlight
/// (`showHomeLimitBars`) always keys on what is left. Provider names show
/// when several accounts need telling apart, and always when the user asks
/// or tool icons are off. Limits never follow the device scope.
struct HomeLimitsModule: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let rows = Self.rows(model)
        if rows.isEmpty {
            EmptyView()
        } else {
            CardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(rows) { row in
                                HomeLimitRowView(row: row, now: context.date)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The accounts the module lists; none: it draws nothing.
    static func rows(_ model: AppModel) -> [LimitPresentation.HomeLimitRow] {
        LimitPresentation.homeRows(model.stats?.limits ?? [], prefs: model.preferences)
    }

    private var header: some View {
        Button {
            model.selectedTab = .limits
        } label: {
            ModuleHeader(title: "Limits") {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TMTheme.muted)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens the Limits tab"))
    }
}

/// One account: mark, name and plan, then its windows side by side.
private struct HomeLimitRowView: View {
    let row: LimitPresentation.HomeLimitRow
    let now: Date

    @Environment(\.tmPresentation) private var presentation
    @ScaledMetric(relativeTo: .subheadline) private var markSize: CGFloat = 12

    var body: some View {
        let bars = presentation.preferences.homeLimitDisplayMode == .bars
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Follows Tool Icons: a dot in the provider's colour when off.
                VendorMark(.provider(row.iconID), size: markSize)
                Text(verbatim: LimitText.homeRowName(row.name))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(row.provider.isStale ? TMTheme.muted : TMTheme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let plan = LimitText.plan(row.plan) {
                    Text(verbatim: plan)
                        .font(.caption)
                        .foregroundStyle(TMTheme.muted)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }
            .accessibilityElement(children: .combine)
            HStack(alignment: .top, spacing: 16) {
                ForEach(row.windows) { window in
                    HomeLimitWindowView(window: window, providerID: row.providerID, tint: tint, bars: bars, now: now)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // Text mode lines the windows up under the name, past the mark.
            .padding(.leading, bars ? 0 : markSize + 8)
        }
    }

    private var tint: Color {
        VendorColor.color(for: row.providerID, palette: presentation.palette)
    }
}

/// One Home window: its name and value, a bar in bars mode, and when it
/// resets.
private struct HomeLimitWindowView: View {
    let window: LimitPresentation.HomeLimitWindow
    let providerID: String
    let tint: Color
    let bars: Bool
    let now: Date

    @Environment(\.tmPresentation) private var presentation
    @Environment(\.tmFormatter) private var format

    var body: some View {
        let prefs = presentation.preferences
        let label = LimitText.homeWindowLabel(window.label)
        let value = LimitText.headline(LimitPresentation.homeValue(window, showUsed: prefs.showLimitUsed), format: format, compactMoney: true)
        let severity = prefs.showHomeLimitBars ? LimitPresentation.homeSeverity(remainingPercent: window.remainingPercent) : nil
        let boundary = boundaryText
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: label)
                    .font(.caption)
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    if severity == .critical {
                        Circle()
                            .fill(TMTheme.critical)
                            .frame(width: 4, height: 4)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: value)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(valueColor(severity))
                        .lineLimit(1)
                }
            }
            if bars, let meter = LimitPresentation.homeMeter(window, showUsed: prefs.showLimitUsed) {
                LimitMeter(fill: meter, color: tint, height: 4)
            }
            if let boundary {
                Text(verbatim: boundary)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: [value, boundary].compactMap { $0 }.joined(separator: ", ")))
    }

    /// "Reset in 2h 30m", with Antigravity's lane in front ("5-hour · …").
    private var boundaryText: String? {
        guard let line = LimitPresentation.homeBoundaryLine(window, now: now) else { return nil }
        let text = LimitText.boundary(line)
        guard let period = window.periodLabel else { return text }
        return LimitText.kindName(period) + " · " + text
    }

    /// Under 20% left red (with a dot), under 50% yellow.
    private func valueColor(_ severity: LimitPresentation.HomeSeverity?) -> Color {
        switch severity {
        case .critical: return TMTheme.critical
        case .low: return TMTheme.warning
        case nil: return TMTheme.text
        }
    }
}

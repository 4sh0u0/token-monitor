import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Page 3: AI tool quota windows, in the user's Limits provider order, each
/// provider with its status chip and the windows the user left visible.
///
/// Limits never follow the device scope (desktop rule).
struct WatchLimitsPage: View {
    let snapshot: TokenSnapshot

    @Environment(\.tmPresentation) private var presentation

    var body: some View {
        // The snapshot is built in this order; ordering again also covers
        // one from an older iPhone app.
        let providers = LimitPresentation.ordered(snapshot.limits, order: presentation.preferences.limitProviderOrder)
        ScrollView {
            // Ages, "Reset now" and the freshness line move on with the clock.
            TimelineView(.everyMinute) { timeline in
                LazyVStack(alignment: .leading, spacing: 8) {
                    if providers.isEmpty {
                        Text("No data")
                            .font(.footnote)
                            .foregroundStyle(TMTheme.muted)
                    } else {
                        ForEach(providers) { provider in
                            let peers = providers.filter { $0.provider == provider.provider }
                            WatchLimitProviderCard(
                                provider: provider,
                                peers: peers,
                                index: peers.firstIndex { $0.id == provider.id } ?? 0,
                                now: timeline.date
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Limits")
        .containerBackground(for: .tabView) { TMBackground() }
    }
}

/// The window a one-number surface leads with, among those the user left
/// visible: the percentage window with the least left, else the balance.
func watchHeadlineWindow(of provider: LimitProvider, windows: [LimitWindow]) -> LimitWindow? {
    var visible = provider
    visible.windows = windows
    return visible.headlineWindow
}

struct WatchLimitProviderCard: View {
    let provider: LimitProvider
    /// Every row of this provider, in Hub order (account titles tell them apart).
    let peers: [LimitProvider]
    let index: Int
    let now: Date

    @Environment(\.tmPresentation) private var presentation
    @Environment(\.tmFormatter) private var format

    var body: some View {
        let showUsed = presentation.preferences.showLimitUsed
        let windows = LimitPresentation.visibleWindows(provider, prefs: presentation.preferences)
        let headline = watchHeadlineWindow(of: provider, windows: windows)
        let chip = LimitPresentation.statusChip(provider)
        let meta = LimitPresentation.metaLine(provider, now: now, showSource: false)
        let freshness = meta.flatMap { WatchText.freshness($0.freshness) }
        let tint = self.tint
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let headline {
                    // Always fills by what is left; the number follows the
                    // used/remaining choice.
                    LimitRing(
                        fill: LimitPresentation.meterFill(window: headline, provider: provider, showUsed: showUsed),
                        color: tint,
                        lineWidth: 3.5
                    ) {
                        Text(verbatim: WatchText.shortValue(
                            LimitPresentation.headline(window: headline, provider: provider, showUsed: showUsed),
                            format: format
                        ))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(3)
                    }
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        VendorMark(.provider(LimitPresentation.iconID(provider)), size: 12, context: .limits, muted: provider.isStale)
                        Text(verbatim: provider.displayName)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(provider.isStale ? TMTheme.muted : TMTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if chip.showsLiveDot {
                            StatusTag(text: WatchText.statusLabel(chip.label), tone: chip.tone, showsOKDot: true)
                        }
                    }
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(.caption2)
                            .foregroundStyle(TMTheme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            // A stale row says so in its meta line ("Stale · 2h ago").
            if !chip.showsLiveDot, !(chip.label == .stale && freshness != nil) {
                StatusTag(text: WatchText.statusLabel(chip.label), tone: chip.tone)
            }
            if LimitPresentation.antigravityNeedsVerification(provider) {
                Text(WatchText.antigravityVerificationDetail)
                    .font(.caption2)
                    .foregroundStyle(TMTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let meta, let freshness {
                Text(verbatim: freshness)
                    .font(.caption2)
                    .foregroundStyle(meta.freshness.tone == .stale ? TMTheme.warning : TMTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            // Retained windows stay visible for a transient status.
            ForEach(windows) { window in
                WatchLimitWindowRow(window: window, provider: provider, tint: tint, now: now)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TMTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The provider's colour (the user's override included); stale rows are
    /// muted.
    private var tint: Color {
        provider.isStale ? TMTheme.staleMuted : VendorColor.color(for: provider.provider, palette: presentation.palette)
    }

    /// "Max", plus the account when the provider has several.
    private var subtitle: String? {
        var parts: [String] = []
        if let plan = WatchText.plan(LimitPresentation.planCell(provider, grouped: peers.count > 1)) {
            parts.append(plan)
        }
        if peers.count > 1 {
            // Snapshots carry masked addresses only.
            parts.append(WatchText.accountTitle(LimitPresentation.accountTitle(provider, peers: peers, index: index, mask: true)))
        }
        let joined = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }
}

struct WatchLimitWindowRow: View {
    let window: LimitWindow
    let provider: LimitProvider
    let tint: Color
    let now: Date

    @Environment(\.tmPresentation) private var presentation
    @Environment(\.tmFormatter) private var format

    var body: some View {
        let showUsed = presentation.preferences.showLimitUsed
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: WatchText.windowName(LimitPresentation.windowName(window, provider: provider)))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text(verbatim: WatchText.headline(
                    LimitPresentation.headline(window: window, provider: provider, showUsed: showUsed),
                    format: format
                ))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(provider.isStale ? TMTheme.muted : TMTheme.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            // Flips with used/remaining; draws nothing for a note row.
            LimitMeter(fill: LimitPresentation.meterFill(window: window, provider: provider, showUsed: showUsed), color: tint, height: 4)
            if let line = LimitPresentation.boundaryLine(window: window, now: now) {
                WatchBoundaryText(line: line, date: window.resetsAt)
                    .font(.caption2)
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

/// "Reset in 2 hr, 30 min", counting down live; "Reset now" inside the
/// minute after; or the provider's own wording ("Reset on the 1st").
struct WatchBoundaryText: View {
    let line: LimitPresentation.BoundaryLine
    let date: Date?

    var body: some View {
        switch line {
        case .boundary(let boundary):
            if let date, !boundary.isNow {
                switch boundary.kind {
                case .reset:
                    Text("Reset in \(Text(date, style: .relative))")
                case .expiry:
                    Text("Expires in \(Text(date, style: .relative))")
                case .mixed:
                    Text("Changes in \(Text(date, style: .relative))")
                }
            } else {
                switch boundary.kind {
                case .reset: Text("Reset now")
                case .expiry: Text("Expires now")
                case .mixed: Text("Changes now")
                }
            }
        case .description(let text):
            Text("Reset \(text)")
        }
    }
}

#Preview {
    NavigationStack {
        WatchLimitsPage(snapshot: .watchSample)
    }
}

#Preview("Used mode") {
    NavigationStack {
        WatchLimitsPage(snapshot: .watchSample)
    }
    .tmPresentation(.watchSample)
}

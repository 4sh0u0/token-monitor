import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Page 2: the period's tools in the user's order (hidden ones left out,
/// pinned ones first), with their share of its tokens.
struct WatchToolsPage: View {
    let snapshot: TokenSnapshot
    let period: UsagePeriodKind

    @Environment(\.tmPresentation) private var presentation

    var body: some View {
        ScrollView {
            // A period that has rolled over since the fetch (today after
            // midnight) has no tools to list until the next fetch.
            TimelineView(.everyMinute) { timeline in
                let summary = snapshot.isCurrent(period, at: timeline.date) ? snapshot[period] : PeriodSummary(kind: period)
                // Snapshots built by `SnapshotBuilder` are already in this order;
                // applying it again also covers one from an older iPhone app.
                let tools = ClientDisplayOrder.apply(
                    summary.tools,
                    id: \.id,
                    preferences: presentation.preferences,
                    known: VendorCatalog.trackedClientIDs
                )
                let other = summary.tokens(notIn: tools)
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(WatchText.periodTitle(period))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(TMTheme.accent)
                        WatchScopeLabel(scope: snapshot.scope)
                    }
                    if tools.isEmpty || summary.totalTokens <= 0 {
                        Text("No data")
                            .font(.footnote)
                            .foregroundStyle(TMTheme.muted)
                    } else {
                        UsageBar(segments: segments(tools, other: other), total: Double(summary.totalTokens), height: 6)
                            .padding(.bottom, 2)
                        ForEach(tools) { share in
                            WatchToolRow(share: share, total: summary.totalTokens)
                        }
                        if other > 0 {
                            WatchOtherToolsRow(tokens: other, total: summary.totalTokens, color: otherColor)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Tools")
        .containerBackground(for: .tabView) { TMBackground() }
    }

    /// Bar segments in the user's vendor colours.
    private func segments(_ tools: [UsageShare], other: Int) -> [UsageBar.Segment] {
        let palette = presentation.palette
        var segments = tools.map { share in
            UsageBar.Segment(id: share.id, value: Double(share.tokens), color: VendorColor.color(for: share.vendorID ?? share.id, palette: palette))
        }
        if other > 0 {
            segments.append(UsageBar.Segment(id: UsageShare.remainderID, value: Double(other), color: otherColor))
        }
        return segments
    }

    /// Hidden tools, tools beyond the top ones and unattributed tokens.
    private var otherColor: Color {
        VendorColor.color(for: nil, palette: presentation.palette)
    }
}

struct WatchToolRow: View {
    let share: UsageShare
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            VendorMark(.client(share.id), size: 12)
            Text(verbatim: share.label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TMTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            WatchShareValues(tokens: share.tokens, fraction: share.fraction(of: total))
        }
        .accessibilityElement(children: .combine)
    }
}

/// The remainder of the period that no listed tool accounts for.
struct WatchOtherToolsRow: View {
    let tokens: Int
    let total: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8.4, height: 8.4)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            Text("Other")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TMTheme.muted)
                .lineLimit(1)
            Spacer(minLength: 4)
            WatchShareValues(tokens: tokens, fraction: total > 0 ? min(1, Double(tokens) / Double(total)) : 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "18.9M  26%".
struct WatchShareValues: View {
    let tokens: Int
    let fraction: Double

    @Environment(\.tmFormatter) private var format

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: format.compactTokens(tokens))
                .font(.caption2)
                .foregroundStyle(TMTheme.muted)
            Text(verbatim: format.percent(fraction * 100))
                .font(.caption2.weight(.medium))
                .foregroundStyle(TMTheme.text)
                .frame(minWidth: 30, alignment: .trailing)
        }
        .monospacedDigit()
    }
}

#Preview {
    NavigationStack {
        WatchToolsPage(snapshot: .watchSample, period: .today)
    }
}

#Preview("Scoped, icons off") {
    NavigationStack {
        WatchToolsPage(snapshot: .watchScopedSample, period: .month)
    }
    .tmPresentation(.watchSample)
}

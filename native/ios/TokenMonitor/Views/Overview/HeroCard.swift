import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The period's headline (the desktop's total panel): the full token count
/// (tap for the short form), the "≈ 1.2M" line when `showCompactTotalTokens`
/// is on, the cost with its unpriced marker, and the live token rate (Live
/// mode with the rate on) or the period's average rate.
///
/// A fixed range that is loading or unavailable shows "—" and why.
struct HeroCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmFormatter) private var formatter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let selection: PeriodSelection
    let state: PeriodUsageState
    @State private var showsCompact = false

    var body: some View {
        CardContainer(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let usage = state.usage {
                    VStack(alignment: .leading, spacing: 4) {
                        tokenHeadline(usage.totalTokens)
                        if let approximation = compactApproximation(usage.totalTokens) {
                            Text(verbatim: approximation)
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(TMTheme.muted)
                                .accessibilityHidden(true)
                        }
                    }
                    figures(usage)
                    if let unpriced = usage.unpricedTokens, unpriced > 0 {
                        Label {
                            Text("\(formatter.fullTokens(unpriced)) tokens excluded from the cost estimate")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "info.circle")
                        }
                        .font(.caption)
                        .foregroundStyle(TMTheme.muted)
                        .accessibilityElement(children: .combine)
                    }
                } else {
                    Text(verbatim: "—")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(TMTheme.muted)
                        .accessibilityLabel(Text("Total tokens"))
                        .accessibilityValue(Text(verbatim: "—"))
                    PeriodUsageNote(state: state)
                }
            }
        }
    }

    // MARK: Header

    /// "Today", "This month", "Last 7 days" …, and a fixed range's days.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: selection.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TMTheme.muted)
                .accessibilityAddTraits(.isHeader)
            if let days = rangeText {
                Text(verbatim: days)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.muted.opacity(0.8))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// "Oct 4 – Oct 10" for a ready fixed range.
    private var rangeText: String? {
        guard let range = state.fixedRange?.range,
              let start = DayKey.date(from: range.start),
              let end = DayKey.date(from: range.end) else { return nil }
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if range.start == range.end { return start.formatted(style) }
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }

    // MARK: Total

    private func headlineText(_ tokens: Int) -> String {
        showsCompact ? formatter.compactTokens(tokens) : formatter.fullTokens(tokens)
    }

    /// `≈ 1.2M` under the full count: only with `showCompactTotalTokens`,
    /// at or above the unit threshold, and while the full count is shown.
    private func compactApproximation(_ tokens: Int) -> String? {
        guard !showsCompact, model.preferences.showCompactTotalTokens else { return nil }
        return formatter.compactApproximation(tokens)
    }

    private func tokenHeadline(_ tokens: Int) -> some View {
        Button {
            withAnimation(.snappy) {
                showsCompact.toggle()
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: headlineText(tokens))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.number)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: tokens)
                Text("tokens")
                    .font(.headline)
                    .foregroundStyle(TMTheme.muted)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Total tokens"))
        .accessibilityValue(Text(verbatim: formatter.fullTokens(tokens)))
        .accessibilityHint(Text("Switches between the short and the full number."))
    }

    // MARK: Cost and rate

    @ViewBuilder
    private func figures(_ usage: UsagePeriod) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                costTile(usage)
                OverviewRateTile(usage: usage)
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                costTile(usage)
                OverviewRateTile(usage: usage)
            }
        }
    }

    /// The cost in the display currency: `$1.23`, `$1.23 + ?` when some
    /// tokens have no price, `—` when none has.
    private func costTile(_ usage: UsagePeriod) -> some View {
        let cost = CostLabelText.string(usd: usage.costUsd, unpricedTokens: usage.unpricedTokens, compact: true, formatter: formatter)
        return VStack(alignment: .leading, spacing: 2) {
            Text("Cost")
                .font(.caption.weight(.medium))
                .foregroundStyle(TMTheme.muted)
            Text(verbatim: cost)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(TMTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cost"))
        .accessibilityValue(Text(verbatim: CostLabelText.string(usd: usage.costUsd, unpricedTokens: usage.unpricedTokens, formatter: formatter)))
    }
}

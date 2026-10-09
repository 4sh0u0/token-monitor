import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The period's headline: total tokens (tap for the full count), cost and
/// output speed.
struct HeroCard: View {
    let period: UsagePeriodKind
    let usage: UsagePeriod
    @State private var showsFullCount = false

    var body: some View {
        CardContainer(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(period.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TMTheme.muted)
                tokenHeadline
                HStack(alignment: .top, spacing: 12) {
                    MetricTile(title: "Cost", value: TokenFormat.usd(usage.costUsd))
                    if let rate = usage.outputTokensPerSecond {
                        MetricTile(title: "Output speed", value: AppFormat.outputSpeed(rate))
                    }
                }
                if let unpriced = usage.unpricedTokens, unpriced > 0 {
                    Text("Cost excludes \(TokenFormat.compactTokens(unpriced)) tokens without a known price.")
                        .font(.caption)
                        .foregroundStyle(TMTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var headlineText: String {
        showsFullCount ? TokenFormat.fullTokens(usage.totalTokens) : TokenFormat.compactTokens(usage.totalTokens)
    }

    private var tokenHeadline: some View {
        Button {
            withAnimation(.snappy) {
                showsFullCount.toggle()
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: headlineText)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.number)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text("tokens")
                    .font(.headline)
                    .foregroundStyle(TMTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Total tokens"))
        .accessibilityValue(Text(verbatim: TokenFormat.fullTokens(usage.totalTokens)))
        .accessibilityHint(Text("Switches between the short and the full number."))
    }
}

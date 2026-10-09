import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// One provider account: who it is, its status and a meter per quota window.
struct LimitProviderCard: View {
    let provider: LimitProvider
    let now: Date

    /// Quota colours only mean something for a healthy, fresh reading.
    private var isMuted: Bool { provider.isStale || provider.status != .ok }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                LimitProviderHeader(provider: provider)
                if provider.isStale {
                    Label("Data may be stale", systemImage: "clock.badge.exclamationmark")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TMTheme.warning)
                }
                if provider.actionRequired != nil {
                    Label("Action needed in Token Monitor on your computer", systemImage: "person.badge.key")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TMTheme.caution)
                }
                if provider.windows.isEmpty {
                    (provider.status == .ok ? Text("No quota reported yet.") : Text(verbatim: provider.statusTitle))
                        .font(.subheadline)
                        .foregroundStyle(TMTheme.muted)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(provider.windows) { window in
                            LimitWindowRow(
                                window: window,
                                fraction: provider.meterFraction(for: window),
                                now: now,
                                isMuted: isMuted
                            )
                        }
                    }
                }
                if let balance = provider.balance {
                    BalanceSpendRow(balance: balance)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct LimitProviderHeader: View {
    let provider: LimitProvider

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            MarkDot(color: provider.color)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: provider.displayName)
                        .font(.headline)
                        .foregroundStyle(TMTheme.text)
                        .lineLimit(1)
                    if let plan = provider.planLabel {
                        Chip(text: plan, color: TMTheme.chartBlue)
                    }
                }
                // Masked: the full email never reaches the screen, and the
                // account key is not even kept by the Kit.
                if let account = provider.maskedAccountDisplayName {
                    Text(verbatim: account)
                        .font(.caption)
                        .foregroundStyle(TMTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            Chip(text: provider.statusTitle, color: TMTheme.statusColor(provider.statusCategory))
        }
        .accessibilityElement(children: .combine)
    }
}

/// One quota window: name, headline, meter (unless `showMeter` is false) and
/// the reset or expiry countdown.
struct LimitWindowRow: View {
    let window: LimitWindow
    /// What is left, 0...1; nil when no meter may be drawn.
    let fraction: Double?
    let now: Date
    let isMuted: Bool

    private var tint: Color {
        isMuted ? TMTheme.muted : TMTheme.quotaColor(remainingFraction: fraction)
    }

    var body: some View {
        let boundary = window.boundaryText(now: now)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: window.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TMTheme.text)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(verbatim: window.headline)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isMuted ? TMTheme.muted : TMTheme.number)
                    .multilineTextAlignment(.trailing)
            }
            if let fraction {
                QuotaBar(fraction: fraction, color: tint, height: 6)
            }
            if boundary != nil || window.detail != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let boundary {
                        Text(verbatim: boundary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    if let detail = window.detail {
                        Text(verbatim: detail)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .font(.caption)
                .foregroundStyle(TMTheme.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: window.displayTitle))
        .accessibilityValue(Text(verbatim: [window.headline, boundary, window.detail].compactMap { $0 }.joined(separator: ", ")))
    }
}

/// Money spent from a balance, when the provider reports it.
private struct BalanceSpendRow: View {
    let balance: LimitBalance

    var body: some View {
        if balance.todaySpend != nil || balance.monthSpend != nil {
            HStack(spacing: 16) {
                if let today = balance.todaySpend {
                    spend(Text("Spent today"), today)
                }
                if let month = balance.monthSpend {
                    spend(Text("Spent this month"), month)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func spend(_ title: Text, _ amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(.caption)
                .foregroundStyle(TMTheme.muted)
            Text(verbatim: TokenFormat.money(amount, currency: balance.currency))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(TMTheme.text)
        }
        .accessibilityElement(children: .combine)
    }
}

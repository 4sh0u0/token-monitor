import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Page 3: AI tool quota windows, ready providers first.
struct WatchLimitsPage: View {
    static let maxProviders = 6
    static let maxWindows = 3

    let snapshot: TokenSnapshot

    var body: some View {
        let providers = Array(snapshot.limits.prefix(Self.maxProviders))
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if providers.isEmpty {
                    Text("No data")
                        .font(.footnote)
                        .foregroundStyle(TMTheme.muted)
                } else {
                    ForEach(providers) { provider in
                        WatchLimitProviderCard(
                            provider: provider,
                            showsAccount: providers.filter { $0.provider == provider.provider }.count > 1
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Limits")
        .containerBackground(for: .tabView) { TMBackground() }
    }
}

/// The meter colour: the provider's own while there is room, the theme's
/// warning colours once a quarter or less is left.
func watchQuotaTint(_ fraction: Double?, provider: LimitProvider) -> Color {
    guard let fraction else { return TMTheme.muted }
    if provider.isStale { return TMTheme.muted }
    return fraction < 0.25 ? TMTheme.quotaColor(remainingFraction: fraction) : provider.color
}

struct WatchLimitProviderCard: View {
    let provider: LimitProvider
    let showsAccount: Bool

    var body: some View {
        let headline = provider.headlineWindow
        let headlineFraction = headline.flatMap { provider.meterFraction(for: $0) }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                QuotaRing(fraction: headlineFraction, color: watchQuotaTint(headlineFraction, provider: provider), lineWidth: 3.5) {
                    Text(WatchText.ringValue(headline, in: provider))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(3)
                }
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(provider.isStale ? TMTheme.muted : TMTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(TMTheme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            if provider.status != .ok {
                Text(WatchText.status(provider.status))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TMTheme.statusColor(provider.statusCategory))
                    .lineLimit(2)
            }
            if provider.isStale {
                Label("Data may be stale", systemImage: "clock.badge.exclamationmark")
                    .font(.caption2)
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ForEach(Array(provider.primaryWindows.prefix(WatchLimitsPage.maxWindows))) { window in
                WatchLimitWindowRow(window: window, provider: provider)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TMTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String? {
        let parts = [provider.planLabel, showsAccount ? provider.accountDisplayName : nil]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct WatchLimitWindowRow: View {
    let window: LimitWindow
    let provider: LimitProvider

    var body: some View {
        let fraction = provider.meterFraction(for: window)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(WatchText.windowTitle(window))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text(WatchText.windowValue(window, in: provider))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(provider.isStale ? TMTheme.muted : TMTheme.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            // Nil when the window must not draw a meter (`showMeter == false`).
            if let fraction {
                QuotaBar(fraction: fraction, color: watchQuotaTint(fraction, provider: provider), height: 4)
            }
            if let resetsAt = window.resetsAt, resetsAt > Date() {
                WatchBoundaryText(kind: window.boundaryKind, date: resetsAt)
                    .font(.caption2)
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

/// "Reset in 2 hr, 30 min", counting down live.
struct WatchBoundaryText: View {
    let kind: LimitBoundaryKind
    let date: Date

    var body: some View {
        switch kind {
        case .reset:
            Text("Reset in \(Text(date, style: .relative))")
        case .expiry:
            Text("Expires in \(Text(date, style: .relative))")
        case .mixed:
            Text("Changes in \(Text(date, style: .relative))")
        }
    }
}

#Preview {
    NavigationStack {
        WatchLimitsPage(snapshot: .watchSample)
    }
}

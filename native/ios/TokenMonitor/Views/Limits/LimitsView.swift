import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The Limits tab: one card per provider in the user's Limits order
/// (`limitProviderOrder`, catalog order by default), then a link to the
/// Hub's subscriptions. Limits never follow the device scope (desktop rule).
///
/// A tab root: `RootView` owns the navigation stack.
struct LimitsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScreenScrollView {
            if let stats = model.stats {
                StatusBanner()
                LimitsPage(stats: stats)
            } else {
                DataPlaceholder()
            }
        }
        .navigationTitle("Limits")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LiveStatusIndicator()
            }
        }
        .task {
            model.subscriptions.ensureLoaded()
        }
    }
}

private struct LimitsPage: View {
    let stats: HubStats

    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let providers = LimitPresentation.ordered(stats.limits, order: model.preferences.limitProviderOrder)
        let groups = LimitAccountGroup.groups(providers)
        VStack(alignment: .leading, spacing: 16) {
            if groups.isEmpty {
                EmptyStateCard(
                    title: "No AI tool limits yet",
                    message: "Set up AI Tool Limits in Token Monitor on your computer. The Hub shares them with this app.",
                    systemImage: "gauge.with.dots.needle.0percent"
                )
            } else {
                // One clock for the whole page, so countdowns and ages move
                // together ("Reset in 4h 26m", "Updated 5m ago").
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    if sizeClass == .regular {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 16, alignment: .top),
                                GridItem(.flexible(), spacing: 16, alignment: .top)
                            ],
                            alignment: .leading,
                            spacing: 16
                        ) {
                            cards(groups, now: context.date)
                        }
                    } else {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            cards(groups, now: context.date)
                        }
                    }
                }
            }
            SubscriptionsLink()
        }
    }

    private func cards(_ groups: [LimitAccountGroup], now: Date) -> some View {
        ForEach(groups) { group in
            LimitProviderCard(group: group, devices: stats.devices, now: now)
        }
    }
}

/// The Hub's subscriptions ("3 · $45.00 / mo"), read-only, one tap away.
/// Hidden for a Hub without `/api/subscriptions`.
private struct SubscriptionsLink: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmFormatter) private var format

    var body: some View {
        if model.subscriptions.phase != .unsupported {
            NavigationLink(value: AppRoute.subscriptions) {
                CardContainer(padding: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "creditcard")
                            .foregroundStyle(TMTheme.muted)
                            .accessibilityHidden(true)
                        Text("Subscriptions")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TMTheme.text)
                        Spacer(minLength: 8)
                        if let summary {
                            Text(verbatim: summary)
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(TMTheme.muted)
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TMTheme.muted)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }

    /// The desktop Settings summary: active subscriptions and their monthly
    /// total in the display currency, or "None yet"; nil until loaded.
    private var summary: String? {
        guard let document = model.subscriptions.document else { return nil }
        guard !document.subscriptions.isEmpty else { return String(localized: "None yet") }
        let active = SubscriptionMath.activeSubscriptions(document.subscriptions)
        let total = format.cost(SubscriptionMath.monthlyTotalUsd(active, rates: format.rates.effectiveMultipliers))
        let count = active.count
        return String(localized: "\(count) · \(total) / mo")
    }
}

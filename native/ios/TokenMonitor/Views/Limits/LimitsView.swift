import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

struct LimitsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScreenScrollView {
                if let stats = model.stats {
                    StatusBanner()
                    // The newest provider reading, not `limitsUpdatedAt`: the
                    // Hub stamps that when it aggregates, i.e. on every read.
                    LimitsList(providers: LimitProvider.sortedForDisplay(stats.limits), updatedAt: stats.limits.compactMap(\.updatedAt).max())
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
        }
    }
}

private struct LimitsList: View {
    let providers: [LimitProvider]
    let updatedAt: Date?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if providers.isEmpty {
            EmptyStateCard(
                title: "No AI tool limits yet",
                message: "Set up AI Tool Limits in Token Monitor on your computer. The Hub shares them with this app.",
                systemImage: "gauge.with.dots.needle.0percent"
            )
        } else {
            // One clock for every countdown on the page, so they tick together.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 16) {
                    if sizeClass == .regular {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                            cards(now: context.date)
                        }
                    } else {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            cards(now: context.date)
                        }
                    }
                    if let updatedAt {
                        Text("Limits updated \(AppFormat.ago(updatedAt, now: context.date))")
                            .font(.caption)
                            .foregroundStyle(TMTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
    }

    private func cards(now: Date) -> some View {
        ForEach(providers) { provider in
            LimitProviderCard(provider: provider, now: now)
        }
    }
}

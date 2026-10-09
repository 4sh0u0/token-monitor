import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScreenScrollView {
                if let stats = model.stats {
                    OverviewDashboard(stats: stats)
                } else {
                    DataPlaceholder()
                }
            }
            .navigationTitle("Overview")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    LiveStatusIndicator()
                }
            }
        }
    }
}

private struct OverviewDashboard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let stats: HubStats

    var body: some View {
        @Bindable var model = model
        let usage = stats[model.selectedPeriod]
        VStack(alignment: .leading, spacing: 16) {
            StatusBanner()
            if stats.isSourceStale {
                SourceStaleNotice()
            }
            Picker("Period", selection: $model.selectedPeriod) {
                ForEach(UsagePeriodKind.allCases) { kind in
                    Text(kind.shortTitle).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            HeroCard(period: model.selectedPeriod, usage: usage)
            TokenComponentsCard(usage: usage)
            TrendChartCard(stats: stats)
            breakdowns(usage)
        }
    }

    @ViewBuilder
    private func breakdowns(_ usage: UsagePeriod) -> some View {
        let unclassified = String(localized: "Unclassified")
        let tools = BreakdownCard(
            title: "Tools",
            rows: usage.clients(remainderLabel: unclassified),
            total: usage.totalTokens,
            emptyMessage: "No tool usage in this period."
        )
        let models = BreakdownCard(
            title: "Models",
            rows: usage.models(remainderLabel: unclassified),
            total: usage.totalTokens,
            emptyMessage: "No model usage in this period."
        )
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: 16) {
                tools
                models
            }
        } else {
            tools
            models
        }
    }
}

/// Every device is offline, so the numbers are the last they reported.
private struct SourceStaleNotice: View {
    var body: some View {
        Label {
            Text("All devices are offline. These are the last numbers they reported.")
                .font(.footnote)
                .foregroundStyle(TMTheme.muted)
        } icon: {
            Image(systemName: "moon.zzz")
                .foregroundStyle(TMTheme.muted)
        }
    }
}

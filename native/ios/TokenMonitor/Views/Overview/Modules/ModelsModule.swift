import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The `model` Overview module (desktop `renderHomeModelModule`): the
/// selected period's top five models by tokens in compact form, linking to
/// the Models view. Like the desktop's Home module it always ranks by
/// tokens; `modelRankingMetric` applies in the Models view. Draws nothing
/// while the period is not ready (the hero says why).
struct ModelsModule: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmFormatter) private var formatter

    static let limit = 5

    var body: some View {
        if let usage = model.selectedUsage.usage {
            let items = Self.items(usage: usage, formatter: formatter)
            CardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    ModuleHeader(title: "Models", route: .models)
                    if items.isEmpty {
                        Text("No model usage in this period")
                            .font(.subheadline)
                            .foregroundStyle(TMTheme.muted)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(items) { item in
                                OverviewListRow(item: item)
                            }
                        }
                    }
                }
            }
        }
    }

    /// `modelRowsForPeriod(period, 'tokens')` (models plus the Unclassified
    /// remainder), then the first five with tokens. The `unknown` model wears
    /// Codex's mark when Codex accounts for all of it.
    static func items(usage: UsagePeriod, formatter: DisplayFormatter) -> [OverviewListItem] {
        let rows = AttributionRows.modelRows(period: usage, ranking: .tokens, formatter: formatter)
        return OverviewListItem.items(
            rows,
            totalTokens: usage.totalTokens,
            limit: limit,
            mark: { .model($0.key, source: $0.modelSource) },
            name: { $0.isUnattributed ? String(localized: "Unclassified") : $0.key }
        )
    }
}

import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The `tool` Overview module (desktop `renderHomeToolModule`): the selected
/// period's top five tools in compact form, linking to the Tools view.
///
/// Unlike the desktop's Home module, the hidden, pinned and ordered tools of
/// Settings › Tools apply here too (as in the Tools view, the widget and the
/// watch). Draws nothing while the period is not ready (the hero says why).
struct ToolsModule: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmFormatter) private var formatter

    static let limit = 5

    var body: some View {
        if let usage = model.selectedUsage.usage {
            let items = Self.items(usage: usage, preferences: model.preferences, formatter: formatter)
            CardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    ModuleHeader(title: "Tools", route: .tools)
                    if items.isEmpty {
                        Text("No tool usage in this period.")
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

    /// `AttributionRows.toolRows` (tools plus the Unclassified remainder,
    /// with the tool-list preferences applied), then the first five with
    /// tokens.
    static func items(usage: UsagePeriod, preferences: DisplayPreferences, formatter: DisplayFormatter) -> [OverviewListItem] {
        let rows = AttributionRows.toolRows(period: usage, prefs: preferences, formatter: formatter)
        return OverviewListItem.items(
            rows,
            totalTokens: usage.totalTokens,
            limit: limit,
            mark: { .client($0.key) },
            name: { $0.isUnattributed ? String(localized: "Unclassified") : VendorCatalog.clientLabel($0.key) }
        )
    }
}

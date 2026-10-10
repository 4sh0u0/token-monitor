import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The five biggest tools and models over the chart's range, by tokens, with
/// their share of the range's tokens (the dashboard's `renderBreakdown`
/// columns, which cover all History there). Side by side on a wide screen.
/// Draws nothing when the range has no tool or model buckets (the stats
/// preview).
struct TrendTopLists: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The range's days (`HistoryStore.trendDays(_:)`).
    let days: [HubHistoryDay]
    let range: TrendRange

    var body: some View {
        let tools = model.history.topClients(days)
        let models = model.history.topModels(days)
        if !tools.isEmpty || !models.isEmpty {
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: 16) {
                    list(title: "Tools", rows: tools, kind: .client)
                    list(title: "Models", rows: models, kind: .model)
                }
            } else {
                list(title: "Tools", rows: tools, kind: .client)
                list(title: "Models", rows: models, kind: .model)
            }
        }
    }

    @ViewBuilder
    private func list(title: LocalizedStringKey, rows: [HistoryBreakdownRow], kind: TrendStack) -> some View {
        if !rows.isEmpty {
            CardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    ModuleHeader(title: title) {
                        Text(verbatim: TrendsFormat.rangeTitle(range))
                            .font(.caption)
                            .foregroundStyle(TMTheme.muted)
                            .lineLimit(1)
                    }
                    ForEach(rows) { row in
                        TrendTopRow(row: row, kind: kind)
                    }
                }
            }
        }
    }
}

private struct TrendTopRow: View {
    @Environment(\.tmPresentation) private var presentation
    @Environment(\.tmFormatter) private var formatter
    let row: HistoryBreakdownRow
    let kind: TrendStack

    private var name: String {
        kind == .client ? VendorCatalog.clientLabel(row.key) : row.key
    }

    private var color: Color {
        kind == .client
            ? VendorColor.color(for: row.key, palette: presentation.palette)
            : VendorColor.model(row.key, palette: presentation.palette)
    }

    var body: some View {
        let share = row.percentLabel + "%"
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                VendorMark(kind == .client ? .client(row.key) : .model(row.key), size: 16)
                Text(verbatim: name)
                    .font(.subheadline)
                    .foregroundStyle(TMTheme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(verbatim: formatter.compactTokens(row.tokens))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.number)
                Text(verbatim: share)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.muted)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(TMTheme.track)
                    Capsule()
                        .fill(color)
                        .frame(width: max(3, proxy.size.width * min(1, max(0, row.fractionOfMax))))
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: formatter.compactTokens(row.tokens) + ", " + share))
    }
}

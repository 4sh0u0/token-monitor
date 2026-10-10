import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// One line of a compact Overview list (the desktop's `home-list-row`):
/// mark, name, compact tokens and share of the period.
struct OverviewListItem: Identifiable, Hashable {
    let id: String
    let mark: VendorMarkSubject
    let name: String
    let tokens: Int
    /// Share of the period's tokens, 0–100.
    let percent: Double

    /// The desktop's `homeToolRows` / `homeModelRows` over attribution rows:
    /// rows with tokens, at most `limit`, each with its share of the
    /// period's total (or of the listed rows when the total is 0).
    static func items(
        _ rows: [AttributionRow],
        totalTokens: Int,
        limit: Int,
        mark: (AttributionRow) -> VendorMarkSubject,
        name: (AttributionRow) -> String
    ) -> [OverviewListItem] {
        let visible = rows.filter { $0.tokens > 0 }.prefix(max(0, limit))
        let total = totalTokens > 0 ? totalTokens : visible.reduce(0) { $0 + $1.tokens }
        return visible.map { row in
            OverviewListItem(
                id: row.key,
                mark: mark(row),
                name: name(row),
                tokens: row.tokens,
                percent: total > 0 ? Double(row.tokens) / Double(total) * 100 : 0
            )
        }
    }
}

struct OverviewListRow: View {
    let item: OverviewListItem
    @Environment(\.tmFormatter) private var formatter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var markSize: CGFloat = 14

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        VendorMark(item.mark, size: markSize)
                        name
                    }
                    HStack(spacing: 10) {
                        value
                        share
                    }
                }
            } else {
                HStack(spacing: 10) {
                    VendorMark(item.mark, size: markSize)
                    name
                    Spacer(minLength: 8)
                    value
                    share
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var name: some View {
        Text(verbatim: item.name)
            .font(.subheadline)
            .foregroundStyle(TMTheme.text)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var value: some View {
        Text(verbatim: formatter.compactTokens(item.tokens))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(TMTheme.number)
    }

    /// `formatPercent(share * 100)`.
    private var share: some View {
        Text(verbatim: formatter.percent(item.percent))
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(TMTheme.muted)
    }
}

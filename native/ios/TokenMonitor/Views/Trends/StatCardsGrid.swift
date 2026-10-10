import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The History summary as stat cards (the dashboard's `statsCards`, value
/// over label): total tokens, total cost, active days, current streak, then
/// the longest streak (iOS adds it; the desktop has the `trends.longestStreak`
/// wording but no card), active time, peak day, top model and messages.
///
/// The figures cover all of the scope's History, not the chart's range, as on
/// the desktop. A cost with unpriced tokens reads "—" when nothing is priced
/// and carries the `usage.excludedFromCost` note below the grid.
struct StatCardsGrid: View {
    @Environment(\.tmFormatter) private var formatter
    let summary: HistorySummary

    private let columns = [GridItem(.adaptive(minimum: 136), spacing: 10, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(tiles) { tile in
                    TrendsStatTile(tile: tile)
                }
            }
            if let unpriced = summary.unpricedTokens, unpriced > 0 {
                Label {
                    Text(verbatim: TrendsFormat.excludedFromCost(unpriced, formatter: formatter))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.caption)
                .foregroundStyle(TMTheme.muted)
            }
        }
    }

    private var tiles: [TrendsStatTileModel] {
        var tiles: [TrendsStatTileModel] = []
        for card in StatCards.cards(summary: summary) {
            tiles.append(tile(for: card))
            if card.key == .currentStreak {
                tiles.append(TrendsStatTileModel(
                    id: "longestStreak",
                    title: String(localized: "Longest streak"),
                    value: formatter.compactTokens(summary.longestStreak)
                ))
            }
        }
        return tiles
    }

    private func tile(for card: StatCard) -> TrendsStatTileModel {
        let title = Self.title(card.key)
        switch card.value {
        case .tokens(let value), .days(let value), .count(let value):
            return TrendsStatTileModel(id: card.key.rawValue, title: title, value: formatter.compactTokens(value))
        case .cost(let usd, let unpriced):
            let unknown = (unpriced ?? 0) > 0 && !(usd > 0)
            return TrendsStatTileModel(
                id: card.key.rawValue,
                title: title,
                value: unknown ? "—" : formatter.compactCost(usd),
                showsInfo: (unpriced ?? 0) > 0
            )
        case .duration(let milliseconds):
            return TrendsStatTileModel(id: card.key.rawValue, title: title, value: TrendsFormat.duration(milliseconds: milliseconds))
        case .model(let name):
            return TrendsStatTileModel(id: card.key.rawValue, title: title, value: name ?? "—", model: name)
        }
    }

    /// The desktop's card labels (`dashboard.stat.*`, `trends.*`).
    static func title(_ key: StatCardKey) -> String {
        switch key {
        case .totalTokens: return String(localized: "Total tokens")
        case .totalCost: return String(localized: "Total cost")
        case .activeDays: return String(localized: "Active days")
        case .currentStreak: return String(localized: "Current streak")
        case .activeTimeMs: return String(localized: "Active time")
        case .peakDayTokens: return String(localized: "Peak day")
        case .favoriteModel: return String(localized: "Top model")
        case .messages: return String(localized: "Messages")
        }
    }
}

private struct TrendsStatTileModel: Identifiable {
    let id: String
    let title: String
    let value: String
    /// The cost excludes unpriced tokens (an info mark, as on the desktop).
    var showsInfo: Bool = false
    /// The top model, for its vendor mark.
    var model: String? = nil
}

private struct TrendsStatTile: View {
    let tile: TrendsStatTileModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 5) {
                if let model = tile.model {
                    VendorMark(.model(model), size: 14)
                }
                Text(verbatim: tile.value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.number)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if tile.showsInfo {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(TMTheme.muted)
                        .accessibilityHidden(true)
                }
            }
            Text(verbatim: tile.title)
                .font(.caption)
                .foregroundStyle(TMTheme.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(TMTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(TMTheme.cardStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tile.title))
        .accessibilityValue(Text(verbatim: tile.value))
    }
}

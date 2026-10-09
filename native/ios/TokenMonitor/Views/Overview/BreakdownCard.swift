import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The Tools or Models of a period: a stacked bar and one row per share. The
/// rows include the remainder row, so they add up to the period total.
struct BreakdownCard: View {
    let title: LocalizedStringKey
    let rows: [UsageShare]
    let total: Int
    let emptyMessage: LocalizedStringKey
    @State private var showsAll = false

    private static let collapsedCount = 8

    private var visibleRows: [UsageShare] {
        showsAll ? rows : Array(rows.prefix(Self.collapsedCount))
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle(title)
                if rows.isEmpty || total <= 0 {
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(TMTheme.muted)
                } else {
                    UsageBar(
                        segments: rows.map { UsageBar.Segment(id: $0.id, value: Double($0.tokens), color: Self.color(of: $0)) },
                        total: Double(total),
                        height: 8
                    )
                    VStack(spacing: 12) {
                        ForEach(visibleRows) { row in
                            BreakdownRow(share: row, total: total, color: Self.color(of: row))
                        }
                    }
                    if rows.count > Self.collapsedCount {
                        Button {
                            withAnimation(.snappy) {
                                showsAll.toggle()
                            }
                        } label: {
                            (showsAll ? Text("Show less") : Text("Show all"))
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    /// The remainder has no identity, so it gets the neutral muted colour.
    static func color(of share: UsageShare) -> Color {
        share.kind == .remainder ? TMTheme.muted : share.color
    }
}

struct BreakdownRow: View {
    let share: UsageShare
    let total: Int
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            MarkDot(color: color)
            Text(verbatim: share.label)
                .font(.subheadline)
                .foregroundStyle(TMTheme.text)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: TokenFormat.compactTokens(share.tokens))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.number)
                Text(verbatim: detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [AppFormat.share(share.fraction(of: total))]
        if let cost = share.costUsd {
            parts.append(TokenFormat.usd(cost))
        }
        return parts.joined(separator: " · ")
    }
}

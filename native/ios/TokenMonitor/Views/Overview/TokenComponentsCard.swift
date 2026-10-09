import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Cache hit / cache miss / output / unclassified, as on the desktop: the
/// unclassified remainder is its own part, never folded into cache miss.
struct TokenComponentsCard: View {
    let usage: UsagePeriod
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Part: Identifiable {
        let id: String
        let title: String
        let tokens: Int
        let color: Color
    }

    private var parts: [Part] {
        let components = usage.components
        var parts = [
            Part(id: "cacheRead", title: String(localized: "Input (cache hit)"), tokens: components.cacheRead, color: TMTheme.chartBlue),
            Part(id: "cacheMiss", title: String(localized: "Input (cache miss)"), tokens: components.cacheMiss, color: TMTheme.purple),
            Part(id: "output", title: String(localized: "Output"), tokens: components.output, color: TMTheme.accent)
        ]
        if components.unclassified > 0 {
            parts.append(Part(id: "unclassified", title: String(localized: "Unclassified"), tokens: components.unclassified, color: TMTheme.muted))
        }
        return parts
    }

    private var columns: [GridItem] {
        let column = GridItem(.flexible(), spacing: 12, alignment: .topLeading)
        return dynamicTypeSize.isAccessibilitySize ? [column] : [column, column]
    }

    var body: some View {
        let components = usage.components
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    CardTitle("Token components")
                    Spacer(minLength: 8)
                    if let hitRate = components.cacheHitFraction {
                        Text("Cache hit rate \(AppFormat.share(hitRate))")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(TMTheme.muted)
                    }
                }
                if components.total == 0 {
                    Text("No usage in this period.")
                        .font(.subheadline)
                        .foregroundStyle(TMTheme.muted)
                } else {
                    UsageBar(
                        segments: parts.map { UsageBar.Segment(id: $0.id, value: Double($0.tokens), color: $0.color) },
                        height: 10
                    )
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(parts) { part in
                            legendRow(part, total: components.total)
                        }
                    }
                    if !usage.hasExactTokenComponents {
                        Text("Some devices don’t report exact token components, so this split is approximate.")
                            .font(.caption)
                            .foregroundStyle(TMTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func legendRow(_ part: Part, total: Int) -> some View {
        let fraction = total > 0 ? Double(part.tokens) / Double(total) : 0
        return HStack(alignment: .top, spacing: 8) {
            MarkDot(color: part.color)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: part.title)
                    .font(.caption)
                    .foregroundStyle(TMTheme.muted)
                Text(verbatim: "\(TokenFormat.compactTokens(part.tokens)) · \(AppFormat.share(fraction))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

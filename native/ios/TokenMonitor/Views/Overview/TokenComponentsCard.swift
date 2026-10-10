import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The `components` Overview module (iOS only): the selected period's cache
/// hit / cache miss / output / unclassified split, as the desktop's tool
/// details show it. The unclassified remainder is its own part, never folded
/// into cache miss. Draws nothing while the period is not ready (the hero
/// says why).
struct TokenComponentsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let usage = model.selectedUsage.usage {
            TokenComponentsContent(usage: usage)
        }
    }
}

private struct TokenComponentsContent: View {
    let usage: UsagePeriod
    @Environment(\.tmFormatter) private var formatter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Part: Identifiable {
        let id: String
        let title: Text
        let tokens: Int
        let color: Color
    }

    private var parts: [Part] {
        let components = usage.components
        var parts = [
            Part(id: "cacheRead", title: Text("Input (cache hit)"), tokens: components.cacheRead, color: TMTheme.chartBlue),
            Part(id: "cacheMiss", title: Text("Input (cache miss)"), tokens: components.cacheMiss, color: TMTheme.purple),
            Part(id: "output", title: Text("Output"), tokens: components.output, color: TMTheme.accent)
        ]
        if components.unclassified > 0 {
            parts.append(Part(id: "unclassified", title: Text("Unclassified"), tokens: components.unclassified, color: TMTheme.muted))
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
                ModuleHeader(title: "Token components") {
                    if components.input > 0 {
                        Text("Cache hit rate \(hitRate(components))")
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
                    .accessibilityHidden(true)
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

    /// `tokenInputPercentages`' rounded hit share (`hitPct`).
    private func hitRate(_ components: TokenComponents) -> String {
        "\(AttributionRows.inputPercentages(components).roundedHit)%"
    }

    private func legendRow(_ part: Part, total: Int) -> some View {
        let percent = total > 0 ? Double(part.tokens) / Double(total) * 100 : 0
        return HStack(alignment: .top, spacing: 8) {
            MarkDot(color: part.color)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                part.title
                    .font(.caption)
                    .foregroundStyle(TMTheme.muted)
                Text(verbatim: "\(formatter.compactTokens(part.tokens)) · \(AttributionRows.detailPercentLabel(percent))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

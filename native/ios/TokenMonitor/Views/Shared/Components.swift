import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// A tab's scrolling page: the Token Monitor background, a readable width on
/// iPad and pull to refresh.
struct ScreenScrollView<Content: View>: View {
    @Environment(AppModel.self) private var model
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .background {
            TMBackground().ignoresSafeArea()
        }
        .refreshable {
            await model.refresh()
        }
    }
}

/// The card surface every section sits on (the desktop widget's glass card).
struct CardContainer<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TMTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(TMTheme.cardStroke, lineWidth: 1)
            }
    }
}

/// A card's section title.
struct CardTitle: View {
    private let title: Text

    init(_ titleKey: LocalizedStringKey) {
        title = Text(titleKey)
    }

    init(verbatim title: String) {
        self.title = Text(verbatim: title)
    }

    var body: some View {
        title
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TMTheme.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A vendor's colour mark in front of a row.
struct MarkDot: View {
    let color: Color
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A small titled figure (cost, speed) under a headline number.
struct MetricTile: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(TMTheme.muted)
            Text(verbatim: value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(TMTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A small capsule label (plan names, status).
struct Chip: View {
    let text: String
    var color: Color = TMTheme.muted

    var body: some View {
        Text(verbatim: text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// The mint call-to-action button with dark text (white on mint is unreadable).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(TMTheme.background)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                TMTheme.accent.opacity(configuration.isPressed ? 0.75 : 1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

/// Lays chips out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            // A chip wider than the line is clipped to it rather than overflowing.
            if size.width > maxWidth { size.width = maxWidth }
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty, needed > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append(Item(index: index, size: size))
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

#if canImport(SwiftUI)
import SwiftUI
import TokenMonitorKit

/// The Activity mosaic (`HeatmapGrid`): one column per week, Sunday on the top
/// row whatever the locale (desktop `contribHeatmap`), month labels below the
/// columns that hold a month's 1st, as the desktop's `heatmapSvg` draws them.
///
/// Drawn with one `Canvas`, so a year of cells stays cheap in lists and
/// widgets. Taps select a day (tap it again to clear) when a `selectedDate`
/// binding or `onSelect` is given; otherwise the view takes no gestures and
/// taps reach its container (a widget link, a navigation row).
public struct ActivityHeatmapView: View {
    private let layout: HeatmapCanvasLayout
    private let cornerRadius: CGFloat
    private let showsMonthLabels: Bool
    private let monthLabelSize: CGFloat
    private let selectedDate: Binding<String?>?
    private let monthLabel: (String) -> String
    private let cellLabel: ((HeatmapCell) -> String)?
    private let onSelect: ((HeatmapCell?) -> Void)?

    /// - Parameters:
    ///   - visibleWeeks: draw only the most recent N week columns (the medium
    ///     widget's ~20 weeks); nil draws the whole grid.
    ///   - showsMonthLabels: the label row under the grid.
    ///   - monthLabelSize: the label font size.
    ///   - selectedDate: the selected day (`yyyy-MM-dd`), outlined; taps set
    ///     it.
    ///   - monthLabel: `yyyy-MM` → the localized short month ("Jun", "6月").
    ///   - cellLabel: a day's VoiceOver label; nil reads the whole grid as one
    ///     element (label it from the outside).
    ///   - onSelect: called after a tap with the new selection (nil when the
    ///     tap cleared it).
    public init(
        grid: HeatmapGrid,
        cellSize: CGFloat = 10,
        spacing: CGFloat = 3,
        cornerRadius: CGFloat = 2,
        visibleWeeks: Int? = nil,
        showsMonthLabels: Bool = true,
        monthLabelSize: CGFloat = 9,
        selectedDate: Binding<String?>? = nil,
        monthLabel: @escaping (String) -> String,
        cellLabel: ((HeatmapCell) -> String)? = nil,
        onSelect: ((HeatmapCell?) -> Void)? = nil
    ) {
        self.layout = HeatmapCanvasLayout(grid: grid, cellSize: cellSize, spacing: spacing, visibleWeeks: visibleWeeks)
        self.cornerRadius = cornerRadius
        self.showsMonthLabels = showsMonthLabels
        self.monthLabelSize = monthLabelSize
        self.selectedDate = selectedDate
        self.monthLabel = monthLabel
        self.cellLabel = cellLabel
        self.onSelect = onSelect
    }

    /// The cell size that fills `width` with `weeks` columns, clamped to
    /// `range` (the dashboard sizes its cells the same way).
    public static func fittedCellSize(width: CGFloat, weeks: Int, spacing: CGFloat = 3, range: ClosedRange<CGFloat> = 6...22) -> CGFloat {
        guard weeks > 0, width.isFinite, width > 0 else { return range.lowerBound }
        let size = (width - CGFloat(weeks - 1) * spacing) / CGFloat(weeks)
        return min(range.upperBound, max(range.lowerBound, size))
    }

    /// How many whole week columns of `cellSize` fit in `width`.
    public static func weeksFitting(width: CGFloat, cellSize: CGFloat = 10, spacing: CGFloat = 3) -> Int {
        let pitch = cellSize + spacing
        guard pitch > 0, width.isFinite, width >= cellSize else { return 0 }
        return Int(((width + spacing) / pitch).rounded(.down))
    }

    private var isInteractive: Bool { selectedDate != nil || onSelect != nil }

    private var labelRowHeight: CGFloat {
        showsMonthLabels && layout.weeks > 0 ? 3 + (monthLabelSize * 1.3).rounded(.up) : 0
    }

    private var contentSize: CGSize {
        let grid = layout.gridSize
        return CGSize(width: grid.width, height: grid.height + labelRowHeight)
    }

    public var body: some View {
        let size = contentSize
        if let cellLabel {
            canvas
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .accessibilityElement(children: .contain)
                .accessibilityChildren { accessibilityCells(cellLabel, size: size) }
        } else {
            canvas
                .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }

    private var canvas: some View {
        let layout = self.layout
        let selected = selectedDate?.wrappedValue
        let cornerRadius = self.cornerRadius
        let showsMonthLabels = self.showsMonthLabels
        let monthLabelSize = self.monthLabelSize
        let monthLabel = self.monthLabel
        return Canvas { context, size in
            for cell in layout.cells {
                let path = Path(roundedRect: layout.rect(for: cell), cornerRadius: cornerRadius)
                context.fill(path, with: .color(TMTheme.heat(cell.level)))
            }
            if let selected, let cell = layout.cell(date: selected) {
                let outline = Path(roundedRect: layout.rect(for: cell).insetBy(dx: -0.75, dy: -0.75), cornerRadius: cornerRadius + 0.75)
                context.stroke(outline, with: .color(TMTheme.text.opacity(0.9)), lineWidth: 1.5)
            }
            guard showsMonthLabels else { return }
            let top = layout.gridSize.height + 3
            var occupiedUntil = -CGFloat.infinity
            for label in layout.monthLabels {
                var text = context.resolve(
                    Text(verbatim: monthLabel(label.month)).font(.system(size: monthLabelSize, weight: .medium))
                )
                text.shading = .color(TMTheme.muted)
                let measured = text.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
                // Left-anchored on the month's column; a late month is pulled
                // back inside the edge, and a label that would collide with
                // the previous one is dropped.
                let x = max(0, min(CGFloat(label.column) * layout.pitch, size.width - measured.width))
                guard x >= occupiedUntil else { continue }
                context.draw(text, at: CGPoint(x: x, y: top), anchor: .topLeading)
                occupiedUntil = x + measured.width + 4
            }
        }
        .contentShape(Rectangle())
        .gesture(isInteractive ? tapGesture : nil)
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture().onEnded { value in
            guard let cell = layout.cell(at: value.location) else { return }
            toggle(cell)
        }
    }

    private func toggle(_ cell: HeatmapCell) {
        let next: String? = selectedDate?.wrappedValue == cell.date ? nil : cell.date
        selectedDate?.wrappedValue = next
        onSelect?(next == nil ? nil : cell)
    }

    private func accessibilityCells(_ cellLabel: @escaping (HeatmapCell) -> String, size: CGSize) -> some View {
        let selected = selectedDate?.wrappedValue
        return ZStack(alignment: .topLeading) {
            ForEach(layout.cells) { cell in
                let rect = layout.rect(for: cell)
                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityElement()
                    .accessibilityLabel(cellLabel(cell))
                    .accessibilityAddTraits(selected == cell.date ? .isSelected : [])
                    .accessibilityAddTraits(isInteractive ? .isButton : [])
                    .accessibilityAction { if isInteractive { toggle(cell) } }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// The mosaic's geometry: which cells and labels are visible, where each
/// cell sits, and which cell a point hits.
struct HeatmapCanvasLayout {
    let cells: [HeatmapCell]
    let monthLabels: [HeatmapMonthLabel]
    let weeks: Int
    let cellSize: CGFloat
    let spacing: CGFloat

    init(grid: HeatmapGrid, cellSize: CGFloat, spacing: CGFloat, visibleWeeks: Int?) {
        let cellSize = max(1, cellSize)
        let spacing = max(0, spacing)
        let first = visibleWeeks.map { max(0, grid.weeks - max(0, $0)) } ?? 0
        let cells = grid.cells.compactMap { cell -> HeatmapCell? in
            guard cell.column >= first, (0..<7).contains(cell.row) else { return nil }
            var shifted = cell
            shifted.column -= first
            return shifted
        }
        var labels = grid.monthLabels.compactMap { label -> HeatmapMonthLabel? in
            guard label.column >= first else { return nil }
            return HeatmapMonthLabel(column: label.column - first, month: label.month)
        }
        // A trimmed grid can start mid-month: name the first column's month
        // unless another label follows closely.
        if first > 0, labels.first.map({ $0.column >= 3 }) ?? true, let leading = cells.first {
            labels.insert(HeatmapMonthLabel(column: 0, month: String(leading.date.prefix(7))), at: 0)
        }
        self.cells = cells
        self.monthLabels = labels
        self.weeks = max(0, grid.weeks - first)
        self.cellSize = cellSize
        self.spacing = spacing
    }

    var pitch: CGFloat { cellSize + spacing }

    var gridSize: CGSize {
        guard weeks > 0 else { return .zero }
        return CGSize(width: CGFloat(weeks) * pitch - spacing, height: 7 * pitch - spacing)
    }

    func rect(for cell: HeatmapCell) -> CGRect {
        CGRect(x: CGFloat(cell.column) * pitch, y: CGFloat(cell.row) * pitch, width: cellSize, height: cellSize)
    }

    func cell(date: String) -> HeatmapCell? {
        cells.first { $0.date == date }
    }

    /// The cell under `point`; the gap after a cell counts as that cell, so a
    /// small grid stays easy to tap.
    func cell(at point: CGPoint) -> HeatmapCell? {
        guard point.x >= 0, point.y >= 0, pitch > 0 else { return nil }
        let column = Int((point.x / pitch).rounded(.down))
        let row = Int((point.y / pitch).rounded(.down))
        guard column < weeks, row < 7 else { return nil }
        // Cells are consecutive days from the first column's Sunday.
        let index = column * 7 + row
        if cells.indices.contains(index), cells[index].column == column, cells[index].row == row {
            return cells[index]
        }
        return cells.first { $0.column == column && $0.row == row }
    }
}

/// "Less ▢▢▢▢▢ More": the five heat levels between two captions.
public struct HeatmapLegend: View {
    private let less: String
    private let more: String
    private let cellSize: CGFloat
    private let spacing: CGFloat
    private let cornerRadius: CGFloat
    private let font: Font

    public init(less: String, more: String, cellSize: CGFloat = 10, spacing: CGFloat = 3, cornerRadius: CGFloat = 2, font: Font = .caption2) {
        self.less = less
        self.more = more
        self.cellSize = cellSize
        self.spacing = spacing
        self.cornerRadius = cornerRadius
        self.font = font
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: less)
            HStack(spacing: spacing) {
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(TMTheme.heat(level))
                        .frame(width: cellSize, height: cellSize)
                }
            }
            .accessibilityHidden(true)
            Text(verbatim: more)
        }
        .font(font)
        .foregroundStyle(TMTheme.muted)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
#endif

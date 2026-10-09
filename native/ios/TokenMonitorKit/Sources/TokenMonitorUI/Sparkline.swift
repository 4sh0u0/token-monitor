#if canImport(SwiftUI)
import SwiftUI
import TokenMonitorKit

/// A smooth trend line (the macOS widget's `SmoothTrendChart`), optionally
/// with a soft area fill. Scales between the series' minimum and maximum.
public struct Sparkline: View {
    private let values: [Double]
    private let color: Color
    private let lineWidth: CGFloat
    private let fillOpacity: Double

    public init(values: [Double], color: Color = TMTheme.chartBlue, lineWidth: CGFloat = 1.8, fillOpacity: Double = 0) {
        self.values = values.map { $0.isFinite ? $0 : 0 }
        self.color = color
        self.lineWidth = lineWidth
        self.fillOpacity = fillOpacity
    }

    /// A trend from History days (tokens).
    public init(days: [HistoryDay], color: Color = TMTheme.chartBlue, lineWidth: CGFloat = 1.8, fillOpacity: Double = 0) {
        self.init(values: days.map { Double($0.tokens) }, color: color, lineWidth: lineWidth, fillOpacity: fillOpacity)
    }

    public var body: some View {
        ZStack {
            if fillOpacity > 0 {
                SparklineShape(values: values, closed: true)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(fillOpacity), color.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            SparklineShape(values: values)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// The curve behind `Sparkline`: a Catmull-Rom style spline through evenly
/// spaced points. `closed` closes it along the bottom edge for an area fill.
public struct SparklineShape: Shape {
    public var values: [Double]
    public var closed: Bool

    public init(values: [Double], closed: Bool = false) {
        self.values = values
        self.closed = closed
    }

    public func path(in rect: CGRect) -> Path {
        guard !values.isEmpty else { return Path() }
        // A single point still reads as a (flat) line rather than nothing.
        let series = values.count == 1 ? [values[0], values[0]] : values
        let low = series.min() ?? 0
        let high = series.max() ?? low
        let range = max(1, high - low)
        let inset = rect.height * 0.08
        let chartHeight = max(1, rect.height - inset * 2)
        let points = series.enumerated().map { index, value in
            CGPoint(
                x: rect.minX + rect.width * CGFloat(index) / CGFloat(series.count - 1),
                y: rect.minY + inset + chartHeight * (1 - CGFloat((value - low) / range))
            )
        }
        var path = Path()
        path.move(to: points[0])
        for index in 0..<(points.count - 1) {
            let previous = points[max(0, index - 1)]
            let current = points[index]
            let next = points[index + 1]
            let following = points[min(points.count - 1, index + 2)]
            let control1 = CGPoint(x: current.x + (next.x - previous.x) / 6, y: current.y + (next.y - previous.y) / 6)
            let control2 = CGPoint(x: next.x - (following.x - current.x) / 6, y: next.y - (following.y - current.y) / 6)
            path.addCurve(to: next, control1: control1, control2: control2)
        }
        if closed, let last = points.last {
            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
            path.addLine(to: CGPoint(x: points[0].x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
#endif

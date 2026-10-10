#if canImport(SwiftUI)
import SwiftUI
import TokenMonitorKit

extension Path {
    /// A path from the Kit's chart geometry (`AreaLineGeometry.line` /
    /// `.area`, `TrendSeriesBuilder.linePath(through:curve:)`), in the same
    /// coordinates.
    public init(trendElements elements: [TrendPathElement]) {
        self.init()
        for element in elements {
            switch element {
            case .move(let point):
                move(to: CGPoint(x: point.x, y: point.y))
            case .line(let point):
                addLine(to: CGPoint(x: point.x, y: point.y))
            case let .curve(to, control1, control2):
                addCurve(
                    to: CGPoint(x: to.x, y: to.y),
                    control1: CGPoint(x: control1.x, y: control1.y),
                    control2: CGPoint(x: control2.x, y: control2.y)
                )
            case .close:
                closeSubpath()
            }
        }
    }
}
#endif

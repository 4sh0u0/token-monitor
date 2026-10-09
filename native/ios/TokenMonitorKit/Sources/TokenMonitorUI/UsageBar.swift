#if canImport(SwiftUI)
import SwiftUI
import TokenMonitorKit

/// A stacked horizontal bar of shares (Tools or Models of a period).
public struct UsageBar: View {
    public struct Segment: Identifiable, Equatable {
        public let id: String
        public let value: Double
        public let color: Color

        public init(id: String, value: Double, color: Color) {
            self.id = id
            self.value = value
            self.color = color
        }
    }

    private let segments: [Segment]
    private let total: Double?
    private let height: CGFloat
    private let spacing: CGFloat
    private let trackColor: Color

    /// - Parameters:
    ///   - total: the whole the bar represents; segments fill only their
    ///     share of it. Defaults to the sum of the segments (a full bar).
    public init(
        segments: [Segment],
        total: Double? = nil,
        height: CGFloat = 6,
        spacing: CGFloat = 1.5,
        trackColor: Color = TMTheme.track
    ) {
        self.segments = segments.filter { $0.value > 0 && $0.value.isFinite }
        self.total = total
        self.height = height
        self.spacing = spacing
        self.trackColor = trackColor
    }

    /// Shares coloured by vendor. Pass the period's `totalTokens` as `total`
    /// when the rows may not add up to it (or append a remainder row).
    public init(shares: [UsageShare], total: Int? = nil, height: CGFloat = 6, spacing: CGFloat = 1.5) {
        self.init(
            segments: shares.map { Segment(id: $0.id, value: Double($0.tokens), color: $0.color) },
            total: total.map(Double.init),
            height: height,
            spacing: spacing
        )
    }

    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: spacing) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: width(of: segment, in: proxy.size.width))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(trackColor)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func width(of segment: Segment, in available: CGFloat) -> CGFloat {
        let sum = segments.reduce(0) { $0 + $1.value }
        let denominator = max(total ?? sum, sum)
        guard denominator > 0 else { return 0 }
        let gaps = spacing * CGFloat(max(0, segments.count - 1))
        let drawable = max(0, available - gaps)
        return drawable * CGFloat(segment.value / denominator)
    }
}
#endif

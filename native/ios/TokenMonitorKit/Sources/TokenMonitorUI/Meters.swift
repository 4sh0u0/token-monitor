#if canImport(SwiftUI)
import SwiftUI
import TokenMonitorKit

/// A circular meter that fills by `fraction` (0...1) clockwise from the top,
/// with optional content in the middle. A nil fraction draws only the track
/// (the window has no meter, e.g. `showMeter == false`).
public struct QuotaRing<Center: View>: View {
    private let fraction: Double?
    private let color: Color
    private let lineWidth: CGFloat
    private let trackColor: Color
    private let center: Center

    public init(
        fraction: Double?,
        color: Color,
        lineWidth: CGFloat = 4,
        trackColor: Color = TMTheme.track,
        @ViewBuilder center: () -> Center
    ) {
        self.fraction = fraction.map { min(1, max(0, $0)) }
        self.color = color
        self.lineWidth = lineWidth
        self.trackColor = trackColor
        self.center = center()
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            if let fraction, fraction > 0 {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            center
        }
        .padding(lineWidth / 2)
    }
}

extension QuotaRing where Center == EmptyView {
    public init(fraction: Double?, color: Color, lineWidth: CGFloat = 4, trackColor: Color = TMTheme.track) {
        self.init(fraction: fraction, color: color, lineWidth: lineWidth, trackColor: trackColor) { EmptyView() }
    }
}

/// A thin horizontal meter (the macOS widget's `PercentageBar`): fills by
/// `fraction` (0...1), usually what is *left* of a quota window.
public struct QuotaBar: View {
    private let fraction: Double
    private let color: Color
    private let height: CGFloat
    private let trackColor: Color

    public init(fraction: Double, color: Color, height: CGFloat = 4, trackColor: Color = TMTheme.track) {
        self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
        self.color = color
        self.height = height
        self.trackColor = trackColor
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule()
                    .fill(color.opacity(0.85))
                    .frame(width: proxy.size.width * CGFloat(fraction))
            }
        }
        .frame(height: height)
    }
}
#endif

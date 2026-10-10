#if canImport(SwiftUI)
import SwiftUI
import TokenMonitorKit

// Quota meters in the provider's colour (desktop `windowsView.js`
// `limitMeterNode`): the track is the colour at 16 %, the fill the colour at
// the window's tone opacity. Linear meters read in the user's used/remaining
// mode (`MeterFill.mode`); rings and gauges always read what is left, as the
// Edge Dock does.

extension MeterFill {
    /// The same reading in remaining mode: rings and gauges always show what
    /// is left, whatever the user's used/remaining choice. The two modes are
    /// complements (`displayMode.js` `limitFillPercent`).
    public var tmRemaining: MeterFill {
        guard mode == .used else { return self }
        return MeterFill(
            fraction: fraction.map { 1 - $0 },
            percent: percent.map { 100 - $0 },
            mode: .remaining,
            toneOpacity: toneOpacity
        )
    }
}

/// A clamped 0...1 fill, nil when there is no meter.
private func meterFraction(_ fill: MeterFill) -> Double? {
    guard let fraction = fill.fraction else { return nil }
    return fraction.isFinite ? min(1, max(0, fraction)) : 0
}

/// The Limits page's linear meter. Draws nothing when the window has no
/// meter (`fill.fraction == nil`); the caller then shows only the text.
public struct LimitMeter: View {
    private let fill: MeterFill
    private let color: Color
    private let height: CGFloat

    public init(fill: MeterFill, color: Color, height: CGFloat = 6) {
        self.fill = fill
        self.color = color
        self.height = height
    }

    public var body: some View {
        if let fraction = meterFraction(fill) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(color.opacity(0.16))
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(color)
                        .opacity(fill.toneOpacity)
                        .frame(width: proxy.size.width * CGFloat(fraction))
                }
            }
            .frame(height: height)
            .animation(.easeOut(duration: 0.42), value: fraction)
            .accessibilityHidden(true)
        }
    }
}

/// A ring meter in the provider's colour. It always reads what is left
/// (`MeterFill.tmRemaining`); a window without a meter draws the centre on a
/// plain disc, never an empty ring ("nothing left").
public struct LimitRing<Center: View>: View {
    private let fill: MeterFill
    private let color: Color
    private let lineWidth: CGFloat
    private let center: Center

    public init(fill: MeterFill, color: Color, lineWidth: CGFloat = 4, @ViewBuilder center: () -> Center) {
        self.fill = fill
        self.color = color
        self.lineWidth = lineWidth
        self.center = center()
    }

    public var body: some View {
        let remaining = fill.tmRemaining
        QuotaRing(
            fraction: meterFraction(remaining),
            color: color.opacity(remaining.toneOpacity),
            lineWidth: lineWidth,
            trackColor: color.opacity(0.16)
        ) {
            center
        }
    }
}

extension LimitRing where Center == EmptyView {
    public init(fill: MeterFill, color: Color, lineWidth: CGFloat = 4) {
        self.init(fill: fill, color: color, lineWidth: lineWidth) { EmptyView() }
    }
}
#endif

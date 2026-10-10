#if canImport(SwiftUI)
import SwiftUI
import TokenMonitorKit

/// A session's context window as a short fuel gauge and its percentage
/// (desktop `.row-context` / `.home-session-context`). It stays neutral
/// while there is room and turns yellow, then orange, as headroom runs out,
/// whichever way the number reads: "93 % used" is the same emergency as
/// "7 % left".
public struct ContextGaugeBar: View {
    @Environment(\.tmFormatter) private var formatter

    private let gauge: SessionContextGauge
    private let metric: ContextMetric
    private let width: CGFloat
    private let height: CGFloat
    private let showsValue: Bool
    private let valueText: String?
    private let font: Font

    /// - Parameters:
    ///   - metric: the user's `sessionContextMetric` (used by default on the
    ///     desktop, as the clients themselves show it).
    ///   - width: the meter's width.
    ///   - valueText: replaces the percentage text; nil formats
    ///     `gauge.percent(for: metric)` with `tmFormatter`.
    public init(
        gauge: SessionContextGauge,
        metric: ContextMetric,
        width: CGFloat = 36,
        height: CGFloat = 3,
        showsValue: Bool = true,
        valueText: String? = nil,
        font: Font = .caption2
    ) {
        self.gauge = gauge
        self.metric = metric
        self.width = width
        self.height = height
        self.showsValue = showsValue
        self.valueText = valueText
        self.font = font
    }

    public var body: some View {
        let percent = gauge.percent(for: metric)
        let fraction = min(1, max(0, Double(percent) / 100))
        let tint = TMTheme.contextColor(gauge.tone)
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(gauge.tone == .neutral ? Color.white.opacity(0.55) : tint)
                    .frame(width: width * CGFloat(fraction))
            }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
            if showsValue {
                Text(verbatim: valueText ?? formatter.percent(Double(percent)))
                    .font(font)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
        }
    }
}

/// A session's live state on Home (`sessionLive.js` `sessionStateMarkup`):
/// a spinner while it runs, a check once the turn ended, a faint dot when
/// idle. Decorative; give it an accessibility label from the outside if the
/// row needs one.
public struct SessionStateGlyph: View {
    private let state: SessionActivityState
    private let size: CGFloat

    public init(state: SessionActivityState, size: CGFloat = 12) {
        self.state = state
        self.size = size
    }

    public var body: some View {
        Group {
            switch state {
            case .running:
                SessionSpinner(color: TMTheme.text)
            case .ended:
                SessionCheckCircle(color: TMTheme.muted)
            case .idle:
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: size / 2, height: size / 2)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The eight-spoke loader (the desktop's `icons/actions/spinner.svg`): spokes
/// fade in turn, one step every 0.1125 s, clockwise. Still when Reduce
/// Motion is on (and in widgets, which do not animate).
struct SessionSpinner: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let step: TimeInterval = 0.1125
    static let opacities: [Double] = [0.95, 0.78, 0.62, 0.44, 0.30, 0.22, 0.16, 0.12]

    var body: some View {
        if reduceMotion {
            spokes(step: 0)
        } else {
            TimelineView(.animation(minimumInterval: Self.step)) { timeline in
                // Reduced in Double first: the step count overflows the
                // watch's 32-bit Int.
                let steps = (timeline.date.timeIntervalSinceReferenceDate / Self.step).rounded(.down)
                spokes(step: Int(abs(steps.truncatingRemainder(dividingBy: 8))))
            }
        }
    }

    private func spokes(step: Int) -> some View {
        let color = self.color
        return Canvas { context, size in
            // The svg's 11-unit viewBox, centred.
            let unit = min(size.width, size.height) / 11
            context.translateBy(x: size.width / 2, y: size.height / 2)
            let spoke = Path(
                roundedRect: CGRect(x: -0.65 * unit, y: -4.75 * unit, width: 1.3 * unit, height: 2.75 * unit),
                cornerRadius: 0.65 * unit
            )
            for index in 0..<8 {
                var layer = context
                layer.rotate(by: .degrees(Double(315 - 45 * index)))
                layer.opacity = Self.opacities[(step + index) % 8]
                layer.fill(spoke, with: .color(color))
            }
        }
    }
}

/// A check in a circle, stroked (the desktop's `CHECK_PATHS` on a 24-unit
/// grid).
struct SessionCheckCircle: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 24
            let origin = CGPoint(x: (size.width - 24 * unit) / 2, y: (size.height - 24 * unit) / 2)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + x * unit, y: origin.y + y * unit)
            }
            var path = Path(ellipseIn: CGRect(x: origin.x + 3 * unit, y: origin.y + 3 * unit, width: 18 * unit, height: 18 * unit))
            path.move(to: point(8.7, 12.2))
            path.addLine(to: point(10.8, 14.3))
            path.addLine(to: point(15.3, 9.7))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2 * unit, lineCap: .round, lineJoin: .round))
        }
    }
}

/// The green "being written to right now" dot a Sessions row lays over its
/// mark's corner while the session runs (desktop `.row-live-dot`). The ring
/// in the surface colour separates it from the mark under it.
public struct SessionLiveDot: View {
    private let size: CGFloat
    private let ringColor: Color

    public init(size: CGFloat = 5, ringColor: Color = TMTheme.background) {
        self.size = size
        self.ringColor = ringColor
    }

    public var body: some View {
        Circle()
            .fill(TMTheme.success)
            .frame(width: size, height: size)
            .shadow(color: TMTheme.success.opacity(0.55), radius: 2)
            .background(
                Circle()
                    .fill(ringColor)
                    .frame(width: size + 3, height: size + 3)
            )
            .accessibilityHidden(true)
    }
}
#endif

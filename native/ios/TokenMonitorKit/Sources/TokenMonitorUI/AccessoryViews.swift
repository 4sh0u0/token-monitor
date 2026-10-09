#if canImport(SwiftUI)
import SwiftUI
import TokenMonitorKit

// Building blocks for iOS Lock Screen widgets (accessoryCircular /
// accessoryRectangular) and watch complications. They only use SwiftUI's
// accessory gauge styles, so the same view renders in both widget extensions
// and in app previews. All text is passed in already formatted and localized.

/// accessoryCircular: a headline number (e.g. today's tokens, "1.2M").
///
/// With a `fraction` it is drawn as a circular gauge (e.g. today against the
/// trend's busiest day); without one, as the number on a plain disc.
public struct AccessoryTokensGauge: View {
    private let valueText: String
    private let label: String?
    private let fraction: Double?

    public init(valueText: String, label: String? = nil, fraction: Double? = nil) {
        self.valueText = valueText
        self.label = label
        self.fraction = fraction.map { $0.isFinite ? min(1, max(0, $0)) : 0 }
    }

    public var body: some View {
        if let fraction {
            Gauge(value: fraction) {
                if let label { Text(label) }
            } currentValueLabel: {
                Text(valueText)
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            ZStack {
                Circle().fill(.quaternary)
                VStack(spacing: 0) {
                    Text(valueText)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let label {
                        Text(label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .padding(4)
            }
        }
    }
}

/// accessoryCircular: what is left of a quota window, as a capacity ring.
public struct AccessoryQuotaGauge: View {
    private let fraction: Double?
    private let valueText: String
    private let label: String
    private let tint: Color

    /// - Parameters:
    ///   - fraction: what is left, 0...1 (`LimitProvider.meterFraction(for:)`);
    ///     nil draws an empty ring with the value text.
    ///   - valueText: the centre text, e.g. "58%" or "$37.50".
    ///   - label: a short provider/window name shown under the ring.
    public init(fraction: Double?, valueText: String, label: String, tint: Color = TMTheme.success) {
        self.fraction = fraction.map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        self.valueText = valueText
        self.label = label
        self.tint = tint
    }

    public var body: some View {
        Gauge(value: fraction ?? 0) {
            Text(label)
        } currentValueLabel: {
            Text(valueText)
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(tint)
    }
}

/// accessoryRectangular: a title, a headline value with an optional trend
/// line, and either a capacity bar or a detail line.
public struct AccessorySummaryView: View {
    private let title: String
    private let value: String
    private let detail: String?
    private let fraction: Double?
    private let trend: [Double]
    private let tint: Color

    public init(
        title: String,
        value: String,
        detail: String? = nil,
        fraction: Double? = nil,
        trend: [Double] = [],
        tint: Color = TMTheme.chartBlue
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.fraction = fraction.map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        self.trend = trend
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .center, spacing: 6) {
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if trend.count > 1 {
                    Sparkline(values: trend, color: tint, lineWidth: 1.5)
                        .frame(maxWidth: .infinity)
                        .frame(height: 16)
                }
            }
            if let fraction {
                Gauge(value: fraction) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(tint)
            } else if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif

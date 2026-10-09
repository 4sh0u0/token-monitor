import SwiftUI
import TokenMonitorKit
import TokenMonitorUI
import WidgetKit

/// What is left of the tightest AI tool quota window.
struct QuotaComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ComplicationKind.quota, provider: ComplicationProvider()) { entry in
            QuotaComplicationView(entry: entry)
                .containerBackground(for: .widget) { TMBackground() }
        }
        .configurationDisplayName("Token Monitor Quota")
        .description("Subscription windows and reset times.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct QuotaComplicationView: View {
    static let maxRows = 3

    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            ComplicationPlaceholderView(isConfigured: entry.isConfigured)
        }
    }

    @ViewBuilder
    private func content(_ snapshot: TokenSnapshot) -> some View {
        let headline = ComplicationQuotaRow.headlines(in: snapshot, limit: 1).first
        switch family {
        case .accessoryRectangular:
            let layout = ComplicationQuotaRow.rectangularRows(in: snapshot, limit: Self.maxRows)
            QuotaRectangularView(header: layout.header, rows: layout.rows)
        case .accessoryInline:
            if let headline {
                Label {
                    Text(verbatim: "\(headline.title) \(headline.value)")
                } icon: {
                    Image(systemName: "gauge.medium")
                }
            } else {
                Text("No data")
            }
        case .accessoryCorner:
            if let headline {
                Text(verbatim: headline.value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                    .widgetLabel {
                        if let fraction = headline.fraction {
                            Gauge(value: fraction) {
                                Text(verbatim: headline.title)
                            }
                            .tint(headline.tint)
                        } else {
                            Text(verbatim: headline.title)
                        }
                    }
            } else {
                Image(systemName: "gauge.medium")
                    .font(.title3)
                    .widgetLabel {
                        Text("No data")
                    }
            }
        default:
            if let headline {
                AccessoryQuotaGauge(
                    fraction: headline.fraction,
                    valueText: headline.value,
                    label: headline.title,
                    tint: headline.tint
                )
            } else {
                AccessoryQuotaGauge(fraction: nil, valueText: "—", label: String(localized: "No data"))
            }
        }
    }
}

/// Up to three meters: one per provider, or one provider's windows under
/// its name.
struct QuotaRectangularView: View {
    let header: String?
    let rows: [ComplicationQuotaRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let header {
                Text(verbatim: header)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if rows.isEmpty {
                Text("No data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                HStack(spacing: 5) {
                    Text(verbatim: row.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 54, alignment: .leading)
                    // `showMeter == false`: the amount alone, no meter.
                    if let fraction = row.fraction {
                        Gauge(value: fraction) {
                            EmptyView()
                        }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(row.tint)
                    } else {
                        Spacer(minLength: 0)
                    }
                    Text(verbatim: row.value)
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .widgetAccentable()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview(as: .accessoryRectangular) {
    QuotaComplication()
} timeline: {
    ComplicationEntry.sample
}

#Preview(as: .accessoryCircular) {
    QuotaComplication()
} timeline: {
    ComplicationEntry.sample
}

#Preview(as: .accessoryCorner) {
    QuotaComplication()
} timeline: {
    ComplicationEntry.sample
}

#Preview(as: .accessoryInline) {
    QuotaComplication()
} timeline: {
    ComplicationEntry.sample
}

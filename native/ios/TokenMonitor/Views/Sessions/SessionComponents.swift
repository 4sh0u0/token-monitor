import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

// Pieces the Sessions list, the background-review list, the Overview module
// and the detail screen share.

// MARK: Re-rendering

/// When a session surface must redraw on its own: at `SessionLive.nextChange`
/// (a session leaving the 10-minute running window, a prompt-cache label
/// ticking down) and at least once a minute (ages, times), as the desktop's
/// `scheduleSessionStatusRepaint` does.
///
/// Views compute with `SessionLiveSchedule.now(context)`, not the entry date
/// alone: a refresh from the Hub redraws between entries, and a prompt cache
/// observed after the last entry would otherwise read as "in the future".
struct SessionLiveSchedule: TimelineSchedule {
    let sessions: [HubSession]

    /// The desktop's 60 s cap on the wait.
    static let maximumWait: TimeInterval = 60

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> UnfoldFirstSequence<Date> {
        let sessions = self.sessions
        return sequence(first: startDate) { previous in
            let cap = previous.addingTimeInterval(Self.maximumWait)
            guard let change = SessionLive.nextChange(sessions: sessions, now: previous) else { return cap }
            // Just past the boundary (the desktop waits 50 ms more), and never
            // a busy loop on a boundary that does not move.
            return min(cap, max(previous.addingTimeInterval(1), change.addingTimeInterval(0.05)))
        }
    }

    /// The clock a session surface reads inside its `TimelineView`.
    static func now(_ context: TimelineViewDefaultContext) -> Date {
        max(context.date, Date())
    }
}

// MARK: Marks and colours

enum SessionColor {
    /// The desktop's row colour: the client's colour, else the model's,
    /// else a stable colour from the session key (`sessionRowsForPeriod`).
    static func color(client: String, model: SessionModelLabel, key: String, palette: VendorPalette) -> Color {
        if VendorCatalog.mark(for: client) != nil {
            return VendorColor.color(for: client, palette: palette)
        }
        if let model = SessionText.modelLabel(model) {
            return VendorColor.model(model, palette: palette)
        }
        return Color(hex: VendorCatalog.fallbackModelColorHex(for: key))
    }
}

/// A session's client mark with the green "running right now" dot at its
/// corner (the desktop list's `.row-live-dot`; nothing for other states).
struct SessionMark: View {
    let client: String
    var color: Color? = nil
    var isRunning: Bool = false
    var size: CGFloat = 16

    var body: some View {
        VendorMark(.client(client), size: size, dotColor: color)
            .overlay(alignment: .bottomTrailing) {
                if isRunning {
                    SessionLiveDot(size: max(5, size * 0.34), ringColor: TMTheme.background)
                        .offset(x: size * 0.18, y: size * 0.18)
                }
            }
    }
}

// MARK: Gauge slot

/// The slot at a session row's end: the context gauge while the session is
/// live, else the prompt-cache countdown ("Cache 4m"), else nothing
/// (`updateRowContext`).
struct SessionGaugeSlot: View {
    @Environment(\.tmFormatter) private var formatter
    let context: SessionContextGauge?
    let promptCache: PromptCacheCountdown?
    let metric: ContextMetric
    var gaugeWidth: CGFloat = 36

    var body: some View {
        if let context {
            ContextGaugeBar(gauge: context, metric: metric, width: gaugeWidth)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: SessionText.contextPercent(context, metric: metric, formatter: formatter)))
        } else if let promptCache {
            Text(verbatim: SessionText.cacheBadge(promptCache))
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(TMTheme.muted)
                .lineLimit(1)
                .accessibilityLabel(Text(verbatim: SessionText.cacheLeft(promptCache)))
        }
    }
}

/// A thin share-of-the-largest bar under a row (the desktop rows' `.bar`).
struct SessionShareBar: View {
    let value: Int
    let maximum: Int
    let color: Color

    var body: some View {
        let fraction = maximum > 0 ? min(1, max(0, Double(value) / Double(maximum))) : 0
        Capsule()
            .fill(TMTheme.track)
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(color.opacity(0.85))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: List row

/// One row of the Sessions list: a session, or the background-review group.
/// Name, the subtitle (tool and model for a titled session, its activity
/// otherwise), a titled session's activity line, the session id when no
/// activity line shows, full tokens, the compact cost and the gauge slot.
struct SessionListRow: View {
    @Environment(\.tmFormatter) private var formatter
    @Environment(\.tmPresentation) private var presentation
    @ScaledMetric(relativeTo: .subheadline) private var markSize: CGFloat = 16

    let row: SessionRow
    let maximum: Int
    let metric: ContextMetric

    var body: some View {
        let color = SessionColor.color(client: row.client, model: row.modelLabel, key: row.session?.id ?? row.id, palette: presentation.palette)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                SessionMark(client: row.client, color: color, isRunning: row.isRunning, size: markSize)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: SessionText.name(row.name))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(TMTheme.text)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    ForEach(Array(secondaryLines.enumerated()), id: \.offset) { index, line in
                        Text(verbatim: line)
                            .font(index == 0 ? .caption : .caption2)
                            .foregroundStyle(TMTheme.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(verbatim: formatter.fullTokens(row.tokens))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(TMTheme.number)
                        .lineLimit(1)
                    CostLabelText(usd: row.costUsd, unpricedTokens: row.unpricedTokens, compact: true)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(TMTheme.muted)
                        .lineLimit(1)
                    SessionGaugeSlot(context: row.context, promptCache: row.showsPromptCache ? row.promptCache : nil, metric: metric)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TMTheme.muted.opacity(0.6))
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
            SessionShareBar(value: row.tokens, maximum: maximum, color: color)
                .padding(.leading, markSize + 10)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .accessibilityValue(Text(verbatim: accessibilityValue))
    }

    /// Subtitle, then a titled session's activity line, then the id (shown
    /// only without an activity line, as the desktop's interactive rows) or
    /// the group's run count.
    private var secondaryLines: [String] {
        var lines: [String] = []
        if let subtitle = row.subtitle {
            let text = SessionText.subtitle(subtitle, formatter: formatter)
            if !text.isEmpty { lines.append(text) }
        }
        if let activity = row.activityLine {
            lines.append(SessionText.activity(activity))
        }
        if row.isReviewGroup {
            lines.append(SessionText.backgroundRuns(row.reviewCount))
        } else if row.activityLine == nil, let id = row.idLabel {
            lines.append(id)
        }
        return lines
    }

    private var accessibilityLabel: String {
        var parts = [SessionText.name(row.name)]
        if row.state != .idle { parts.append(SessionText.state(row.state)) }
        parts.append(contentsOf: secondaryLines)
        return parts.joined(separator: ", ")
    }

    private var accessibilityValue: String {
        var parts = [
            formatter.fullTokens(row.tokens) + " " + String(localized: "tokens"),
            CostLabelText.string(usd: row.costUsd, unpricedTokens: row.unpricedTokens, formatter: formatter)
        ]
        if let context = row.context {
            parts.append(SessionText.contextPercent(context, metric: metric, formatter: formatter))
        } else if row.showsPromptCache, let cache = row.promptCache {
            parts.append(SessionText.cacheLeft(cache))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: Detail building blocks

/// A label on the left, a value on the right; the value wraps under the
/// label at large Dynamic Type sizes.
struct SessionField<Value: View>: View {
    private let label: Text
    private let value: Value

    init(_ label: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.label = Text(label)
        self.value = value()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                styledLabel
                Spacer(minLength: 8)
                value
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                styledLabel
                value
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private var styledLabel: some View {
        label
            .foregroundStyle(TMTheme.muted)
            .lineLimit(1)
    }
}

extension SessionField where Value == Text {
    /// A field whose value is already formatted.
    init(_ label: LocalizedStringKey, verbatim value: String) {
        self.init(label) {
            Text(verbatim: value)
                .monospacedDigit()
                .foregroundStyle(TMTheme.text)
        }
    }
}

/// A thin divider between rows inside a card.
struct SessionRowDivider: View {
    var leading: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(TMTheme.divider.opacity(0.5))
            .frame(height: 1 / 3)
            .padding(.leading, leading)
    }
}

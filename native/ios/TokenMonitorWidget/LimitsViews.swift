import SwiftUI
import TokenMonitorKit
import TokenMonitorUI
import WidgetKit

/// Which limits a widget shows.
enum LimitSelection {
    /// The snapshot's providers with the windows the user hid on the Limits
    /// page removed. `SnapshotBuilder` already drops them; a snapshot built
    /// for older settings (shown while a refresh is due) may still carry them.
    static func visible(_ snapshot: TokenSnapshot, preferences: DisplayPreferences) -> [LimitProvider] {
        let hiddenItems = preferences.limitProviderHiddenItems
        guard !hiddenItems.isEmpty else { return snapshot.limits }
        return snapshot.limits.map { provider in
            var visible = provider
            visible.windows = provider.visibleWindows(hiddenItems: hiddenItems)
            return visible
        }
    }

    static func pinned(_ id: String?, in providers: [LimitProvider]) -> LimitProvider? {
        guard let id else { return nil }
        return providers.first { $0.id == id }
    }

    /// The automatic order, shaped by the Home limits settings like the
    /// app's Home module: providers hidden there are left out; with a Home
    /// provider order set, that order (accounts with readings before those
    /// without), else the most constrained first
    /// (`LimitProvider.sortedByUrgency`, which the watch's Quota complication
    /// uses too).
    static func automatic(_ providers: [LimitProvider], preferences: DisplayPreferences) -> [LimitProvider] {
        let hidden = Set(preferences.hiddenHomeLimitProviders.map(OrderedIDs.normalizeID))
        let shown = providers.filter { !hidden.contains(OrderedIDs.normalizeID($0.provider)) }
        let order = LimitPresentation.normalizedHomeProviderOrder(preferences.homeLimitProviderOrder)
        guard !order.isEmpty else { return LimitProvider.sortedByUrgency(shown) }
        let ordered = OrderedIDs.ordered(shown, id: \.provider, order: order, known: LimitPresentation.catalogProviderIDs)
        return ordered.filter(\.hasData) + ordered.filter { !$0.hasData }
    }

    /// The pinned provider first while it is still in the snapshot (even one
    /// hidden from Home: pinning is this widget's own choice), then the
    /// automatic order.
    static func providers(in snapshot: TokenSnapshot, pinnedID: String?, preferences: DisplayPreferences, limit: Int) -> [LimitProvider] {
        let providers = visible(snapshot, preferences: preferences)
        let automatic = automatic(providers, preferences: preferences)
        guard let pinned = pinned(pinnedID, in: providers) else {
            return Array(automatic.prefix(limit))
        }
        return Array(([pinned] + automatic.filter { $0.id != pinned.id }).prefix(limit))
    }

    /// Medium widget cells: a pinned provider's windows, else one cell per
    /// provider showing its headline window.
    static func cells(in snapshot: TokenSnapshot, pinnedID: String?, preferences: DisplayPreferences, limit: Int) -> [LimitCell] {
        if let pinned = pinned(pinnedID, in: visible(snapshot, preferences: preferences)) {
            let windows = Array(pinned.primaryWindows.prefix(limit))
            if windows.isEmpty {
                return [LimitCell(id: pinned.id, title: pinned.displayName, provider: pinned, window: nil)]
            }
            return windows.map { window in
                LimitCell(id: "\(pinned.id)|\(window.id)", title: WidgetText.windowName(window, provider: pinned), provider: pinned, window: window)
            }
        }
        return providers(in: snapshot, pinnedID: nil, preferences: preferences, limit: limit).map { provider in
            LimitCell(id: provider.id, title: provider.displayName, provider: provider, window: provider.headlineWindow)
        }
    }
}

struct LimitCell: Identifiable {
    let id: String
    let title: String
    let provider: LimitProvider
    let window: LimitWindow?
}

/// How a provider's mark, rings and bars are drawn: in the provider's colour
/// (the user's vendor-colour override applies) at the window's tone, grey
/// while the reading is not healthy and fresh.
enum LimitStyle {
    static func tint(_ provider: LimitProvider, palette: VendorPalette) -> Color {
        provider.isReady ? VendorColor.color(for: provider.provider, palette: palette) : TMTheme.muted
    }

    /// The mark a row wears (a relay draws its adapter's mark).
    static func mark(_ provider: LimitProvider) -> VendorMarkSubject {
        .provider(LimitPresentation.iconID(provider))
    }

    /// The status chip needs the user's attention: anything but a healthy
    /// reading or a stale one (the stale mark already says so).
    static func needsAttention(_ chip: LimitPresentation.StatusChip) -> Bool {
        switch chip.label {
        case .live, .linked, .stale: return false
        default: return true
        }
    }

    static let emptyFill = MeterFill(fraction: nil, percent: nil, mode: .remaining, toneOpacity: 1)
}

/// A window as a ring: it always fills by what is left, while the number in
/// the middle follows the user's used/remaining mode and says which
/// (`LimitPresentation.headline`). A window without a meter shows its value
/// on a plain disc, never an empty ring.
struct LimitWindowRing: View {
    @Environment(\.tmPresentation) private var presentation
    @Environment(\.tmFormatter) private var format
    let provider: LimitProvider
    let window: LimitWindow?
    let lineWidth: CGFloat
    let valueSize: CGFloat

    var body: some View {
        let showUsed = presentation.preferences.showLimitUsed
        let fill = window.map { LimitPresentation.meterFill(window: $0, provider: provider, showUsed: showUsed) } ?? LimitStyle.emptyFill
        let headline = window.map { LimitPresentation.headline(window: $0, provider: provider, showUsed: showUsed) } ?? .none
        let caption = Self.modeCaption(headline)
        LimitRing(fill: fill, color: LimitStyle.tint(provider, palette: presentation.palette), lineWidth: lineWidth) {
            VStack(spacing: 0) {
                Text(verbatim: WidgetText.headline(headline, format, compact: true))
                    .font(.system(size: valueSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(provider.isReady ? TMTheme.number : TMTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                if let caption {
                    Text(verbatim: caption)
                        .font(.system(size: max(8, valueSize * 0.42), weight: .medium))
                        .foregroundStyle(TMTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, lineWidth + 3)
        }
        .aspectRatio(1, contentMode: .fit)
        .widgetAccentable()
    }

    /// "left" / "used" under a percentage.
    private static func modeCaption(_ headline: LimitPresentation.Headline) -> String? {
        guard case let .percent(_, mode) = headline else { return nil }
        return WidgetText.modeWord(mode)
    }
}

/// The line under a meter: a status that needs the user (in its chip's
/// colour), else the live reset/expiry countdown, else the plan.
enum LimitDetailLine {
    static func text(provider: LimitProvider, window: LimitWindow?, now: Date) -> Text {
        let chip = LimitPresentation.statusChip(provider)
        if LimitStyle.needsAttention(chip) {
            return Text(verbatim: WidgetText.status(chip.label)).foregroundStyle(TMTheme.tagColor(chip.tone))
        }
        if let window, let boundary = WidgetText.boundary(window, now: now) {
            return boundary
        }
        // A space keeps the line's height so rows stay aligned.
        return Text(verbatim: WidgetText.planCell(provider) ?? " ")
    }
}

/// A full-width limits row: mark, name, window and value, then the meter
/// (in the user's used/remaining mode) and the countdown. Used by the large
/// Usage dashboard.
struct LimitMeterRow: View {
    @Environment(\.tmPresentation) private var presentation
    @Environment(\.tmFormatter) private var format
    let provider: LimitProvider
    let now: Date

    var body: some View {
        let window = provider.headlineWindow
        let showUsed = presentation.preferences.showLimitUsed
        let fill = window.map { LimitPresentation.meterFill(window: $0, provider: provider, showUsed: showUsed) } ?? LimitStyle.emptyFill
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                VendorMark(LimitStyle.mark(provider), size: 12, muted: !provider.isReady)
                Text(verbatim: provider.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(provider.isReady ? TMTheme.text : TMTheme.muted)
                    .lineLimit(1)
                if let window {
                    Text(verbatim: WidgetText.windowName(window, provider: provider))
                        .font(.caption2)
                        .foregroundStyle(TMTheme.muted)
                        .lineLimit(1)
                }
                if provider.isStale { StaleBadge() }
                Spacer(minLength: 4)
                Text(verbatim: valueText(window, showUsed: showUsed))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(provider.isReady ? TMTheme.number : TMTheme.muted)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                if fill.fraction != nil {
                    LimitMeter(fill: fill, color: LimitStyle.tint(provider, palette: presentation.palette), height: 3)
                        .widgetAccentable()
                } else {
                    Spacer(minLength: 0)
                }
                LimitDetailLine.text(provider: provider, window: window, now: now)
                    .font(.system(size: 10))
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func valueText(_ window: LimitWindow?, showUsed: Bool) -> String {
        guard let window else { return WidgetText.status(LimitPresentation.statusChip(provider).label) }
        return WidgetText.headline(LimitPresentation.headline(window: window, provider: provider, showUsed: showUsed), format, compact: false)
    }
}

// MARK: - Families

/// systemSmall: the most constrained (or pinned) provider as one ring.
struct LimitsSmallView: View {
    let entry: TokenEntry
    let provider: LimitProvider

    var body: some View {
        let window = provider.headlineWindow
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                VendorMark(LimitStyle.mark(provider), size: 13, muted: !provider.isReady)
                Text(verbatim: provider.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TMTheme.text)
                    .lineLimit(1)
                if entry.isStale || provider.isStale { StaleBadge() }
                Spacer(minLength: 0)
            }
            LimitWindowRing(provider: provider, window: window, lineWidth: 7, valueSize: 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            detail(window)
                .font(.caption2)
                .foregroundStyle(TMTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        // One VoiceOver element: provider, value, mode and countdown.
        .accessibilityElement(children: .combine)
    }

    /// "Session · Reset in 2 hr, 13 min": which window the ring shows, and
    /// when it resets.
    private func detail(_ window: LimitWindow?) -> Text {
        let line = LimitDetailLine.text(provider: provider, window: window, now: entry.date)
        guard let window else { return line }
        return Text(verbatim: WidgetText.windowName(window, provider: provider)) + Text(verbatim: " · ") + line
    }
}

/// systemMedium: up to four rings — one per provider, or a pinned
/// provider's windows.
struct LimitsMediumView: View {
    let entry: TokenEntry
    let snapshot: TokenSnapshot

    var body: some View {
        let pinned = LimitSelection.pinned(entry.pinnedLimitID, in: snapshot.limits)
        let cells = LimitSelection.cells(in: snapshot, pinnedID: entry.pinnedLimitID, preferences: entry.preferences, limit: 4)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                if let pinned {
                    VendorMark(LimitStyle.mark(pinned), size: 12, muted: !pinned.isReady)
                    Text(verbatim: pinned.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TMTheme.text)
                        .lineLimit(1)
                } else {
                    SectionLabel(text: WidgetText.limits)
                }
                if entry.isStale || pinned?.isStale == true { StaleBadge() }
                Spacer(minLength: 4)
                UpdatedFootnote(fetchedAt: snapshot.fetchedAt, now: entry.date, isStale: entry.isStale)
                RefreshButton()
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(cells) { cell in
                    LimitRingCell(cell: cell, now: entry.date, showsMark: pinned == nil)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct LimitRingCell: View {
    let cell: LimitCell
    let now: Date
    let showsMark: Bool

    var body: some View {
        VStack(spacing: 4) {
            LimitWindowRing(provider: cell.provider, window: cell.window, lineWidth: 5, valueSize: 13)
                .frame(maxWidth: 56, maxHeight: 56)
            HStack(spacing: 3) {
                if showsMark { VendorMark(LimitStyle.mark(cell.provider), size: 10, muted: !cell.provider.isReady) }
                Text(verbatim: cell.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(cell.provider.isReady ? TMTheme.text : TMTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            LimitDetailLine.text(provider: cell.provider, window: cell.window, now: now)
                .font(.system(size: 9.5))
                .foregroundStyle(TMTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// accessoryCircular: the headline window as a capacity gauge. Like every
/// ring it fills by what is left; the number follows the user's mode.
struct LimitsCircularView: View {
    @Environment(\.tmPresentation) private var presentation
    @Environment(\.tmFormatter) private var format
    let provider: LimitProvider

    var body: some View {
        let window = provider.headlineWindow
        let showUsed = presentation.preferences.showLimitUsed
        let gauge = window.map { LimitPresentation.gaugeFill(window: $0, provider: provider, showUsed: showUsed) }
        AccessoryQuotaGauge(
            fraction: gauge?.remainingFraction,
            valueText: window.map { WidgetText.headline(LimitPresentation.headline(window: $0, provider: provider, showUsed: showUsed), format, compact: true) } ?? WidgetText.noValue,
            label: provider.displayName,
            tint: LimitStyle.tint(provider, palette: presentation.palette)
        )
    }
}

/// accessoryRectangular: provider and window, the value, the meter and the
/// live countdown — `AccessorySummaryView` takes only static text, and the
/// countdown has to stay live without timeline churn.
struct LimitsRectangularView: View {
    @Environment(\.tmPresentation) private var presentation
    @Environment(\.tmFormatter) private var format
    let provider: LimitProvider
    let now: Date

    var body: some View {
        let window = provider.headlineWindow
        let showUsed = presentation.preferences.showLimitUsed
        let fill = window.map { LimitPresentation.meterFill(window: $0, provider: provider, showUsed: showUsed) }
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: title(window))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(verbatim: value(window, showUsed: showUsed))
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            if let fraction = fill?.fraction {
                Gauge(value: min(1, max(0, fraction))) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
            }
            LimitDetailLine.text(provider: provider, window: window, now: now)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func title(_ window: LimitWindow?) -> String {
        guard let window else { return provider.displayName }
        return [provider.displayName, WidgetText.windowName(window, provider: provider)].joined(separator: " · ")
    }

    private func value(_ window: LimitWindow?, showUsed: Bool) -> String {
        guard let window else { return WidgetText.status(LimitPresentation.statusChip(provider).label) }
        return WidgetText.headline(LimitPresentation.headline(window: window, provider: provider, showUsed: showUsed), format, compact: false)
    }
}

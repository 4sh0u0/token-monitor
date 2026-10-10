import Foundation
import TokenMonitorKit
import WidgetKit

/// One timeline entry, shared by the Usage and Limits widgets. The
/// configuration and the user's presentation context travel with it so views
/// stay pure functions of the entry.
struct TokenEntry: TimelineEntry {
    let date: Date
    let state: WidgetDataState
    var period: UsagePeriodKind = .today
    var breakdown: BreakdownOption = .tools
    /// `LimitProvider.id` pinned in the Limits widget, nil for automatic.
    var pinnedLimitID: String? = nil
    /// Preferences, exchange rates and UI language at the time of the entry.
    var context: PresentationContext = .standard

    var snapshot: TokenSnapshot? { state.snapshot }
    var preferences: DisplayPreferences { context.preferences }

    /// The snapshot is old at this entry's date (twice the user's widget
    /// refresh interval), or the Hub reported every device — or the scoped
    /// device — as stale. A snapshot from an earlier day is always stale:
    /// its "today" is that day's.
    var isStale: Bool {
        guard let snapshot else { return false }
        return snapshot.isSourceStale
            || snapshot.isOlder(than: context.widgetTiming.staleAfter, at: date)
            || !snapshot.isCurrent(.today, at: date)
    }

    /// The configured period's figures, nil once that period has rolled over
    /// since the fetch (after midnight a cached "today" is yesterday's, after
    /// the 1st "this month" is last month's): views show "—" then, never the
    /// old totals under the new period's name.
    var periodSummary: PeriodSummary? {
        guard let snapshot, snapshot.isCurrent(period, at: date) else { return nil }
        return snapshot[period]
    }

    /// The scoped device's name while one device's numbers are shown; nil for
    /// all devices, and when the scoped device left the Hub (the numbers are
    /// then the aggregate's).
    var scopeName: String? {
        guard let snapshot, snapshot.isDeviceScoped else { return nil }
        return snapshot.scope?.deviceName
    }
}

/// The per-widget configuration, resolved from its intent.
struct EntryOptions {
    var period: UsagePeriodKind = .today
    var breakdown: BreakdownOption = .tools
    var pinnedLimitID: String? = nil

    func entry(at date: Date, state: WidgetDataState, context: PresentationContext) -> TokenEntry {
        TokenEntry(date: date, state: state, period: period, breakdown: breakdown, pinnedLimitID: pinnedLimitID, context: context)
    }
}

enum TokenTimeline {
    static func placeholder(_ options: EntryOptions) -> TokenEntry {
        let now = Date()
        return options.entry(at: now, state: .ready(SampleSnapshot.make(now: now)), context: PresentationContext.load())
    }

    /// The widget gallery shows the user's own cached numbers when there are
    /// any, else the sample: a gallery of "Not connected" cards would not show
    /// what the widget looks like. A placed widget never shows sample data.
    static func gallery(_ options: EntryOptions) -> TokenEntry {
        let now = Date()
        let context = PresentationContext.load()
        if let cached = SnapshotLoader.cachedSnapshot() {
            return options.entry(at: now, state: .ready(cached), context: context)
        }
        return options.entry(at: now, state: .ready(SampleSnapshot.make(now: now)), context: context)
    }

    static func current(_ options: EntryOptions) async -> TokenEntry {
        let now = Date()
        let context = PresentationContext.load()
        return options.entry(at: now, state: await SnapshotLoader.load(forceRefresh: false, context: context, now: now), context: context)
    }

    static func timeline(_ options: EntryOptions) async -> Timeline<TokenEntry> {
        let now = Date()
        let context = PresentationContext.load()
        let timing = context.widgetTiming
        let state = await SnapshotLoader.load(forceRefresh: false, context: context, now: now)
        let entries = entryDates(for: state, timing: timing, now: now).map { options.entry(at: $0, state: state, context: context) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(timing.reloadInterval)))
    }

    /// Now, the moments the data turns stale (its age, the next midnight), and
    /// the next few reset/expiry boundaries — the only times the same snapshot
    /// draws differently. Countdowns themselves are live `Text` date styles
    /// and need no entries.
    static func entryDates(for state: WidgetDataState, timing: WidgetRefreshTiming, now: Date, calendar: Calendar = .current) -> [Date] {
        guard let snapshot = state.snapshot else { return [now] }
        var dates: Set<Date> = [now]
        let staleAt = snapshot.fetchedAt.addingTimeInterval(timing.staleAfter)
        if staleAt > now { dates.insert(staleAt) }
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            dates.insert(midnight)
        }
        let horizon = now.addingTimeInterval(WidgetTiming.boundaryHorizon)
        let boundaries = snapshot.limits
            .flatMap { provider in provider.windows.compactMap { $0.resetsAt } }
            .filter { $0 > now && $0 <= horizon }
            .sorted()
            .prefix(WidgetTiming.maxBoundaryEntries)
        dates.formUnion(boundaries)
        return dates.sorted()
    }
}

struct UsageTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TokenEntry {
        TokenTimeline.placeholder(EntryOptions())
    }

    func snapshot(for configuration: UsageWidgetIntent, in context: Context) async -> TokenEntry {
        let options = Self.options(configuration)
        if context.isPreview { return TokenTimeline.gallery(options) }
        return await TokenTimeline.current(options)
    }

    func timeline(for configuration: UsageWidgetIntent, in context: Context) async -> Timeline<TokenEntry> {
        await TokenTimeline.timeline(Self.options(configuration))
    }

    private static func options(_ configuration: UsageWidgetIntent) -> EntryOptions {
        EntryOptions(period: configuration.period.kind, breakdown: configuration.breakdown)
    }
}

struct LimitsTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TokenEntry {
        TokenTimeline.placeholder(EntryOptions())
    }

    func snapshot(for configuration: LimitsWidgetIntent, in context: Context) async -> TokenEntry {
        let options = Self.options(configuration)
        if context.isPreview { return TokenTimeline.gallery(options) }
        return await TokenTimeline.current(options)
    }

    func timeline(for configuration: LimitsWidgetIntent, in context: Context) async -> Timeline<TokenEntry> {
        await TokenTimeline.timeline(Self.options(configuration))
    }

    private static func options(_ configuration: LimitsWidgetIntent) -> EntryOptions {
        EntryOptions(pinnedLimitID: configuration.provider?.id)
    }
}

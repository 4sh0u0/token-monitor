import Foundation
import TokenMonitorKit
import WidgetKit

/// One timeline entry, shared by the Usage and Limits widgets. The
/// configuration travels with it so views stay pure functions of the entry.
struct TokenEntry: TimelineEntry {
    let date: Date
    let state: WidgetDataState
    var period: UsagePeriodKind = .today
    var breakdown: BreakdownOption = .tools
    /// `LimitProvider.id` pinned in the Limits widget, nil for automatic.
    var pinnedLimitID: String? = nil

    var snapshot: TokenSnapshot? { state.snapshot }

    /// The snapshot is old at this entry's date, or the Hub itself reported
    /// every device as stale. A snapshot from an earlier day is always stale:
    /// its "today" is that day's.
    var isStale: Bool {
        guard let snapshot else { return false }
        return snapshot.isSourceStale
            || snapshot.isOlder(than: WidgetTiming.staleAfter, at: date)
            || !Calendar.current.isDate(snapshot.fetchedAt, inSameDayAs: date)
    }
}

/// The per-widget configuration, resolved from its intent.
struct EntryOptions {
    var period: UsagePeriodKind = .today
    var breakdown: BreakdownOption = .tools
    var pinnedLimitID: String? = nil

    func entry(at date: Date, state: WidgetDataState) -> TokenEntry {
        TokenEntry(date: date, state: state, period: period, breakdown: breakdown, pinnedLimitID: pinnedLimitID)
    }
}

enum TokenTimeline {
    static func placeholder(_ options: EntryOptions) -> TokenEntry {
        let now = Date()
        return options.entry(at: now, state: .ready(SampleSnapshot.make(now: now)))
    }

    /// The widget gallery shows the user's own cached numbers when there are
    /// any, else the sample: a gallery of "Not connected" cards would not show
    /// what the widget looks like. A placed widget never shows sample data.
    static func gallery(_ options: EntryOptions) -> TokenEntry {
        let now = Date()
        if HubConnectionStore.shared.isConfigured, let cached = SnapshotStore.shared.load() {
            return options.entry(at: now, state: .ready(cached))
        }
        return options.entry(at: now, state: .ready(SampleSnapshot.make(now: now)))
    }

    static func current(_ options: EntryOptions) async -> TokenEntry {
        let now = Date()
        return options.entry(at: now, state: await SnapshotLoader.load(forceRefresh: false, now: now))
    }

    static func timeline(_ options: EntryOptions) async -> Timeline<TokenEntry> {
        let now = Date()
        let state = await SnapshotLoader.load(forceRefresh: false, now: now)
        let entries = entryDates(for: state, now: now).map { options.entry(at: $0, state: state) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(WidgetTiming.reloadInterval)))
    }

    /// Now, the moments the data turns stale (its age, the next midnight), and
    /// the next few reset/expiry boundaries — the only times the same snapshot
    /// draws differently. Countdowns themselves are live `Text` date styles
    /// and need no entries.
    static func entryDates(for state: WidgetDataState, now: Date, calendar: Calendar = .current) -> [Date] {
        guard let snapshot = state.snapshot else { return [now] }
        var dates: Set<Date> = [now]
        let staleAt = snapshot.fetchedAt.addingTimeInterval(WidgetTiming.staleAfter)
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

import Foundation
import TokenMonitorKit
import WidgetKit

/// What the Activity widget can draw. It never decodes `/api/history`: the
/// app writes the compact `activity.json` (`ActivitySnapshot`) after loading
/// History and reloads this widget's timelines.
enum ActivityDataState: Sendable {
    /// No Hub URL saved.
    case notConfigured
    /// The app has not written activity for this Hub and device scope yet.
    case missing
    case ready(ActivitySnapshot)

    var snapshot: ActivitySnapshot? {
        if case .ready(let snapshot) = self { return snapshot }
        return nil
    }
}

struct ActivityEntry: TimelineEntry {
    let date: Date
    let state: ActivityDataState
    var metric: HeatmapMetric = .cost
    var context: PresentationContext = .standard
    /// The scoped device's name, nil for all devices.
    var scopeName: String? = nil

    var snapshot: ActivitySnapshot? { state.snapshot }

    /// The app last wrote the activity more than a day before this entry.
    var isStale: Bool {
        snapshot?.isOlder(than: WidgetTiming.activityStaleAfter, at: date) ?? false
    }
}

enum ActivityLoader {
    /// The stored activity of the saved Hub and the user's device scope.
    /// When the scoped device has left the Hub every surface falls back to
    /// all devices, so the aggregate activity is accepted then.
    static func state(scope: DeviceScope) -> (state: ActivityDataState, scopeName: String?) {
        guard let hubKey = HubConnectionStore.shared.snapshotKey else { return (.notConfigured, nil) }
        let store = ActivitySnapshotStore.shared
        let usage = SnapshotLoader.cachedSnapshot(hubKey: hubKey)
        if let activity = store.load(hubKey: hubKey, scope: scope) {
            return (.ready(activity), activity.scopeDeviceID.flatMap { scopeName($0, usage: usage) })
        }
        if let deviceID = scope.deviceID,
           let usageScope = usage?.scope, usageScope.deviceID == deviceID, usageScope.isMissing,
           let activity = store.load(hubKey: hubKey, scope: .all) {
            return (.ready(activity), nil)
        }
        return (.missing, nil)
    }

    /// The device's name from the usage snapshot when it is scoped to the
    /// same device, else its Hub id. Nil once the Hub no longer lists the
    /// device: the app then writes all devices' activity under the scope, as
    /// every surface falls back to all devices, so naming the device would
    /// mislabel it (`TokenEntry.scopeName` drops the name the same way).
    private static func scopeName(_ deviceID: String, usage: TokenSnapshot?) -> String? {
        guard let scope = usage?.scope, scope.deviceID == deviceID else { return deviceID }
        return scope.isMissing ? nil : scope.deviceName
    }

    static func entry(at date: Date, option: ActivityMetricOption, context: PresentationContext) -> ActivityEntry {
        let loaded = state(scope: context.preferences.deviceScope)
        return ActivityEntry(
            date: date,
            state: loaded.state,
            metric: option.metric(context.preferences),
            context: context,
            scopeName: loaded.scopeName
        )
    }
}

struct ActivityTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ActivityEntry {
        Self.sample(option: .automatic)
    }

    /// The gallery shows the user's own activity when there is any, else the
    /// sample.
    func snapshot(for configuration: ActivityWidgetIntent, in context: Context) async -> ActivityEntry {
        let entry = ActivityLoader.entry(at: Date(), option: configuration.metric, context: PresentationContext.load())
        if context.isPreview, entry.snapshot == nil { return Self.sample(option: configuration.metric) }
        return entry
    }

    /// The file is local, so reading it again costs nothing: entries now, at
    /// the moment the data turns stale and at the next midnight (a new day
    /// adds a cell), then a reload after the user's widget refresh interval.
    func timeline(for configuration: ActivityWidgetIntent, in context: Context) async -> Timeline<ActivityEntry> {
        let now = Date()
        let presentation = PresentationContext.load()
        let first = ActivityLoader.entry(at: now, option: configuration.metric, context: presentation)
        var dates: Set<Date> = [now]
        if let generatedAt = first.snapshot?.generatedAt {
            let staleAt = generatedAt.addingTimeInterval(WidgetTiming.activityStaleAfter)
            if staleAt > now { dates.insert(staleAt) }
        }
        let calendar = Calendar.current
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            dates.insert(midnight)
        }
        let entries = dates.sorted().map { date in
            ActivityEntry(date: date, state: first.state, metric: first.metric, context: presentation, scopeName: first.scopeName)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(presentation.widgetTiming.reloadInterval)))
    }

    private static func sample(option: ActivityMetricOption) -> ActivityEntry {
        let now = Date()
        let context = PresentationContext.load()
        return ActivityEntry(
            date: now,
            state: .ready(SampleSnapshot.activity(now: now)),
            metric: option.metric(context.preferences),
            context: context
        )
    }
}

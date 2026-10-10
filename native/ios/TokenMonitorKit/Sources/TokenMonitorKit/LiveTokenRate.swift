import Foundation

// Port of the live token rate in `src/electron/renderer/tokenRatePresentation.js`
// (lines 50-333): the rate is the ratio of the throughput counters one
// snapshot added over the previous one, per device, never an average of the
// cumulative period. Value types with mutating methods and an injectable
// clock; the app feeds them each `/api/stats` snapshot while SSE is live.

/// One period's throughput as the tracker reads it: `usageCounters(period)`
/// (nil when the period marked its throughput incomplete or a counter is
/// missing) and `modelThroughput` (nil when the wire has none).
public struct LiveTokenRateInput: Sendable, Equatable {
    public var counters: ThroughputCounters?
    public var modelThroughput: [String: ThroughputCounters]?

    public init(counters: ThroughputCounters?, modelThroughput: [String: ThroughputCounters]? = nil) {
        self.counters = counters
        self.modelThroughput = modelThroughput
    }

    /// A device's period (`devices[].periods.today`). An expired period has
    /// no counters.
    public init(_ usage: DeviceUsage) {
        self.init(counters: usage.throughput, modelThroughput: usage.modelThroughput)
    }

    /// An aggregate or derived period. The Kit cannot tell an absent
    /// `capabilities.throughput` from `false` here, so the counters count
    /// only when the period says its throughput is complete.
    public init(_ period: UsagePeriod) {
        self.init(
            counters: period.hasCompleteThroughput ? period.throughput : nil,
            modelThroughput: period.modelThroughput
        )
    }
}

/// One device the group tracker follows (`selectLiveTokenRatePeriods`
/// entries).
public struct LiveTokenRateEntry: Sendable, Equatable, Identifiable {
    /// `device:<deviceId>`.
    public var id: String
    /// `deviceLabel(device)`.
    public var name: String
    public var input: LiveTokenRateInput

    public init(id: String, name: String, input: LiveTokenRateInput) {
        self.id = id
        self.name = name
        self.input = input
    }

    /// The entry for a device's `today` period.
    public init(device: DeviceSummary) {
        self.init(id: "device:" + device.id, name: device.displayName, input: LiveTokenRateInput(device.today))
    }
}

/// The devices to follow and where they came from (`devices:all` or
/// `device:<id>`); a different source means a new baseline.
public struct LiveTokenRateSelection: Sendable, Equatable {
    public var source: String
    public var entries: [LiveTokenRateEntry]

    public init(source: String, entries: [LiveTokenRateEntry]) {
        self.source = source
        self.entries = entries
    }
}

/// One model's rate in a sample.
public struct LiveTokenRateModelRate: Sendable, Hashable, Identifiable {
    public var model: String
    /// Output tokens per second.
    public var speed: Double
    /// All timed tokens per minute (TPM).
    public var burn: Double

    public var id: String { model }

    public init(model: String, speed: Double, burn: Double) {
        self.model = model
        self.speed = speed
        self.burn = burn
    }

    public func value(_ mode: TokenRateMode) -> Double {
        mode == .burn ? burn : speed
    }
}

/// One period's tracker (`createLiveTokenRateTracker`): the scope is a
/// single source, e.g. the selected device.
public struct LiveTokenRateTracker: Sendable {
    /// The rate of the counters one snapshot added.
    public struct Sample: Sendable, Equatable {
        public var speed: Double
        public var burn: Double
        public var sampledAt: Date
        /// Increments with each new sample; a repeated snapshot keeps it.
        public var revision: Int
        /// Models whose counters moved within this snapshot's delta, in
        /// model-id order (the desktop uses wire order; consumers sort).
        public var models: [LiveTokenRateModelRate]
        /// The counters this snapshot added.
        public var delta: ThroughputCounters

        public init(speed: Double, burn: Double, sampledAt: Date, revision: Int, models: [LiveTokenRateModelRate], delta: ThroughputCounters) {
            self.speed = speed
            self.burn = burn
            self.sampledAt = sampledAt
            self.revision = revision
            self.models = models
            self.delta = delta
        }

        public func value(_ mode: TokenRateMode) -> Double {
            mode == .burn ? burn : speed
        }
    }

    public private(set) var sample: Sample?
    private var baseline: ThroughputCounters?
    private var modelBaseline: [String: ThroughputCounters]?
    private var revision = 0
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Starts over from `input` as the baseline (no sample).
    public mutating func reset(_ input: LiveTokenRateInput? = nil) {
        baseline = input?.counters
        modelBaseline = input?.modelThroughput
        sample = nil
    }

    /// Feeds the next snapshot. Equal counters (no added duration) keep the
    /// last sample; any counter going backwards (midnight, reconfiguration)
    /// clears it and starts a new baseline; missing counters clear both.
    @discardableResult
    public mutating func observe(_ input: LiveTokenRateInput?) -> Sample? {
        let current = input?.counters
        let models = input?.modelThroughput
        let previousModels = modelBaseline
        modelBaseline = models
        guard let current else {
            baseline = nil
            sample = nil
            return nil
        }
        guard let previous = baseline else {
            baseline = current
            return nil
        }
        let delta = ThroughputCounters(
            timedTokens: current.timedTokens - previous.timedTokens,
            timedOutputTokens: current.timedOutputTokens - previous.timedOutputTokens,
            timedDurationMs: current.timedDurationMs - previous.timedDurationMs
        )
        baseline = current
        if delta.timedTokens < 0 || delta.timedOutputTokens < 0 || delta.timedDurationMs < 0 {
            sample = nil
            return nil
        }
        guard delta.timedDurationMs > 0 else { return sample }

        revision += 1
        var modelRates: [LiveTokenRateModelRate] = []
        // Missing attribution is unknown, not an exact zero baseline.
        if let previousModels, let models {
            for model in models.keys.sorted() {
                guard let counters = models[model] else { continue }
                let before = previousModels[model] ?? .zero
                let change = ThroughputCounters(
                    timedTokens: counters.timedTokens - before.timedTokens,
                    timedOutputTokens: counters.timedOutputTokens - before.timedOutputTokens,
                    timedDurationMs: counters.timedDurationMs - before.timedDurationMs
                )
                // A renamed or retroactively attributed model may appear with
                // historical counters; it cannot have added more than this
                // snapshot's whole delta.
                if change.timedTokens < 0 || change.timedTokens > delta.timedTokens
                    || change.timedOutputTokens < 0 || change.timedOutputTokens > delta.timedOutputTokens
                    || change.timedDurationMs < 0 || change.timedDurationMs > delta.timedDurationMs
                    || !(change.timedDurationMs > 0) {
                    continue
                }
                modelRates.append(LiveTokenRateModelRate(
                    model: model,
                    speed: LiveTokenRate.tokensPerSecond(change),
                    burn: LiveTokenRate.burnPerMinute(change)
                ))
            }
        }
        let next = Sample(
            speed: LiveTokenRate.tokensPerSecond(delta),
            burn: LiveTokenRate.burnPerMinute(delta),
            sampledAt: now(),
            revision: revision,
            models: modelRates,
            delta: delta
        )
        sample = next
        return next
    }

    /// The current rate in `mode`, nil without a sample.
    public func value(_ mode: TokenRateMode) -> Double? {
        sample?.value(mode)
    }
}

/// The fleet reading (`createLiveTokenRateGroupTracker().getSample()`).
public struct LiveTokenRateSample: Sendable, Equatable {
    /// A device that contributed per-model rates.
    public struct Device: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var models: [LiveTokenRateModelRate]

        public init(id: String, name: String, models: [LiveTokenRateModelRate]) {
            self.id = id
            self.name = name
            self.models = models
        }
    }

    /// Sum of the live devices' output tok/s (capped at 1e12).
    public var speed: Double
    /// Sum of the live devices' TPM (capped at 1e12).
    public var burn: Double
    /// The newest contributing sample.
    public var sampledAt: Date
    /// Live devices with per-model rates, in the order they were first seen.
    public var devices: [Device]
    /// Live devices, with or without per-model rates.
    public var deviceCount: Int
    /// Bumps whenever any device produced a fresh sample (the desktop
    /// flashes the reading on a new revision).
    public var revision: Int
    /// When the reading changes next: the first live sample's end, or, when
    /// `idle`, when the dimmed reading clears.
    public var expiresAt: Date
    /// No device sample is live any more; the last reading stays visible,
    /// dimmed, until `expiresAt`.
    public var idle: Bool

    public init(
        speed: Double,
        burn: Double,
        sampledAt: Date,
        devices: [Device],
        deviceCount: Int,
        revision: Int,
        expiresAt: Date,
        idle: Bool
    ) {
        self.speed = speed
        self.burn = burn
        self.sampledAt = sampledAt
        self.devices = devices
        self.deviceCount = deviceCount
        self.revision = revision
        self.expiresAt = expiresAt
        self.idle = idle
    }

    public func value(_ mode: TokenRateMode) -> Double {
        mode == .burn ? burn : speed
    }
}

/// One line of the live-rate popover (`liveTokenRateTooltipEntries()`).
public enum LiveTokenRateTooltipEntry: Sendable, Hashable {
    /// A device heading, shown when several devices are live; `separated`
    /// draws a divider above it.
    case device(name: String, separated: Bool)
    /// A model and its rate in the requested mode (targets format it with
    /// `DisplayFormatter.liveTokenRate` plus "tok/s" or "TPM").
    case model(String, rate: Double)
}

/// Follows every selected device with its own tracker and sums the samples
/// that are still live (`createLiveTokenRateGroupTracker`): a device sample
/// is live for `activeWindow` (8 s); with none live the last reading stays,
/// idle, until `clearAfter` (3 min) after it was taken.
public struct LiveTokenRateGroupTracker: Sendable {
    public struct ObserveResult: Sendable, Equatable {
        /// Something visible changed (a fresh or cleared device sample, or a
        /// device with a sample left).
        public var changed: Bool
        public var sample: LiveTokenRateSample?
        /// `observe(_:context:)` started over because the source changed.
        public var didReset: Bool

        public init(changed: Bool, sample: LiveTokenRateSample?, didReset: Bool = false) {
            self.changed = changed
            self.sample = sample
            self.didReset = didReset
        }
    }

    private struct Slot: Sendable {
        var id: String
        var name: String
        var tracker: LiveTokenRateTracker
    }

    private struct DisplaySample: Sendable {
        var speed: Double
        var burn: Double
        var sampledAt: Date
        var devices: [LiveTokenRateSample.Device]
        var deviceCount: Int
        var revision: Int
    }

    public let activeWindow: TimeInterval
    public let clearAfter: TimeInterval
    /// The `context + source` the trackers were last reset for.
    public private(set) var sourceKey: String?
    private let now: @Sendable () -> Date
    private var slots: [Slot] = []
    private var revision = 0
    private var lastDisplaySample: DisplaySample?

    /// An `activeWindow` that is not positive, or a `clearAfter` not longer
    /// than it, falls back to the defaults (the desktop throws).
    public init(
        activeWindow: TimeInterval = LiveTokenRate.activeWindow,
        clearAfter: TimeInterval = LiveTokenRate.clearAfter,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let active = activeWindow.isFinite && activeWindow > 0 ? activeWindow : LiveTokenRate.activeWindow
        self.activeWindow = active
        self.clearAfter = clearAfter.isFinite && clearAfter > active
            ? clearAfter
            : max(LiveTokenRate.clearAfter, active * 2)
        self.now = now
    }

    /// Follows `entries` from scratch: each becomes a baseline.
    public mutating func reset(_ entries: [LiveTokenRateEntry] = []) {
        slots = []
        lastDisplaySample = nil
        for entry in Self.normalized(entries) {
            var tracker = LiveTokenRateTracker(now: now)
            tracker.reset(entry.input)
            slots.append(Slot(id: entry.id, name: entry.name, tracker: tracker))
        }
    }

    /// Feeds the next snapshot's entries. Devices that left are dropped,
    /// new ones start as baselines, the rest are observed.
    @discardableResult
    public mutating func observe(_ entries: [LiveTokenRateEntry]) -> ObserveResult {
        let next = Self.normalized(entries)
        let present = Set(next.map(\.id))
        var changed = false
        var fresh = false
        var invalidated = false

        slots.removeAll { slot in
            guard !present.contains(slot.id) else { return false }
            if slot.tracker.sample != nil { changed = true }
            return true
        }

        for entry in next {
            guard let index = slots.firstIndex(where: { $0.id == entry.id }) else {
                var tracker = LiveTokenRateTracker(now: now)
                tracker.reset(entry.input)
                slots.append(Slot(id: entry.id, name: entry.name, tracker: tracker))
                continue
            }
            slots[index].name = entry.name
            let previous = slots[index].tracker.sample?.revision
            let sample = slots[index].tracker.observe(entry.input)
            if sample?.revision == previous { continue }
            changed = true
            if sample != nil {
                fresh = true
            } else if previous != nil {
                invalidated = true
            }
        }

        if invalidated { lastDisplaySample = nil }
        if fresh { revision += 1 }
        return ObserveResult(changed: changed, sample: currentSample())
    }

    /// Feeds a selection the way the desktop's `observeLiveTokenRate` does:
    /// when `context` (e.g. the Hub key) or the selection's source differs
    /// from the last call, the trackers start over from these entries and
    /// the result has `didReset` (render, no sample yet).
    @discardableResult
    public mutating func observe(_ selection: LiveTokenRateSelection, context: String = "") -> ObserveResult {
        let key = context + "|" + selection.source
        if key != sourceKey {
            sourceKey = key
            reset(selection.entries)
            return ObserveResult(changed: true, sample: currentSample(), didReset: true)
        }
        return observe(selection.entries)
    }

    /// Forgets every tracker and the source (`resetLiveTokenRateTracking`).
    public mutating func clear() {
        sourceKey = nil
        reset()
    }

    /// The reading now (`getSample()`). Like the desktop, reading it while
    /// samples are live refreshes the retained reading the idle state shows.
    public mutating func currentSample() -> LiveTokenRateSample? {
        let timestamp = now()
        let live = slots.compactMap { slot -> (slot: Slot, sample: LiveTokenRateTracker.Sample)? in
            guard let sample = slot.tracker.sample,
                  timestamp < sample.sampledAt.addingTimeInterval(activeWindow) else { return nil }
            return (slot, sample)
        }
        if !live.isEmpty {
            let display = DisplaySample(
                speed: LiveTokenRate.cappedRate(live.reduce(0) { $0 + $1.sample.speed }),
                burn: LiveTokenRate.cappedRate(live.reduce(0) { $0 + $1.sample.burn }),
                sampledAt: live.map(\.sample.sampledAt).max() ?? timestamp,
                devices: live.filter { !$0.sample.models.isEmpty }.map {
                    LiveTokenRateSample.Device(id: $0.slot.id, name: $0.slot.name, models: $0.sample.models)
                },
                deviceCount: live.count,
                revision: revision
            )
            lastDisplaySample = display
            let expiresAt = live.map { $0.sample.sampledAt.addingTimeInterval(activeWindow) }.min() ?? timestamp
            return Self.sample(display, expiresAt: expiresAt, idle: false)
        }
        guard let retained = lastDisplaySample else { return nil }
        let expiresAt = retained.sampledAt.addingTimeInterval(clearAfter)
        guard timestamp < expiresAt else { return nil }
        return Self.sample(retained, expiresAt: expiresAt, idle: true)
    }

    /// When the reading changes next without a new snapshot
    /// (`nextExpiryAt()`); schedule a re-render then.
    public mutating func nextExpiry() -> Date? {
        currentSample()?.expiresAt
    }

    private static func sample(_ display: DisplaySample, expiresAt: Date, idle: Bool) -> LiveTokenRateSample {
        LiveTokenRateSample(
            speed: display.speed,
            burn: display.burn,
            sampledAt: display.sampledAt,
            devices: display.devices,
            deviceCount: display.deviceCount,
            revision: display.revision,
            expiresAt: expiresAt,
            idle: idle
        )
    }

    /// `normalizedEntries()`: trimmed ids, blanks and repeats dropped, a
    /// blank name falls back to the id.
    private static func normalized(_ entries: [LiveTokenRateEntry]) -> [LiveTokenRateEntry] {
        var seen = Set<String>()
        var result: [LiveTokenRateEntry] = []
        for entry in entries {
            let id = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            var copy = entry
            copy.id = id
            if copy.name.isEmpty { copy.name = id }
            result.append(copy)
        }
        return result
    }
}

public enum LiveTokenRate {
    /// How long one device sample counts towards the reading
    /// (`LIVE_TOKEN_RATE_ACTIVE_MS`).
    public static let activeWindow: TimeInterval = 8
    /// How long the last reading stays visible, dimmed, after it was taken
    /// (`LIVE_TOKEN_RATE_CLEAR_MS`).
    public static let clearAfter: TimeInterval = 180

    /// `cappedTokenRate()`: 0 for non-positive or NaN, at most 1e12.
    public static func cappedRate(_ value: Double) -> Double {
        if value.isNaN || value <= 0 { return 0 }
        return min(ThroughputCounters.maximumDisplayRate, value)
    }

    /// `tokenRatePerSecond()`: output tokens per second, 0 when nothing was
    /// timed.
    public static func tokensPerSecond(_ counters: ThroughputCounters?) -> Double {
        guard let counters else { return 0 }
        let duration = positive(counters.timedDurationMs)
        let output = positive(counters.timedOutputTokens)
        guard duration > 0, output > 0 else { return 0 }
        return cappedRate(output * 1000 / duration)
    }

    /// `tokenBurnPerMinute()`: all timed tokens per minute (TPM), 0 when
    /// nothing was timed.
    public static func burnPerMinute(_ counters: ThroughputCounters?) -> Double {
        guard let counters else { return 0 }
        let duration = positive(counters.timedDurationMs)
        let timed = positive(counters.timedTokens)
        guard duration > 0, timed > 0 else { return 0 }
        return cappedRate(timed * 60000 / duration)
    }

    /// The scope that applies (D-LIVESCOPE): `.device` only while a device
    /// is scoped; otherwise every device.
    public static func effectiveScope(rateScope: LiveRateScope, deviceScope: DeviceScope) -> LiveRateScope {
        rateScope == .device && deviceScope.deviceID != nil ? .device : .all
    }

    /// `selectLiveTokenRatePeriods(stats, deviceId, 'client', scope)`:
    /// `.all` follows every non-stale device's `today`; `.device` follows
    /// the scoped device (stale or not), and nothing when it is gone.
    public static func selection(stats: HubStats, rateScope: LiveRateScope, deviceScope: DeviceScope) -> LiveTokenRateSelection {
        selection(devices: stats.devices, rateScope: rateScope, deviceScope: deviceScope)
    }

    public static func selection(devices: [DeviceSummary], rateScope: LiveRateScope, deviceScope: DeviceScope) -> LiveTokenRateSelection {
        guard effectiveScope(rateScope: rateScope, deviceScope: deviceScope) == .device,
              let rawID = deviceScope.deviceID else {
            return LiveTokenRateSelection(
                source: "devices:all",
                entries: devices.filter { !$0.isStale }.map(LiveTokenRateEntry.init(device:))
            )
        }
        let deviceID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = devices.first { $0.id == deviceID }.map { [LiveTokenRateEntry(device: $0)] } ?? []
        return LiveTokenRateSelection(source: "device:" + deviceID, entries: entries)
    }

    /// The plan's `entries(stats:rateScope:deviceScope:)`.
    public static func entries(stats: HubStats, rateScope: LiveRateScope, deviceScope: DeviceScope) -> [LiveTokenRateEntry] {
        selection(stats: stats, rateScope: rateScope, deviceScope: deviceScope).entries
    }

    /// `liveTokenRateTooltipEntries(sample, mode)`: per device (with a
    /// heading when more than one device is live), its models by rate
    /// descending, then name.
    public static func tooltipEntries(sample: LiveTokenRateSample?, mode: TokenRateMode) -> [LiveTokenRateTooltipEntry] {
        guard let sample else { return [] }
        let grouped = (sample.deviceCount > 0 ? sample.deviceCount : sample.devices.count) > 1
        var entries: [LiveTokenRateTooltipEntry] = []
        for device in sample.devices where !device.models.isEmpty {
            if grouped { entries.append(.device(name: device.name, separated: !entries.isEmpty)) }
            let models = device.models.sorted { left, right in
                let leftValue = left.value(mode)
                let rightValue = right.value(mode)
                if leftValue != rightValue { return leftValue > rightValue }
                return DevicePresentation.localeAscending(left.model, right.model)
            }
            entries.append(contentsOf: models.map { .model($0.model, rate: $0.value(mode)) })
        }
        return entries
    }

    private static func positive(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : 0
    }
}

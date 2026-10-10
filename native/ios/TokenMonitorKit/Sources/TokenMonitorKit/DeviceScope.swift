import Foundation

// Device scope (`DisplayPreferences.deviceScope`): every usage surface shows
// either the Hub aggregate or one device's own periods. The desktop has no
// global selector; iOS follows the Hub's own aggregate rules for a device
// (`aggregateDevices` in `src/shared/usage.js`): a `today`/`month` window
// that has ended counts as zero (`isPeriodExpired`, applied at decode by
// `DeviceSummary.applyPeriodExpiry`), and `allTime` never expires. Limits and
// the device list never follow the scope (`limits/core.js` aggregates them
// per provider account, not per device).

/// Stats as a surface presents them: the aggregate, or one device's periods.
public struct ScopedStats: Sendable, Equatable {
    /// What views show. For a device scope the three periods are the
    /// device's own (sessions and projects as decoded), the History preview
    /// is cleared (it is the aggregate's), and the omission counts and
    /// `projectsIncomplete` are the device's. Limits, devices, revisions and
    /// the Hub clock are the aggregate's, unchanged.
    public var stats: HubStats
    /// The scope that was asked for (the stored preference).
    public var scope: DeviceScope
    /// The scoped device; nil for all devices and when it is missing.
    public var device: DeviceSummary?
    /// The scope names a device the Hub no longer lists: `stats` is the
    /// aggregate and the surface should say so.
    public var isScopeMissing: Bool

    public init(stats: HubStats, scope: DeviceScope = .all, device: DeviceSummary? = nil, isScopeMissing: Bool = false) {
        self.stats = stats
        self.scope = scope
        self.device = device
        self.isScopeMissing = isScopeMissing
    }

    /// One device's numbers are shown.
    public var isDeviceScoped: Bool { device != nil }

    /// The scope actually applied: `.all` when the device is missing.
    public var effectiveScope: DeviceScope {
        device.map { .device($0.id) } ?? .all
    }

    /// The numbers describe the past: the scoped device is stale, or (all
    /// devices) every device is.
    public var isSourceStale: Bool {
        device?.isStale ?? stats.isSourceStale
    }

    /// When the Hub last heard from the scoped device, or from any device.
    public var sourceUpdatedAt: Date? {
        guard let device else { return stats.newestDeviceActivity }
        return device.lastSeen
    }

    public subscript(period: UsagePeriodKind) -> UsagePeriod {
        stats[period]
    }
}

extension HubStats {
    /// These stats as `scope` presents them.
    ///
    /// - `.all`, or a device the Hub does not list: the stats unchanged
    ///   (`isScopeMissing` tells the second case apart).
    /// - A listed device: its full periods (`DeviceSummary.details`), so
    ///   totals, cost, components, tools, models, throughput, sessions and
    ///   projects are the device's. An expired `today`/`month` is
    ///   `UsagePeriod.empty`, the Hub's rule. A device decoded without
    ///   details (see `HubDecodingOptions.deviceDetail`) falls back to its
    ///   totals and tool rows, with every token unclassified.
    public func scoped(to scope: DeviceScope) -> ScopedStats {
        guard let deviceID = scope.deviceID else { return ScopedStats(stats: self) }
        guard let device = device(id: deviceID) else {
            return ScopedStats(stats: self, scope: scope, isScopeMissing: true)
        }
        var scoped = self
        for kind in UsagePeriodKind.allCases {
            scoped[kind] = device.scopedPeriod(kind)
        }
        scoped.history = []
        scoped.historyMonths = []
        scoped.historyPreviewSummary = nil
        scoped.sessionDetailsOmitted = device.sessionDetailsOmitted
        scoped.periodProjectsOmitted = device.periodProjectsOmitted
        scoped.projectsIncomplete = device.hasIncompleteProjects
        return ScopedStats(stats: scoped, scope: scope, device: device)
    }

    /// Aliases first, then the scope: what the app's views, the snapshot and
    /// the watch present. A nil or inactive document skips the projection.
    public func presenting(scope: DeviceScope, aliases document: ModelAliasDocument?) -> ScopedStats {
        let projected = ModelAliasResolver.forStats(self, document: document).map(projectingModelAliases) ?? self
        return projected.scoped(to: scope)
    }
}

extension DeviceSummary {
    /// One period of this device as the Hub would aggregate it alone.
    func scopedPeriod(_ kind: UsagePeriodKind) -> UsagePeriod {
        let usage = usage(kind)
        if usage.isExpired { return .empty }
        if let detail = detail(kind) { return detail }
        return UsagePeriod(deviceUsage: usage)
    }

    /// The Hub's `projectsIncomplete` rule for this device alone
    /// (`aggregateDevices`): its all-time rollup was omitted or is partial,
    /// or project collection is off while it has usage.
    var hasIncompleteProjects: Bool {
        allTimeProjectsOmitted || allTimeProjectsIncomplete || (projectsEnabled == false && allTime.tokens > 0)
    }
}

extension UsagePeriod {
    /// A period built from a device's totals when its full period was not
    /// decoded: tokens, cost, unpriced tokens, tool rows and throughput are
    /// known; components are not, so every token is unclassified.
    init(deviceUsage usage: DeviceUsage) {
        let counters = usage.throughput ?? .zero
        var breakdown: [String: UsageBreakdownEntry] = [:]
        for share in usage.clients {
            breakdown[share.id] = UsageBreakdownEntry(tokens: share.tokens, costUsd: share.costUsd ?? 0)
        }
        self.init(
            totalTokens: usage.tokens,
            costUsd: usage.costUsd,
            unclassifiedTokens: usage.tokens,
            unpricedTokens: usage.unpricedTokens,
            timedTokens: nonNegative(clampedInt(counters.timedTokens)),
            timedOutputTokens: nonNegative(clampedInt(counters.timedOutputTokens)),
            timedDurationMs: nonNegative(counters.timedDurationMs),
            hasExactTokenComponents: false,
            hasCompleteThroughput: usage.hasThroughput && usage.throughput != nil,
            clients: usage.clients,
            clientBreakdown: breakdown,
            modelThroughput: usage.modelThroughput,
            explicitUnclassified: .period
        )
    }
}

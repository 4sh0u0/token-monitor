import Foundation

/// Builds the `TokenSnapshot` every compact surface reads, from raw stats and
/// the user's preferences and aliases. The iPhone app, its widgets, the watch
/// app and its complications all build through this, so a snapshot written by
/// one is exactly what the others would build.
///
/// - Models are folded through the alias document (`ModelAliasResolver.forStats`).
/// - Periods follow `preferences.deviceScope` (`HubStats.scoped(to:)`); a
///   missing device falls back to all devices and says so in `scope`. The
///   trend is empty for a scoped device.
/// - Tools are ordered, pinned and hidden by `ClientDisplayOrder` before the
///   top `TokenSnapshot.maxShares` are kept; hidden tools count as other.
/// - Limits never follow the scope. They are ordered by
///   `limitProviderOrder` (catalog order when unset; accounts of one provider
///   keep the Hub's order) and compacted: emails masked, path-like names
///   dropped, extras stripped, primary windows the user has not hidden, at
///   most `TokenSnapshot.maxWindowsPerProvider`.
public struct SnapshotBuilder: Sendable, Equatable {
    /// Always held normalized, so equal settings build equal snapshots and
    /// keys.
    public var preferences: DisplayPreferences {
        didSet { preferences = preferences.normalized() }
    }
    /// The connected Hub's model-alias document (`ModelAliasCache`); nil when
    /// none is known.
    public var aliases: ModelAliasDocument?

    public init(preferences: DisplayPreferences = .defaults, aliases: ModelAliasDocument? = nil) {
        self.preferences = preferences.normalized()
        self.aliases = aliases
    }

    /// A builder from the shared stores: the stored preferences and the
    /// cached alias document of the Hub `hubKey` names (none without a key).
    public static func load(
        preferences: PreferencesStore = .shared,
        aliasCache: ModelAliasCache = .shared,
        hubKey: String?
    ) -> SnapshotBuilder {
        SnapshotBuilder(preferences: preferences.load(), aliases: hubKey.flatMap(aliasCache.load(hubKey:)))
    }

    /// The revision of the alias document applied; nil without one, and for
    /// a group never initialized (which folds nothing, like no document).
    public var aliasRevision: Int? {
        guard let aliases, aliases.isInitialized else { return nil }
        return aliases.revision
    }

    /// A stable hash of everything besides the stats that shapes a snapshot:
    /// the device scope, the alias revision, the tool order, hidden and
    /// pinned tools, the Limits provider order and hidden Limits items. Equal
    /// settings give equal keys on every device and launch.
    public var projectionKey: String {
        func list(_ ids: [String]) -> String {
            "[" + ids.map(JSCompat.jsonQuoted).joined(separator: ",") + "]"
        }
        let hiddenItems = LimitUsageItems.normalizeHiddenItems(preferences.limitProviderHiddenItems)
        let items = hiddenItems.keys.sorted().map { provider in
            JSCompat.jsonQuoted(provider) + ":" + list((hiddenItems[provider] ?? []).sorted())
        }
        let parts = [
            "\"v\":1",
            "\"scope\":" + JSCompat.jsonQuoted(preferences.deviceScope.storageValue),
            "\"aliases\":" + (aliasRevision.map(String.init) ?? "null"),
            "\"toolOrder\":" + list(preferences.clientDisplayOrder),
            "\"hiddenTools\":" + list(preferences.hiddenClients),
            "\"pinnedTools\":" + list(preferences.pinnedClients),
            "\"limitOrder\":" + list(preferences.limitProviderOrder),
            "\"hiddenItems\":{" + items.joined(separator: ",") + "}"
        ]
        return StableHash.hex("{" + parts.joined(separator: ",") + "}", length: 16)
    }

    /// The snapshot of `stats` for these preferences and aliases.
    /// - Parameters:
    ///   - fetchedAt: when the stats were fetched (the cache's age).
    ///   - hub: the connection the stats came from, recorded as `hubKey`.
    ///   - calendar: the calendar whose "today" ends the trend.
    public func snapshot(
        from stats: HubStats,
        fetchedAt: Date = Date(),
        hub: HubConnection? = nil,
        calendar: Calendar = .current
    ) -> TokenSnapshot {
        let presented = stats.presenting(scope: preferences.deviceScope, aliases: aliases)
        let shown = presented.stats
        func summary(_ kind: UsagePeriodKind) -> PeriodSummary {
            let period = shown[kind]
            let tools = ClientDisplayOrder.apply(period.clients, id: \.id, preferences: preferences, known: VendorCatalog.trackedClientIDs)
            return PeriodSummary(kind: kind, period: period, tools: tools)
        }
        let scope = preferences.deviceScope.deviceID.map { id in
            SnapshotScope(
                deviceID: id,
                deviceName: presented.device?.displayName,
                isStale: presented.device?.isStale ?? false,
                isMissing: presented.isScopeMissing
            )
        }
        return TokenSnapshot(
            fetchedAt: fetchedAt,
            hubKey: hub?.snapshotKey,
            sourceUpdatedAt: presented.sourceUpdatedAt,
            isSourceStale: presented.isSourceStale,
            today: summary(.today),
            month: summary(.month),
            allTime: summary(.allTime),
            limits: limits(stats.limits),
            devices: DeviceCounts(online: stats.onlineDeviceCount, total: stats.devices.count),
            trend: presented.isDeviceScoped
                ? []
                : shown.dailyTrend(days: TokenSnapshot.maxTrendDays, endingAt: fetchedAt, calendar: calendar),
            scope: scope,
            aliasRevision: aliasRevision,
            projectionKey: projectionKey
        )
    }

    /// The Limits rows a snapshot carries, in the user's provider order,
    /// each compacted with the user's hidden items.
    public func limits(_ providers: [LimitProvider]) -> [LimitProvider] {
        OrderedIDs.ordered(
            providers,
            id: \.provider,
            order: preferences.limitProviderOrder,
            known: VendorCatalog.limitProviders.map(\.id)
        )
        .map { $0.compacted(maxWindows: TokenSnapshot.maxWindowsPerProvider, hiddenItems: preferences.limitProviderHiddenItems) }
    }

    /// Whether `snapshot` came from the Hub `hubKey` names and was built with
    /// this builder's projection: the test a widget or the watch applies
    /// before treating a cached snapshot as fresh.
    public func isCurrent(_ snapshot: TokenSnapshot, hubKey: String?) -> Bool {
        snapshot.belongs(toHubKey: hubKey) && snapshot.matches(projectionKey: projectionKey)
    }
}

import Foundation

/// Keeps the App Group copy of the Hub's shared model aliases current, the
/// way the desktop's `syncContentRuntime.notifyStats` does: the group is
/// fetched only when nothing is held for this Hub or when stats advertise a
/// revision other than the held one (`stats.syncSettingsRevisions`); an
/// absent marker is no news.
///
/// The iPhone app runs it after each stats update, the watch app after each
/// poll, and widgets may run it before building a snapshot; all of them then
/// build through `SnapshotBuilder` with the returned document.
public enum SharedSettingsRefresher {
    /// The model-alias document to apply for the Hub `client` talks to.
    ///
    /// - Returns: the cached document when it is current; otherwise the
    ///   fetched one, after saving it. A Hub that predates shared settings
    ///   (404/405) gets `ModelAliasDocument.uninitialized` saved and returned,
    ///   so it is not asked again until it advertises a revision. Any other
    ///   failure keeps the cache and returns what it held (nil when nothing).
    /// - Parameters:
    ///   - hubKey: the cache key; `client.connection.snapshotKey` when nil.
    ///   - force: fetch even when the cached document is current.
    public static func modelAliases(
        stats: HubStats,
        client: HubClient,
        cache: ModelAliasCache = .shared,
        hubKey: String? = nil,
        force: Bool = false
    ) async -> ModelAliasDocument? {
        let key = hubKey ?? client.connection.snapshotKey
        let cached = cache.load(hubKey: key)
        let advertised = SharedSettingsKind.modelAliases.advertisedRevision(in: stats.syncSettingsRevisions)
        guard force || ModelAliasDocument.needsFetch(cached: cached, advertisedRevision: advertised) else {
            return cached
        }
        do {
            let document = try await client.modelAliasDocument()
            try? cache.save(document, hubKey: key)
            return document
        } catch let error as HubClientError where error.isUnsupportedEndpoint {
            try? cache.save(.uninitialized, hubKey: key)
            return .uninitialized
        } catch {
            return cached
        }
    }
}

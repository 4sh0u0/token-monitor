import Foundation

// Read-only models and clients for the Hub's shared sync surfaces
// (`docs/API.md`, `src/shared/syncContent.js`):
//
// - `GET /api/sync/content`: capability discovery.
// - `GET /api/sync/settings/modelAliases` and `/customPricing`: the two shared
//   groups, each `{ok, version: 1, revision, updatedAt, value}`. `value: null`
//   (revision 0, `updatedAt: ""`) means the group was never initialized; an
//   intentionally empty map or array is a written value with a positive
//   revision.
//
// Authenticated stats carry `syncSettingsRevisions: {modelAliases, customPricing}`.
// A revision that differs from the held document's is the refetch signal; an
// absent marker (an older Hub) is "no news". The phone never writes a group.

/// A shared settings group on the Hub.
public enum SharedSettingsKind: String, Sendable, CaseIterable, Identifiable {
    case modelAliases
    case customPricing

    public var id: String { rawValue }

    public var endpoint: HubEndpoint {
        switch self {
        case .modelAliases: return .syncSettingsModelAliases
        case .customPricing: return .syncSettingsCustomPricing
        }
    }

    /// This group's revision in `stats.syncSettingsRevisions`; nil when the
    /// marker is absent (an older Hub) or not a non-negative integer.
    public func advertisedRevision(in revisions: [String: Int]?) -> Int? {
        guard let revision = revisions?[rawValue], revision >= 0 else { return nil }
        return revision
    }
}

// MARK: - Model aliases document

/// `GET /api/sync/settings/modelAliases`: explicit aliases plus the automatic
/// grouping mode, shared by every device that opted in on the desktop.
public struct ModelAliasDocument: Sendable, Equatable {
    /// The group's revision; 0 for a group never written.
    public var revision: Int
    /// When the group was last written; nil when never written.
    public var updatedAt: Date?
    /// `value.modelAliases` as sent: `alias → canonical`. Entries whose
    /// target is not a string are dropped; the resolver normalizes the rest
    /// (`aliasPairs`).
    public var aliases: [String: String]
    /// `value.modelAliasGrouping`, normalized; `.off` when never written.
    public var grouping: ModelAliasGrouping
    /// False for `value: null`: no device has published the group yet.
    public var isInitialized: Bool

    /// An uninitialized document has no aliases and grouping `.off`,
    /// whatever is passed.
    public init(
        revision: Int,
        updatedAt: Date? = nil,
        aliases: [String: String] = [:],
        grouping: ModelAliasGrouping = .off,
        isInitialized: Bool = true
    ) {
        self.revision = max(0, revision)
        self.updatedAt = updatedAt
        self.aliases = isInitialized ? aliases : [:]
        self.grouping = isInitialized ? grouping : .off
        self.isInitialized = isInitialized
    }

    /// What a Hub returns for a group never written:
    /// `{"version":1,"revision":0,"updatedAt":"","value":null}`.
    public static let uninitialized = ModelAliasDocument(revision: 0, isInitialized: false)

    /// The response body of `GET /api/sync/settings/modelAliases` (or a
    /// cached copy).
    /// - Throws: `DecodingError` when the body is not a version-1 document
    ///   with a non-negative integer revision and a `value` (the desktop's
    ///   `unsupported`).
    public static func decode(from data: Data) throws -> ModelAliasDocument {
        try JSONDecoder().decode(ModelAliasDocument.self, from: data)
    }

    /// The explicit aliases the resolver applies (`normalizeModelAliases`),
    /// in the Hub's order. Its count is the "N aliases" summary.
    public var aliasPairs: [ModelAliasPair] {
        ModelAliasResolver.normalizeAliases(aliases)
    }

    /// The resolver for a payload that shows `observedModels`.
    public func resolver(observedModels: [String] = []) -> ModelAliasResolver {
        ModelAliasResolver(document: self, observedModels: observedModels)
    }

    /// Whether this document is still the Hub's current one, given the
    /// revision stats advertise (`SharedSettingsKind.advertisedRevision`). An
    /// absent marker is no news, so the document stays current.
    public func isCurrent(advertisedRevision: Int?) -> Bool {
        guard let advertisedRevision else { return true }
        return advertisedRevision == revision
    }

    /// Whether to `GET` the group: nothing held yet, or the advertised
    /// revision moved (the desktop's `notifyStats`). After a 404/405 from a
    /// Hub that predates shared settings, hold `.uninitialized` so the Hub is
    /// not asked again until it advertises a revision.
    public static func needsFetch(cached: ModelAliasDocument?, advertisedRevision: Int?) -> Bool {
        guard let cached else { return true }
        return !cached.isCurrent(advertisedRevision: advertisedRevision)
    }
}

extension ModelAliasDocument: Codable {
    private enum ValueKeys: String, CodingKey {
        case modelAliases, modelAliasGrouping
    }

    /// Decodes the wire document (the cache stores the same shape).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SharedDocumentKeys.self)
        let header = try SharedDocumentHeader(container)
        guard header.hasValue else {
            self.init(revision: header.revision, updatedAt: header.updatedAt, isInitialized: false)
            return
        }
        let value = try container.nestedContainer(keyedBy: ValueKeys.self, forKey: .value)
        var aliases: [String: String] = [:]
        if let map = try? value.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .modelAliases) {
            for key in map.allKeys {
                if let canonical = try? map.decode(String.self, forKey: key) { aliases[key.stringValue] = canonical }
            }
        }
        self.init(
            revision: header.revision,
            updatedAt: header.updatedAt,
            aliases: aliases,
            grouping: ModelAliasGrouping(normalizing: try? value.decode(String.self, forKey: .modelAliasGrouping))
        )
    }

    /// Encodes the wire document: `{version, revision, updatedAt, value}`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SharedDocumentKeys.self)
        try SharedDocumentHeader.encode(revision: revision, updatedAt: updatedAt, into: &container)
        guard isInitialized else {
            try container.encodeNil(forKey: .value)
            return
        }
        var value = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .value)
        try value.encode(aliases, forKey: .modelAliases)
        try value.encode(grouping.rawValue, forKey: .modelAliasGrouping)
    }
}

// MARK: - Custom pricing

/// One `customPricing` row: per-million-token USD rates a device applies at
/// collection time. Shown read-only; nil is "unknown", 0 is "free".
public struct CustomPricingEntry: Sendable, Hashable, Identifiable {
    public var modelId: String
    public var inputPerM: Double?
    public var outputPerM: Double?
    public var cacheReadPerM: Double?
    public var cacheWritePerM: Double?
    public var cacheWrite1hPerM: Double?

    public var id: String { modelId }

    public init(
        modelId: String,
        inputPerM: Double? = nil,
        outputPerM: Double? = nil,
        cacheReadPerM: Double? = nil,
        cacheWritePerM: Double? = nil,
        cacheWrite1hPerM: Double? = nil
    ) {
        self.modelId = modelId
        self.inputPerM = inputPerM
        self.outputPerM = outputPerM
        self.cacheReadPerM = cacheReadPerM
        self.cacheWritePerM = cacheWritePerM
        self.cacheWrite1hPerM = cacheWrite1hPerM
    }
}

extension CustomPricingEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case modelId, inputPerM, outputPerM, cacheReadPerM, cacheWritePerM, cacheWrite1hPerM
    }

    /// Lenient: a row without a model id fails (and is dropped from the
    /// list); a rate that is not a finite non-negative number is unknown.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let modelId = container.lenientString(.modelId) else {
            throw DecodingError.dataCorruptedError(forKey: .modelId, in: container, debugDescription: "missing modelId")
        }
        func rate(_ key: CodingKeys) -> Double? {
            guard !container.isNullOrMissing(key), let value = try? container.decode(Double.self, forKey: key),
                  value.isFinite, value >= 0 else { return nil }
            return value
        }
        self.init(
            modelId: modelId,
            inputPerM: rate(.inputPerM),
            outputPerM: rate(.outputPerM),
            cacheReadPerM: rate(.cacheReadPerM),
            cacheWritePerM: rate(.cacheWritePerM),
            cacheWrite1hPerM: rate(.cacheWrite1hPerM)
        )
    }

    /// The Hub's canonical shape: unknown rates are omitted.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelId, forKey: .modelId)
        try container.encodeIfPresent(inputPerM, forKey: .inputPerM)
        try container.encodeIfPresent(outputPerM, forKey: .outputPerM)
        try container.encodeIfPresent(cacheReadPerM, forKey: .cacheReadPerM)
        try container.encodeIfPresent(cacheWritePerM, forKey: .cacheWritePerM)
        try container.encodeIfPresent(cacheWrite1hPerM, forKey: .cacheWrite1hPerM)
    }
}

/// `GET /api/sync/settings/customPricing`.
public struct CustomPricingDocument: Sendable, Equatable {
    public var revision: Int
    public var updatedAt: Date?
    /// In the Hub's order (sorted by model id); nil when never initialized.
    public var entries: [CustomPricingEntry]?

    public init(revision: Int, updatedAt: Date? = nil, entries: [CustomPricingEntry]?) {
        self.revision = max(0, revision)
        self.updatedAt = updatedAt
        self.entries = entries
    }

    public var isInitialized: Bool { entries != nil }

    /// - Throws: `DecodingError` when the body is not a version-1 document
    ///   (see `ModelAliasDocument.decode(from:)`).
    public static func decode(from data: Data) throws -> CustomPricingDocument {
        try JSONDecoder().decode(CustomPricingDocument.self, from: data)
    }
}

extension CustomPricingDocument: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SharedDocumentKeys.self)
        let header = try SharedDocumentHeader(container)
        guard header.hasValue else {
            self.init(revision: header.revision, updatedAt: header.updatedAt, entries: nil)
            return
        }
        let rows = try container.decode([Lossy<CustomPricingEntry>].self, forKey: .value)
        self.init(revision: header.revision, updatedAt: header.updatedAt, entries: rows.compactMap(\.value))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SharedDocumentKeys.self)
        try SharedDocumentHeader.encode(revision: revision, updatedAt: updatedAt, into: &container)
        if let entries {
            try container.encode(entries, forKey: .value)
        } else {
            try container.encodeNil(forKey: .value)
        }
    }
}

// MARK: - Shared document envelope

private enum SharedDocumentKeys: String, CodingKey {
    case version, revision, updatedAt, value
}

/// The checks the desktop's `syncContentRuntime` applies before using a
/// shared document: `version === 1`, a safe non-negative integer revision,
/// and a `value` key (null allowed).
private struct SharedDocumentHeader {
    static let version = 1
    /// `Number.MAX_SAFE_INTEGER`; `Int64` so the Kit still compiles where
    /// `Int` is 32-bit (the watch's arm64_32).
    static let maxSafeInteger: Int64 = 9_007_199_254_740_991

    let revision: Int
    let updatedAt: Date?
    let hasValue: Bool

    init(_ container: KeyedDecodingContainer<SharedDocumentKeys>) throws {
        guard (try? container.decode(Int.self, forKey: .version)) == Self.version else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "unsupported shared settings version")
        }
        guard let revision = try? container.decode(Int.self, forKey: .revision), revision >= 0, Int64(revision) <= Self.maxSafeInteger else {
            throw DecodingError.dataCorruptedError(forKey: .revision, in: container, debugDescription: "invalid shared settings revision")
        }
        guard container.contains(.value) else {
            throw DecodingError.keyNotFound(SharedDocumentKeys.value, .init(codingPath: container.codingPath, debugDescription: "missing value"))
        }
        self.revision = revision
        updatedAt = container.lenientDate(.updatedAt)
        hasValue = !((try? container.decodeNil(forKey: .value)) ?? true)
    }

    static func encode(revision: Int, updatedAt: Date?, into container: inout KeyedEncodingContainer<SharedDocumentKeys>) throws {
        try container.encode(version, forKey: .version)
        try container.encode(revision, forKey: .revision)
        try container.encode(updatedAt.map(ISODate.string(from:)) ?? "", forKey: .updatedAt)
    }
}

// MARK: - Capabilities

/// `GET /api/sync/content`:
/// `{"ok":true,"version":1,"sessionTitles":{"enabled":false},"sharedSettings":true}`.
public struct SyncContentCapabilities: Sendable, Equatable {
    public var version: Int?
    /// The Hub accepts session titles from devices that opted in (server
    /// permission; each device still decides).
    public var sessionTitlesEnabled: Bool
    /// The Hub stores the shared `modelAliases` and `customPricing` groups.
    public var sharedSettings: Bool
    /// The desktop's capability check: version 1, `sharedSettings === true`
    /// and a boolean `sessionTitles.enabled`. False means "unsupported".
    public var isSupported: Bool

    public init(version: Int? = 1, sessionTitlesEnabled: Bool, sharedSettings: Bool, isSupported: Bool? = nil) {
        self.version = version
        self.sessionTitlesEnabled = sessionTitlesEnabled
        self.sharedSettings = sharedSettings
        self.isSupported = isSupported ?? (version == 1 && sharedSettings)
    }

    public static func decode(from data: Data) throws -> SyncContentCapabilities {
        try JSONDecoder().decode(SyncContentCapabilities.self, from: data)
    }
}

extension SyncContentCapabilities: Decodable {
    private enum CodingKeys: String, CodingKey {
        case version, sessionTitles, sharedSettings
    }

    private enum TitleKeys: String, CodingKey {
        case enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try? container.decode(Int.self, forKey: .version)
        let titles = try? container.nestedContainer(keyedBy: TitleKeys.self, forKey: .sessionTitles)
        let titlesEnabled = try? titles?.decode(Bool.self, forKey: .enabled)
        let sharedSettings = (try? container.decode(Bool.self, forKey: .sharedSettings)) == true
        self.init(
            version: version,
            sessionTitlesEnabled: titlesEnabled == true,
            sharedSettings: sharedSettings,
            isSupported: version == 1 && sharedSettings && titlesEnabled != nil
        )
    }
}

// MARK: - Client

extension HubClient {
    /// `GET /api/sync/content`.
    /// - Throws: `HubClientError` (`isUnsupportedEndpoint` for an older Hub).
    public func syncContent() async throws -> SyncContentCapabilities {
        try Self.decodeSyncBody(SyncContentCapabilities.self, from: try await data(for: .syncContent))
    }

    /// `GET /api/sync/settings/modelAliases`.
    /// - Throws: `HubClientError` (`isUnsupportedEndpoint` for an older Hub;
    ///   `.decoding` for a document the desktop would call unsupported).
    public func modelAliasDocument() async throws -> ModelAliasDocument {
        try Self.decodeSyncBody(ModelAliasDocument.self, from: try await data(for: .syncSettingsModelAliases))
    }

    /// `GET /api/sync/settings/customPricing`.
    public func customPricingDocument() async throws -> CustomPricingDocument {
        try Self.decodeSyncBody(CustomPricingDocument.self, from: try await data(for: .syncSettingsCustomPricing))
    }

    /// `GET /api/sync/settings/customPricing`; `entries` is nil when the
    /// group was never initialized.
    public func customPricing() async throws -> (revision: Int, entries: [CustomPricingEntry]?) {
        let document = try await customPricingDocument()
        return (document.revision, document.entries)
    }

    private static func decodeSyncBody<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw HubClientError.decoding(String(describing: error))
        }
    }
}

extension HubClientError {
    /// 404 or 405: a Hub that predates the endpoint (the desktop's
    /// `unsupported`), as opposed to a failure worth retrying.
    public var isUnsupportedEndpoint: Bool {
        guard case .http(let status) = self else { return false }
        return status == 404 || status == 405
    }
}

// MARK: - Cache

/// The model-alias document of the connected Hub, cached in the App Group so
/// widgets and complications fold model names without fetching the group
/// themselves. One file, `{hubKey, document}`; a different Hub's document is
/// never returned.
public struct ModelAliasCache: Sendable {
    public static let fileName = "model-aliases.json"

    public struct Entry: Sendable, Equatable, Codable {
        /// `HubConnection.snapshotKey` of the Hub the document came from.
        public var hubKey: String
        public var document: ModelAliasDocument

        public init(hubKey: String, document: ModelAliasDocument) {
            self.hubKey = hubKey
            self.document = document
        }
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Beside the snapshot in the App Group container; nil without the
    /// entitlement.
    public static var appGroup: ModelAliasCache? {
        SnapshotStore.appGroup.map { ModelAliasCache(directory: $0.directory) }
    }

    /// `appGroup`, else the app's own caches directory.
    public static var shared: ModelAliasCache {
        appGroup ?? ModelAliasCache(directory: SnapshotStore.shared.directory)
    }

    public var fileURL: URL { directory.appendingPathComponent(Self.fileName, isDirectory: false) }

    /// The stored entry, whichever Hub it belongs to; nil when there is none
    /// or it is unreadable.
    public func loadEntry() -> Entry? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    /// The cached document of the Hub `hubKey` names, nil for any other Hub.
    public func load(hubKey: String) -> ModelAliasDocument? {
        guard let entry = loadEntry(), entry.hubKey == hubKey else { return nil }
        return entry.document
    }

    /// Whether the Hub `hubKey` names must be asked for the group again
    /// (`ModelAliasDocument.needsFetch`).
    public func needsRefresh(hubKey: String, advertisedRevision: Int?) -> Bool {
        ModelAliasDocument.needsFetch(cached: load(hubKey: hubKey), advertisedRevision: advertisedRevision)
    }

    /// Writes atomically, readable by widgets while locked after first unlock.
    public func save(_ document: ModelAliasDocument, hubKey: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS) || os(watchOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try encoder.encode(Entry(hubKey: hubKey, document: document)).write(to: fileURL, options: options)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

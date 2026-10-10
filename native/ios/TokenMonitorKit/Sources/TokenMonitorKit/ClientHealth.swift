import Foundation

/// A tracked client's overall health (`clientHealth.clients.*.overall`). The
/// Hub recomputes it from the entry's own inputs; values this build does not
/// know decode as `.unknown`.
public enum ClientHealthOverall: String, Sendable, Codable, CaseIterable {
    /// Usage was observed.
    case healthy
    /// Sources exist but nothing has been counted yet.
    case waiting
    /// Something done on the user's behalf (a self-sync) is failing.
    case attention
    /// No source root on disk.
    case unavailable
    case unknown

    init(wire: String?) {
        self = wire.flatMap { ClientHealthOverall(rawValue: $0.lowercased()) } ?? .unknown
    }
}

/// One probed source root, by stable id (never a path).
public struct ClientHealthCheck: Sendable, Hashable, Identifiable {
    public var id: String
    public var exists: Bool

    public init(id: String, exists: Bool) {
        self.id = id
        self.exists = exists
    }
}

/// One client's health entry (`clientHealth.clients.<id>`). Closed enums on
/// the wire stay strings here; `ClientHealthPresentation` maps them.
public struct ClientHealthEntry: Sendable, Equatable {
    public var overall: ClientHealthOverall
    /// `source.state`: `detected`, `missing` or `unknown`.
    public var sourceState: String
    public var detectedCount: Int
    public var checkedCount: Int
    public var checks: [ClientHealthCheck]
    /// `collection.state`: `direct`, `idle`, `pending`, `ok`, `failed` or
    /// `unknown`.
    public var collectionState: String
    public var syncFailureStage: String?
    public var syncDetailCode: String?
    public var syncExitCode: Int?
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    /// `data.liveTokens`: all-time tokens counted for the client.
    public var liveTokens: Int
    /// `data.lastActivityDay` (`yyyy-MM-dd`, device-local).
    public var lastActivityDay: String?
    /// Diagnostic codes in wire order (`source-missing`, `sync-timeout`, …).
    public var diagnostics: [String]

    public init(
        overall: ClientHealthOverall = .unknown,
        sourceState: String = "unknown",
        detectedCount: Int = 0,
        checkedCount: Int = 0,
        checks: [ClientHealthCheck] = [],
        collectionState: String = "unknown",
        syncFailureStage: String? = nil,
        syncDetailCode: String? = nil,
        syncExitCode: Int? = nil,
        lastAttemptAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        liveTokens: Int = 0,
        lastActivityDay: String? = nil,
        diagnostics: [String] = []
    ) {
        self.overall = overall
        self.sourceState = sourceState
        self.detectedCount = detectedCount
        self.checkedCount = checkedCount
        self.checks = checks
        self.collectionState = collectionState
        self.syncFailureStage = syncFailureStage
        self.syncDetailCode = syncDetailCode
        self.syncExitCode = syncExitCode
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.liveTokens = liveTokens
        self.lastActivityDay = lastActivityDay
        self.diagnostics = diagnostics
    }
}

/// A device's `clientHealth` (per device only; never aggregated).
public struct ClientHealthReport: Sendable, Equatable {
    public var version: Int?
    public var observedAt: Date?
    /// Keyed by client id as the Hub normalized it (lower case).
    public var clients: [String: ClientHealthEntry]

    public init(version: Int? = nil, observedAt: Date? = nil, clients: [String: ClientHealthEntry] = [:]) {
        self.version = version
        self.observedAt = observedAt
        self.clients = clients
    }

    /// The entry for a client id, matched trimmed and case-insensitively
    /// (`healthFor()` in `clientHealthPresentation.js`).
    public func entry(for clientID: String) -> ClientHealthEntry? {
        clients[clientID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }
}

extension ClientHealthReport: Decodable {
    private enum CodingKeys: String, CodingKey {
        case version, observedAt, clients
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var clients: [String: ClientHealthEntry] = [:]
        if let nested = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .clients) {
            for key in nested.allKeys {
                let id = key.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, let entry = try? nested.decode(ClientHealthEntry.self, forKey: key) else { continue }
                clients[id] = entry
            }
        }
        self.init(
            version: container.lenientInt(.version),
            observedAt: container.lenientDate(.observedAt),
            clients: clients
        )
    }
}

extension ClientHealthEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case overall, source, collection, data, diagnostics
    }

    private enum SourceKeys: String, CodingKey {
        case state, detectedCount, checkedCount, checks
    }

    private enum CollectionKeys: String, CodingKey {
        case state, syncFailureStage, syncDetailCode, syncExitCode, lastAttemptAt, lastSuccessAt
    }

    private enum DataKeys: String, CodingKey {
        case liveTokens, lastActivityDay
    }

    private struct Check: Decodable {
        let value: ClientHealthCheck?

        private enum Keys: String, CodingKey {
            case id, exists
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            value = container.lenientString(.id).map {
                ClientHealthCheck(id: $0, exists: container.strictBool(.exists) == true)
            }
        }
    }

    /// `{ "code": "…" }` on a current Hub; a bare string is accepted too.
    private struct Diagnostic: Decodable {
        let code: String?

        private enum Keys: String, CodingKey {
            case code
        }

        init(from decoder: Decoder) throws {
            if let container = try? decoder.container(keyedBy: Keys.self) {
                code = container.lenientString(.code)
            } else {
                let raw = try decoder.singleValueContainer().decode(String.self)
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                code = trimmed.isEmpty ? nil : trimmed
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let source = try? container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
        let collection = try? container.nestedContainer(keyedBy: CollectionKeys.self, forKey: .collection)
        let data = try? container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        self.init(
            overall: ClientHealthOverall(wire: container.lenientString(.overall)),
            sourceState: source?.lenientString(.state) ?? "unknown",
            detectedCount: nonNegative(source?.lenientInt(.detectedCount) ?? 0),
            checkedCount: nonNegative(source?.lenientInt(.checkedCount) ?? 0),
            checks: (source?.lenientArray(.checks, of: Check.self) ?? []).compactMap(\.value),
            collectionState: collection?.lenientString(.state) ?? "unknown",
            syncFailureStage: collection?.lenientString(.syncFailureStage),
            syncDetailCode: collection?.lenientString(.syncDetailCode),
            syncExitCode: collection?.lenientInt(.syncExitCode),
            lastAttemptAt: collection?.lenientDate(.lastAttemptAt),
            lastSuccessAt: collection?.lenientDate(.lastSuccessAt),
            liveTokens: nonNegative(data?.lenientInt(.liveTokens) ?? 0),
            lastActivityDay: data?.lenientString(.lastActivityDay),
            diagnostics: container.lenientArray(.diagnostics, of: Diagnostic.self).compactMap(\.code)
        )
    }
}

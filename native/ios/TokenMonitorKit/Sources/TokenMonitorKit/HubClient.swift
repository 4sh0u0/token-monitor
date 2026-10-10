import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HubClientError: Error, Equatable, Sendable {
    /// No Hub URL has been saved.
    case notConfigured
    /// The Hub URL is not a usable http(s) URL.
    case invalidURL
    /// 401/403: the secret is missing or wrong.
    case unauthorized
    /// Any other non-2xx status (e.g. 503 from a Worker without a secret).
    case http(status: Int)
    /// The request never produced a response (offline, DNS, TLS, timeout);
    /// carries the system's (already localized) description.
    case transport(String)
    /// The body was not the expected JSON (e.g. a captive portal's HTML).
    case decoding(String)

    /// Worth retrying later without the user changing settings.
    public var isTransient: Bool {
        switch self {
        case .transport: return true
        case .http(let status): return status >= 500 || status == 408 || status == 429
        default: return false
        }
    }
}

/// `GET /api/health` (unauthenticated).
public struct HubHealth: Sendable, Equatable {
    public var ok: Bool
    /// `node-hub` or `cloudflare-worker`.
    public var runtime: String?
    public var deviceCount: Int?
    public var secretRequired: Bool?
    /// The Hub's clock.
    public var now: Date?
    public var coreRevision: Int?
    public var runtimeRevision: Int?

    public init(
        ok: Bool,
        runtime: String? = nil,
        deviceCount: Int? = nil,
        secretRequired: Bool? = nil,
        now: Date? = nil,
        coreRevision: Int? = nil,
        runtimeRevision: Int? = nil
    ) {
        self.ok = ok
        self.runtime = runtime
        self.deviceCount = deviceCount
        self.secretRequired = secretRequired
        self.now = now
        self.coreRevision = coreRevision
        self.runtimeRevision = runtimeRevision
    }
}

extension HubHealth: Decodable {
    private enum CodingKeys: String, CodingKey {
        case ok, runtime, deviceCount, secretRequired, now, hubBuild
    }

    private enum BuildKeys: String, CodingKey {
        case coreRevision, runtimeRevision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let build = try? container.nestedContainer(keyedBy: BuildKeys.self, forKey: .hubBuild)
        self.init(
            ok: container.lenientBool(.ok) ?? false,
            runtime: container.lenientString(.runtime),
            deviceCount: container.lenientInt(.deviceCount),
            secretRequired: container.lenientBool(.secretRequired),
            now: container.lenientDate(.now),
            coreRevision: build?.lenientInt(.coreRevision),
            runtimeRevision: build?.lenientInt(.runtimeRevision)
        )
    }
}

/// Read-only client for a Token Monitor Hub (Node hub, the widget's embedded
/// Host hub, or the Cloudflare Worker).
///
/// Authenticates with `Authorization: Bearer` (never `?secret=`). Each call
/// is independent; create one per refresh or keep one around — it holds no
/// mutable state.
public struct HubClient: @unchecked Sendable {
    // @unchecked: URLSession is thread-safe but not annotated Sendable on
    // every SDK this builds against.

    /// Foreground app requests.
    public static let defaultTimeout: TimeInterval = 20
    /// Widget timeline providers and complications: they have seconds, not
    /// minutes, before the system kills them.
    public static let widgetTimeout: TimeInterval = 10
    /// Idle timeout for the SSE stream; the Hub sends `: hb` every 30 s.
    public static let streamIdleTimeout: TimeInterval = 75

    public let connection: HubConnection
    public let session: URLSession
    public var timeout: TimeInterval

    public init(connection: HubConnection, session: URLSession = .shared, timeout: TimeInterval = HubClient.defaultTimeout) {
        self.connection = connection
        self.session = session
        self.timeout = timeout
    }

    /// The request for an endpoint, with the Kit's headers. Exposed for tests
    /// and for callers that need their own transport (e.g. background
    /// `URLSession` download tasks).
    public func request(for endpoint: HubEndpoint) -> URLRequest {
        var request = URLRequest(url: connection.url(for: endpoint))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        switch endpoint {
        case .statsStream:
            request.timeoutInterval = max(timeout, Self.streamIdleTimeout)
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            // Deliberately no `x-token-monitor-stream: 2`: with it the Hub sends
            // `freshness` deltas that must be merged into a held snapshot;
            // without it every update is a complete `stats` event.
        case .health, .stats, .history, .devices, .subscriptions, .syncContent,
             .syncSettingsModelAliases, .syncSettingsCustomPricing:
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }
        // Health is public; the secret only goes where it is required.
        if endpoint != .health, connection.hasSecret {
            request.setValue("Bearer \(connection.secret)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    public func health() async throws -> HubHealth {
        let data = try await fetch(.health)
        do {
            return try JSONDecoder().decode(HubHealth.self, from: data)
        } catch {
            throw HubClientError.decoding(String(describing: error))
        }
    }

    /// - Throws: `HubClientError`, or `CancellationError` when the calling
    ///   task was cancelled.
    public func stats() async throws -> HubStats {
        try HubStats.decode(from: try await fetch(.stats))
    }

    /// The raw stats body, for callers that cache the response themselves.
    public func statsData() async throws -> Data {
        try await fetch(.stats)
    }

    /// The raw body of a JSON endpoint: a GET with `Accept: application/json`
    /// and, except for `.health`, `Authorization: Bearer`. Not for
    /// `.statsStream`, which never finishes; use `statsStream()`.
    /// - Throws: `HubClientError` (`.http(status: 404)` from a Hub that lacks
    ///   the endpoint), or `CancellationError` when the calling task was
    ///   cancelled.
    public func data(for endpoint: HubEndpoint) async throws -> Data {
        try await fetch(endpoint)
    }

    /// "Test connection": the public health check, then an authenticated
    /// stats read so a wrong secret surfaces as `.unauthorized`.
    public func verify() async throws -> HubHealth {
        let result = try await self.health()
        _ = try await stats()
        return result
    }

    private func fetch(_ endpoint: HubEndpoint) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request(for: endpoint))
        } catch {
            // A cancelled refresh is the caller's decision, not a Hub failure.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw HubClientError.transport(error.localizedDescription)
        }
        try Self.validate(response)
        return data
    }

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw HubClientError.transport("not an HTTP response")
        }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw HubClientError.unauthorized
        default: throw HubClientError.http(status: http.statusCode)
        }
    }

    #if canImport(Darwin)
    /// Live updates while the app is in the foreground.
    ///
    /// Yields a complete `HubStats` for the initial `snapshot` event and for
    /// every `stats` event; heartbeats and other events are skipped. The
    /// sequence finishes when the Hub closes the connection and throws a
    /// `HubClientError` when it fails; reconnect with backoff (each new
    /// connection starts with a full snapshot, so nothing is lost). Cancelling
    /// the consuming task closes the connection.
    public func statsStream() -> AsyncThrowingStream<HubStats, Error> {
        let request = self.request(for: .statsStream)
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.validate(response)
                    var parser = ServerSentEventParser()
                    let decoder = HubStreamDecoder()
                    // Bytes, not `bytes.lines`: AsyncLineSequence drops the
                    // blank lines that delimit SSE events.
                    for try await byte in bytes {
                        guard let event = parser.consume(byte) else { continue }
                        if let stats = decoder.stats(from: event) { continuation.yield(stats) }
                    }
                    continuation.finish()
                } catch let error as HubClientError {
                    continuation.finish(throwing: error)
                } catch {
                    if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: HubClientError.transport(error.localizedDescription))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    #endif
}

extension HubClient {
    /// A client for the saved connection.
    /// - Throws: `HubClientError.notConfigured` when no Hub URL is saved, or
    ///   the `SecretStorageError` when the Keychain cannot be read yet (before
    ///   first unlock) — fall back to the cached snapshot rather than calling
    ///   the Hub without its secret.
    public init(store: HubConnectionStore, session: URLSession = .shared, timeout: TimeInterval = HubClient.defaultTimeout) throws {
        guard let connection = try store.loadConnection() else { throw HubClientError.notConfigured }
        self.init(connection: connection, session: session, timeout: timeout)
    }
}

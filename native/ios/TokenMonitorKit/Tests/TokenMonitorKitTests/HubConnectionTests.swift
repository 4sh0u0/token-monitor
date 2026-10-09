import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TokenMonitorKit

final class HubConnectionTests: XCTestCase {
    func testNormalizesUserInput() {
        let cases: [(String, String?)] = [
            ("hub.example.com", "https://hub.example.com"),
            ("  https://hub.example.com/  ", "https://hub.example.com"),
            ("HTTPS://Hub.Example.COM", "https://hub.example.com"),
            ("http://192.168.1.10:17321/api/stats", "http://192.168.1.10:17321"),
            ("http://192.168.1.10:17321/api", "http://192.168.1.10:17321"),
            ("https://example.com/tokens/api/stats/stream?secret=x#frag", "https://example.com/tokens"),
            ("https://example.com/tokens/", "https://example.com/tokens"),
            ("https://user:pw@hub.example.com", "https://hub.example.com"),
            ("localhost:17321", "https://localhost:17321"),
            ("http://[::1]:17321/", "http://[::1]:17321"),
            ("token-monitor.example.workers.dev", "https://token-monitor.example.workers.dev"),
            ("ftp://hub.example.com", nil),
            ("", nil),
            ("   ", nil),
            ("https://", nil),
            ("hub example.com", nil),
            ("mailto:me@example.com", nil),
            ("javascript:alert(1)", nil)
        ]
        for (input, expected) in cases {
            XCTAssertEqual(HubConnection.normalizedBaseURL(from: input)?.absoluteString, expected, input)
        }
        XCTAssertEqual(HubConnection.normalizedBaseURL(from: "nas:17321", defaultScheme: "http")?.absoluteString, "http://nas:17321")
    }

    func testUserInputInitializer() throws {
        let connection = try HubConnection(userInput: "hub.example.com/api/stats", secret: "  s3cret \n")
        XCTAssertEqual(connection.baseURL.absoluteString, "https://hub.example.com")
        XCTAssertEqual(connection.secret, "s3cret")
        XCTAssertTrue(connection.hasSecret)
        XCTAssertThrowsError(try HubConnection(userInput: "mailto:me@example.com", secret: "")) { error in
            XCTAssertEqual(error as? HubClientError, .invalidURL)
        }
    }

    func testEndpointURLsKeepAProxyPrefix() throws {
        let plain = try HubConnection(userInput: "http://192.168.1.10:17321", secret: "")
        XCTAssertEqual(plain.url(for: .stats).absoluteString, "http://192.168.1.10:17321/api/stats")
        XCTAssertEqual(plain.url(for: .statsStream).absoluteString, "http://192.168.1.10:17321/api/stats/stream")
        let prefixed = try HubConnection(userInput: "https://example.com/tokens", secret: "")
        XCTAssertEqual(prefixed.url(for: .health).absoluteString, "https://example.com/tokens/api/health")
    }

    func testInsecureRemoteDetection() {
        let cases: [(String, Bool)] = [
            ("http://hub.example.com", true),
            ("http://8.8.8.8:17321", true),
            ("http://172.32.0.1", true),
            ("http://100.128.0.1", true),
            ("http://[2001:db8::1]", true),
            ("https://hub.example.com", false),
            ("https://8.8.8.8", false),
            ("http://localhost:17321", false),
            ("http://app.localhost", false),
            ("http://127.0.0.1:17321", false),
            ("http://10.0.0.2", false),
            ("http://172.16.0.1", false),
            ("http://172.31.255.255", false),
            ("http://192.168.1.5:17321", false),
            ("http://100.64.0.1", false),
            ("http://100.101.102.103", false),
            ("http://169.254.10.1", false),
            ("http://macbook.local:17321", false),
            ("http://nas.home.arpa", false),
            ("http://nas", false),
            ("http://my-mac.tail1234.ts.net:17321", false),
            ("http://[::1]:17321", false),
            ("http://[fe80::1]", false),
            ("http://[fd00::1]", false),
            ("http://[::ffff:192.168.0.1]", false)
        ]
        for (input, expected) in cases {
            guard let url = URL(string: input) else { return XCTFail(input) }
            XCTAssertEqual(HubConnection.isInsecureRemote(url), expected, input)
        }
    }

    func testDisplayHostNeverShowsSecretsOrPaths() throws {
        let connection = try HubConnection(userInput: "https://user:pw@example.com:8443/tokens/api/stats", secret: "s")
        XCTAssertEqual(connection.displayHost, "example.com:8443")
        XCTAssertEqual(try HubConnection(userInput: "http://[::1]:17321", secret: "").displayHost, "[::1]:17321")
    }

    func testCodableRoundTrip() throws {
        let connection = try HubConnection(userInput: "https://hub.example.com", secret: "abc")
        let decoded = try JSONDecoder().decode(HubConnection.self, from: JSONEncoder().encode(connection))
        XCTAssertEqual(decoded, connection)
    }
}

final class HubConnectionStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TokenMonitorKitTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSaveLoadClear() throws {
        let secrets = InMemorySecretStorage()
        let store = HubConnectionStore(defaults: defaults, secrets: secrets)
        XCTAssertNil(store.load())
        XCTAssertFalse(store.isConfigured)

        let connection = try HubConnection(userInput: "https://hub.example.com", secret: "abc")
        try store.save(connection)
        XCTAssertEqual(store.load(), connection)
        XCTAssertEqual(store.baseURL?.absoluteString, "https://hub.example.com")
        XCTAssertEqual(defaults.string(forKey: HubConnectionStore.baseURLKey), "https://hub.example.com")
        XCTAssertEqual(try secrets.readSecret(), "abc")
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { ($0 as? String) == "abc" }, "the secret never lands in defaults")

        try store.save(HubConnection(baseURL: connection.baseURL, secret: ""))
        XCTAssertNil(try secrets.readSecret(), "an empty secret deletes the stored one")
        XCTAssertEqual(store.load()?.secret, "")

        try store.clear()
        XCTAssertNil(store.load())
        XCTAssertNil(try secrets.readSecret())
    }

    func testUnreadableSecretIsReportedNotSilentlyEmpty() throws {
        defaults.set("https://hub.example.com", forKey: HubConnectionStore.baseURLKey)
        let store = HubConnectionStore(defaults: defaults, secrets: LockedSecretStorage())
        XCTAssertThrowsError(try store.loadConnection())
        XCTAssertNil(store.load())
        XCTAssertThrowsError(try HubClient(store: store)) { error in
            XCTAssertEqual(error as? SecretStorageError, .keychain(status: -25308), "a locked Keychain is not \"not configured\"")
        }
        let empty = HubConnectionStore(defaults: UserDefaults(suiteName: "\(suiteName).empty")!, secrets: InMemorySecretStorage())
        XCTAssertThrowsError(try HubClient(store: empty)) { error in
            XCTAssertEqual(error as? HubClientError, .notConfigured)
        }
    }

    private struct LockedSecretStorage: SecretStorage {
        func readSecret() throws -> String? { throw SecretStorageError.keychain(status: -25308) }
        func writeSecret(_ secret: String) throws { throw SecretStorageError.keychain(status: -25308) }
        func deleteSecret() throws { throw SecretStorageError.keychain(status: -25308) }
    }
}

final class HubClientTests: XCTestCase {
    private func client(secret: String = "s3cret") throws -> HubClient {
        HubClient(connection: try HubConnection(userInput: "http://127.0.0.1:17321", secret: secret), timeout: HubClient.widgetTimeout)
    }

    func testStatsRequestHeaders() throws {
        let request = try client().request(for: .stats)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:17321/api/stats")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertNil(request.url?.query, "the secret is never put in the URL")
    }

    func testHealthIsSentWithoutTheSecret() throws {
        let request = try client().request(for: .health)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testStreamRequestUsesFullStatsEvents() throws {
        let request = try client().request(for: .statsStream)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:17321/api/stats/stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-token-monitor-stream"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret")
        XCTAssertGreaterThanOrEqual(request.timeoutInterval, 60, "outlives the 30 s heartbeat")
    }

    func testNoAuthorizationWithoutASecret() throws {
        XCTAssertNil(try client(secret: "").request(for: .stats).value(forHTTPHeaderField: "Authorization"))
    }

    func testStatusMapping() throws {
        func validate(_ status: Int) -> HubClientError? {
            let url = URL(string: "http://127.0.0.1/api/stats")!
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            do {
                try HubClient.validate(response)
                return nil
            } catch {
                return error as? HubClientError
            }
        }
        XCTAssertNil(validate(200))
        XCTAssertEqual(validate(401), .unauthorized)
        XCTAssertEqual(validate(403), .unauthorized)
        XCTAssertEqual(validate(503), .http(status: 503))
        XCTAssertEqual(validate(404), .http(status: 404))
        XCTAssertTrue(HubClientError.http(status: 503).isTransient)
        XCTAssertTrue(HubClientError.transport("offline").isTransient)
        XCTAssertFalse(HubClientError.unauthorized.isTransient)
    }
}

/// Serves canned responses so the client's whole request → decode path runs
/// without a network.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status: Int
        var body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [String: Stub] = [:]
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func stub(path: String, status: Int, body: Data) {
        lock.lock()
        defer { lock.unlock() }
        stubs[path] = Stub(status: status, body: body)
    }

    static var recordedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        stubs = [:]
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let stub = request.url.flatMap { Self.stubs[$0.path] }
        Self.lock.unlock()
        guard let url = request.url, let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class HubClientNetworkTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    private func client() throws -> HubClient {
        HubClient(connection: try HubConnection(userInput: "http://hub.test:17321", secret: "s3cret"), session: session)
    }

    func testStatsAndHealthEndToEnd() async throws {
        StubURLProtocol.stub(path: "/api/stats", status: 200, body: try Fixture.data("stats.json"))
        StubURLProtocol.stub(path: "/api/health", status: 200, body: try Fixture.data("health.json"))
        let client = try client()
        let health = try await client.verify()
        XCTAssertEqual(health.deviceCount, 3)
        let stats = try await client.stats()
        XCTAssertEqual(stats.today.totalTokens, 72_250_000)
        let authorization = StubURLProtocol.recordedRequests.map { $0.value(forHTTPHeaderField: "Authorization") }
        XCTAssertEqual(authorization, [nil, "Bearer s3cret", "Bearer s3cret"])
    }

    func testErrorsAreMapped() async throws {
        StubURLProtocol.stub(path: "/api/stats", status: 401, body: Data(#"{"error":"unauthorized"}"#.utf8))
        StubURLProtocol.stub(path: "/api/health", status: 200, body: Data("<html>portal</html>".utf8))
        let client = try client()
        await assertThrows(.unauthorized) { _ = try await client.stats() }
        await assertThrows(nil) { _ = try await client.health() }

        StubURLProtocol.stub(path: "/api/stats", status: 503, body: Data(#"{"error":"secret_required"}"#.utf8))
        await assertThrows(.http(status: 503)) { _ = try await client.stats() }

        StubURLProtocol.reset()
        let offline = HubClient(connection: try HubConnection(userInput: "http://nowhere.test", secret: ""), session: session)
        do {
            _ = try await offline.health()
            XCTFail("expected a transport error")
        } catch HubClientError.transport {
        } catch {
            XCTFail("\(error)")
        }
    }

    /// `expected == nil` means "a decoding error".
    private func assertThrows(_ expected: HubClientError?, _ body: () async throws -> Void, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("did not throw", line: line)
        } catch let error as HubClientError {
            if let expected {
                XCTAssertEqual(error, expected, line: line)
            } else if case .decoding = error {
            } else {
                XCTFail("\(error)", line: line)
            }
        } catch {
            XCTFail("\(error)", line: line)
        }
    }
}

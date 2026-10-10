import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TokenMonitorKit

// MARK: - Fixtures

/// Loads `Fixtures/v2/golden/statuspage/*`: five synthetic Statuspage v2
/// `summary.json` bodies and `summaries.json`, which holds what the desktop's
/// `summarizeStatuspageProvider` and presentation helpers made of them at the
/// frozen clock.
private enum ServiceStatusFixture {
    static let directory = "Fixtures/v2/golden/statuspage"

    static func data(_ name: String) throws -> Data {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let url = Bundle.module.url(forResource: parts[0], withExtension: parts.count > 1 ? parts[1] : nil, subdirectory: directory) else {
            throw NSError(domain: "ServiceStatusFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name)"])
        }
        return try Data(contentsOf: url)
    }

    static func object(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(name)) as? [String: Any])
    }

    static let checkedAt = ISODate.parse("2026-10-10T16:30:00.000Z")!
}

/// A `URLProtocol` that answers per host, can hang or fail, and records every
/// request. Several providers share the path `/api/v2/summary.json`, so unlike
/// `StubURLProtocol` (keyed by path) this one is keyed by host.
final class StatusStubURLProtocol: URLProtocol {
    enum Behavior {
        case respond(status: Int, body: Data)
        case hang
        case fail(URLError.Code)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var behaviors: [String: Behavior] = [:]
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func stub(host: String, _ behavior: Behavior) {
        lock.lock()
        defer { lock.unlock() }
        behaviors[host] = behavior
    }

    static func stubAll(_ behavior: Behavior) {
        for provider in ServiceStatusProvider.all {
            stub(host: provider.summaryURL.host ?? "", behavior)
        }
    }

    static var recordedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    static func requestCount(host: String? = nil) -> Int {
        guard let host else { return recordedRequests.count }
        return recordedRequests.filter { $0.url?.host == host }.count
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        behaviors = [:]
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let behavior = request.url?.host.flatMap { Self.behaviors[$0] }
        Self.lock.unlock()
        guard let url = request.url, let behavior else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        switch behavior {
        case .respond(let status, let body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["content-type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .hang:
            break
        case .fail(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}

/// A clock the test moves by hand.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

// MARK: - Providers and parser

final class ServiceStatusParserTests: XCTestCase {
    private func summarize(_ json: String, provider: String = "claude") -> ServiceStatusSummary {
        ServiceStatusParser.summarize(
            provider: ServiceStatusProvider.provider(id: provider)!,
            data: Data(json.utf8),
            checkedAt: ServiceStatusFixture.checkedAt
        )
    }

    func testProvidersMatchTheDesktopTable() throws {
        let golden = try ServiceStatusFixture.object("summaries.json")
        let rows = try XCTUnwrap(golden["providers"] as? [[String: String]])
        XCTAssertEqual(ServiceStatusProvider.all.count, rows.count)
        for (provider, row) in zip(ServiceStatusProvider.all, rows) {
            XCTAssertEqual(provider.id, row["id"])
            XCTAssertEqual(provider.label, row["label"])
            XCTAssertEqual(provider.pageURL.absoluteString, row["pageUrl"])
            XCTAssertEqual(provider.summaryURL.absoluteString, row["summaryUrl"])
        }
        XCTAssertEqual(ServiceStatusProvider.all.map(\.markID), ["claude", "codex", "cursor", "deepseek"])
        // Public HTTPS pages only; nothing here can be a Hub.
        for provider in ServiceStatusProvider.all {
            XCTAssertEqual(provider.summaryURL.scheme, "https")
            XCTAssertEqual(provider.summaryURL.path, "/api/v2/summary.json")
            XCTAssertNil(provider.summaryURL.query)
        }
        XCTAssertEqual(ServiceStatusProvider.provider(id: "openai")?.markID, "codex")
        XCTAssertNil(ServiceStatusProvider.provider(id: "nope"))
    }

    /// Every payload file, summarized at the frozen clock, equals the desktop's summary.
    func testSummariesMatchTheDesktopGolden() throws {
        let golden = try ServiceStatusFixture.object("summaries.json")
        XCTAssertEqual(golden["checkedAt"] as? String, "2026-10-10T16:30:00.000Z")
        let entries = try XCTUnwrap(golden["summaries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 5)
        for entry in entries {
            let file = try XCTUnwrap(entry["file"] as? String)
            let provider = try XCTUnwrap(ServiceStatusProvider.provider(id: try XCTUnwrap(entry["provider"] as? String)))
            let summary = ServiceStatusParser.summarize(provider: provider, data: try ServiceStatusFixture.data(file), checkedAt: ServiceStatusFixture.checkedAt)
            try assertSummary(summary, equals: try XCTUnwrap(entry["summary"] as? [String: Any]), context: file)
            try assertPresentation(summary, entry: entry, context: file)
        }
    }

    func testFailedChecksMatchTheDesktopGolden() throws {
        let golden = try ServiceStatusFixture.object("summaries.json")
        let errors = try XCTUnwrap(golden["errors"] as? [[String: Any]])
        XCTAssertEqual(errors.count, 3)
        for entry in errors {
            let name = try XCTUnwrap(entry["name"] as? String)
            let provider = try XCTUnwrap(ServiceStatusProvider.provider(id: try XCTUnwrap(entry["provider"] as? String)))
            let input = try XCTUnwrap(entry["input"] as? [String: Any])
            let summary: ServiceStatusSummary
            switch name {
            case "httpError":
                XCTAssertEqual(input["error"] as? String, "HTTP 503")
                summary = ServiceStatusParser.summarize(provider: provider, data: nil, error: ServiceStatusFailure.http(status: 503), checkedAt: ServiceStatusFixture.checkedAt)
            case "nullPayload":
                summary = ServiceStatusParser.summarize(provider: provider, data: Data("null".utf8), checkedAt: ServiceStatusFixture.checkedAt)
                let missing = ServiceStatusParser.summarize(provider: provider, data: nil, checkedAt: ServiceStatusFixture.checkedAt)
                XCTAssertEqual(summary, missing, name)
            case "stringPayload":
                summary = ServiceStatusParser.summarize(provider: provider, data: Data(#""garbage""#.utf8), checkedAt: ServiceStatusFixture.checkedAt)
            default:
                return XCTFail("unexpected golden case \(name)")
            }
            try assertSummary(summary, equals: try XCTUnwrap(entry["summary"] as? [String: Any]), context: name)
            XCTAssertEqual(summary.headline, entry["headline"] as? String, name)
            XCTAssertTrue(summary.isCheckFailure, name)
        }
    }

    func testAgoBucketsMatchTheDesktopGolden() throws {
        let golden = try ServiceStatusFixture.object("summaries.json")
        let rows = try XCTUnwrap(golden["agoBuckets"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            let milliseconds = try XCTUnwrap(row["ms"] as? Double)
            let expected = try XCTUnwrap(row["bucket"] as? [String: Any])
            let bucket = ServiceStatusPresentation.agoBucket(milliseconds: milliseconds)
            XCTAssertEqual(bucket.unit.rawValue, expected["unit"] as? String, "\(milliseconds)")
            XCTAssertEqual(bucket.value, expected["value"] as? Int, "\(milliseconds)")
        }
        let checked = ServiceStatusFixture.checkedAt
        XCTAssertEqual(
            ServiceStatusPresentation.agoBucket(since: checked, now: checked.addingTimeInterval(125)),
            ServiceStatusPresentation.AgoBucket(unit: .minutes, value: 2)
        )
        // A clock that ran backwards, NaN and an unreasonably large span do not trap.
        XCTAssertEqual(ServiceStatusPresentation.agoBucket(since: checked, now: checked.addingTimeInterval(-30)).value, 0)
        XCTAssertEqual(ServiceStatusPresentation.agoBucket(milliseconds: .nan), .init(unit: .seconds, value: 0))
        XCTAssertEqual(ServiceStatusPresentation.agoBucket(milliseconds: .infinity), .init(unit: .hours, value: Int.max))
    }

    private func assertSummary(_ summary: ServiceStatusSummary, equals golden: [String: Any], context: String) throws {
        XCTAssertEqual(summary.id, golden["id"] as? String, context)
        XCTAssertEqual(summary.label, golden["label"] as? String, context)
        XCTAssertEqual(summary.pageURL.absoluteString, golden["pageUrl"] as? String, context)
        XCTAssertEqual(summary.tone.rawValue, golden["status"] as? String, context)
        XCTAssertEqual(summary.indicator, golden["indicator"] as? String, context)
        XCTAssertEqual(summary.description, golden["description"] as? String, context)
        XCTAssertEqual(summary.checkedAt, ISODate.parse(try XCTUnwrap(golden["checkedAt"] as? String)), context)
        // The desktop's empty strings are nil here.
        let updatedAt = golden["updatedAt"] as? String ?? ""
        XCTAssertEqual(summary.updatedAt, updatedAt.isEmpty ? nil : ISODate.parse(updatedAt), context)
        let issues = try XCTUnwrap(golden["componentIssues"] as? [[String: String]])
        XCTAssertEqual(summary.componentIssues.map(\.name), issues.map { $0["name"] }, context)
        XCTAssertEqual(summary.componentIssues.map(\.status), issues.map { $0["status"] }, context)
        let incidentTitle = golden["incidentTitle"] as? String ?? ""
        XCTAssertEqual(summary.incidentTitle, incidentTitle.isEmpty ? nil : incidentTitle, context)
        XCTAssertEqual(summary.incidentCount, golden["incidentCount"] as? Int, context)
        XCTAssertEqual(summary.maintenanceCount, golden["maintenanceCount"] as? Int, context)
        XCTAssertEqual(summary.error, golden["error"] as? String, context)
    }

    private func assertPresentation(_ summary: ServiceStatusSummary, entry: [String: Any], context: String) throws {
        for (key, limit) in [("affected", 2), ("affectedLimit1", 1)] {
            let expected = try XCTUnwrap(entry[key] as? [String: Any], context)
            let names = summary.affectedNames(limit: limit)
            XCTAssertEqual(names.all, expected["all"] as? [String], "\(context) \(key)")
            XCTAssertEqual(names.visible, expected["visible"] as? [String], "\(context) \(key)")
            XCTAssertEqual(names.overflow, expected["overflow"] as? Int, "\(context) \(key)")
        }
        XCTAssertEqual(summary.headline, entry["headline"] as? String, context)
    }

    // MARK: Desktop quirks the golden files do not reach

    func testIndicatorsMapToTonesAfterNormalizing() {
        let cases: [(String, ServiceStatusTone, String)] = [
            (#""none""#, .ok, "none"),
            (#"" NONE ""#, .ok, "none"),
            (#"" Minor ""#, .degraded, "minor"),
            (#""major""#, .outage, "major"),
            (#""CRITICAL""#, .outage, "critical"),
            (#""maintenance""#, .unknown, "maintenance"),
            (#""""#, .unknown, "unknown"),
            ("null", .unknown, "unknown"),
            ("false", .unknown, "unknown"),
            ("0", .unknown, "unknown"),
            ("5", .unknown, "5"),
            ("true", .unknown, "true")
        ]
        for (indicator, tone, normalized) in cases {
            let summary = summarize(#"{"status":{"indicator":\#(indicator),"description":"x"}}"#)
            XCTAssertEqual(summary.tone, tone, indicator)
            XCTAssertEqual(summary.indicator, normalized, indicator)
            XCTAssertNil(summary.error, indicator)
        }
        XCTAssertEqual(ServiceStatusTone(indicator: " Critical "), .outage)
    }

    func testAJSONArrayIsAnObjectToJavaScript() {
        // `typeof [] === 'object'`, so the desktop reports "unknown" without an error.
        let summary = summarize("[]")
        XCTAssertEqual(summary.tone, .unknown)
        XCTAssertEqual(summary.indicator, "unknown")
        XCTAssertEqual(summary.description, "Unknown")
        XCTAssertNil(summary.error)
        XCTAssertFalse(summary.isCheckFailure)
        XCTAssertEqual(summarize("{}"), summary)
    }

    func testUnusableBodiesAreFailedChecks() {
        for body in ["null", "5", "true", #""text""#, "<html>maintenance</html>", "", "{"] {
            let summary = summarize(body)
            XCTAssertEqual(summary.tone, .unknown, body)
            XCTAssertEqual(summary.description, "Unable to check status", body)
            XCTAssertNotNil(summary.error, body)
        }
        XCTAssertEqual(summarize("null").error, "Unable to check status")
        XCTAssertEqual(summarize("<html>").error, "Invalid JSON response")
    }

    func testErrorMessages() {
        let provider = ServiceStatusProvider.all[0]
        let valid = Data(#"{"status":{"indicator":"none"}}"#.utf8)
        // An error wins over a body.
        let cases: [(Error, String)] = [
            (ServiceStatusFailure.http(status: 503), "HTTP 503"),
            (ServiceStatusFailure.http(status: nil), "HTTP error"),
            (ServiceStatusFailure.timeout, "Timed out"),
            (ServiceStatusFailure.invalidJSON, "Invalid JSON response"),
            (ServiceStatusFailure.transport("The Internet connection appears to be offline."), "The Internet connection appears to be offline."),
            (ServiceStatusFailure.transport("  "), "Unable to check status")
        ]
        for (error, message) in cases {
            let summary = ServiceStatusParser.summarize(provider: provider, data: valid, error: error, checkedAt: ServiceStatusFixture.checkedAt)
            XCTAssertEqual(summary.error, message)
            XCTAssertEqual(summary.tone, .unknown)
            XCTAssertEqual(summary.description, "Unable to check status")
            XCTAssertEqual(summary.pageURL, provider.pageURL)
        }
        let foundation = ServiceStatusParser.summarize(provider: provider, data: nil, error: URLError(.notConnectedToInternet), checkedAt: ServiceStatusFixture.checkedAt)
        XCTAssertEqual(foundation.error, URLError(.notConnectedToInternet).localizedDescription)
    }

    func testIncidentsAndMaintenanceCountOnlyActiveItems() {
        let summary = summarize("""
        {"status":{"indicator":"minor","description":"Partial"},
         "incidents":[
           {"name":"Old","status":"resolved"},
           {"name":"Also old","status":" Completed "},
           {"name":"Review","status":"postmortem"},
           {"name":"  Newest active  ","status":"Investigating"},
           {"name":"Second","status":"monitoring"},
           {"name":"No status"},
           {"name":"Blank status","status":"  "},
           null, 7, "text", []
         ],
         "scheduled_maintenances":[
           {"name":"a","status":"completed"},
           {"name":"b","status":"CANCELED"},
           {"name":"c","status":"scheduled"},
           {"name":"d","status":"in_progress"},
           {"name":"e","status":"verifying"},
           {"name":"f"}
         ]}
        """)
        XCTAssertEqual(summary.incidentCount, 2)
        // The first *active* incident leads, trimmed.
        XCTAssertEqual(summary.incidentTitle, "Newest active")
        XCTAssertEqual(summary.maintenanceCount, 3)
        XCTAssertEqual(summary.headline, "Newest active")
    }

    func testAnActiveIncidentWithoutAnAnnouncedNameHasNoTitle() {
        let summary = summarize(#"{"incidents":[{"status":"investigating"},{"name":"Later","status":"identified"}]}"#)
        XCTAssertEqual(summary.incidentCount, 2)
        XCTAssertNil(summary.incidentTitle)
        XCTAssertEqual(summary.headline, "Unknown")
    }

    func testComponentIssuesSkipOperationalAndMaintenance() {
        let summary = summarize("""
        {"components":[
          {"name":"API","status":"operational"},
          {"name":"Web","status":" Operational "},
          {"name":"Batch","status":"under_maintenance"},
          {"name":" Codex ","status":" Degraded_Performance "},
          {"name":"","status":"partial_outage"},
          {"name":0,"status":"major_outage"},
          {"name":7,"status":"major_outage"},
          {"status":"full_outage"},
          {"name":"No status"},
          null,
          "text"
        ]}
        """)
        XCTAssertEqual(summary.componentIssues, [
            ServiceStatusComponentIssue(name: "Codex", status: "degraded_performance"),
            ServiceStatusComponentIssue(name: "Unknown", status: "partial_outage"),
            ServiceStatusComponentIssue(name: "Unknown", status: "major_outage"),
            ServiceStatusComponentIssue(name: "7", status: "major_outage"),
            ServiceStatusComponentIssue(name: "Unknown", status: "full_outage"),
            // A component without a status is not known to be operational.
            ServiceStatusComponentIssue(name: "No status", status: "unknown"),
            ServiceStatusComponentIssue(name: "Unknown", status: "unknown"),
            ServiceStatusComponentIssue(name: "Unknown", status: "unknown")
        ])
    }

    func testUpdatedAtPrefersThePageThenTheStatus() {
        let page = summarize(#"{"page":{"updated_at":"2026-10-10T16:12:03.512Z"},"status":{"updated_at":"2026-01-01T00:00:00Z"}}"#)
        XCTAssertEqual(page.updatedAt, ISODate.parse("2026-10-10T16:12:03.512Z"))
        let status = summarize(#"{"page":{},"status":{"updated_at":"2026-01-01T00:00:00Z"}}"#)
        XCTAssertEqual(status.updatedAt, ISODate.parse("2026-01-01T00:00:00Z"))
        // Statuspage also writes numeric offsets.
        let offset = summarize(#"{"page":{"updated_at":"2026-10-11T01:12:03.512+09:00"}}"#)
        XCTAssertEqual(offset.updatedAt, ISODate.parse("2026-10-10T16:12:03.512Z"))
        XCTAssertNil(summarize(#"{"page":{"updated_at":"yesterday"}}"#).updatedAt)
        XCTAssertNil(summarize(#"{"page":"text"}"#).updatedAt)
        XCTAssertNil(summarize("{}").updatedAt)
    }

    func testDescriptionIsTrimmedAndDefaults() {
        XCTAssertEqual(summarize(#"{"status":{"description":"  Partially Degraded Service \n"}}"#).description, "Partially Degraded Service")
        XCTAssertEqual(summarize(#"{"status":{"description":"   "}}"#).description, "Unknown")
        XCTAssertEqual(summarize(#"{"status":{"description":null}}"#).description, "Unknown")
        XCTAssertEqual(summarize(#"{"status":"text"}"#).description, "Unknown")
        // JavaScript's trim() also strips a BOM, which Foundation's whitespace set does not.
        XCTAssertEqual(summarize("{\"status\":{\"description\":\"\u{FEFF}Operational\u{FEFF}\"}}").description, "Operational")
    }

    func testSummaryCodableRoundTrip() throws {
        let summary = try summarize(String(decoding: ServiceStatusFixture.data("minor.json"), as: UTF8.self), provider: "openai")
        let decoded = try JSONDecoder().decode(ServiceStatusSummary.self, from: JSONEncoder().encode(summary))
        XCTAssertEqual(decoded, summary)
        XCTAssertEqual(decoded.markID, "codex")
    }

    // MARK: Presentation

    func testAffectedNamesLimits() {
        let issues = ["A", " B ", "", "  ", "C"].map { ServiceStatusComponentIssue(name: $0, status: "partial_outage") }
        let limited = ServiceStatusPresentation.affectedNames(issues, limit: 2)
        XCTAssertEqual(limited.all, ["A", "B", "C"])
        XCTAssertEqual(limited.visible, ["A", "B"])
        XCTAssertEqual(limited.overflow, 1)
        // The desktop default is 2; a limit below 1 or above the count shows everything.
        XCTAssertEqual(ServiceStatusPresentation.affectedNames(issues).visible, ["A", "B"])
        for limit in [0, -3, 3, 10] {
            let names = ServiceStatusPresentation.affectedNames(issues, limit: limit)
            XCTAssertEqual(names.visible, ["A", "B", "C"], "\(limit)")
            XCTAssertEqual(names.overflow, 0, "\(limit)")
        }
        XCTAssertEqual(ServiceStatusPresentation.affectedNames([]), .init(all: [], visible: [], overflow: 0))
    }

    func testHeadlineAndMeta() {
        let base = ServiceStatusSummary(id: "claude", label: "Claude", pageURL: ServiceStatusProvider.all[0].pageURL, tone: .ok, indicator: "none", description: "  All Systems Operational ", checkedAt: ServiceStatusFixture.checkedAt)
        XCTAssertEqual(base.headline, "All Systems Operational")
        var incident = base
        incident.incidentTitle = "  Elevated errors  "
        XCTAssertEqual(incident.headline, "Elevated errors")
        incident.incidentTitle = "   "
        XCTAssertEqual(incident.headline, "All Systems Operational")

        XCTAssertEqual(ServiceStatusPresentation.meta(base), .init(affectedCount: 0, incidentCount: 0, maintenanceCount: 0, showsNoIssues: true))
        XCTAssertFalse(ServiceStatusPresentation.meta(base).hasCounts)
        var degraded = base
        degraded.tone = .degraded
        XCTAssertFalse(ServiceStatusPresentation.meta(degraded).showsNoIssues, "a degraded provider with nothing to count shows no 'no issues'")
        degraded.componentIssues = [ServiceStatusComponentIssue(name: "API", status: "partial_outage"), ServiceStatusComponentIssue(name: "", status: "x")]
        degraded.incidentCount = 2
        degraded.maintenanceCount = 1
        let meta = ServiceStatusPresentation.meta(degraded)
        XCTAssertEqual(meta, .init(affectedCount: 1, incidentCount: 2, maintenanceCount: 1, showsNoIssues: false))
        XCTAssertTrue(meta.hasCounts)
    }
}

// MARK: - Client

final class ServiceStatusClientTests: XCTestCase {
    private var session: URLSession!
    private var clock: TestClock!
    private let hosts = ["status.claude.com", "status.openai.com", "status.cursor.com", "deepseek.statuspage.io"]

    override func setUp() {
        super.setUp()
        StatusStubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StatusStubURLProtocol.self]
        session = URLSession(configuration: configuration)
        clock = TestClock(ServiceStatusFixture.checkedAt)
    }

    override func tearDown() {
        StatusStubURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient(timeout: TimeInterval = 5, cacheTTL: TimeInterval = 60, errorTTL: TimeInterval = 10) -> ServiceStatusClient {
        let clock = self.clock!
        return ServiceStatusClient(session: session, cacheTTL: cacheTTL, errorTTL: errorTTL, timeout: timeout, now: { clock.now })
    }

    private func stubHealthy() throws {
        StatusStubURLProtocol.stubAll(.respond(status: 200, body: try ServiceStatusFixture.data("none.json")))
    }

    func testChecksEveryProviderOncePublicly() async throws {
        try StatusStubURLProtocol.stub(host: "status.openai.com", .respond(status: 200, body: ServiceStatusFixture.data("minor.json")))
        try StatusStubURLProtocol.stub(host: "status.cursor.com", .respond(status: 200, body: ServiceStatusFixture.data("major.json")))
        try StatusStubURLProtocol.stub(host: "deepseek.statuspage.io", .respond(status: 200, body: ServiceStatusFixture.data("maintenance.json")))
        try StatusStubURLProtocol.stub(host: "status.claude.com", .respond(status: 200, body: ServiceStatusFixture.data("none.json")))

        let report = await makeClient().statuses()
        XCTAssertEqual(report.checkedAt, ServiceStatusFixture.checkedAt)
        XCTAssertEqual(report.summaries.map(\.id), ["claude", "openai", "cursor", "deepseek"])
        XCTAssertEqual(report.summaries.map(\.tone), [.ok, .degraded, .outage, .unknown])
        XCTAssertTrue(report.summaries.allSatisfy { $0.checkedAt == ServiceStatusFixture.checkedAt && $0.error == nil })
        XCTAssertEqual(report.summaries[1].incidentTitle, "Elevated error rates for Codex")
        XCTAssertEqual(report.summaries[3].maintenanceCount, 2)

        let requests = StatusStubURLProtocol.recordedRequests
        XCTAssertEqual(requests.compactMap { $0.url?.host }.sorted(), hosts.sorted())
        for request in requests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.path, "/api/v2/summary.json")
            XCTAssertNil(request.url?.query)
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("TokenMonitor") ?? false)
            // A public page gets no Hub secret, device id or cookie.
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Device-Id"))
            XCTAssertFalse(request.httpShouldHandleCookies)
        }
        XCTAssertEqual(Set(requests.flatMap { ($0.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() } }), ["accept", "user-agent"])
    }

    func testRequestUsesTheAppVersionInTheUserAgent() {
        let provider = ServiceStatusProvider.all[0]
        let request = ServiceStatusClient.request(for: provider, timeout: 5, userAgent: ServiceStatusClient.userAgent(appVersion: " 1.4.2 "))
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "TokenMonitor/1.4.2 (+https://github.com/Javis603/token-monitor)")
        XCTAssertEqual(request.timeoutInterval, 5)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(ServiceStatusClient.defaultUserAgent, "TokenMonitor-iOS (+https://github.com/Javis603/token-monitor)")
        XCTAssertEqual(ServiceStatusClient.userAgent(appVersion: "  "), ServiceStatusClient.defaultUserAgent)
    }

    func testGoodResultsAreCachedForSixtySeconds() async throws {
        try stubHealthy()
        let client = makeClient()
        let first = await client.statuses()
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 4)

        clock.advance(59.999)
        let cached = await client.statuses()
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 4)
        XCTAssertEqual(cached, first)
        XCTAssertEqual(cached.checkedAt, ServiceStatusFixture.checkedAt)

        // `now < cacheUntil` is strict: at exactly 60 s it is stale.
        clock.advance(0.001)
        let refreshed = await client.statuses()
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 8)
        XCTAssertEqual(refreshed.checkedAt, ServiceStatusFixture.checkedAt.addingTimeInterval(60))
        XCTAssertTrue(refreshed.summaries.allSatisfy { $0.checkedAt == refreshed.checkedAt })
    }

    func testAnyFailureShortensTheCacheToTenSeconds() async throws {
        try stubHealthy()
        StatusStubURLProtocol.stub(host: "status.openai.com", .respond(status: 503, body: Data()))
        let client = makeClient()
        let failed = await client.statuses()
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 4)
        let openai = try XCTUnwrap(failed.summaries.first { $0.id == "openai" })
        XCTAssertEqual(openai.error, "HTTP 503")
        XCTAssertEqual(openai.tone, .unknown)
        XCTAssertEqual(failed.summaries.filter { $0.error == nil }.count, 3, "one failure does not fail the others")

        clock.advance(9.999)
        _ = await client.statuses()
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 4)

        // The blip is over: ten seconds later the next visit recovers, and the clean result is kept for the full minute.
        try StatusStubURLProtocol.stub(host: "status.openai.com", .respond(status: 200, body: ServiceStatusFixture.data("minor.json")))
        clock.advance(0.001)
        let recovered = await client.statuses()
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 8)
        XCTAssertTrue(recovered.summaries.allSatisfy { $0.error == nil })
        clock.advance(59.9)
        _ = await client.statuses()
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 8)
        clock.advance(0.1)
        _ = await client.statuses()
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 12)
    }

    func testForceAndInvalidateSkipTheCache() async throws {
        try stubHealthy()
        let client = makeClient()
        _ = await client.statuses()
        _ = await client.statuses(force: true)
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 8)
        _ = await client.statuses()
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 8)
        await client.invalidate()
        _ = await client.statuses()
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 12)
    }

    func testAProviderSubsetKeepsTheTableOrderAndHasOneCacheEntry() async throws {
        try stubHealthy()
        let client = makeClient()
        let subset = await client.statuses(providerIDs: ["cursor", "claude", "nope"])
        XCTAssertEqual(subset.summaries.map(\.id), ["claude", "cursor"])
        XCTAssertEqual(StatusStubURLProtocol.requestCount(host: "status.claude.com"), 1)
        XCTAssertEqual(StatusStubURLProtocol.requestCount(host: "status.cursor.com"), 1)
        XCTAssertEqual(StatusStubURLProtocol.requestCount(host: "status.openai.com"), 0)
        XCTAssertEqual(StatusStubURLProtocol.requestCount(host: "deepseek.statuspage.io"), 0)

        // The same set in another order is the same cache key.
        _ = await client.statuses(providerIDs: ["claude", "cursor"])
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 2)

        // A different set fetches again and replaces the entry (the desktop keeps only one).
        let all = await client.statuses()
        XCTAssertEqual(all.summaries.count, 4)
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 6)
        _ = await client.statuses(providerIDs: ["claude", "cursor"])
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 8)

        // Nothing wanted: an empty (and cached) report, no requests.
        let none = await client.statuses(providerIDs: [])
        XCTAssertEqual(none.summaries, [])
        _ = await client.statuses(providerIDs: ["nope"])
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 8)
    }

    func testFailuresBecomeSummariesNotThrows() async throws {
        StatusStubURLProtocol.stub(host: "status.claude.com", .respond(status: 200, body: Data("<html>captive portal</html>".utf8)))
        StatusStubURLProtocol.stub(host: "status.openai.com", .respond(status: 404, body: Data()))
        StatusStubURLProtocol.stub(host: "status.cursor.com", .fail(.notConnectedToInternet))
        StatusStubURLProtocol.stub(host: "deepseek.statuspage.io", .respond(status: 200, body: Data("null".utf8)))
        let report = await makeClient().statuses()
        XCTAssertEqual(report.summaries.map(\.error), [
            "Invalid JSON response",
            "HTTP 404",
            URLError(.notConnectedToInternet).localizedDescription,
            "Unable to check status"
        ])
        XCTAssertTrue(report.summaries.allSatisfy { $0.tone == .unknown && $0.isCheckFailure })
        XCTAssertEqual(report.summaries.map(\.pageURL), ServiceStatusProvider.all.map(\.pageURL))
    }

    func testASlowProviderTimesOutWithoutHoldingBackTheOthers() async throws {
        try stubHealthy()
        StatusStubURLProtocol.stub(host: "deepseek.statuspage.io", .hang)
        let client = makeClient(timeout: 0.3)
        let started = Date()
        let report = await client.statuses()
        XCTAssertLessThan(Date().timeIntervalSince(started), 4, "the deadline must end the hung request")
        let deepseek = try XCTUnwrap(report.summaries.first { $0.id == "deepseek" })
        XCTAssertEqual(deepseek.error, "Timed out")
        XCTAssertEqual(deepseek.tone, .unknown)
        XCTAssertEqual(report.summaries.filter { $0.error == nil }.count, 3)
        // A failed result is only cached for the error TTL.
        clock.advance(10)
        StatusStubURLProtocol.stub(host: "deepseek.statuspage.io", .respond(status: 200, body: try ServiceStatusFixture.data("none.json")))
        let recovered = await client.statuses()
        XCTAssertTrue(recovered.summaries.allSatisfy { $0.error == nil })
    }

    func testACancelledCheckIsNotCached() async throws {
        StatusStubURLProtocol.stubAll(.hang)
        let client = makeClient(timeout: 30)
        let task = Task { await client.statuses() }
        // Let the four requests start, then cancel.
        for _ in 0..<100 where StatusStubURLProtocol.requestCount() < 4 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 4)
        task.cancel()
        let cancelled = await task.value
        XCTAssertTrue(cancelled.summaries.allSatisfy { $0.tone == .unknown })

        try stubHealthy()
        let next = await client.statuses()
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 8, "the cancelled result must not satisfy the next call")
        XCTAssertTrue(next.summaries.allSatisfy { $0.tone == .ok })
    }

    func testNonPositiveTimingsFallBackToTheDesktopDefaults() async throws {
        try stubHealthy()
        let client = makeClient(timeout: 0, cacheTTL: 0, errorTTL: -1)
        _ = await client.statuses()
        clock.advance(59)
        _ = await client.statuses()
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 4)
        clock.advance(1)
        _ = await client.statuses()
        XCTAssertEqual(StatusStubURLProtocol.requestCount(), 8)
    }

    func testDefaultSessionKeepsNoCookiesOrCache() {
        let configuration = ServiceStatusClient.makeSession().configuration
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }
}

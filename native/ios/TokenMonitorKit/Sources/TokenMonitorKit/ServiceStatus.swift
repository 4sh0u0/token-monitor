import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Service status: Claude, OpenAI, Cursor and DeepSeek incident and maintenance
// summaries, read straight from each vendor's public Atlassian Statuspage
// `api/v2/summary.json`. A port of the desktop's `src/electron/serviceStatus.js`
// and `renderer/serviceStatusPresentation.js`.
//
// This never touches the Hub: the requests go to the vendors' public pages and
// carry nothing but a User-Agent and `Accept` header (no Hub URL, secret, device
// id or cookie). Everything here is Foundation-only; the targets localize the
// tones, counts and "ago" buckets this file returns.

// MARK: - Providers

/// One tracked service status page.
public struct ServiceStatusProvider: Sendable, Hashable, Identifiable {
    /// The desktop's id: `claude`, `openai`, `cursor` or `deepseek`.
    public let id: String
    /// The brand name (not localized).
    public let label: String
    /// The official status page, where a tap on the row goes.
    public let pageURL: URL
    /// The public Statuspage v2 summary the Kit reads.
    public let summaryURL: URL
    /// The tracked-client mark that draws this row's icon. OpenAI shows the
    /// Codex mark, as on the desktop (`serviceStatusIconId`).
    public let markID: String

    public init(id: String, label: String, pageURL: URL, summaryURL: URL, markID: String? = nil) {
        self.id = id
        self.label = label
        self.pageURL = pageURL
        self.summaryURL = summaryURL
        self.markID = markID ?? id
    }

    /// `SERVICE_STATUS_PROVIDERS` in the desktop's order.
    public static let all: [ServiceStatusProvider] = [
        ServiceStatusProvider(
            id: "claude",
            label: "Claude",
            pageURL: Self.url("https://status.claude.com"),
            summaryURL: Self.url("https://status.claude.com/api/v2/summary.json"),
            markID: "claude"
        ),
        ServiceStatusProvider(
            id: "openai",
            label: "OpenAI",
            pageURL: Self.url("https://status.openai.com"),
            summaryURL: Self.url("https://status.openai.com/api/v2/summary.json"),
            markID: "codex"
        ),
        ServiceStatusProvider(
            id: "cursor",
            label: "Cursor",
            pageURL: Self.url("https://status.cursor.com"),
            summaryURL: Self.url("https://status.cursor.com/api/v2/summary.json"),
            markID: "cursor"
        ),
        // The official status.deepseek.com only serves HTML to browsers (its
        // /api/v2 returns nothing to programmatic clients), so the JSON comes
        // from the Atlassian-hosted mirror while the row still links to the
        // official page, exactly as on the desktop.
        ServiceStatusProvider(
            id: "deepseek",
            label: "DeepSeek",
            pageURL: Self.url("https://status.deepseek.com"),
            summaryURL: Self.url("https://deepseek.statuspage.io/api/v2/summary.json"),
            markID: "deepseek"
        )
    ]

    /// The provider with this id, if it is one of `all`.
    public static func provider(id: String) -> ServiceStatusProvider? {
        all.first { $0.id == id }
    }

    private static func url(_ string: String) -> URL {
        // Compile-time constants above; a typo would fail every test.
        URL(string: string)!
    }
}

// MARK: - Summary

/// The overall state of one provider, from Statuspage's `status.indicator`.
public enum ServiceStatusTone: String, Codable, Sendable, CaseIterable {
    /// `none`.
    case ok
    /// `minor`.
    case degraded
    /// `major` or `critical`.
    case outage
    /// Anything else (including `maintenance`), and every failed check.
    case unknown

    /// The desktop's `providerTone`: the indicator is trimmed and lower-cased.
    public init(indicator: String) {
        switch indicator.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "none": self = .ok
        case "minor": self = .degraded
        case "major", "critical": self = .outage
        default: self = .unknown
        }
    }
}

/// A component that is not operational and not in planned maintenance.
public struct ServiceStatusComponentIssue: Codable, Sendable, Hashable {
    public var name: String
    /// Statuspage's component status, lower-cased: `degraded_performance`,
    /// `partial_outage`, `major_outage`, or `unknown` when it was missing.
    public var status: String

    public init(name: String, status: String) {
        self.name = name
        self.status = status
    }
}

/// The result of one check of one provider (`summarizeStatuspageProvider`).
public struct ServiceStatusSummary: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    /// The brand name (not localized).
    public var label: String
    public var pageURL: URL
    public var tone: ServiceStatusTone
    /// Statuspage's `status.indicator`, trimmed and lower-cased (`none`, `minor`,
    /// `major`, `critical`, `maintenance`, ...), or `unknown`.
    public var indicator: String
    /// Statuspage's own `status.description` ("All Systems Operational"), as
    /// the vendor wrote it. `Unknown` when it was blank and `Unable to check
    /// status` when the check failed; the desktop shows both untranslated, and
    /// a target may localize them (see `isCheckFailure`).
    public var description: String
    /// When this check started.
    public var checkedAt: Date
    /// The vendor page's own `updated_at`, when it gave a parseable one.
    public var updatedAt: Date?
    /// Components that are neither operational nor under maintenance.
    public var componentIssues: [ServiceStatusComponentIssue]
    /// The newest active incident's name; nil when none is active.
    public var incidentTitle: String?
    public var incidentCount: Int
    public var maintenanceCount: Int
    /// A short diagnostic ("HTTP 503") when the check failed; nil otherwise.
    public var error: String?

    public init(
        id: String,
        label: String,
        pageURL: URL,
        tone: ServiceStatusTone,
        indicator: String,
        description: String,
        checkedAt: Date,
        updatedAt: Date? = nil,
        componentIssues: [ServiceStatusComponentIssue] = [],
        incidentTitle: String? = nil,
        incidentCount: Int = 0,
        maintenanceCount: Int = 0,
        error: String? = nil
    ) {
        self.id = id
        self.label = label
        self.pageURL = pageURL
        self.tone = tone
        self.indicator = indicator
        self.description = description
        self.checkedAt = checkedAt
        self.updatedAt = updatedAt
        self.componentIssues = componentIssues
        self.incidentTitle = incidentTitle
        self.incidentCount = incidentCount
        self.maintenanceCount = maintenanceCount
        self.error = error
    }

    /// The provider's mark id (`codex` for OpenAI).
    public var markID: String {
        ServiceStatusProvider.provider(id: id)?.markID ?? id
    }

    /// The check itself failed (network, HTTP status or unusable body), so
    /// `tone` is `.unknown` for lack of data rather than because the vendor
    /// reported something unrecognized.
    public var isCheckFailure: Bool { error != nil }

    /// See `ServiceStatusPresentation.affectedNames`.
    public func affectedNames(limit: Int = 2) -> ServiceStatusPresentation.AffectedNames {
        ServiceStatusPresentation.affectedNames(componentIssues, limit: limit)
    }

    /// See `ServiceStatusPresentation.headline`.
    public var headline: String { ServiceStatusPresentation.headline(self) }
}

/// Why a check failed. `message` is the technical diagnostic stored in
/// `ServiceStatusSummary.error`.
public enum ServiceStatusFailure: Error, Equatable, Sendable, LocalizedError {
    /// A non-2xx status, or a response that was not HTTP (`status` nil).
    case http(status: Int?)
    /// The deadline passed before the whole body arrived.
    case timeout
    /// The body was not JSON.
    case invalidJSON
    /// The request never produced a response; carries the system's description.
    case transport(String)

    public var message: String {
        switch self {
        case .http(let status): return "HTTP \(status.map(String.init) ?? "error")"
        case .timeout: return "Timed out"
        case .invalidJSON: return "Invalid JSON response"
        case .transport(let description): return description
        }
    }

    public var errorDescription: String? { message }
}

// MARK: - Parser

/// `summarizeStatuspageProvider`.
public enum ServiceStatusParser {
    static let unableToCheck = "Unable to check status"

    /// Summarizes a Statuspage v2 `summary.json` body.
    ///
    /// - Parameters:
    ///   - data: The raw response body. Nil, a JSON `null`/scalar, or bytes
    ///     that are not JSON all give a failed-check summary, as the desktop
    ///     does for a missing or non-object payload. A JSON array is an
    ///     object to JavaScript, so it gives an `unknown` summary without an
    ///     error, also like the desktop.
    ///   - error: A failure that happened before there was a body. When set,
    ///     `data` is ignored; `error.localizedDescription` becomes
    ///     `ServiceStatusSummary.error` (`Unable to check status` if blank).
    ///   - checkedAt: When the check started.
    public static func summarize(
        provider: ServiceStatusProvider,
        data: Data?,
        error: Error? = nil,
        checkedAt: Date
    ) -> ServiceStatusSummary {
        if let error {
            return failure(provider, message: message(for: error), checkedAt: checkedAt)
        }
        guard let data else {
            return failure(provider, message: unableToCheck, checkedAt: checkedAt)
        }
        guard let payload = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return failure(provider, message: ServiceStatusFailure.invalidJSON.message, checkedAt: checkedAt)
        }
        switch payload {
        case .object, .array:
            return summarize(provider: provider, payload: payload, checkedAt: checkedAt)
        case .null, .bool, .number, .string:
            return failure(provider, message: unableToCheck, checkedAt: checkedAt)
        }
    }

    private static func summarize(provider: ServiceStatusProvider, payload: JSONValue, checkedAt: Date) -> ServiceStatusSummary {
        // `payload.status?.indicator`: a property read on anything that is not an object is undefined.
        let status = payload["status"]
        let indicator = normalizedStatus(status?["indicator"]).nilIfEmpty ?? "unknown"
        let incidents = activeItems(payload["incidents"], inactive: inactiveIncidentStatuses)
        let maintenances = activeItems(payload["scheduled_maintenances"], inactive: inactiveMaintenanceStatuses)
        let updated = jsTrim((payload["page"]?["updated_at"]).jsStringOrEmpty.nilIfEmpty
            ?? (status?["updated_at"]).jsStringOrEmpty)
        return ServiceStatusSummary(
            id: provider.id,
            label: provider.label,
            pageURL: provider.pageURL,
            tone: ServiceStatusTone(indicator: indicator),
            indicator: indicator,
            description: jsTrim((status?["description"]).jsStringOrEmpty).nilIfEmpty ?? "Unknown",
            checkedAt: checkedAt,
            updatedAt: updated.isEmpty ? nil : ISODate.parse(updated),
            componentIssues: componentIssues(payload["components"]),
            // The newest active incident's name: the headline the official page leads with.
            incidentTitle: incidents.first.flatMap { jsTrim(($0["name"]).jsStringOrEmpty).nilIfEmpty },
            incidentCount: incidents.count,
            maintenanceCount: maintenances.count
        )
    }

    private static func failure(_ provider: ServiceStatusProvider, message: String, checkedAt: Date) -> ServiceStatusSummary {
        ServiceStatusSummary(
            id: provider.id,
            label: provider.label,
            pageURL: provider.pageURL,
            tone: .unknown,
            indicator: "unknown",
            description: unableToCheck,
            checkedAt: checkedAt,
            error: message
        )
    }

    private static func message(for error: Error) -> String {
        let text: String
        if let failure = error as? ServiceStatusFailure {
            text = failure.message
        } else {
            text = error.localizedDescription
        }
        return jsTrim(text).nilIfEmpty ?? unableToCheck
    }

    // Components in planned maintenance are not degradations; they surface
    // through `maintenanceCount`, the way Atlassian and incident.io separate
    // maintenance from incidents.
    private static let componentsWithoutIssue: Set<String> = ["operational", "under_maintenance"]
    private static let inactiveIncidentStatuses: Set<String> = ["resolved", "completed", "postmortem"]
    private static let inactiveMaintenanceStatuses: Set<String> = ["completed", "canceled"]

    private static func activeItems(_ items: JSONValue?, inactive: Set<String>) -> [JSONValue] {
        guard case .array(let array)? = items else { return [] }
        return array.filter { item in
            let status = normalizedStatus(item["status"])
            return !status.isEmpty && !inactive.contains(status)
        }
    }

    /// Every entry that is not operational or under maintenance, including a
    /// malformed one, which the desktop lists as `Unknown` / `unknown`.
    private static func componentIssues(_ components: JSONValue?) -> [ServiceStatusComponentIssue] {
        guard case .array(let array)? = components else { return [] }
        return array.compactMap { component in
            let status = normalizedStatus(component["status"])
            guard !componentsWithoutIssue.contains(status) else { return nil }
            return ServiceStatusComponentIssue(
                name: jsTrim((component["name"]).jsStringOrEmpty).nilIfEmpty ?? "Unknown",
                status: status.nilIfEmpty ?? "unknown"
            )
        }
    }

    private static func normalizedStatus(_ value: JSONValue?) -> String {
        jsTrim(value.jsStringOrEmpty).lowercased()
    }
}

// MARK: - Presentation

/// `renderer/serviceStatusPresentation.js`, plus the count line of the desktop's
/// `serviceStatusMeta`. Returns data; the targets format it.
public enum ServiceStatusPresentation {
    /// The affected component names split into a short visible slice and an
    /// overflow count ("Claude Code, API +2").
    public struct AffectedNames: Sendable, Hashable {
        public var all: [String]
        public var visible: [String]
        public var overflow: Int

        public init(all: [String], visible: [String], overflow: Int) {
            self.all = all
            self.visible = visible
            self.overflow = overflow
        }
    }

    /// `affectedComponentNames`. A `limit` below 1 shows every name.
    public static func affectedNames(_ issues: [ServiceStatusComponentIssue], limit: Int = 2) -> AffectedNames {
        let names = issues.map { jsTrim($0.name) }.filter { !$0.isEmpty }
        let maximum = limit > 0 ? limit : names.count
        return AffectedNames(
            all: names,
            visible: Array(names.prefix(maximum)),
            overflow: max(0, names.count - maximum)
        )
    }

    /// `statusHeadline`: the active incident's name, else the overall
    /// description. It is far more useful than "Partially Degraded Service",
    /// which the tone pill already conveys.
    public static func headline(_ summary: ServiceStatusSummary) -> String {
        if let incident = summary.incidentTitle.map(jsTrim), !incident.isEmpty { return incident }
        return jsTrim(summary.description)
    }

    public enum AgoUnit: String, Sendable, Hashable {
        case seconds, minutes, hours
    }

    /// "Checked 12 s / 3 m / 2 h ago".
    public struct AgoBucket: Sendable, Hashable {
        public var unit: AgoUnit
        public var value: Int

        public init(unit: AgoUnit, value: Int) {
            self.unit = unit
            self.value = value
        }
    }

    /// `agoBucket`. Negative and non-numeric durations count as zero.
    public static func agoBucket(milliseconds: Double) -> AgoBucket {
        let seconds = milliseconds.isNaN ? 0 : max(0, (milliseconds / 1000).rounded(.down))
        if seconds < 60 { return AgoBucket(unit: .seconds, value: clampedInt(seconds)) }
        if seconds < 3600 { return AgoBucket(unit: .minutes, value: clampedInt((seconds / 60).rounded(.down))) }
        return AgoBucket(unit: .hours, value: clampedInt((seconds / 3600).rounded(.down)))
    }

    /// The bucket for a check that started at `checkedAt`, seen at `now`.
    public static func agoBucket(since checkedAt: Date, now: Date) -> AgoBucket {
        agoBucket(milliseconds: now.timeIntervalSince(checkedAt) * 1000)
    }

    /// The three counts behind the second line of a row (`serviceStatusMeta`).
    public struct Meta: Sendable, Hashable {
        public var affectedCount: Int
        public var incidentCount: Int
        public var maintenanceCount: Int
        /// "No active issues" only reads true for a healthy provider; a
        /// degraded one with nothing to count shows just its timestamp.
        public var showsNoIssues: Bool

        public init(affectedCount: Int, incidentCount: Int, maintenanceCount: Int, showsNoIssues: Bool) {
            self.affectedCount = affectedCount
            self.incidentCount = incidentCount
            self.maintenanceCount = maintenanceCount
            self.showsNoIssues = showsNoIssues
        }

        public var hasCounts: Bool { affectedCount > 0 || incidentCount > 0 || maintenanceCount > 0 }
    }

    public static func meta(_ summary: ServiceStatusSummary) -> Meta {
        let affected = affectedNames(summary.componentIssues).all.count
        let incidents = max(0, summary.incidentCount)
        let maintenance = max(0, summary.maintenanceCount)
        let hasCounts = affected > 0 || incidents > 0 || maintenance > 0
        return Meta(
            affectedCount: affected,
            incidentCount: incidents,
            maintenanceCount: maintenance,
            showsNoIssues: !hasCounts && summary.tone == .ok
        )
    }

    private static func clampedInt(_ value: Double) -> Int {
        value >= Double(Int.max) ? Int.max : Int(value)
    }
}

// MARK: - Client

/// What a check of a set of providers returned.
public struct ServiceStatusReport: Sendable, Hashable {
    /// When the check started (every summary carries the same time).
    public var checkedAt: Date
    /// One summary per requested provider, in the provider table's order.
    public var summaries: [ServiceStatusSummary]

    public init(checkedAt: Date, summaries: [ServiceStatusSummary]) {
        self.checkedAt = checkedAt
        self.summaries = summaries
    }
}

/// Fetches and caches the providers' summaries (`createServiceStatusClient`).
///
/// - A good result is reused for `cacheTTL` (60 s); a result in which any
///   provider failed only for `errorTTL` (10 s), so a transient blip recovers
///   on the next visit instead of staying "unknown" for a minute.
/// - There is one cache entry, keyed by the sorted ids of the providers asked
///   for; asking for a different set fetches again.
/// - Providers are fetched in parallel, each with a `timeout` (5 s) deadline
///   on the whole response. A failure is a summary with `error` set, never a
///   thrown error.
/// - Time comes from the injected `now`, so TTLs are testable without waiting.
public actor ServiceStatusClient {
    public static let defaultCacheTTL: TimeInterval = 60
    public static let defaultErrorTTL: TimeInterval = 10
    public static let defaultTimeout: TimeInterval = 5
    public static let defaultUserAgent = userAgent(appVersion: nil)

    /// `TokenMonitor/<version> (+https://github.com/Javis603/token-monitor)`,
    /// the desktop's User-Agent.
    public static func userAgent(appVersion: String?) -> String {
        let name = appVersion.flatMap { jsTrim($0).nilIfEmpty }.map { "TokenMonitor/\($0)" } ?? "TokenMonitor-iOS"
        return "\(name) (+https://github.com/Javis603/token-monitor)"
    }

    /// An ephemeral session for the public status pages: no cookies, no
    /// credentials, no on-disk cache.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// The request for one provider. Exposed for tests: a GET with the
    /// User-Agent and `Accept`, and nothing else.
    public static func request(for provider: ServiceStatusProvider, timeout: TimeInterval, userAgent: String) -> URLRequest {
        var request = URLRequest(url: provider.summaryURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = false
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private struct CacheEntry {
        var key: String
        var report: ServiceStatusReport
        var until: Date
    }

    private let session: URLSession
    private let providers: [ServiceStatusProvider]
    private let cacheTTL: TimeInterval
    private let errorTTL: TimeInterval
    private let timeout: TimeInterval
    private let userAgent: String
    private let now: @Sendable () -> Date
    private var cache: CacheEntry?

    /// A non-positive or non-finite TTL or timeout falls back to its default,
    /// like the desktop's `Number(options.x || DEFAULT)`.
    public init(
        session: URLSession = ServiceStatusClient.makeSession(),
        cacheTTL: TimeInterval = ServiceStatusClient.defaultCacheTTL,
        errorTTL: TimeInterval = ServiceStatusClient.defaultErrorTTL,
        timeout: TimeInterval = ServiceStatusClient.defaultTimeout,
        providers: [ServiceStatusProvider] = ServiceStatusProvider.all,
        userAgent: String = ServiceStatusClient.defaultUserAgent,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        func positive(_ value: TimeInterval, _ fallback: TimeInterval) -> TimeInterval {
            value.isFinite && value > 0 ? value : fallback
        }
        self.session = session
        self.providers = providers
        self.cacheTTL = positive(cacheTTL, Self.defaultCacheTTL)
        self.errorTTL = positive(errorTTL, Self.defaultErrorTTL)
        self.timeout = positive(timeout, Self.defaultTimeout)
        self.userAgent = userAgent
        self.now = now
    }

    /// Checks the providers (all of them, or those whose id is in `providerIDs`;
    /// unknown ids are ignored), or returns the cached result while it is fresh.
    ///
    /// - Parameter force: Skip the cache (the refresh button).
    ///
    /// Never throws. If the calling task is cancelled the partial result is
    /// returned but not cached.
    public func statuses(force: Bool = false, providerIDs: [String]? = nil) async -> ServiceStatusReport {
        let wanted = providerIDs.map { ids in providers.filter { ids.contains($0.id) } } ?? providers
        let key = wanted.map(\.id).sorted().joined(separator: ",")
        let current = now()
        if !force, let cache, cache.key == key, current < cache.until { return cache.report }

        let summaries = await Self.checkAll(wanted, session: session, timeout: timeout, userAgent: userAgent, checkedAt: current)
        let report = ServiceStatusReport(checkedAt: current, summaries: summaries)
        guard !Task.isCancelled else { return report }
        let anyError = summaries.contains { $0.error != nil }
        cache = CacheEntry(key: key, report: report, until: current.addingTimeInterval(anyError ? errorTTL : cacheTTL))
        return report
    }

    /// Drops the cached result, so the next `statuses` fetches again.
    public func invalidate() {
        cache = nil
    }

    private static func checkAll(
        _ wanted: [ServiceStatusProvider],
        session: URLSession,
        timeout: TimeInterval,
        userAgent: String,
        checkedAt: Date
    ) async -> [ServiceStatusSummary] {
        await withTaskGroup(of: (Int, ServiceStatusSummary).self) { group in
            for (index, provider) in wanted.enumerated() {
                group.addTask {
                    (index, await check(provider, session: session, timeout: timeout, userAgent: userAgent, checkedAt: checkedAt))
                }
            }
            var ordered = [ServiceStatusSummary?](repeating: nil, count: wanted.count)
            for await (index, summary) in group { ordered[index] = summary }
            return ordered.compactMap { $0 }
        }
    }

    private static func check(
        _ provider: ServiceStatusProvider,
        session: URLSession,
        timeout: TimeInterval,
        userAgent: String,
        checkedAt: Date
    ) async -> ServiceStatusSummary {
        do {
            let data = try await fetch(provider, session: session, timeout: timeout, userAgent: userAgent)
            return ServiceStatusParser.summarize(provider: provider, data: data, checkedAt: checkedAt)
        } catch {
            return ServiceStatusParser.summarize(provider: provider, data: nil, error: error, checkedAt: checkedAt)
        }
    }

    /// One GET with a deadline on the whole response. `timeoutInterval` only
    /// bounds the idle time between packets, so a task racing a sleep enforces
    /// the total, like the desktop's `AbortController`.
    private static func fetch(
        _ provider: ServiceStatusProvider,
        session: URLSession,
        timeout: TimeInterval,
        userAgent: String
    ) async throws -> Data {
        let urlRequest = Self.request(for: provider, timeout: timeout, userAgent: userAgent)
        let nanoseconds = UInt64(min(timeout, 3600) * 1_000_000_000)
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                do {
                    let (data, response) = try await session.data(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else { throw ServiceStatusFailure.http(status: nil) }
                    guard (200..<300).contains(http.statusCode) else { throw ServiceStatusFailure.http(status: http.statusCode) }
                    return data
                } catch let error as ServiceStatusFailure {
                    throw error
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as URLError where error.code == .cancelled {
                    throw CancellationError()
                } catch let error as URLError where error.code == .timedOut {
                    throw ServiceStatusFailure.timeout
                } catch {
                    throw ServiceStatusFailure.transport(error.localizedDescription)
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw ServiceStatusFailure.timeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw ServiceStatusFailure.timeout }
            return first
        }
    }
}

// MARK: - JavaScript semantics

/// A decoded JSON value, read the way the desktop's JavaScript reads it: a
/// property of anything but an object is `undefined`, and `String(x || '')`
/// turns every falsy value into the empty string.
private enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// `value?.key`: nil for a missing key and for every non-object value.
    subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    /// JavaScript truthiness.
    var isTruthy: Bool {
        switch self {
        case .null: return false
        case .bool(let value): return value
        case .number(let value): return value != 0 && !value.isNaN
        case .string(let value): return !value.isEmpty
        case .array, .object: return true
        }
    }

    /// `String(value)`.
    var jsString: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return JSCompat.numberString(value)
        case .string(let value): return value
        case .array(let values):
            // Array.prototype.toString: null elements are empty, the rest join with ",".
            return values.map { value -> String in
                if case .null = value { return "" }
                return value.jsString
            }.joined(separator: ",")
        case .object: return "[object Object]"
        }
    }
}

private extension Optional where Wrapped == JSONValue {
    /// `String(value || '')`, with a missing value (`undefined`) as `''`.
    var jsStringOrEmpty: String {
        guard let value = self, value.isTruthy else { return "" }
        return value.jsString
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// `String.prototype.trim`: whitespace and line terminators, including U+FEFF
/// but not U+0085.
private func jsTrim(_ string: String) -> String {
    string.trimmingCharacters(in: jsWhitespace)
}

private let jsWhitespace: CharacterSet = {
    var set = CharacterSet.whitespacesAndNewlines
    set.remove(charactersIn: "\u{0085}")
    set.insert(charactersIn: "\u{FEFF}")
    return set
}()

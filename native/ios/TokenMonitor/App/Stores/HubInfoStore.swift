import Foundation
import Observation
import TokenMonitorKit

/// What the Hub info screen shows: `GET /api/health` (runtime, device count,
/// `hubBuild` revisions or a legacy Hub), the sync capabilities
/// (`GET /api/sync/content`) and the shared custom pricing
/// (`GET /api/sync/settings/customPricing`), read-only and on demand. The
/// model-alias summary is `AppModel.aliasDocument`.
@MainActor
@Observable
final class HubInfoStore {
    /// The state of one of the three reads.
    enum Availability: Equatable, Sendable {
        case unknown
        case loading
        case available
        /// The Hub predates the endpoint (404/405).
        case unsupported
        case failed(HubClientError)
    }

    private(set) var health: HubHealth?
    private(set) var syncContent: SyncContentCapabilities?
    /// `entries` nil: the group was never initialized on this Hub.
    private(set) var customPricing: CustomPricingDocument?
    private(set) var healthStatus: Availability = .unknown
    private(set) var syncContentStatus: Availability = .unknown
    private(set) var customPricingStatus: Availability = .unknown
    private(set) var isLoading = false
    private(set) var loadedAt: Date?

    /// The Hub answered health without `hubBuild` (plan D-HUBBUILD:
    /// "Legacy Hub"; no comparison with the build registry).
    var isLegacyHub: Bool {
        guard let health else { return false }
        return health.coreRevision == nil && health.runtimeRevision == nil
    }

    /// The custom pricing rows, `[]` when none are shared.
    var customPricingEntries: [CustomPricingEntry] { customPricing?.entries ?? [] }

    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var hubKey: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Reads the three endpoints in parallel. A call while one is running for
    /// the same Hub joins it; another Hub's values are cleared first.
    func load(connection: HubConnection?) async {
        guard let connection else {
            reset()
            return
        }
        if connection.snapshotKey != hubKey {
            reset()
            hubKey = connection.snapshotKey
        }
        if let task {
            await task.value
            return
        }
        let client = HubClient(connection: connection, session: session)
        let generation = self.generation
        isLoading = true
        if health == nil { healthStatus = .loading }
        if syncContent == nil { syncContentStatus = .loading }
        if customPricing == nil { customPricingStatus = .loading }
        let task = Task { [weak self] in
            async let health = Self.read { try await client.health() }
            async let content = Self.read { try await client.syncContent() }
            async let pricing = Self.read { try await client.customPricingDocument() }
            let results = await (health, content, pricing)
            guard let self, generation == self.generation else { return }
            self.task = nil
            self.isLoading = false
            self.loadedAt = Date()
            Self.store(results.0, into: &self.health, status: &self.healthStatus)
            Self.store(results.1, into: &self.syncContent, status: &self.syncContentStatus)
            Self.store(results.2, into: &self.customPricing, status: &self.customPricingStatus)
        }
        self.task = task
        await task.value
    }

    /// Forgets everything (Hub switch or disconnect).
    func reset() {
        generation += 1
        task?.cancel()
        task = nil
        hubKey = nil
        if health != nil { health = nil }
        if syncContent != nil { syncContent = nil }
        if customPricing != nil { customPricing = nil }
        if healthStatus != .unknown { healthStatus = .unknown }
        if syncContentStatus != .unknown { syncContentStatus = .unknown }
        if customPricingStatus != .unknown { customPricingStatus = .unknown }
        if isLoading { isLoading = false }
        if loadedAt != nil { loadedAt = nil }
    }

    // MARK: Private

    private enum ReadResult<Value: Sendable>: Sendable {
        case value(Value)
        case unsupported
        case failure(HubClientError)
        case cancelled
    }

    private nonisolated static func read<Value: Sendable>(_ body: @Sendable () async throws -> Value) async -> ReadResult<Value> {
        do {
            return .value(try await body())
        } catch is CancellationError {
            return .cancelled
        } catch let error as HubClientError {
            return error.isUnsupportedEndpoint ? .unsupported : .failure(error)
        } catch {
            return .failure(.decoding(String(describing: error)))
        }
    }

    /// A failed read keeps the previous value on screen.
    private static func store<Value: Sendable & Equatable>(_ result: ReadResult<Value>, into value: inout Value?, status: inout Availability) {
        switch result {
        case .value(let new):
            if value != new { value = new }
            status = .available
        case .unsupported:
            value = nil
            status = .unsupported
        case .failure(let error):
            status = .failed(error)
        case .cancelled:
            if status == .loading { status = value == nil ? .unknown : .available }
        }
    }
}

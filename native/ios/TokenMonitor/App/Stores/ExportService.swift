import Foundation
import Observation
import TokenMonitorKit

/// Builds the desktop's export file set (`token-monitor-export.json`,
/// `token-monitor-snapshot.csv`, and the daily and daily-models CSVs when
/// History has rows) from the Hub's raw `/api/stats` and `/api/history`
/// bodies, for a `ShareLink`.
///
/// Like the desktop (`writeExportTo`) the export is the aggregate, costs stay
/// in USD and model ids are exported raw (display aliases never rewrite
/// them). A Hub without `/api/history` exports the snapshot files only; any
/// other History failure fails the export rather than writing a set that
/// silently lacks the time series. Files go to
/// `temporaryDirectory/TokenMonitorExport-<yyyyMMdd-HHmmss>/`; earlier export
/// folders are removed first.
@MainActor
@Observable
final class ExportService {
    enum Failure: Error, Equatable, Sendable {
        /// No Hub is connected.
        case notConfigured
        /// A Hub read failed.
        case hub(HubClientError)
        /// The Hub's stats body was not the expected JSON.
        case invalidStats
        /// The Hub's History body was not the expected JSON.
        case invalidHistory
        /// The files could not be written (the system's description).
        case write(String)
    }

    private(set) var isExporting = false
    /// The files of the last export, for a `ShareLink`.
    private(set) var files: [URL] = []
    private(set) var generatedAt: Date?
    private(set) var lastError: Failure?

    nonisolated static let folderPrefix = "TokenMonitorExport-"

    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var generation = 0

    init(session: URLSession = .shared, directory: URL = FileManager.default.temporaryDirectory) {
        self.session = session
        self.directory = directory
    }

    /// Fetches the Hub's data, writes the export files and returns their
    /// URLs (also kept in `files`).
    /// - Throws: `ExportService.Failure`, or `CancellationError`.
    @discardableResult
    func makeFiles(connection: HubConnection?) async throws -> [URL] {
        guard let connection else {
            lastError = .notConfigured
            throw Failure.notConfigured
        }
        generation += 1
        let generation = self.generation
        isExporting = true
        lastError = nil
        defer {
            if generation == self.generation { isExporting = false }
        }
        let client = HubClient(connection: connection, session: session)
        let now = Date()
        do {
            let urls = try await Self.export(client: client, generatedAt: now, directory: directory, version: Self.appVersion)
            guard generation == self.generation else { throw CancellationError() }
            files = urls
            generatedAt = now
            return urls
        } catch let failure as Failure {
            if generation == self.generation { lastError = failure }
            throw failure
        }
    }

    /// Removes the export folders and forgets the files (Hub switch,
    /// disconnect, or the share sheet closed).
    func clear() {
        generation += 1
        isExporting = false
        if !files.isEmpty { files = [] }
        if generatedAt != nil { generatedAt = nil }
        if lastError != nil { lastError = nil }
        let directory = self.directory
        Task.detached(priority: .utility) {
            Self.removeExportFolders(in: directory)
        }
    }

    // MARK: Private

    nonisolated static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private nonisolated static func export(client: HubClient, generatedAt: Date, directory: URL, version: String?) async throws -> [URL] {
        let statsData: Data
        let historyData: Data?
        do {
            statsData = try await client.statsData()
            do {
                historyData = try await client.historyData()
            } catch let error as HubClientError where error.isUnsupportedEndpoint {
                historyData = nil
            }
        } catch let error as HubClientError {
            throw Failure.hub(error)
        }
        let exportFiles: [ExportFile]
        do {
            exportFiles = try ExportSerializer.fileSet(
                statsData: statsData,
                historyData: historyData,
                generatedAt: generatedAt,
                app: ExportApp(version: version)
            )
        } catch ExportError.invalidHistory {
            throw Failure.invalidHistory
        } catch {
            throw Failure.invalidStats
        }
        try Task.checkCancellation()
        removeExportFolders(in: directory)
        let folder = directory.appendingPathComponent(folderPrefix + stamp(generatedAt), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return try exportFiles.map { file in
                let url = folder.appendingPathComponent(file.name, isDirectory: false)
                try file.data.write(to: url, options: [.atomic])
                return url
            }
        } catch {
            throw Failure.write(error.localizedDescription)
        }
    }

    private nonisolated static func removeExportFolders(in directory: URL) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(folderPrefix) {
            try? manager.removeItem(at: directory.appendingPathComponent(name, isDirectory: true))
        }
    }

    /// `yyyyMMdd-HHmmss` in the phone's time zone.
    private nonisolated static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

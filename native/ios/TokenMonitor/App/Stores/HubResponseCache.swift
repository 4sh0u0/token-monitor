import Foundation

/// One Hub response body kept in the app's own caches directory (never the
/// App Group: only the app reads it), so a relaunch shows the last History or
/// subscription list at once and refetches only when the Hub advertises a
/// different revision.
///
/// One file per kind holds the body of one Hub: a single-line JSON header
/// (`hubKey`, `revision`, `savedAt`) followed by the raw body bytes, written
/// atomically. A different Hub's body is never returned, and connecting to
/// another Hub simply overwrites the file on its first load.
struct HubResponseCache: Sendable {
    struct Header: Codable, Equatable, Sendable {
        /// `HubConnection.snapshotKey` of the Hub the body came from.
        var hubKey: String
        /// The signature the body was fetched for (a Hub revision).
        var revision: String?
        var savedAt: Date
    }

    struct Entry: Sendable {
        var header: Header
        var body: Data
    }

    /// `history`, `devices`, `subscriptions`.
    let name: String
    let directory: URL

    init(name: String, directory: URL = HubResponseCache.defaultDirectory) {
        self.name = name
        self.directory = directory
    }

    /// `Library/Caches/TokenMonitor/HubResponses` in the app's container.
    static var defaultDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches
            .appendingPathComponent("TokenMonitor", isDirectory: true)
            .appendingPathComponent("HubResponses", isDirectory: true)
    }

    var fileURL: URL { directory.appendingPathComponent("\(name).cache", isDirectory: false) }

    /// The cached body of the Hub `hubKey` names; nil for another Hub, a
    /// missing file or an unreadable one.
    func load(hubKey: String) -> Entry? {
        guard let data = try? Data(contentsOf: fileURL),
              let newline = data.firstIndex(of: 0x0A),
              let header = try? JSONDecoder().decode(Header.self, from: data[data.startIndex..<newline]),
              header.hubKey == hubKey else { return nil }
        return Entry(header: header, body: Data(data[data.index(after: newline)...]))
    }

    /// Replaces the file. Failures are ignored: the cache only saves a fetch.
    func save(body: Data, hubKey: String, revision: String?, savedAt: Date = Date()) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // JSONEncoder escapes control characters, so the header is one line.
        guard var file = try? encoder.encode(Header(hubKey: hubKey, revision: revision, savedAt: savedAt)) else { return }
        file.append(0x0A)
        file.append(body)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try file.write(to: fileURL, options: [.atomic])
        } catch {
            // A cache that cannot be written only costs a refetch next launch.
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Removes every cached Hub response (disconnect).
    static func clearAll(directory: URL = HubResponseCache.defaultDirectory) {
        try? FileManager.default.removeItem(at: directory)
    }
}

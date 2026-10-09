import Foundation
import XCTest
@testable import TokenMonitorKit

final class TokenSnapshotTests: XCTestCase {
    private let fetchedAt = Fixture.date("2026-10-09T02:50:00Z")

    private func snapshot() throws -> TokenSnapshot {
        TokenSnapshot(stats: try Fixture.stats(), fetchedAt: fetchedAt, calendar: Fixture.utc)
    }

    func testProjection() throws {
        let snapshot = try snapshot()
        XCTAssertEqual(snapshot.schemaVersion, TokenSnapshot.currentSchemaVersion)
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.sourceUpdatedAt, Fixture.date("2026-10-09T02:47:57.136Z"))
        XCTAssertFalse(snapshot.isSourceStale)
        XCTAssertEqual(snapshot.devices, DeviceCounts(online: 2, total: 3))
        XCTAssertEqual(snapshot.devices.stale, 1)

        let today = snapshot.today
        XCTAssertEqual(today.kind, .today)
        XCTAssertEqual(today.totalTokens, 72_250_000)
        XCTAssertEqual(today.costUsd, 122.825, accuracy: 1e-9)
        XCTAssertEqual(today.outputTokensPerSecond ?? 0, 62, accuracy: 0.1)
        XCTAssertEqual(today.tools.map(\.id), ["claude", "codex", "hermes", "opencode", "cursor", "gemini"])
        XCTAssertEqual(today.tools.first?.label, "Claude", "compact surfaces use the limits name")
        XCTAssertEqual(today.otherToolTokens, 0)
        XCTAssertEqual(today.models.count, TokenSnapshot.maxShares)
        XCTAssertEqual(today.otherModelTokens, 900_000 + 450_000)
        XCTAssertEqual(today.models(otherLabel: "Other").last?.tokens, 1_350_000)
        XCTAssertEqual(today.components.total, 72_250_000)

        let month = snapshot[.month]
        XCTAssertEqual(month.tools.count, TokenSnapshot.maxShares)
        XCTAssertEqual(month.otherToolTokens, 4_200_000 + 990_000)
        XCTAssertEqual(month.tools(otherLabel: "Other").count, TokenSnapshot.maxShares + 1)

        XCTAssertEqual(snapshot.limits.map(\.provider), ["claude", "codex", "opencode", "deepseek", "openrouter", "cursor", "kimi"])
        XCTAssertEqual(snapshot.limits[0].accountEmail, "d***v@example.com", "emails are masked in shared containers")
        XCTAssertEqual(snapshot.limits[1].windows.count, 2, "additional Codex buckets are dropped")
        XCTAssertTrue(snapshot.limits.allSatisfy { $0.windows.count <= TokenSnapshot.maxWindowsPerProvider })

        XCTAssertEqual(snapshot.trend.count, TokenSnapshot.maxTrendDays)
        XCTAssertEqual(snapshot.trend.last?.date, "2026-10-09")
        XCTAssertEqual(snapshot.trend.last?.tokens, 72_250_000)
        XCTAssertEqual(snapshot.trend.first?.date, "2026-09-10")
    }

    func testStaysSmall() throws {
        let data = try snapshot().jsonData()
        XCTAssertLessThan(data.count, 16 * 1024, "snapshot is \(data.count) bytes")
    }

    func testCodableRoundTrip() throws {
        let original = try snapshot()
        XCTAssertEqual(try TokenSnapshot(jsonData: original.jsonData()), original)
        // Dates are encoded by hand, so plain coders round-trip too.
        let plain = try JSONDecoder().decode(TokenSnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(plain, original)
    }

    func testDecodingToleratesMissingParts() throws {
        let snapshot = try TokenSnapshot(jsonData: Data(#"{"schemaVersion":1,"fetchedAt":"2026-10-09T02:50:00Z"}"#.utf8))
        XCTAssertEqual(snapshot.today.totalTokens, 0)
        XCTAssertEqual(snapshot.limits, [])
        XCTAssertThrowsError(try TokenSnapshot(jsonData: Data(#"{"schemaVersion":1}"#.utf8)))
    }

    func testAge() throws {
        let snapshot = try snapshot()
        XCTAssertFalse(snapshot.isOlder(than: 600, at: fetchedAt.addingTimeInterval(300)))
        XCTAssertTrue(snapshot.isOlder(than: 600, at: fetchedAt.addingTimeInterval(601)))
    }
}

final class SnapshotStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenMonitorKitTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTripAndClear() throws {
        let store = SnapshotStore(directory: directory)
        XCTAssertNil(store.load())
        let snapshot = TokenSnapshot(stats: try Fixture.stats(), fetchedAt: Fixture.date("2026-10-09T02:50:00Z"), calendar: Fixture.utc)
        try store.save(snapshot)
        XCTAssertEqual(store.load(), snapshot)
        XCTAssertEqual(store.fileURL.lastPathComponent, SnapshotStore.fileName)

        var newer = snapshot
        newer.today.totalTokens += 1
        try store.save(newer)
        XCTAssertEqual(store.load(), newer)

        try store.clear()
        XCTAssertNil(store.load())
        XCTAssertNoThrow(try store.clear())
    }

    func testIgnoresCorruptAndFutureFiles() throws {
        let store = SnapshotStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.fileURL)
        XCTAssertNil(store.load())

        var future = TokenSnapshot(stats: try Fixture.stats(), fetchedAt: Date(), calendar: Fixture.utc)
        future.schemaVersion = TokenSnapshot.currentSchemaVersion + 1
        try store.save(future)
        XCTAssertNil(store.load(), "a newer schema may mean something else")
    }
}

import Foundation
import XCTest
@testable import TokenMonitorKit

/// A stand-in Hub: records each fetch and can hold one open until cancelled.
private actor FetchProbe {
    private(set) var started: [String] = []

    /// A snapshot of `hubKey`, stamped with `stamp` when given.
    func fetch(_ hubKey: String, fetchedAt: Date, stamp: String? = nil, holdNanoseconds: UInt64 = 0) async -> TokenSnapshot? {
        started.append(hubKey)
        if holdNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: holdNanoseconds)
            if Task.isCancelled { return nil }
        }
        return .stub(hubKey: stamp ?? hubKey, fetchedAt: fetchedAt)
    }
}

private extension TokenSnapshot {
    static func stub(hubKey: String?, fetchedAt: Date) -> TokenSnapshot {
        TokenSnapshot(
            fetchedAt: fetchedAt,
            hubKey: hubKey,
            today: PeriodSummary(kind: .today, totalTokens: 1),
            month: PeriodSummary(kind: .month),
            allTime: PeriodSummary(kind: .allTime)
        )
    }
}

final class SnapshotFetchCoalescerTests: XCTestCase {
    private let now = Fixture.date("2026-10-09T02:50:00Z")

    func testConcurrentCallersShareOneFetch() async {
        let coalescer = SnapshotFetchCoalescer(reuseWindow: 60)
        let probe = FetchProbe()
        let now = self.now
        let results = await withTaskGroup(of: TokenSnapshot?.self) { group -> [TokenSnapshot?] in
            for _ in 0..<5 {
                group.addTask {
                    await coalescer.snapshot(hubKey: "a", now: now) {
                        await probe.fetch("a", fetchedAt: now, holdNanoseconds: 50_000_000)
                    }
                }
            }
            var all: [TokenSnapshot?] = []
            for await result in group { all.append(result) }
            return all
        }
        XCTAssertEqual(results, Array(repeating: TokenSnapshot.stub(hubKey: "a", fetchedAt: now), count: 5))
        let started = await probe.started
        XCTAssertEqual(started, ["a"])
    }

    func testReusesARecentFetchOfTheSameHubOnly() async {
        let coalescer = SnapshotFetchCoalescer(reuseWindow: 60)
        let probe = FetchProbe()
        let now = self.now
        let first = await coalescer.snapshot(hubKey: "a", now: now) { await probe.fetch("a", fetchedAt: now) }
        XCTAssertEqual(first?.hubKey, "a")

        let reused = await coalescer.snapshot(hubKey: "a", now: now.addingTimeInterval(30)) { await probe.fetch("a", fetchedAt: now) }
        XCTAssertEqual(reused, first)
        var started = await probe.started
        XCTAssertEqual(started, ["a"])

        let otherHub = await coalescer.snapshot(hubKey: "b", now: now.addingTimeInterval(30)) {
            await probe.fetch("b", fetchedAt: now.addingTimeInterval(30))
        }
        XCTAssertEqual(otherHub?.hubKey, "b", "another Hub never gets the last fetch")
        started = await probe.started
        XCTAssertEqual(started, ["a", "b"])

        _ = await coalescer.snapshot(hubKey: "b", now: now.addingTimeInterval(91)) { await probe.fetch("b", fetchedAt: now) }
        _ = await coalescer.snapshot(hubKey: "b", force: true, now: now.addingTimeInterval(91)) { await probe.fetch("b", fetchedAt: now) }
        started = await probe.started
        XCTAssertEqual(started, ["a", "b", "b", "b"], "past the reuse window, and when forced, the Hub is read again")
    }

    func testAHubSwitchCancelsTheOldFetch() async throws {
        let coalescer = SnapshotFetchCoalescer(reuseWindow: 60)
        let probe = FetchProbe()
        let now = self.now
        let old = Task {
            await coalescer.snapshot(hubKey: "a", now: now) {
                await probe.fetch("a", fetchedAt: now, holdNanoseconds: 10_000_000_000)
            }
        }
        while await probe.started.isEmpty {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let new = await coalescer.snapshot(hubKey: "b", now: now) { await probe.fetch("b", fetchedAt: now) }
        XCTAssertEqual(new?.hubKey, "b")
        let oldResult = await old.value
        XCTAssertNil(oldResult, "the previous Hub's fetch is cancelled, not decoded beside the new one")

        // B's fetch is not undone by the old one finishing: it is still reused.
        let reused = await coalescer.snapshot(hubKey: "b", now: now) { await probe.fetch("b", fetchedAt: now) }
        XCTAssertEqual(reused, new)
        let started = await probe.started
        XCTAssertEqual(started, ["a", "b"])
    }

    func testAResultFromAnotherHubIsNotHandedOut() async {
        let coalescer = SnapshotFetchCoalescer(reuseWindow: 60)
        let probe = FetchProbe()
        let now = self.now
        // The saved Hub changed between reading the cache and the request.
        let switched = await coalescer.snapshot(hubKey: "a", now: now) { await probe.fetch("a", fetchedAt: now, stamp: "b") }
        XCTAssertNil(switched)
        // A snapshot of unknown origin (written before `hubKey` existed) is accepted.
        let legacy = await coalescer.snapshot(hubKey: "a", now: now) { .stub(hubKey: nil, fetchedAt: now) }
        XCTAssertNotNil(legacy)
        let failed = await coalescer.snapshot(hubKey: "c", now: now) { nil }
        XCTAssertNil(failed)
    }
}

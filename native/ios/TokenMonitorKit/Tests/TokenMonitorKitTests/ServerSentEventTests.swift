import Foundation
import XCTest
@testable import TokenMonitorKit

final class ServerSentEventTests: XCTestCase {
    func testCapturedHubStream() throws {
        // Captured with curl -N from a Node hub: the connection's `snapshot`,
        // one `stats` broadcast after an ingest, then a `: hb` heartbeat.
        let bytes = try Fixture.data("stats-stream.txt")
        var parser = ServerSentEventParser()
        let events = parser.consume(bytes)
        XCTAssertEqual(events.map(\.event), ["snapshot", "stats"])

        let decoder = HubStreamDecoder()
        let snapshot = try XCTUnwrap(decoder.update(from: events[0]))
        let update = try XCTUnwrap(decoder.update(from: events[1]))
        XCTAssertEqual(snapshot.reason, "snapshot")
        XCTAssertEqual(update.reason, "ingest")
        XCTAssertNotNil(update.at)
        XCTAssertEqual(snapshot.stats.devices.count, 3)
        let before = try XCTUnwrap(snapshot.stats.today.clients.first { $0.id == "claude" }).tokens
        let after = try XCTUnwrap(update.stats.today.clients.first { $0.id == "claude" }).tokens
        XCTAssertEqual(after - before, 250_000)
        XCTAssertEqual(update.stats.today.totalTokens - snapshot.stats.today.totalTokens, 250_000)
    }

    func testChunkBoundariesDoNotMatter() throws {
        let bytes = Array(try Fixture.data("stats-stream.txt"))
        var whole = ServerSentEventParser()
        let expected = whole.consume(bytes)
        for chunkSize in [1, 7, 4096] {
            var parser = ServerSentEventParser()
            var events: [ServerSentEvent] = []
            var index = 0
            while index < bytes.count {
                let end = min(bytes.count, index + chunkSize)
                events += parser.consume(bytes[index..<end])
                index = end
            }
            XCTAssertEqual(events, expected, "chunk size \(chunkSize)")
        }
    }

    func testFieldParsing() {
        var parser = ServerSentEventParser()
        let events = parser.consume(text: """
        : comment line
        retry: 5000
        id: 7
        event: stats
        data: first
        data:second
        data:  indented

        data: no event name
        unknown: ignored

        event: empty

        data


        """)
        XCTAssertEqual(events, [
            ServerSentEvent(event: "stats", data: "first\nsecond\n indented", id: "7", retry: 5000),
            ServerSentEvent(event: "message", data: "no event name", id: "7"),
            ServerSentEvent(event: "message", data: "", id: "7")
        ])
    }

    func testLineEndingsAndBOM() {
        var parser = ServerSentEventParser()
        let crlf = parser.consume(Array("\u{FEFF}event: a\r\ndata: 1\r\n\r\n".utf8))
        let cr = parser.consume(Array("event: b\rdata: 2\r\r".utf8))
        let mixed = parser.consume(Array("data: 3\r\n\n".utf8))
        XCTAssertEqual(crlf, [ServerSentEvent(event: "a", data: "1")])
        XCTAssertEqual(cr, [ServerSentEvent(event: "b", data: "2")])
        XCTAssertEqual(mixed, [ServerSentEvent(event: "message", data: "3")])
    }

    func testMultiByteCharacterSplitAcrossChunks() {
        let bytes = Array("data: 日本\n\n".utf8)
        var parser = ServerSentEventParser()
        var events: [ServerSentEvent] = []
        for byte in bytes {
            if let event = parser.consume(byte) { events.append(event) }
        }
        XCTAssertEqual(events.first?.data, "日本")
    }

    func testIncompleteEventIsDiscardedOnReset() {
        var parser = ServerSentEventParser()
        XCTAssertEqual(parser.consume(text: "event: stats\ndata: {\"partial\""), [])
        parser.reset()
        XCTAssertEqual(parser.consume(text: "data: next\n\n"), [ServerSentEvent(event: "message", data: "next")])
    }

    func testStreamDecoderPassesOptionsToEveryFrame() throws {
        let bytes = try Fixture.data("stats-stream.txt")
        var parser = ServerSentEventParser()
        let events = parser.consume(bytes)
        let compact = try XCTUnwrap(HubStreamDecoder().update(from: events[1]))
        let app = try XCTUnwrap(HubStreamDecoder(options: .app).update(from: events[1]))
        XCTAssertEqual(compact.stats.today.sessions, [])
        XCTAssertEqual(app.stats.today.sessions.count, app.stats.today.sessionCount)
        XCTAssertTrue(compact.stats.devices.allSatisfy { $0.details.isEmpty })
        XCTAssertTrue(app.stats.devices.allSatisfy { !$0.details.isEmpty })
        XCTAssertEqual(app.stats.today.totalTokens, compact.stats.today.totalTokens)

        // A bare (unwrapped) frame sees the options too.
        let frame = #"{"periods":{"today":{"totalTokens":6,"sessions":{"a:1":{"client":"a","totalTokens":6}}}}}"#
        let bare = HubStreamDecoder(options: .app).stats(from: ServerSentEvent(event: "snapshot", data: frame))
        XCTAssertEqual(bare?.today.sessions.map(\.id), ["a:1"])
        XCTAssertEqual(HubStreamDecoder().stats(from: ServerSentEvent(event: "snapshot", data: frame))?.today.sessions, [])
    }

    func testStreamDecoderIgnoresOtherEventsAndBadFrames() {
        let decoder = HubStreamDecoder()
        XCTAssertNil(decoder.stats(from: ServerSentEvent(event: "freshness", data: #"{"limits":{}}"#)))
        XCTAssertNil(decoder.stats(from: ServerSentEvent(event: "message", data: #"{"stats":{}}"#)))
        XCTAssertNil(decoder.stats(from: ServerSentEvent(event: "stats", data: "{not json")))
        XCTAssertNil(decoder.stats(from: ServerSentEvent(event: "stats", data: #"{"type":"stats"}"#)))
        let wrapped = decoder.stats(from: ServerSentEvent(event: "stats", data: #"{"stats":{"periods":{"today":{"totalTokens":5}}}}"#))
        XCTAssertEqual(wrapped?.today.totalTokens, 5)
        let bare = decoder.stats(from: ServerSentEvent(event: "snapshot", data: #"{"periods":{"today":{"totalTokens":6}}}"#))
        XCTAssertEqual(bare?.today.totalTokens, 6)
    }
}

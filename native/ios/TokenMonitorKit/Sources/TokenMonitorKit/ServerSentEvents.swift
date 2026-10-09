import Foundation

/// One dispatched Server-Sent Event.
public struct ServerSentEvent: Sendable, Equatable {
    /// The `event:` field; `message` when the event named none.
    public var event: String
    /// The `data:` lines joined with `\n`.
    public var data: String
    /// The last `id:` seen on the stream, if any.
    public var id: String?
    /// The `retry:` reconnection time in milliseconds, when this event set one.
    public var retry: Int?

    public init(event: String = "message", data: String, id: String? = nil, retry: Int? = nil) {
        self.event = event
        self.data = data
        self.id = id
        self.retry = retry
    }
}

/// An incremental `text/event-stream` parser (WHATWG HTML, "Server-sent
/// events"), independent of any transport so it is unit-tested on every
/// platform.
///
/// Feed it bytes as they arrive; it returns each event when its terminating
/// blank line arrives. Lines may end in LF, CRLF or CR; `:` lines are comments
/// (the Hub's `: hb` heartbeats); a line split across chunks — including inside
/// a multi-byte UTF-8 character — is reassembled before decoding.
public struct ServerSentEventParser: Sendable {
    private var line: [UInt8] = []
    private var lastByteWasCR = false
    private var isFirstLine = true
    private var eventType = ""
    private var dataBuffer = ""
    private var hasData = false
    private var lastEventID: String?
    private var retry: Int?

    public init() {}

    /// Consumes one byte; returns an event when this byte completed one.
    public mutating func consume(_ byte: UInt8) -> ServerSentEvent? {
        switch byte {
        case 0x0A: // LF
            if lastByteWasCR {
                // Second half of CRLF: the line was already processed at CR.
                lastByteWasCR = false
                return nil
            }
            return endLine()
        case 0x0D: // CR
            lastByteWasCR = true
            return endLine()
        default:
            lastByteWasCR = false
            line.append(byte)
            return nil
        }
    }

    /// Consumes a chunk; returns every event it completed, in order.
    public mutating func consume<Bytes: Sequence>(_ bytes: Bytes) -> [ServerSentEvent] where Bytes.Element == UInt8 {
        var events: [ServerSentEvent] = []
        for byte in bytes {
            if let event = consume(byte) { events.append(event) }
        }
        return events
    }

    /// Consumes UTF-8 text (convenient in tests).
    public mutating func consume(text: String) -> [ServerSentEvent] {
        consume(Array(text.utf8))
    }

    /// Forgets a partially received event, as the spec requires at end of
    /// stream. The last event id is kept for a reconnect.
    public mutating func reset() {
        line.removeAll(keepingCapacity: true)
        lastByteWasCR = false
        eventType = ""
        dataBuffer = ""
        hasData = false
        retry = nil
    }

    private mutating func endLine() -> ServerSentEvent? {
        var bytes = line
        line.removeAll(keepingCapacity: true)
        if isFirstLine {
            isFirstLine = false
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        }
        if bytes.isEmpty { return dispatch() }
        let text = String(decoding: bytes, as: UTF8.self)
        if text.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = text.firstIndex(of: ":") {
            field = text[..<colon]
            value = text[text.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = text[...]
            value = ""
        }
        switch field {
        case "event":
            eventType = String(value)
        case "data":
            if hasData { dataBuffer.append("\n") }
            dataBuffer.append(contentsOf: value)
            hasData = true
        case "id":
            if !value.contains("\u{0}") { lastEventID = String(value) }
        case "retry":
            if !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }) { retry = Int(value) }
        default:
            break
        }
        return nil
    }

    private mutating func dispatch() -> ServerSentEvent? {
        defer {
            eventType = ""
            dataBuffer = ""
            hasData = false
            retry = nil
        }
        // An event with no data is not dispatched (it only resets the type).
        guard hasData else { return nil }
        return ServerSentEvent(
            event: eventType.isEmpty ? "message" : eventType,
            data: dataBuffer,
            id: lastEventID,
            retry: retry
        )
    }
}

/// One complete stats frame of `GET /api/stats/stream`.
public struct HubStreamUpdate: Sendable, Equatable {
    /// `snapshot` (first frame of every connection) or `stats`.
    public var event: String
    /// Why the Hub broadcast (`snapshot`, `ingest`, `delete`, `subscriptions`, …).
    public var reason: String?
    public var stats: HubStats
    /// When the Hub sent the frame.
    public var at: Date?
}

/// Turns SSE events from the Hub into stats. Platform-neutral so it is
/// tested with captured frames on Linux.
public struct HubStreamDecoder: Sendable {
    /// Events that carry a complete stats payload. `freshness` is only sent
    /// to clients that ask for it with `x-token-monitor-stream: 2`, which the
    /// Kit does not.
    public static let statsEvents: Set<String> = ["snapshot", "stats"]

    public init() {}

    /// The update an event carries, or nil for heartbeats, other events and
    /// frames that are not JSON objects (one bad frame must not end a live
    /// stream; the next one is complete again).
    public func update(from event: ServerSentEvent) -> HubStreamUpdate? {
        guard Self.statsEvents.contains(event.event), let data = event.data.data(using: .utf8) else { return nil }
        guard let frame = try? JSONDecoder().decode(Frame.self, from: data) else { return nil }
        return HubStreamUpdate(event: event.event, reason: frame.reason, stats: frame.stats, at: frame.at)
    }

    public func stats(from event: ServerSentEvent) -> HubStats? {
        update(from: event)?.stats
    }

    private struct Frame: Decodable {
        let reason: String?
        let at: Date?
        let stats: HubStats

        private enum CodingKeys: String, CodingKey {
            case reason, at, stats, periods
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            reason = container.lenientString(.reason)
            at = container.lenientDate(.at)
            if let nested = container.lenientObject(.stats, as: HubStats.self) {
                stats = nested
            } else if container.contains(.periods) {
                // A bare stats object, in case a proxy or older Hub unwraps it.
                stats = try HubStats(from: decoder)
            } else {
                throw DecodingError.dataCorruptedError(forKey: .stats, in: container, debugDescription: "frame without stats")
            }
        }
    }
}

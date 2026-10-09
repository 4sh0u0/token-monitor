import Foundation
import XCTest
@testable import TokenMonitorKit

/// Fixtures captured from a real Node hub (`npm run hub`) after posting three
/// synthetic devices to `/api/ingest`: `studio-mac` and `build-box` fresh,
/// `old-laptop` stale (its record back-dated by 70 minutes). No real accounts.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let url = Bundle.module.url(
            forResource: parts[0],
            withExtension: parts.count > 1 ? parts[1] : nil,
            subdirectory: "Fixtures"
        ) else {
            throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name)"])
        }
        return try Data(contentsOf: url)
    }

    static func stats() throws -> HubStats {
        try HubStats.decode(from: data("stats.json"))
    }

    /// The stats fixture as a mutable JSON object, for variations.
    static func statsObject() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data("stats.json")) as? [String: Any])
    }

    static func decodeStats(_ object: Any) throws -> HubStats {
        try HubStats.decode(from: JSONSerialization.data(withJSONObject: object))
    }

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func date(_ iso: String) -> Date {
        ISODate.parse(iso)!
    }

    static let enUS = Locale(identifier: "en_US")
}

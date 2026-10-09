import Foundation

/// Port of `stableHash()` in `src/shared/macWidgetSnapshot.js`: two 32-bit
/// FNV-style lanes over UTF-16 code units. Used to derive identifiers from
/// private values (account keys) without carrying the value itself.
enum StableHash {
    static func hex(_ value: String, length: Int = 12) -> String {
        var first: UInt32 = 0x811c_9dc5
        var second: UInt32 = 0x9e37_79b9
        for unit in value.utf16 {
            let code = UInt32(unit)
            first = (first ^ code) &* 0x0100_0193
            second = (second ^ code) &* 0x85eb_ca6b
        }
        let digest = hex8(first) + hex8(second)
        return String(digest.prefix(length))
    }

    private static func hex8(_ value: UInt32) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 8 - digits.count)) + digits
    }
}

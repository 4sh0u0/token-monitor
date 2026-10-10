import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The cached daily USD rates, the desktop's `exchange-rates.json`
/// (`{rates, date, source, fetchedAt}`).
///
/// It encodes in that same shape, with `fetchedAt` in epoch milliseconds, so
/// it never depends on a coder's date strategy. Decoding is lenient: a
/// numeric-string `fetchedAt` or rate is accepted, a missing `fetchedAt`
/// reads as long ago, and rate values that are not numbers are dropped. A
/// payload without a `rates` object fails to decode, as the desktop treats
/// one as no cache.
public struct ExchangeRateCache: Codable, Equatable, Sendable {
    /// USD multipliers by upper-case ISO code, USD included (1).
    public var rates: [String: Double]
    /// The payload's own `date` (`yyyy-MM-dd`, UTC).
    public var date: String?
    /// The URL the rates came from.
    public var source: String?
    public var fetchedAt: Date

    public init(rates: [String: Double], date: String? = nil, source: String? = nil, fetchedAt: Date) {
        self.rates = rates
        self.date = date
        self.source = source
        self.fetchedAt = fetchedAt
    }

    /// `isCacheStale(cache, now)`. The cache is fresh when its `date` is
    /// today's UTC date or when it was fetched less than 24 hours ago.
    public func isStale(now: Date = Date()) -> Bool {
        if let date, !date.isEmpty, date == Self.todayUTC(now) { return false }
        let ageMs = Self.epochMilliseconds(now) - Self.epochMilliseconds(fetchedAt)
        if ageMs.isFinite, ageMs < 24 * 60 * 60 * 1000 { return false }
        return true
    }

    /// `isCacheStale` for an optional cache: no cache is stale.
    public static func isStale(_ cache: ExchangeRateCache?, now: Date = Date()) -> Bool {
        cache?.isStale(now: now) ?? true
    }

    /// `todayUtc(now)`: `now`'s UTC calendar date as `yyyy-MM-dd`.
    public static func todayUTC(_ now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let year = parts.year ?? 1970
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        func pad(_ value: Int, _ width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case rates, date, source, fetchedAt
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rateContainer = try container.nestedContainer(keyedBy: AnyKey.self, forKey: .rates)
        var rates: [String: Double] = [:]
        for key in rateContainer.allKeys {
            if let value = try? rateContainer.decode(Double.self, forKey: key) {
                rates[key.stringValue] = value
            } else if let text = try? rateContainer.decode(String.self, forKey: key), let value = JSNumber.number(text) {
                rates[key.stringValue] = value
            }
        }
        self.rates = rates
        self.date = try? container.decodeIfPresent(String.self, forKey: .date)
        self.source = try? container.decodeIfPresent(String.self, forKey: .source)
        var milliseconds: Double?
        if let value = try? container.decodeIfPresent(Double.self, forKey: .fetchedAt) {
            milliseconds = value
        } else if let text = try? container.decodeIfPresent(String.self, forKey: .fetchedAt) {
            milliseconds = JSNumber.number(text)
        }
        if let milliseconds, milliseconds.isFinite {
            self.fetchedAt = Date(timeIntervalSince1970: milliseconds / 1000)
        } else {
            self.fetchedAt = .distantPast
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rates, forKey: .rates)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(source, forKey: .source)
        let milliseconds = Self.epochMilliseconds(fetchedAt)
        if milliseconds.isFinite, abs(milliseconds) < 9e15 {
            try container.encode(Int64(milliseconds), forKey: .fetchedAt)
        }
    }

    /// Whole epoch milliseconds, as JavaScript's `Date.now()` reports them.
    static func epochMilliseconds(_ date: Date) -> Double {
        (date.timeIntervalSince1970 * 1000).rounded()
    }
}

/// Why `ExchangeRateClient.fetch` failed for a source.
public enum ExchangeRateError: Error, Equatable, Sendable {
    /// The response was not 2xx.
    case httpStatus(Int)
    /// The body was not a payload with every supported currency.
    case unexpectedPayload
    /// No source was given.
    case noSources
}

/// The daily USD rate fetch, a port of `src/shared/exchangeRates.js`.
/// It uses the same public CDN as the desktop and the same fallback mirror.
public enum ExchangeRateClient {
    /// The desktop's `SOURCES`, tried in order.
    public static let sources: [URL] = [
        URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json")!,
        URL(string: "https://latest.currency-api.pages.dev/v1/currencies/usd.json")!
    ]

    /// The desktop's per-source timeout.
    public static let defaultTimeout: TimeInterval = 8

    /// `parseUsdRates(json)` and the payload's `date`, from response bytes.
    /// nil unless every supported currency has a finite positive rate. A
    /// partial payload must not be cached as live.
    ///
    /// The bytes go through `JSONDecoder`, which reads every double exactly.
    /// `JSONSerialization` in swift-corelibs-foundation can be off by an ulp
    /// on 17-digit decimals.
    public static func parse(_ data: Data) -> (rates: [String: Double], date: String?)? {
        guard let payload = try? JSONDecoder().decode(RatePayload.self, from: data) else { return nil }
        guard let rates = completeRates({ payload.usd[$0]?.number }) else { return nil }
        return (rates, payload.date)
    }

    /// `parseUsdRates` on a decoded JSON value. It reads the lower-case
    /// `usd.<code>` keys, converts values as JavaScript's `Number()` would
    /// (`"31.2"` counts), and always sets USD to 1.
    public static func parse(json: Any?) -> (rates: [String: Double], date: String?)? {
        guard let object = json as? [String: Any], let usd = object["usd"] as? [String: Any] else { return nil }
        guard let rates = completeRates({ JSNumber.number(usd[$0]) }) else { return nil }
        return (rates, object["date"] as? String)
    }

    /// Every supported currency's rate from the lower-case `usd` keys, USD
    /// forced to 1; nil when any is missing, non-finite or not positive.
    private static func completeRates(_ lookup: (String) -> Double?) -> [String: Double]? {
        var rates: [String: Double] = [:]
        for currency in DisplayCurrency.allCases {
            if currency == .usd {
                rates[currency.rawValue] = 1
            } else if let value = lookup(currency.rawValue.lowercased()), CurrencyRates.isValidRate(value) {
                rates[currency.rawValue] = value
            } else {
                return nil
            }
        }
        return rates
    }

    /// `{date?, usd: {code: value}}`, with a non-string `date` read as none,
    /// as the desktop's `typeof json.date === 'string'` check does.
    private struct RatePayload: Decodable {
        var date: String?
        var usd: [String: RateValue]

        private enum CodingKeys: String, CodingKey { case date, usd }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            date = try? container.decodeIfPresent(String.self, forKey: .date)
            usd = try container.decode([String: RateValue].self, forKey: .usd)
        }
    }

    /// One `usd` entry as JavaScript's `Number()` reads it.
    private struct RateValue: Decodable {
        var number: Double?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                number = 0
            } else if let value = try? container.decode(Double.self) {
                number = value
            } else if let value = try? container.decode(Bool.self) {
                number = value ? 1 : 0
            } else if let value = try? container.decode(String.self) {
                number = JSNumber.number(value)
            } else {
                number = nil
            }
        }
    }

    /// `fetchRates()`: tries each source in order and returns the first
    /// complete payload as a cache stamped `now`.
    ///
    /// A source fails on a transport error, a non-2xx status or an incomplete
    /// payload. When every source fails, the last error is thrown, and the
    /// caller keeps its previous cache. Cancellation stops at once.
    public static func fetch(
        session: URLSession = .shared,
        timeout: TimeInterval = defaultTimeout,
        now: Date = Date(),
        sources: [URL] = ExchangeRateClient.sources
    ) async throws -> ExchangeRateCache {
        var lastError: Error = ExchangeRateError.noSources
        for url in sources {
            try Task.checkCancellation()
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) else { throw ExchangeRateError.httpStatus(status) }
                guard let parsed = parse(data) else { throw ExchangeRateError.unexpectedPayload }
                return ExchangeRateCache(rates: parsed.rates, date: parsed.date, source: url.absoluteString, fetchedAt: now)
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                lastError = error
            }
        }
        throw lastError
    }
}

/// The rate cache in the App Group defaults (`exchangeRates.v1`).
///
/// Only the iPhone app fetches. The watch receives the same bytes through
/// the WatchConnectivity preferences payload (`data()` / `save(data:)`).
public struct ExchangeRateStore: @unchecked Sendable {
    public static let key = "exchangeRates.v1"

    public let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The App Group store (standard defaults without the group).
    public static var shared: ExchangeRateStore {
        ExchangeRateStore(defaults: AppGroup.defaults)
    }

    /// The cached rates, nil when none are stored or the entry is unreadable.
    public func load() -> ExchangeRateCache? {
        guard let data = data() else { return nil }
        return try? JSONDecoder().decode(ExchangeRateCache.self, from: data)
    }

    /// The stored JSON bytes, as sent to the watch.
    public func data() -> Data? {
        defaults.data(forKey: Self.key)
    }

    public func save(_ cache: ExchangeRateCache) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(cache) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Stores bytes received from the phone. Returns false, and keeps the
    /// current entry, when they do not decode as a cache.
    @discardableResult
    public func save(data: Data) -> Bool {
        guard (try? JSONDecoder().decode(ExchangeRateCache.self, from: data)) != nil else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}

/// JavaScript's `Number(value)` for the JSON values a rate payload can hold.
/// It returns nil where `Number` gives NaN.
enum JSNumber {
    static func number(_ value: Any?) -> Double? {
        guard let value else { return nil }               // `Number(undefined)`
        if value is NSNull { return 0 }                   // `Number(null)`
        if let text = value as? String { return number(text) }
        if let double = value as? Double { return double } // NSNumber bridges here too
        if let int = value as? Int { return Double(int) }
        if let bool = value as? Bool { return bool ? 1 : 0 }
        return nil
    }

    /// `StringToNumber`: whitespace-trimmed; `""` is 0. It accepts decimal
    /// literals with an optional sign and exponent, `Infinity`, and
    /// unsigned `0x`/`0o`/`0b` integers.
    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: jsWhitespace)
        if trimmed.isEmpty { return 0 }
        switch trimmed {
        case "Infinity", "+Infinity": return .infinity
        case "-Infinity": return -.infinity
        default: break
        }
        let lower = trimmed.lowercased()
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where lower.hasPrefix(prefix) {
            let digits = lower.dropFirst(2)
            guard !digits.isEmpty else { return nil }
            var result = 0.0
            for character in digits {
                guard let digit = character.hexDigitValue, digit < radix else { return nil }
                result = result * Double(radix) + Double(digit)
            }
            return result
        }
        guard isDecimalLiteral(trimmed) else { return nil }
        return Double(trimmed)
    }

    /// `[+-]? (digits (. digits?)? | . digits) ([eE] [+-]? digits)?`
    private static func isDecimalLiteral(_ text: String) -> Bool {
        var bytes = Substring(text).utf8[...]
        func isDigit(_ byte: UInt8) -> Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) }
        func digitRun() -> Int {
            var count = 0
            while let byte = bytes.first, isDigit(byte) {
                bytes = bytes.dropFirst()
                count += 1
            }
            return count
        }
        if let sign = bytes.first, sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") { bytes = bytes.dropFirst() }
        var mantissaDigits = digitRun()
        if bytes.first == UInt8(ascii: ".") {
            bytes = bytes.dropFirst()
            mantissaDigits += digitRun()
        }
        guard mantissaDigits > 0 else { return false }
        if let marker = bytes.first, marker == UInt8(ascii: "e") || marker == UInt8(ascii: "E") {
            bytes = bytes.dropFirst()
            if let sign = bytes.first, sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") { bytes = bytes.dropFirst() }
            guard digitRun() > 0 else { return false }
        }
        return bytes.isEmpty
    }

    /// ECMAScript `WhiteSpace` and `LineTerminator`.
    private static let jsWhitespace = CharacterSet(charactersIn:
        "\u{09}\u{0A}\u{0B}\u{0C}\u{0D}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}"
        + "\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
}

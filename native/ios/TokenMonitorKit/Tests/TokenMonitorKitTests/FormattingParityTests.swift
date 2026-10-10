import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TokenMonitorKit

/// Loads the v2 goldens rendered by running the desktop modules
/// (`Fixtures/v2/golden/*.json`, see `Fixtures/v2/README.txt`).
private enum FormattingGolden {
    static func object(_ name: String) throws -> [String: Any] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/v2/golden") else {
            throw NSError(domain: "FormattingGolden", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing golden \(name).json"])
        }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url), options: [.fragmentsAllowed])
        return try XCTUnwrap(json as? [String: Any], name)
    }

    /// A JSON number as a Double; nil for null, strings and other values.
    static func number(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull), !(value is String) else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        return nil
    }

    static func numbers(_ value: Any?) throws -> [Double?] {
        try XCTUnwrap(value as? [Any], "expected an array").map(number)
    }

    static func rows(_ value: Any?) throws -> [[String: Any]] {
        try XCTUnwrap(value as? [[String: Any]], "expected rows")
    }

    static func strings(_ value: Any?) throws -> [String] {
        try XCTUnwrap(value as? [String], "expected strings")
    }

    /// The desktop options object as Swift arguments. `fractionDigits` of
    /// `null`, `''` or `'auto'` is nil; `compact: false` turns units off.
    struct Options {
        var fractionDigits: Int?
        var keepTrailingZeros = false
        var style: CompactNumberFormat.Style = .standard
        var useUnits = true
    }

    static func options(_ value: Any?) -> Options {
        var options = Options()
        guard let dict = value as? [String: Any] else { return options }
        if let digits = number(dict["fractionDigits"]) {
            options.fractionDigits = Int(JSCompat.round(digits))
        }
        options.keepTrailingZeros = (dict["keepTrailingZeros"] as? Bool) == true
        options.style = (dict["style"] as? String) == "tray" ? .tray : .standard
        if let compact = dict["compact"] as? Bool { options.useUnits = compact }
        return options
    }

    static func units(_ value: Any?) -> CompactTokenUnits {
        CompactNumberFormat.normalizeUnits(value as? String)
    }

    /// A `{CODE: value}` map with values read the way JavaScript's
    /// `Number()` reads them; NaN where it would be NaN.
    static func rateMap(_ value: Any?) -> [String: Double] {
        guard let dict = value as? [String: Any] else { return [:] }
        return dict.mapValues { JSNumber.number($0) ?? .nan }
    }
}

final class FormattingParityTests: XCTestCase {
    // MARK: compact-tokens.json

    func testCompactTokensDesktopTestVectors() throws {
        let golden = try FormattingGolden.object("compact-tokens")
        let vectors = try FormattingGolden.rows(golden["testVectors"])
        XCTAssertEqual(vectors.count, 23)
        for vector in vectors {
            let args = try XCTUnwrap(vector["args"] as? [Any])
            let value = try XCTUnwrap(FormattingGolden.number(args[0]))
            let units = FormattingGolden.units(args.count > 1 ? args[1] : nil)
            let language = args.count > 2 ? try XCTUnwrap(args[2] as? String) : "en"
            let options = FormattingGolden.options(args.count > 3 ? args[3] : nil)
            let expected = try XCTUnwrap(vector["output"] as? String)
            let actual: String
            switch vector["fn"] as? String {
            case "formatCompactTokens":
                actual = CompactNumberFormat.tokens(value, units: units, language: language, fractionDigits: options.fractionDigits,
                                                    keepTrailingZeros: options.keepTrailingZeros, style: options.style)
            default:
                actual = CompactNumberFormat.format(value, units: units, language: language, fractionDigits: options.fractionDigits,
                                                    keepTrailingZeros: options.keepTrailingZeros, style: options.style)
            }
            XCTAssertEqual(actual, expected, "\(vector)")
        }
    }

    func testCompactTokensGrid() throws {
        let golden = try FormattingGolden.object("compact-tokens")
        let values = try FormattingGolden.numbers(golden["values"])
        for row in try FormattingGolden.rows(golden["formatCompactTokens"]) {
            let units = FormattingGolden.units(row["units"])
            let language = try XCTUnwrap(row["locale"] as? String)
            let outputs = try FormattingGolden.strings(row["outputs"])
            XCTAssertEqual(outputs.count, values.count)
            for (value, expected) in zip(values, outputs) {
                let value = try XCTUnwrap(value)
                XCTAssertEqual(CompactNumberFormat.tokens(value, units: units, language: language), expected, "\(value) \(units) \(language)")
                if value == value.rounded(), abs(value) < 1e15 {
                    XCTAssertEqual(CompactNumberFormat.tokens(Int(value), units: units, language: language), expected, "Int \(value) \(language)")
                }
            }
        }
    }

    func testCompactValueGrid() throws {
        let golden = try FormattingGolden.object("compact-tokens")
        let values = try FormattingGolden.numbers(golden["fractionalValues"])
        for row in try FormattingGolden.rows(golden["formatCompactValue"]) {
            let units = FormattingGolden.units(row["units"])
            let language = try XCTUnwrap(row["locale"] as? String)
            for (value, expected) in zip(values, try FormattingGolden.strings(row["outputs"])) {
                let value = try XCTUnwrap(value)
                XCTAssertEqual(CompactNumberFormat.format(value, units: units, language: language), expected, "\(value) \(language)")
            }
        }
    }

    func testCompactOptionsGrid() throws {
        let golden = try FormattingGolden.object("compact-tokens")
        let values = try FormattingGolden.numbers(golden["optionValues"])
        let rows = try FormattingGolden.rows(golden["withOptions"])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let units = FormattingGolden.units(row["units"])
            let language = try XCTUnwrap(row["locale"] as? String)
            let options = FormattingGolden.options(row["options"])
            let isTokens = (row["fn"] as? String) == "formatCompactTokens"
            for (value, expected) in zip(values, try FormattingGolden.strings(row["outputs"])) {
                let value = try XCTUnwrap(value)
                let actual = isTokens
                    ? CompactNumberFormat.tokens(value, units: units, language: language, fractionDigits: options.fractionDigits,
                                                 keepTrailingZeros: options.keepTrailingZeros, style: options.style)
                    : CompactNumberFormat.format(value, units: units, language: language, fractionDigits: options.fractionDigits,
                                                 keepTrailingZeros: options.keepTrailingZeros, style: options.style)
                XCTAssertEqual(actual, expected, "\(row["fn"] ?? "") \(value) \(language) \(row["options"] ?? "")")
            }
        }
    }

    func testUnitSystemTable() throws {
        let golden = try FormattingGolden.object("compact-tokens")
        let rows = try FormattingGolden.rows(golden["units"])
        XCTAssertEqual(rows.count, 42)
        for row in rows {
            let raw = row["units"] as? String
            let language = try XCTUnwrap(row["locale"] as? String)
            let units = CompactNumberFormat.normalizeUnits(raw)
            let context = "\(raw ?? "nil") \(language)"
            XCTAssertEqual(units.rawValue, row["normalized"] as? String, context)
            XCTAssertEqual(CompactNumberFormat.supportsLocalizedUnits(language), row["supportsLocalized"] as? Bool, context)
            XCTAssertEqual(CompactNumberFormat.effectiveUnits(units, language: language).rawValue, row["effective"] as? String, context)
            XCTAssertEqual(CompactNumberFormat.threshold(units, language: language), FormattingGolden.number(row["threshold"]), context)
        }
    }

    func testLocalizedSuffixesFollowTheUILanguage() {
        // D-UNITS-LANG: the iOS UI language codes map like the desktop's.
        // Edge tags computed with node against compactTokens.js.
        let cases: [(String, String)] = [
            ("zh-Hans", "1.23万"), ("zh-Hant", "1.23萬"), ("zh-Hans-CN", "1.23万"), ("zh-HK", "1.23萬"),
            ("zh-SG", "1.23万"), ("zh_TW", "1.23萬"), ("ja", "1.23万"), ("ko", "1.23만"), ("en", "12.3K"), ("pt-BR", "12.3K"),
            ("zh-Latn-MY", "1.23万"), ("zh-x_y-cn", "1.23万"), ("zh-ä-cn", "1.23萬"), ("zh--cn", "1.23萬"),
            ("zh-cnx", "1.23萬"), ("zh-hk-sg-x", "1.23万")
        ]
        for (language, expected) in cases {
            XCTAssertEqual(CompactNumberFormat.tokens(12_345, units: .localized, language: language), expected, language)
        }
        XCTAssertEqual(CompactNumberFormat.tokens(295_116_445, units: .localized, language: "zh-Hans"), "2.95亿")
        XCTAssertEqual(CompactNumberFormat.tokens(295_116_445, units: .localized, language: "ja"), "2.95億")
    }

    func testCompactEdgeValuesMatchJavaScript() {
        // Computed with node: formatCompactValue(NaN) → "0", Infinity → "InfinityB",
        // -0 with fractionDigits 2 → "0.00", 1e12 → "1000B".
        XCTAssertEqual(CompactNumberFormat.format(.nan), "0")
        XCTAssertEqual(CompactNumberFormat.format(.infinity), "InfinityB")
        XCTAssertEqual(CompactNumberFormat.format(-0.0, fractionDigits: 2), "0.00")
        XCTAssertEqual(CompactNumberFormat.tokens(1_000_000_000_000), "1000B")
        XCTAssertEqual(CompactNumberFormat.tokens(-999_950), "-1M")
    }

    // MARK: compact-money.json

    func testCurrencyConversionAndFormatting() throws {
        let golden = try FormattingGolden.object("compact-money")
        let values = try FormattingGolden.numbers(golden["values"])
        let byRates = try XCTUnwrap(golden["currencyFromUsd"] as? [String: Any])
        for name in ["builtIn", "configured"] {
            let entry = try XCTUnwrap(byRates[name] as? [String: Any])
            let rates = CurrencyRates(multipliers: FormattingGolden.rateMap(entry["rates"]))
            for row in try FormattingGolden.rows(entry["rows"]) {
                let currency = try XCTUnwrap(DisplayCurrency(rawValue: row["currency"] as? String ?? ""))
                let converted = try FormattingGolden.numbers(row["convertUsd"])
                let formatted = try FormattingGolden.strings(row["formatCurrencyFromUsd"])
                for (index, value) in values.enumerated() {
                    let value = try XCTUnwrap(value)
                    let context = "\(name) \(currency) \(value)"
                    XCTAssertEqual(CurrencyFormat.convert(usd: value, to: currency, rates: rates), converted[index], context)
                    XCTAssertEqual(CurrencyFormat.format(usd: value, currency: currency, rates: rates), formatted[index], context)
                }
            }
        }
    }

    func testCompactCurrencyGrid() throws {
        let golden = try FormattingGolden.object("compact-money")
        let values = try FormattingGolden.numbers(golden["values"])
        let rates = CurrencyRates(multipliers: FormattingGolden.rateMap(golden["configuredRates"]))
        let rows = try FormattingGolden.rows(golden["compact"])
        XCTAssertEqual(rows.count, 20)
        for row in rows {
            let currency = try XCTUnwrap(DisplayCurrency(rawValue: row["currency"] as? String ?? ""))
            let units = FormattingGolden.units(row["units"])
            let language = try XCTUnwrap(row["locale"] as? String)
            for (value, expected) in zip(values, try FormattingGolden.strings(row["outputs"])) {
                let value = try XCTUnwrap(value)
                XCTAssertEqual(
                    CurrencyFormat.compact(usd: value, currency: currency, rates: rates, units: units, language: language),
                    expected, "\(currency) \(units) \(language) \(value)"
                )
            }
        }
    }

    func testCompactCurrencyOptions() throws {
        let golden = try FormattingGolden.object("compact-money")
        let values = try FormattingGolden.numbers(golden["optionValues"])
        let rates = CurrencyRates(multipliers: FormattingGolden.rateMap(golden["configuredRates"]))
        for row in try FormattingGolden.rows(golden["options"]) {
            let currency = try XCTUnwrap(DisplayCurrency(rawValue: row["currency"] as? String ?? ""))
            let units = FormattingGolden.units(row["units"])
            let language = try XCTUnwrap(row["locale"] as? String)
            let options = FormattingGolden.options(row["options"])
            for (value, expected) in zip(values, try FormattingGolden.strings(row["outputs"])) {
                let value = try XCTUnwrap(value)
                let actual = CurrencyFormat.compact(
                    usd: value, currency: currency, rates: rates, units: units, language: language,
                    fractionDigits: options.fractionDigits, keepTrailingZeros: options.keepTrailingZeros, useUnits: options.useUnits
                )
                XCTAssertEqual(actual, expected, "\(currency) \(language) \(row["options"] ?? "") \(value)")
            }
        }
    }

    func testCompactCurrencyDesktopTestVectors() throws {
        let golden = try FormattingGolden.object("compact-money")
        let vectors = try FormattingGolden.rows(golden["testVectors"])
        XCTAssertEqual(vectors.count, 18)
        for vector in vectors {
            let args = try XCTUnwrap(vector["args"] as? [Any])
            let value = try XCTUnwrap(FormattingGolden.number(args[0]))
            let currency = CurrencyFormat.normalize(args[1] as? String)
            let units = FormattingGolden.units(args[2])
            let language = try XCTUnwrap(args[3] as? String)
            let options = FormattingGolden.options(args.count > 4 ? args[4] : nil)
            // configureRates(map) overlays the floors, which is what
            // `multiplier(for:)` falls back to.
            let rates = CurrencyRates(multipliers: FormattingGolden.rateMap(vector["rates"]))
            let actual = CurrencyFormat.compact(
                usd: value, currency: currency, rates: rates, units: units, language: language,
                fractionDigits: options.fractionDigits, keepTrailingZeros: options.keepTrailingZeros, useUnits: options.useUnits
            )
            XCTAssertEqual(actual, vector["output"] as? String, "\(vector)")
        }
    }

    func testCurrencyNormalizationAndFloors() {
        XCTAssertEqual(CurrencyFormat.normalize(nil), .usd)
        XCTAssertEqual(CurrencyFormat.normalize(""), .usd)
        XCTAssertEqual(CurrencyFormat.normalize(" twd "), .twd)
        XCTAssertEqual(CurrencyFormat.normalize("jpy"), .usd)
        XCTAssertEqual(CurrencyFormat.normalize("jpy", fallback: .cny), .cny)
        // currency.test.js: built-in defaults and the configureRates overlay.
        XCTAssertEqual(CurrencyFormat.format(usd: 1, currency: .usd), "$1.0000")
        XCTAssertEqual(CurrencyFormat.format(usd: 1, currency: .twd), "NT$31.50")
        XCTAssertEqual(CurrencyFormat.format(usd: 1, currency: .hkd), "HK$7.80")
        XCTAssertEqual(CurrencyFormat.format(usd: 1, currency: .cny), "¥6.80")
        let overlay = CurrencyRates(multipliers: ["CNY": 7.25, "TWD": 0, "HKD": -1, "JPY": 150])
        XCTAssertEqual(CurrencyFormat.convert(usd: 1, to: .cny, rates: overlay), 7.25)
        XCTAssertEqual(CurrencyFormat.convert(usd: 1, to: .twd, rates: overlay), 31.5)
        XCTAssertEqual(CurrencyFormat.convert(usd: 1, to: .hkd, rates: overlay), 7.8)
        XCTAssertEqual(CurrencyFormat.convert(usd: .nan, to: .cny, rates: overlay), 0)
    }

    func testBalanceFormatting() throws {
        let golden = try FormattingGolden.object("compact-money")
        let values = try XCTUnwrap(golden["balanceValues"] as? [Any]).map(FormattingGolden.number)
        let rows = try FormattingGolden.rows(golden["balanceFormat"])
        XCTAssertEqual(rows.count, 9)
        for row in rows {
            let currency = row["currency"] as? String
            for (value, expected) in zip(values, try FormattingGolden.strings(row["outputs"])) {
                XCTAssertEqual(BalanceFormat.format(amount: value, currency: currency), expected, "\(currency ?? "nil") \(value.map(String.init(describing:)) ?? "nil")")
            }
        }
        XCTAssertEqual(BalanceFormat.format(amount: .nan, currency: "USD"), "")
        // limitBalanceDisplay.test.js
        XCTAssertEqual(BalanceFormat.format(amount: 7.006, currency: "USD"), "$7.01")
        XCTAssertEqual(BalanceFormat.format(amount: 12.5, currency: "EUR"), "EUR 12.50")
        XCTAssertEqual(BalanceFormat.format(amount: 680, currency: "CREDITS"), "680.00")
    }

    func testCompactBalanceFormatting() throws {
        let golden = try FormattingGolden.object("compact-money")
        let values = try FormattingGolden.numbers(golden["balanceCompactValues"])
        let rows = try FormattingGolden.rows(golden["balanceCompact"])
        XCTAssertEqual(rows.count, 20)
        for row in rows {
            let currency = row["currency"] as? String
            let units = FormattingGolden.units(row["units"])
            let language = try XCTUnwrap(row["locale"] as? String)
            for (value, expected) in zip(values, try FormattingGolden.strings(row["outputs"])) {
                XCTAssertEqual(BalanceFormat.compact(amount: value, currency: currency, units: units, language: language), expected,
                               "\(currency ?? "nil") \(units) \(language) \(value ?? .nan)")
            }
        }
        // limitBalanceDisplay.test.js
        XCTAssertEqual(BalanceFormat.compact(amount: 99_999.99, currency: "USD"), "$99999.99")
        XCTAssertEqual(BalanceFormat.compact(amount: 1_250_000, currency: "USD"), "$1.25M")
        XCTAssertEqual(BalanceFormat.compact(amount: 1_250_000, currency: "CREDITS"), "1.25M")
        XCTAssertEqual(BalanceFormat.compact(amount: 1_250_000, currency: "USD", units: .localized, language: "zh-TW"), "$125萬")
        XCTAssertEqual(BalanceFormat.compact(amount: 123_456_789, currency: "USD", units: .localized, language: "zh-TW"), "$1.23億")
        XCTAssertEqual(BalanceFormat.compact(amount: 1_250_000, currency: "USD", units: .localized, language: "en"), "$1.25M")
        XCTAssertEqual(BalanceFormat.compact(amount: nil, currency: "USD"), "")
    }

    func testEnglishCompactNotationMatchesICU() {
        // new Intl.NumberFormat('en-US', { notation: 'compact', maximumFractionDigits: 2 })
        // in Node 22 / ICU 77. ICU rounds the shortest decimal half away from
        // zero, so 100005 keeps its 5 (toFixed would give 100K).
        let cases: [(Double, String)] = [
            (100_005, "100.01K"), (123_456.789, "123.46K"), (999_995, "1M"), (999_994.9, "999.99K"),
            (999_999.999, "1M"), (1e15, "1000T"), (1.5e16, "15,000T"), (12_345_678_901_234_567_168, "12,345,678.9T"),
            (-250_000, "-250K"), (0, "0"), (267_500, "267.5K"), (100_000.5, "100K"), (999.995, "1K"),
            (0.005, "0.01"), (1234, "1.23K"), (1_005_000, "1.01M"), (5e-7, "0"), (99_999.995, "100K")
        ]
        for (value, expected) in cases {
            XCTAssertEqual(IntlNumberFormat.englishCompact(value), expected, "\(value)")
        }
    }

    // MARK: exchange-rates.json

    func testExchangeRateSourcesAndFloors() throws {
        let golden = try FormattingGolden.object("exchange-rates")
        XCTAssertEqual(ExchangeRateClient.sources.map(\.absoluteString), try FormattingGolden.strings(golden["sources"]))
        XCTAssertEqual(CurrencyRates.floors, FormattingGolden.rateMap(golden["builtInFloors"]))
        XCTAssertEqual(ExchangeRateCache.todayUTC(Fixture.date("2026-10-10T16:30:00Z")), golden["todayUtc"] as? String)
        XCTAssertEqual(ExchangeRateCache.todayUTC(Fixture.date("2026-10-10T23:59:59Z")), "2026-10-10")
        XCTAssertEqual(ExchangeRateCache.todayUTC(Fixture.date("2026-10-11T00:00:00Z")), "2026-10-11")
    }

    func testParseUsdRates() throws {
        let golden = try FormattingGolden.object("exchange-rates")
        let cases = try XCTUnwrap(golden["parse"] as? [String: Any])
        XCTAssertEqual(cases.count, 10)
        for (name, value) in cases {
            let entry = try XCTUnwrap(value as? [String: Any])
            let payload = entry["payload"]
            let data = try JSONSerialization.data(withJSONObject: payload ?? NSNull(), options: [.fragmentsAllowed])
            let parsed = ExchangeRateClient.parse(data)
            if let expected = entry["rates"] as? [String: Any] {
                let result = try XCTUnwrap(parsed, name)
                XCTAssertEqual(result.rates, FormattingGolden.rateMap(expected), name)
                XCTAssertEqual(result.date, entry["date"] as? String, name)
            } else {
                XCTAssertNil(parsed, name)
            }
            XCTAssertEqual(ExchangeRateClient.parse(json: payload)?.rates, parsed?.rates, name)
        }
        // exchangeRates.test.js
        XCTAssertNil(ExchangeRateClient.parse(json: [String: Any]()))
        XCTAssertNil(ExchangeRateClient.parse(json: ["usd": [String: Any]()]))
        XCTAssertNil(ExchangeRateClient.parse(json: ["usd": ["cny": 6.778, "twd": 31.67]]))
        XCTAssertNil(ExchangeRateClient.parse(Data("not json".utf8)))

        // Full-precision CDN values survive (JSONSerialization on Linux is an
        // ulp off here), a non-string date is dropped as on the desktop, and
        // values convert like `Number()`.
        let precise = Data(#"{"date":20261010,"usd":{"twd":31.672485910000002,"hkd":"7.8","cny":true,"eur":null}}"#.utf8)
        let parsed = try XCTUnwrap(ExchangeRateClient.parse(precise))
        XCTAssertEqual(parsed.rates["TWD"], Double("31.672485910000002"))
        XCTAssertEqual(parsed.rates["HKD"], 7.8)
        XCTAssertEqual(parsed.rates["CNY"], 1)
        XCTAssertNil(parsed.date)
        XCTAssertNil(ExchangeRateClient.parse(Data(#"{"usd":{"twd":31,"hkd":7.8,"cny":null}}"#.utf8)))
        XCTAssertNil(ExchangeRateClient.parse(Data(#"{"usd":[31,7.8,7.1]}"#.utf8)))
    }

    func testResolvePrecedenceOverrideThenFetchedThenFloor() throws {
        let golden = try FormattingGolden.object("exchange-rates")
        for entry in try FormattingGolden.rows(golden["resolve"]) {
            let fetched = FormattingGolden.rateMap(entry["fetched"])
            let overrides = FormattingGolden.rateMap(entry["overrides"])
            var expected = FormattingGolden.rateMap(entry["output"])
            // Deviation (documented on `resolve`): iOS ignores a USD override.
            if overrides["USD"] != nil { expected["USD"] = 1 }
            XCTAssertEqual(CurrencyRates.resolve(fetched: fetched, overrides: overrides).effectiveMultipliers, expected, "\(entry)")
        }

        let effective = try XCTUnwrap(golden["effectiveRates"] as? [String: Any])
        let parsed = try XCTUnwrap(ExchangeRateClient.parse(json: effective["fetched"]))
        let resolved = CurrencyRates.resolve(fetched: parsed.rates, overrides: FormattingGolden.rateMap(effective["overrides"]), fetchedDate: parsed.date)
        XCTAssertEqual(resolved.effectiveMultipliers, FormattingGolden.rateMap(effective["rates"]))
        XCTAssertEqual(resolved.origin(for: .hkd), .manual)
        XCTAssertEqual(resolved.origin(for: .twd), .fetched, "a zero override is ignored")
        XCTAssertEqual(resolved.origin(for: .cny), .fetched, "a negative override is ignored")
        XCTAssertEqual(resolved.origin(for: .usd), .builtIn)
        XCTAssertEqual(resolved.fetchedDate, "2026-10-10")

        // currency.test.js
        let desktop = CurrencyRates.resolve(fetched: ["CNY": 6.9, "TWD": 31.2], overrides: ["CNY": 7.25])
        XCTAssertEqual(desktop.effectiveMultipliers, ["USD": 1, "TWD": 31.2, "HKD": 7.8, "CNY": 7.25])
        XCTAssertEqual(desktop.origin(for: .hkd), .builtIn)
        let invalid = CurrencyRates.resolve(fetched: ["CNY": 0], overrides: ["CNY": .nan, "TWD": -3])
        XCTAssertEqual(invalid.multiplier(for: .cny), 6.8)
        XCTAssertEqual(invalid.multiplier(for: .twd), 31.5)

        let cache = ExchangeRateCache(rates: parsed.rates, date: "2026-10-01", source: "x", fetchedAt: Date(timeIntervalSince1970: 0))
        let fromStaleCache = CurrencyRates.resolve(cache: cache, overrides: [:])
        XCTAssertEqual(fromStaleCache.multiplier(for: .twd), 30.4821, "a stale cache still beats the floor")
        XCTAssertEqual(fromStaleCache.fetchedDate, "2026-10-01")
        XCTAssertEqual(CurrencyRates.resolve(cache: nil, overrides: [:]).effectiveMultipliers, CurrencyRates.floors)
    }

    func testCacheStaleness() throws {
        let golden = try FormattingGolden.object("exchange-rates")
        let cases = try FormattingGolden.rows(golden["staleness"])
        XCTAssertEqual(cases.count, 7)
        for entry in cases {
            let name = entry["name"] as? String ?? "?"
            let now = Fixture.date(try XCTUnwrap(entry["now"] as? String))
            var cache: ExchangeRateCache?
            if let object = entry["cache"] as? [String: Any] {
                cache = try? JSONDecoder().decode(ExchangeRateCache.self, from: JSONSerialization.data(withJSONObject: object))
            }
            XCTAssertEqual(ExchangeRateCache.isStale(cache, now: now), entry["stale"] as? Bool, name)
        }
        // exchangeRates.test.js
        let now = Fixture.date("2026-06-22T12:00:00Z")
        let rates = ["CNY": 6.78]
        XCTAssertFalse(ExchangeRateCache(rates: rates, date: "2026-06-22", fetchedAt: .distantPast).isStale(now: now))
        XCTAssertFalse(ExchangeRateCache(rates: rates, date: "2026-06-21", fetchedAt: now.addingTimeInterval(-3600)).isStale(now: now))
        XCTAssertTrue(ExchangeRateCache(rates: rates, date: "2026-06-20", fetchedAt: now.addingTimeInterval(-26 * 3600)).isStale(now: now))
        XCTAssertTrue(ExchangeRateCache(rates: rates, date: nil, fetchedAt: now.addingTimeInterval(-24 * 3600)).isStale(now: now))
        XCTAssertFalse(ExchangeRateCache(rates: rates, date: nil, fetchedAt: now.addingTimeInterval(-24 * 3600 + 0.001)).isStale(now: now))
    }

    func testCacheCodableRoundTripsTheDesktopShape() throws {
        let cache = ExchangeRateCache(
            rates: ["USD": 1, "TWD": 30.4821, "HKD": 7.7712, "CNY": 7.1234],
            date: "2026-10-10",
            source: ExchangeRateClient.sources[0].absoluteString,
            fetchedAt: Date(timeIntervalSince1970: 1_791_541_800)
        )
        let data = try JSONEncoder().encode(cache)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(FormattingGolden.number(object["fetchedAt"]), 1_791_541_800_000, "epoch milliseconds, like the desktop")
        XCTAssertEqual(try JSONDecoder().decode(ExchangeRateCache.self, from: data), cache)

        let lenient = Data(#"{"rates":{"CNY":"7.2","TWD":31,"bad":[1]},"fetchedAt":"1791541800000"}"#.utf8)
        let decoded = try JSONDecoder().decode(ExchangeRateCache.self, from: lenient)
        XCTAssertEqual(decoded.rates, ["CNY": 7.2, "TWD": 31])
        XCTAssertEqual(decoded.fetchedAt, Date(timeIntervalSince1970: 1_791_541_800))
        XCTAssertNil(decoded.date)
        XCTAssertThrowsError(try JSONDecoder().decode(ExchangeRateCache.self, from: Data(#"{"date":"2026-10-10"}"#.utf8)))
        let noFetchedAt = try JSONDecoder().decode(ExchangeRateCache.self, from: Data(#"{"rates":{}}"#.utf8))
        XCTAssertEqual(noFetchedAt.fetchedAt, .distantPast)
    }

    func testJavaScriptNumberParsing() {
        let cases: [(String, Double?)] = [
            ("31.2", 31.2), ("  7.5\n", 7.5), ("", 0), ("   ", 0), ("x", nil), ("1e3", 1000), (".5", 0.5), ("5.", 5),
            ("+2", 2), ("-2", -2), ("0x10", 16), ("0b11", 3), ("0o17", 15), ("Infinity", .infinity), ("inf", nil),
            ("nan", nil), ("1e", nil), ("0x", nil), ("-0x10", nil), ("1_000", nil), ("0x1p3", nil)
        ]
        for (text, expected) in cases {
            XCTAssertEqual(JSNumber.number(text), expected, text)
        }
        XCTAssertNil(JSNumber.number(nil as Any?))
        XCTAssertEqual(JSNumber.number(NSNull()), 0)
        XCTAssertEqual(JSNumber.number(NSNumber(value: 7.1)), 7.1)
        XCTAssertEqual(JSNumber.number(true), 1)
        XCTAssertNil(JSNumber.number([1]))
    }

    // MARK: Fetch and store

    private func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExchangeRateStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    private let sampleBody = Data(#"{"date":"2026-06-22","usd":{"cny":6.778,"twd":31.67,"hkd":7.839,"jpy":150}}"#.utf8)
    private let primary = URL(string: "https://rates.example.test/a/usd.json")!
    private let fallback = URL(string: "https://rates.example.test/b/usd.json")!

    override func tearDown() {
        ExchangeRateStubProtocol.reset()
        super.tearDown()
    }

    func testFetchUsesTheFirstWorkingSource() async throws {
        ExchangeRateStubProtocol.stub(primary, status: 200, body: sampleBody)
        ExchangeRateStubProtocol.stub(fallback, status: 200, body: Data("{}".utf8))
        let now = Fixture.date("2026-06-22T12:00:00Z")
        let cache = try await ExchangeRateClient.fetch(session: stubbedSession(), timeout: 3, now: now, sources: [primary, fallback])
        XCTAssertEqual(cache.rates, ["USD": 1, "CNY": 6.778, "TWD": 31.67, "HKD": 7.839])
        XCTAssertEqual(cache.date, "2026-06-22")
        XCTAssertEqual(cache.source, primary.absoluteString)
        XCTAssertEqual(cache.fetchedAt, now)
        XCTAssertEqual(ExchangeRateStubProtocol.requestedURLs, [primary])
        XCTAssertEqual(ExchangeRateStubProtocol.lastTimeout, 3)
    }

    func testFetchFallsBackOnHTTPErrorsAndPartialPayloads() async throws {
        ExchangeRateStubProtocol.stub(primary, status: 503, body: sampleBody)
        ExchangeRateStubProtocol.stub(fallback, status: 200, body: sampleBody)
        let fromFallback = try await ExchangeRateClient.fetch(session: stubbedSession(), sources: [primary, fallback])
        XCTAssertEqual(fromFallback.source, fallback.absoluteString)
        XCTAssertEqual(ExchangeRateStubProtocol.requestedURLs, [primary, fallback])

        ExchangeRateStubProtocol.reset()
        ExchangeRateStubProtocol.stub(primary, status: 200, body: Data(#"{"date":"2026-06-22","usd":{"cny":6.778}}"#.utf8))
        ExchangeRateStubProtocol.stub(fallback, status: 200, body: sampleBody)
        let afterPartial = try await ExchangeRateClient.fetch(session: stubbedSession(), sources: [primary, fallback])
        XCTAssertEqual(afterPartial.source, fallback.absoluteString, "a partial payload must not stop the chain")
    }

    func testFetchThrowsWhenEverySourceFails() async {
        ExchangeRateStubProtocol.stub(primary, status: 200, body: Data(#"{"usd":{"cny":6.778}}"#.utf8))
        // `fallback` is not stubbed: the transport fails.
        do {
            _ = try await ExchangeRateClient.fetch(session: stubbedSession(), sources: [primary, fallback])
            XCTFail("expected an error")
        } catch {
            XCTAssertFalse(error is ExchangeRateError, "the last (transport) error is rethrown: \(error)")
        }
        do {
            _ = try await ExchangeRateClient.fetch(session: stubbedSession(), sources: [primary])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ExchangeRateError, .unexpectedPayload)
        }
        do {
            _ = try await ExchangeRateClient.fetch(session: stubbedSession(), sources: [])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ExchangeRateError, .noSources)
        }
    }

    func testStoreRoundTripAndWatchBytes() throws {
        let suite = "ExchangeRateStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ExchangeRateStore(defaults: defaults)
        XCTAssertNil(store.load())
        XCTAssertEqual(ExchangeRateStore.key, "exchangeRates.v1")

        let cache = ExchangeRateCache(rates: ["USD": 1, "CNY": 7.1], date: "2026-10-10", source: "s", fetchedAt: Date(timeIntervalSince1970: 1_791_541_800))
        store.save(cache)
        XCTAssertEqual(store.load(), cache)
        let bytes = try XCTUnwrap(store.data())

        let watchSuite = suite + ".watch"
        let watchDefaults = try XCTUnwrap(UserDefaults(suiteName: watchSuite))
        defer { watchDefaults.removePersistentDomain(forName: watchSuite) }
        let watchStore = ExchangeRateStore(defaults: watchDefaults)
        XCTAssertFalse(watchStore.save(data: Data("junk".utf8)))
        XCTAssertNil(watchStore.load())
        XCTAssertTrue(watchStore.save(data: bytes))
        XCTAssertEqual(watchStore.load(), cache)

        store.clear()
        XCTAssertNil(store.load())
    }
}

final class DisplayFormatterTests: XCTestCase {
    func testUnitsFollowTheUILanguage() {
        var preferences = DisplayPreferences.defaults
        preferences.compactTokenUnits = .localized
        let hans = DisplayFormatter(preferences: preferences, languageIdentifier: "zh-Hans")
        XCTAssertEqual(hans.effectiveUnits, .localized)
        XCTAssertTrue(hans.supportsLocalizedUnits)
        XCTAssertEqual(hans.compactThreshold, 10_000)
        XCTAssertEqual(hans.compactTokens(12_345), "1.23万")
        XCTAssertEqual(DisplayFormatter(preferences: preferences, languageIdentifier: "zh-Hant").compactTokens(12_345), "1.23萬")
        XCTAssertEqual(DisplayFormatter(preferences: preferences, languageIdentifier: "ja").compactTokens(295_116_445), "2.95億")
        XCTAssertEqual(DisplayFormatter(preferences: preferences, languageIdentifier: "ko").compactTokens(50_000), "5만")
        let english = DisplayFormatter(preferences: preferences, languageIdentifier: "en")
        XCTAssertEqual(english.effectiveUnits, .western)
        XCTAssertFalse(english.supportsLocalizedUnits)
        XCTAssertEqual(english.compactTokens(12_345), "12.3K")
        XCTAssertEqual(english.compactNumber(999.5), "999.5")
        XCTAssertEqual(english.compactTokens(999.5), "1K")
        XCTAssertEqual(DisplayFormatter(languageIdentifier: "zh-Hans").compactTokens(12_345), "12.3K", "western is the default")
    }

    func testFullTokensAlwaysUseEnglishGrouping() {
        let formatter = DisplayFormatter(languageIdentifier: "pt-BR")
        XCTAssertEqual(formatter.fullTokens(1_234_567), "1,234,567")
        XCTAssertEqual(formatter.fullTokens(999), "999")
        XCTAssertEqual(formatter.fullTokens(-1_000), "-1,000")
        XCTAssertEqual(formatter.fullTokens(1_234.5), "1,235")
        XCTAssertEqual(formatter.fullTokens(Double.nan), "0")
    }

    func testCompactApproximation() {
        let english = DisplayFormatter()
        XCTAssertNil(english.compactApproximation(999))
        XCTAssertEqual(english.compactApproximation(1_234), "≈ 1.2K")
        XCTAssertEqual(english.compactApproximation(-1_234), "≈ -1.2K")
        let localized = DisplayFormatter(units: .localized, languageIdentifier: "zh-Hant")
        XCTAssertNil(localized.compactApproximation(9_999))
        XCTAssertEqual(localized.compactApproximation(12_345), "≈ 1.23萬")
    }

    func testCostsUseCurrencyAndRatePrecedence() {
        var preferences = DisplayPreferences.defaults
        preferences.currency = .twd
        let fetched = CurrencyRates.resolve(fetched: ["TWD": 30.4821], overrides: [:])
        XCTAssertEqual(DisplayFormatter(preferences: preferences, rates: fetched).cost(1), "NT$30.48")
        preferences.currencyRates = ["TWD": 32, "USD": 2]
        let manual = DisplayFormatter(preferences: preferences, rates: fetched)
        XCTAssertEqual(manual.cost(1), "NT$32.00", "a manual rate beats the fetched one")
        XCTAssertEqual(manual.rates.origin(for: .twd), .manual)
        XCTAssertEqual(manual.rates.multiplier(for: .usd), 1, "a USD override is ignored")
        XCTAssertEqual(DisplayFormatter(preferences: preferences, rates: fetched.applying(overrides: preferences.currencyRates)), manual,
                       "applying the overrides twice changes nothing")

        let usd = DisplayFormatter()
        XCTAssertEqual(usd.cost(0.125), "$0.1250")
        XCTAssertEqual(usd.cost(12.5), "$12.50")
        XCTAssertEqual(usd.compactCost(12_345), "$12.3K")
        XCTAssertEqual(usd.compactCost(0.125), "$0.1250")
        XCTAssertEqual(DisplayFormatter(units: .localized, currency: .usd, languageIdentifier: "zh-Hans").compactCost(61_900), "$6.19万")
    }

    func testCostLabels() {
        let formatter = DisplayFormatter()
        XCTAssertEqual(formatter.costLabel(1.2345, unpricedTokens: nil, compact: false), .plain("$1.2345"))
        XCTAssertEqual(formatter.costLabel(1.2345, unpricedTokens: 0, compact: true), .plain("$1.2345"))
        XCTAssertEqual(formatter.costLabel(1.2345, unpricedTokens: 1_234, compact: false), .partial(cost: "$1.2345", unpriced: "1,234"))
        XCTAssertEqual(formatter.costLabel(0, unpricedTokens: 1_234, compact: false), .unknown(unpriced: "1,234"))
        XCTAssertEqual(formatter.costLabel(1.2345, unpricedTokens: 1_234, compact: true), .compactPartial(cost: "$1.2345"))
        XCTAssertEqual(formatter.costLabel(0, unpricedTokens: 1_234, compact: true), .compactUnknown)
        XCTAssertEqual(formatter.costLabel(.nan, unpricedTokens: nil, compact: false), .plain("$0.0000"))
        XCTAssertEqual(formatter.costLabel(12_345, unpricedTokens: 5, compact: true, compactAmount: true), .compactPartial(cost: "$12.3K"))
    }

    func testBalances() {
        let formatter = DisplayFormatter(units: .localized, languageIdentifier: "zh-Hant")
        XCTAssertEqual(formatter.balance(86.42, currency: "CNY"), "¥86.42")
        XCTAssertEqual(formatter.balance(nil, currency: "USD"), "")
        XCTAssertEqual(formatter.compactBalance(1_250_000, currency: "USD"), "$125萬")
        XCTAssertEqual(DisplayFormatter().compactBalance(123_456.789, currency: "usd"), "$123.46K")
    }

    func testPercentRateAndLiveRate() {
        // app.js formatPercent / formatRate / formatLiveTokenRate, computed with node.
        let formatter = DisplayFormatter()
        XCTAssertEqual(formatter.percent(42.5), "43%")
        XCTAssertEqual(formatter.percent(-0.4), "0%")
        XCTAssertEqual(formatter.percent(99.5), "100%")
        XCTAssertEqual(formatter.percent(.nan), "--")
        XCTAssertEqual(formatter.rate(31.6749), "31.67")
        XCTAssertEqual(formatter.rate(7.8), "7.8")
        XCTAssertEqual(formatter.rate(0.123456), "0.1235")
        XCTAssertEqual(formatter.rate(1), "1")
        XCTAssertEqual(formatter.rate(0.00001), "0")
        XCTAssertEqual(formatter.rate(.infinity), "")
        let live: [(Double, String)] = [(0.05, "<0.1"), (0.45, "0.5"), (0.95, "1"), (0.25, "0.3"), (62.4, "62"), (1_234, "1.2K"), (0, "0"), (-5, "0")]
        for (value, expected) in live {
            XCTAssertEqual(formatter.liveTokenRate(value), expected, "\(value)")
        }
        XCTAssertEqual(DisplayFormatter(languageIdentifier: "pt-BR").liveTokenRate(0.45), "0,5")
        XCTAssertEqual(DisplayFormatter(languageIdentifier: "zh-Hans").liveTokenRate(0.45), "0.5")
    }
}

/// Serves canned responses by absolute URL; unknown URLs fail to connect.
private final class ExchangeRateStubProtocol: URLProtocol {
    private struct Stub {
        var status: Int
        var body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [String: Stub] = [:]
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func stub(_ url: URL, status: Int, body: Data) {
        lock.lock()
        defer { lock.unlock() }
        stubs[url.absoluteString] = Stub(status: status, body: body)
    }

    static var requestedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requests.compactMap(\.url)
    }

    static var lastTimeout: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return requests.last?.timeoutInterval
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        stubs = [:]
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let stub = request.url.flatMap { Self.stubs[$0.absoluteString] }
        Self.lock.unlock()
        guard let url = request.url, let stub,
              let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

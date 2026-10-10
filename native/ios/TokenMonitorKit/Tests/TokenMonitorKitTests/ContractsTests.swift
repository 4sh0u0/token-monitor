import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TokenMonitorKit

/// The Phase-0 contracts: the JS primitives every formatter port builds on,
/// the display enums, the vendor palette and the new Hub endpoints.
///
/// The JSCompat vectors were computed with Node (`x.toFixed(d)`, `String(x)`,
/// `Math.round(x)`, `s.replace(/\.?0+$/, '')`, `JSON.stringify(s)`) and are
/// inlined as the expected values.
final class ContractsTests: XCTestCase {
    // MARK: JSCompat

    func testToFixedMatchesJavaScript() {
        let toFixedCases: [(Double, Int, String)] = [
            (0.125, 2, "0.13"),
            (0.125, 1, "0.1"),
            (1.005, 2, "1.00"),
            (999.95, 1, "1000.0"),
            (2.5, 0, "3"),
            (1.5, 0, "2"),
            (0.5, 0, "1"),
            (-0.5, 0, "-1"),
            (-2.5, 0, "-3"),
            (-1.005, 2, "-1.00"),
            (-0.001, 2, "-0.00"),
            (-0.0, 2, "0.00"),
            (0.0, 0, "0"),
            (1.45, 1, "1.4"),
            (1.55, 1, "1.6"),
            (8.345, 2, "8.35"),
            (8.335, 2, "8.34"),
            (0.000001, 4, "0.0000"),
            (123.456, 0, "123"),
            (100000000000000000000.0, 2, "100000000000000000000.00"),
            (1e+21, 2, "1e+21"),
            (1.5e+21, 0, "1.5e+21"),
            (-1e+21, 2, "-1e+21"),
            (12345.6789, 4, "12345.6789"),
            (0.1, 20, "0.10000000000000000555"),
            (0.3, 20, "0.29999999999999998890"),
            (5e-21, 20, "0.00000000000000000000"),
            (4.35, 1, "4.3"),
            (1234.5, 2, "1234.50"),
            (0.045, 2, "0.04"),
            (10.235, 2, "10.23"),
            (1.0000000000000002, 15, "1.000000000000000"),
            (99.995, 2, "100.00"),
            (0.00005, 4, "0.0001"),
            (0.00015, 4, "0.0001"),
            (13.229999999999999, 2, "13.23"),
            (Double.nan, 2, "NaN"),
            (Double.infinity, 2, "Infinity"),
            (-Double.infinity, 1, "-Infinity"),
            (9.995, 2, "9.99"),
            (0.07, 1, "0.1"),
            (0.95, 1, "0.9"),
            (0.05, 1, "0.1"),
            (2.675, 2, "2.67"),
            (1.255, 2, "1.25"),
            (123456789.125, 2, "123456789.13"),
            (999999.9999, 3, "1000000.000")
        ]
        for (value, digits, expected) in toFixedCases {
            XCTAssertEqual(JSCompat.toFixed(value, digits), expected, "(\(value)).toFixed(\(digits))")
        }
    }

    func testToFixedClampsDigits() {
        XCTAssertEqual(JSCompat.toFixed(1.5, -3), "2")
        XCTAssertEqual(JSCompat.toFixed(0.1, 25), JSCompat.toFixed(0.1, 20))
    }

    func testNumberStringMatchesJavaScript() {
        let numberCases: [(Double, String)] = [
            (5.0, "5"),
            (0.0, "0"),
            (-0.0, "0"),
            (1e-7, "1e-7"),
            (1.5e+21, "1.5e+21"),
            (1e+21, "1e+21"),
            (100000000000000000000.0, "100000000000000000000"),
            (123456789012345680000.0, "123456789012345680000"),
            (0.1, "0.1"),
            (0.000001, "0.000001"),
            (1e-7, "1e-7"),
            (1.5e-7, "1.5e-7"),
            (-1.5e-7, "-1.5e-7"),
            (100.0, "100"),
            (-42.5, "-42.5"),
            (0.3333333333333333, "0.3333333333333333"),
            (0.6666666666666666, "0.6666666666666666"),
            (123.456, "123.456"),
            (1e+300, "1e+300"),
            (5e-324, "5e-324"),
            (1.7976931348623157e+308, "1.7976931348623157e+308"),
            (Double.nan, "NaN"),
            (Double.infinity, "Infinity"),
            (-Double.infinity, "-Infinity"),
            (0.30000000000000004, "0.30000000000000004"),
            (4.35, "4.35"),
            (1234567.891, "1234567.891"),
            (9007199254740992.0, "9007199254740992"),
            (9007199254740994.0, "9007199254740994"),
            (10000000000000000.0, "10000000000000000"),
            (1.2e+21, "1.2e+21"),
            (1.23e-18, "1.23e-18"),
            (0.5, "0.5"),
            (-0.0001, "-0.0001"),
            (0.000001, "0.000001"),
            (0.00001234, "0.00001234"),
            (2147483648.0, "2147483648"),
            (-2147483648.0, "-2147483648")
        ]
        for (value, expected) in numberCases {
            XCTAssertEqual(JSCompat.numberString(value), expected, "String(\(value))")
        }
    }

    func testRoundMatchesJavaScript() {
        let roundCases: [(Double, Double)] = [
            (0.5, 1.0),
            (1.5, 2.0),
            (2.5, 3.0),
            (-0.5, -0.0),
            (-1.5, -1.0),
            (-2.5, -2.0),
            (0.49999999999999994, 0.0),
            (-0.49999999999999994, -0.0),
            (2.4999999999999996, 2.0),
            (-0.4, -0.0),
            (-0.6, -1.0),
            (10000000000000002.0, 10000000000000002.0),
            (4503599627370495.5, 4503599627370496.0),
            (-4503599627370495.5, -4503599627370495.0),
            (Double.infinity, Double.infinity),
            (-Double.infinity, -Double.infinity),
            (0.0, 0.0),
            (-0.0, -0.0),
            (3.7, 4.0),
            (-3.7, -4.0),
            (1.4999999999999998, 1.0)
        ]
        for (value, expected) in roundCases {
            let result = JSCompat.round(value)
            XCTAssertEqual(result, expected, "Math.round(\(value))")
            XCTAssertEqual(result.sign, expected.sign, "Math.round(\(value)) sign")
        }
        XCTAssertTrue(JSCompat.round(.nan).isNaN)
    }

    func testTrimTrailingZerosKeepsTheRegexQuirk() {
        let trimCases: [(String, String)] = [
            ("100", "1"),
            ("0", ""),
            ("1.50", "1.5"),
            ("1.0", "1"),
            ("10.00", "10"),
            ("1.0050", "1.005"),
            ("1.5", "1.5"),
            ("0.0", "0"),
            ("12", "12"),
            ("1.", "1."),
            (".0", ""),
            ("abc", "abc"),
            ("1.2300", "1.23"),
            ("00", ""),
            ("12.30M", "12.30M"),
            ("-0.50", "-0.5"),
            ("", "")
        ]
        for (input, expected) in trimCases {
            XCTAssertEqual(JSCompat.trimTrailingZeros(input), expected, "\"\(input)\".replace(/\\.?0+$/, '')")
        }
    }

    func testJSONQuotedMatchesJavaScript() {
        let jsonCases: [(String, String)] = [
            ("plain", "\"plain\""),
            ("a\"b", "\"a\\\"b\""),
            ("back\\slash", "\"back\\\\slash\""),
            ("\u{8}\u{c}\u{a}\u{d}\u{9}", "\"\\b\\f\\n\\r\\t\""),
            ("\u{0}\u{1}\u{1f}", "\"\\u0000\\u0001\\u001f\""),
            ("\u{7f}", "\"\u{7f}\""),
            ("é日本😀", "\"é日本😀\""),
            ("\u{2028}\u{2029}", "\"\u{2028}\u{2029}\""),
            ("</script>", "\"</script>\""),
            ("tab\u{9}here", "\"tab\\there\""),
            ("\u{d}\u{a}", "\"\\r\\n\""),
            ("", "\"\"")
        ]
        for (input, expected) in jsonCases {
            XCTAssertEqual(JSCompat.jsonQuoted(input), expected)
        }
    }

    // MARK: DisplayEnums

    func testDeviceScopeCodableRoundTrip() throws {
        let scopes: [DeviceScope] = [.all, .device("studio-mac"), .device("dev:with:colons")]
        let data = try JSONEncoder().encode(scopes)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["all","device:studio-mac","device:dev:with:colons"]"#)
        XCTAssertEqual(try JSONDecoder().decode([DeviceScope].self, from: data), scopes)

        struct Holder: Codable, Equatable { var deviceScope: DeviceScope }
        let holder = Holder(deviceScope: .device("build-box"))
        let encoded = try JSONEncoder().encode(holder)
        XCTAssertEqual(try JSONDecoder().decode(Holder.self, from: encoded), holder)

        for invalid in [#"["device:"]"#, #"["bogus"]"#, #"["All"]"#, "[42]"] {
            XCTAssertThrowsError(try JSONDecoder().decode([DeviceScope].self, from: Data(invalid.utf8)), invalid)
        }
    }

    func testDeviceScopeStorageValue() {
        XCTAssertEqual(DeviceScope.all.storageValue, "all")
        XCTAssertNil(DeviceScope.all.deviceID)
        XCTAssertTrue(DeviceScope.all.isAll)
        XCTAssertEqual(DeviceScope.device("tokyo-mac").deviceID, "tokyo-mac")
        XCTAssertEqual(DeviceScope.device("  ").storageValue, "all", "a blank id never stores as a device")
        XCTAssertEqual(DeviceScope(storageValue: " device: old-laptop "), .device("old-laptop"))
        XCTAssertNil(DeviceScope(storageValue: "device:"))
        XCTAssertNil(DeviceScope(storageValue: ""))
    }

    func testPeriodSelection() {
        XCTAssertEqual(PeriodSelection.today.nativeKind, .today)
        XCTAssertEqual(PeriodSelection.month.nativeKind, .month)
        XCTAssertEqual(PeriodSelection.allTime.nativeKind, .allTime)
        for derived in [PeriodSelection.week, .last7, .last30] {
            XCTAssertNil(derived.nativeKind)
            XCTAssertTrue(derived.isDerived)
        }
        XCTAssertFalse(PeriodSelection.month.isDerived)
        XCTAssertEqual(PeriodMonthMode.allCases.map(PeriodSelection.middle(for:)), [.month, .week, .last7, .last30])
        XCTAssertEqual(UsagePeriodKind.allCases.map(PeriodSelection.init), [.today, .month, .allTime])
        XCTAssertEqual(PeriodSelection(rawValue: "last30"), .last30, "deep-link values")
    }

    func testEnumRawValuesMatchTheStoredValues() {
        XCTAssertEqual(DisplayCurrency.allCases.map(\.rawValue), ["USD", "TWD", "HKD", "CNY"])
        XCTAssertEqual(DisplayCurrency.allCases.map(\.symbol), ["$", "NT$", "HK$", "¥"])
        XCTAssertEqual(PeriodMonthMode.allCases.map(\.rawValue), ["month", "week", "last7", "last30"])
        XCTAssertEqual(HomeModule.defaultOrder.map(\.rawValue), ["components", "limits", "tool", "model", "session", "device", "trends"])
        XCTAssertEqual(HomeModule.defaultHidden, [.tool, .device])
        XCTAssertEqual(AppRefreshMode.allCases.map(\.rawValue), [0, 60, 120, 300, 900, 1800])
        XCTAssertEqual(WidgetRefreshInterval.allCases.map(\.rawValue), [15, 30, 60])
        XCTAssertEqual(WatchRefreshInterval.allCases.map(\.rawValue), [60, 120, 300, 900])
        XCTAssertEqual(ComplicationRefreshInterval.allCases.map(\.rawValue), [20, 30, 60])
        XCTAssertEqual(ServiceStatusRefresh.allCases.map(\.rawValue), [0, 60_000, 120_000, 300_000, 900_000, 1_800_000])
        XCTAssertEqual(TrendRange.allCases.map(\.rawValue), ["7", "30", "90", "365", "all"])
        XCTAssertEqual(TrendRange.allCases.map(\.dayCount), [7, 30, 90, 365, nil])
        XCTAssertEqual(TrendChartMode.allCases.map(\.rawValue), ["bars", "line", "kline"])
    }

    func testPreferenceDefaults() {
        let prefs = DisplayPreferences.defaults
        XCTAssertTrue(prefs.showToolIcons)
        XCTAssertEqual(prefs.compactTokenUnits, .western)
        XCTAssertEqual(prefs.currency, .usd)
        XCTAssertEqual(prefs.deviceScope, .all)
        XCTAssertEqual(prefs.homeModuleOrder, HomeModule.defaultOrder)
        XCTAssertEqual(prefs.hiddenHomeModules, [.tool, .device])
        XCTAssertEqual(prefs.heatmapMetric, .cost)
        XCTAssertEqual(prefs.homeLimitAccountCount, 3)
        XCTAssertTrue(prefs.showCodexAdditionalLimits)
        XCTAssertFalse(prefs.showLimitUsed)
        XCTAssertFalse(prefs.maskLimitAccountEmails)
        XCTAssertTrue(prefs.sessionTitlesEnabled)
        XCTAssertEqual(prefs.appRefreshSeconds, .live)
        XCTAssertEqual(prefs.widgetRefreshMinutes, .fifteenMinutes)
        XCTAssertEqual(prefs.watchRefreshSeconds, .oneMinute)
        XCTAssertEqual(prefs.complicationRefreshMinutes, .twentyMinutes)
        XCTAssertEqual(prefs.serviceStatusRefreshMs, .oneMinute)
        XCTAssertFalse(prefs.showStatusTab)
        XCTAssertEqual(DisplayPreferences(), .defaults)
    }

    // MARK: Currency

    func testCurrencyRatesFallBackToTheFloors() throws {
        let builtIn = CurrencyRates.builtIn
        XCTAssertEqual(DisplayCurrency.allCases.map(builtIn.multiplier(for:)), [1, 31.5, 7.8, 6.8])
        XCTAssertEqual(builtIn.origin(for: .twd), .builtIn)

        let rates = CurrencyRates(multipliers: ["TWD": 32.1, "HKD": 0, "CNY": .nan], origins: ["TWD": .fetched, "HKD": .manual], fetchedDate: "2026-10-10")
        XCTAssertEqual(rates.multiplier(for: .twd), 32.1)
        XCTAssertEqual(rates.origin(for: .twd), .fetched)
        XCTAssertEqual(rates.multiplier(for: .hkd), 7.8, "an invalid rate falls back to the floor")
        XCTAssertEqual(rates.origin(for: .hkd), .builtIn)
        XCTAssertEqual(rates.multiplier(for: .usd), 1)

        let valid = CurrencyRates(multipliers: ["TWD": 32.1], origins: ["TWD": .manual], fetchedDate: nil)
        XCTAssertEqual(try JSONDecoder().decode(CurrencyRates.self, from: JSONEncoder().encode(valid)), valid)
    }

    // MARK: VendorPalette

    func testNearBlackOverrideBecomesInk() {
        let palette = VendorPalette(overrides: ["claude": "#0A0A0A", "codex": "#292929", "gemini": "#2a2a2a"])
        XCTAssertEqual(palette.paint(for: "claude"), .ink)
        XCTAssertEqual(palette.paint(for: "codex"), .ink, "luminance 41 < 42")
        XCTAssertEqual(palette.paint(for: "gemini"), .hex("#2a2a2a"), "luminance 42 stays a colour")
        XCTAssertEqual(palette.brandHex(for: "claude"), "#0a0a0a", "swatches keep the chosen colour")
    }

    func testValidOverrideWins() {
        let palette = VendorPalette(overrides: [" claude ": "#ff0000", "claude": " #FF8800 ", "codex": "red", "cursor": "#12345", "newapi": "#00ff00"])
        XCTAssertEqual(palette.paint(for: "claude"), .hex("#ff8800"))
        XCTAssertEqual(palette.brandHex(for: "claude"), "#ff8800")
        XCTAssertEqual(palette.paint(for: "codex"), VendorCatalog.paint(for: "codex"), "invalid overrides are ignored")
        XCTAssertEqual(palette.paint(for: "cursor"), .ink, "the catalog's ink stays without a valid override")
        XCTAssertEqual(palette.paint(for: "newapi"), VendorCatalog.paint(for: "newapi"), "only colour-bearing marks are overridable")
        XCTAssertEqual(VendorPalette().paint(for: "claude"), VendorCatalog.paint(for: "claude"))
        XCTAssertEqual(VendorPalette().brandHex(for: "claude"), VendorCatalog.brandColorHex(for: "claude"))
    }

    func testDefaultOverrideRepaintsUncolouredIDs() {
        let palette = VendorPalette(overrides: ["default": "#336699"])
        XCTAssertEqual(palette.paint(for: nil), .hex("#336699"))
        XCTAssertEqual(palette.paint(for: "no-such-mark"), .hex("#336699"))
        XCTAssertEqual(palette.paint(for: "newapi"), .hex("#336699"))
        XCTAssertEqual(palette.paint(for: "claude"), VendorCatalog.paint(for: "claude"))
        XCTAssertEqual(palette.paint(for: "factory"), .ink, "an ink mark keeps its ink")
        XCTAssertEqual(palette.brandHex(for: nil), "#336699")
    }

    func testModelPaintFollowsItsVendor() {
        let palette = VendorPalette(overrides: ["claude": "#ff8800", "default": "#336699"])
        XCTAssertEqual(palette.modelPaint(for: "claude-sonnet-4-5"), .hex("#ff8800"))
        XCTAssertEqual(palette.modelPaint(for: "totally-unknown-model"), VendorCatalog.modelPaint(for: "totally-unknown-model"),
                       "the hashed fallback colours are not overridable")
    }

    // MARK: Presentation context

    func testPresentationContextPalette() {
        XCTAssertEqual(PresentationContext.standard, PresentationContext())
        XCTAssertEqual(PresentationContext.standard.languageIdentifier, "en")
        XCTAssertEqual(PresentationContext.standard.rates, .builtIn)
        let context = PresentationContext(preferences: DisplayPreferences(vendorColors: ["claude": "#ff8800"]))
        XCTAssertEqual(context.palette, VendorPalette(overrides: ["claude": "#ff8800"]))
    }

    func testDataContracts() {
        let gauge = SessionContextGauge(contextTokens: 190_900, contextWindow: 950_000, percentLeft: 80, percentUsed: 20, tone: .neutral)
        XCTAssertEqual(gauge.percent(for: .used), 20)
        XCTAssertEqual(gauge.percent(for: .remaining), 80)
        XCTAssertEqual(HeatmapGrid.empty.cells, [])
        XCTAssertEqual(TrendBarsModel.empty.maxTotal, 0)
        XCTAssertEqual(LimitStatusLabel.allCases.count, 22)
    }

    func testActivitySnapshotRoundTrip() throws {
        let snapshot = ActivitySnapshot(hubKey: "abc", scopeDeviceID: nil, generatedAt: Date(timeIntervalSince1970: 1_790_000_000),
                                        startDay: "2026-10-08", tokens: [0, 12, 3], costMicros: [0, 1_250_000, 7])
        XCTAssertEqual(snapshot.schemaVersion, ActivitySnapshot.currentSchemaVersion)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(ActivitySnapshot.self, from: encoder.encode(snapshot)), snapshot)
    }

    // MARK: Hub endpoints

    func testNewEndpointRequests() throws {
        let connection = try HubConnection(userInput: "https://hub.example.com/proxy/", secret: "s3cret")
        let client = HubClient(connection: connection)
        let expected: [(HubEndpoint, String)] = [
            (.history, "https://hub.example.com/proxy/api/history"),
            (.devices, "https://hub.example.com/proxy/api/devices"),
            (.subscriptions, "https://hub.example.com/proxy/api/subscriptions"),
            (.syncContent, "https://hub.example.com/proxy/api/sync/content"),
            (.syncSettingsModelAliases, "https://hub.example.com/proxy/api/sync/settings/modelAliases"),
            (.syncSettingsCustomPricing, "https://hub.example.com/proxy/api/sync/settings/customPricing")
        ]
        for (endpoint, url) in expected {
            let request = client.request(for: endpoint)
            XCTAssertEqual(request.url?.absoluteString, url)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret")
            XCTAssertEqual(request.timeoutInterval, HubClient.defaultTimeout)
        }
    }

    func testDataForEndpoint() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = HubClient(connection: try HubConnection(userInput: "http://hub.test:17321", secret: "s3cret"), session: session)

        let body = Data(#"{"daily":[],"monthly":[]}"#.utf8)
        StubURLProtocol.stub(path: "/api/history", status: 200, body: body)
        StubURLProtocol.stub(path: "/api/subscriptions", status: 404, body: Data())
        let data = try await client.data(for: .history)
        XCTAssertEqual(data, body)
        XCTAssertEqual(StubURLProtocol.recordedRequests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret")
        do {
            _ = try await client.data(for: .subscriptions)
            XCTFail("a 404 must throw")
        } catch {
            XCTAssertEqual(error as? HubClientError, .http(status: 404))
        }
    }
}

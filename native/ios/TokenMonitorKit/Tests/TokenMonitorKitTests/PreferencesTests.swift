import Foundation
import XCTest
@testable import TokenMonitorKit

// MARK: - DisplayPreferences Codable and normalization

final class DisplayPreferencesCodingTests: XCTestCase {
    private func decode(_ json: String) throws -> DisplayPreferences {
        try DisplayPreferences(jsonData: Data(json.utf8))
    }

    private func object(_ preferences: DisplayPreferences) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: preferences.jsonData()) as? [String: Any])
    }

    func testDefaultsEncodeEveryKeyWithItsDefault() throws {
        let json = try object(.defaults)
        XCTAssertEqual(Set(json.keys), Set(DisplayPreferences.CodingKeys.allCases.map(\.stringValue)))
        XCTAssertEqual(json.count, 41)

        XCTAssertEqual(json["showToolIcons"] as? Bool, true)
        XCTAssertEqual(json["compactTokenUnits"] as? String, "western")
        XCTAssertEqual(json["showCompactTotalTokens"] as? Bool, false)
        XCTAssertEqual(json["currency"] as? String, "USD")
        XCTAssertEqual((json["currencyRates"] as? [String: Any])?.count, 0)
        XCTAssertEqual((json["vendorColors"] as? [String: Any])?.count, 0)
        XCTAssertEqual(json["showLiveTokenRate"] as? Bool, false)
        XCTAssertEqual(json["tokenRateMode"] as? String, "speed")
        XCTAssertEqual(json["liveTokenRateScope"] as? String, "all")
        XCTAssertEqual(json["periodMonthMode"] as? String, "month")
        XCTAssertEqual(json["deviceScope"] as? String, "all")
        XCTAssertEqual(json["homeModuleOrder"] as? [String], ["components", "limits", "tool", "model", "session", "device", "trends"])
        XCTAssertEqual(json["hiddenHomeModules"] as? [String], ["tool", "device"])
        XCTAssertEqual(json["heatmapMetric"] as? String, "cost")
        XCTAssertEqual(json["homeActiveDaysWindow"] as? String, "all")
        XCTAssertEqual(json["homeLimitAccountCount"] as? Int, 3)
        XCTAssertEqual(json["homeLimitDisplayMode"] as? String, "text")
        XCTAssertEqual(json["showHomeLimitBars"] as? Bool, false)
        XCTAssertEqual(json["showHomeLimitProviderNames"] as? Bool, false)
        XCTAssertEqual(json["homeLimitProviderOrder"] as? [String], [])
        XCTAssertEqual(json["hiddenHomeLimitProviders"] as? [String], [])
        XCTAssertEqual(json["clientDisplayOrder"] as? [String], [])
        XCTAssertEqual(json["hiddenClients"] as? [String], [])
        XCTAssertEqual(json["pinnedClients"] as? [String], [])
        XCTAssertEqual(json["modelRankingMetric"] as? String, "tokens")
        XCTAssertEqual(json["showLimitUsed"] as? Bool, false)
        XCTAssertEqual(json["limitProviderOrder"] as? [String], [])
        XCTAssertEqual((json["limitProviderHiddenItems"] as? [String: Any])?.count, 0)
        XCTAssertEqual(json["showCodexAdditionalLimits"] as? Bool, true)
        XCTAssertEqual(json["showLimitSource"] as? Bool, false)
        XCTAssertEqual(json["maskLimitAccountEmails"] as? Bool, false)
        XCTAssertEqual(json["sessionTitlesEnabled"] as? Bool, true)
        XCTAssertEqual(json["sessionContextMetric"] as? String, "used")
        XCTAssertEqual(json["appRefreshSeconds"] as? Int, 0)
        XCTAssertEqual(json["widgetRefreshMinutes"] as? Int, 15)
        XCTAssertEqual(json["watchRefreshSeconds"] as? Int, 60)
        XCTAssertEqual(json["complicationRefreshMinutes"] as? Int, 20)
        XCTAssertEqual(json["serviceStatusRefreshMs"] as? Int, 60000)
        XCTAssertEqual(json["showStatusTab"] as? Bool, false)
        XCTAssertEqual(json["hiddenServiceProviders"] as? [String], [])
        XCTAssertEqual(json["serviceProviderDisplayOrder"] as? [String], [])
    }

    func testEveryNonDefaultValueRoundTrips() throws {
        let custom = Self.everyKeyChanged
        let decoded = try DisplayPreferences(jsonData: custom.jsonData())
        XCTAssertEqual(decoded, custom)
        XCTAssertEqual(custom, custom.normalized(), "fixture should already be normalized")
        // Every stored property differs from its default, so a key the coder
        // forgot would show up as a mismatch above.
        let customJSON = try object(custom)
        let defaultJSON = try object(.defaults)
        for key in DisplayPreferences.CodingKeys.allCases.map(\.stringValue) {
            let custom = try JSONSerialization.data(withJSONObject: [customJSON[key] ?? NSNull()], options: .sortedKeys)
            let standard = try JSONSerialization.data(withJSONObject: [defaultJSON[key] ?? NSNull()], options: .sortedKeys)
            XCTAssertNotEqual(custom, standard, "\(key) is not exercised")
        }
    }

    func testEncodingIsDeterministic() throws {
        XCTAssertEqual(try Self.everyKeyChanged.jsonData(), try Self.everyKeyChanged.jsonData())
        XCTAssertEqual(try DisplayPreferences.defaults.jsonData(), try DisplayPreferences().jsonData())
    }

    func testEmptyAndUnknownKeysDecodeAsDefaults() throws {
        XCTAssertEqual(try decode("{}"), .defaults)
        XCTAssertEqual(try decode(#"{"futureKey": {"nested": [1, 2]}, "anotherOne": 5}"#), .defaults)
    }

    func testTopLevelThatIsNotAnObjectFails() {
        XCTAssertThrowsError(try decode("[]"))
        XCTAssertThrowsError(try decode("\"prefs\""))
        XCTAssertThrowsError(try decode("not json"))
    }

    func testInvalidValuesFallBackPerKey() throws {
        let decoded = try decode("""
        {
          "showToolIcons": "yes", "compactTokenUnits": "metric", "showCompactTotalTokens": 1,
          "currency": "EUR", "currencyRates": [1, 2], "vendorColors": "red",
          "showLiveTokenRate": null, "tokenRateMode": 3, "liveTokenRateScope": "everything",
          "periodMonthMode": "year", "deviceScope": "laptop", "homeModuleOrder": 7,
          "hiddenHomeModules": {"tool": true}, "heatmapMetric": "", "homeActiveDaysWindow": false,
          "homeLimitAccountCount": "lots", "homeLimitDisplayMode": "rings", "showHomeLimitBars": [],
          "showHomeLimitProviderNames": {}, "homeLimitProviderOrder": 12, "hiddenHomeLimitProviders": true,
          "clientDisplayOrder": null, "hiddenClients": {"a": 1}, "pinnedClients": 4.5, "modelRankingMetric": "speed",
          "showLimitUsed": "false", "limitProviderOrder": false, "limitProviderHiddenItems": ["claude"],
          "showCodexAdditionalLimits": 0, "showLimitSource": "true", "maskLimitAccountEmails": null,
          "sessionTitlesEnabled": "on", "sessionContextMetric": "left",
          "appRefreshSeconds": 45, "widgetRefreshMinutes": 10, "watchRefreshSeconds": 30.5,
          "complicationRefreshMinutes": "fast", "serviceStatusRefreshMs": 1000,
          "showStatusTab": "1", "hiddenServiceProviders": 0, "serviceProviderDisplayOrder": {}
        }
        """)
        XCTAssertEqual(decoded, .defaults)
    }

    func testOneBadValueDoesNotSpoilTheOthers() throws {
        let decoded = try decode("""
        {"currency": "JPY", "heatmapMetric": "tokens", "showLimitUsed": true, "appRefreshSeconds": 7,
         "widgetRefreshMinutes": 60, "hiddenClients": ["Codex"]}
        """)
        XCTAssertEqual(decoded.currency, .usd)
        XCTAssertEqual(decoded.heatmapMetric, .tokens)
        XCTAssertTrue(decoded.showLimitUsed)
        XCTAssertEqual(decoded.appRefreshSeconds, .live)
        XCTAssertEqual(decoded.widgetRefreshMinutes, .oneHour)
        XCTAssertEqual(decoded.hiddenClients, ["codex"])
    }

    func testLenientSpellingsOfValidValues() throws {
        let decoded = try decode("""
        {"compactTokenUnits": " Localized ", "currency": "twd", "homeLimitDisplayMode": "BARS",
         "appRefreshSeconds": "300", "serviceStatusRefreshMs": 900000.0, "complicationRefreshMinutes": 60,
         "watchRefreshSeconds": " 120 ", "homeLimitAccountCount": "5",
         "hiddenClients": "codex, Hermes,,codex", "homeModuleOrder": "trends,model",
         "hiddenHomeModules": ["TOOL", 3, "nope"], "deviceScope": " device:studio-mac "}
        """)
        XCTAssertEqual(decoded.compactTokenUnits, .localized)
        XCTAssertEqual(decoded.currency, .twd)
        XCTAssertEqual(decoded.homeLimitDisplayMode, .bars)
        XCTAssertEqual(decoded.appRefreshSeconds, .fiveMinutes)
        XCTAssertEqual(decoded.serviceStatusRefreshMs, .fifteenMinutes)
        XCTAssertEqual(decoded.complicationRefreshMinutes, .oneHour)
        XCTAssertEqual(decoded.watchRefreshSeconds, .twoMinutes)
        XCTAssertEqual(decoded.homeLimitAccountCount, 5)
        XCTAssertEqual(decoded.hiddenClients, ["codex", "hermes"])
        XCTAssertEqual(decoded.homeModuleOrder, [.trends, .model, .components, .limits, .tool, .session, .device])
        XCTAssertEqual(decoded.hiddenHomeModules, [.tool])
        XCTAssertEqual(decoded.deviceScope, .device("studio-mac"))
    }

    func testHomeLimitAccountCountFollowsTheDesktopClamp() throws {
        // `Math.trunc(Number(value))`, clamped to 1…12 (`main.js:540-544`).
        let cases: [(String, Int)] = [("0", 1), ("-4", 1), ("1", 1), ("3.9", 3), ("12", 12), ("99", 12),
                                      ("1e300", 12), ("-1e300", 1), ("\"7\"", 7), ("\"\"", 3), ("true", 3), ("null", 3)]
        for (raw, expected) in cases {
            XCTAssertEqual(try decode(#"{"homeLimitAccountCount": \#(raw)}"#).homeLimitAccountCount, expected, raw)
        }
        XCTAssertEqual(DisplayPreferences(homeLimitAccountCount: 40).normalized().homeLimitAccountCount, 12)
        XCTAssertEqual(DisplayPreferences(homeLimitAccountCount: -2).normalized().homeLimitAccountCount, 1)
    }

    func testIDListsAreTrimmedLowercasedDeduplicatedAndCapped() {
        let long = String(repeating: "x", count: DisplayPreferences.maxIDLength + 1)
        let many = (0..<100).map { "tool-\($0)" }
        let preferences = DisplayPreferences(
            homeLimitProviderOrder: [" Claude ", "claude", "", "  ", "CODEX"],
            hiddenHomeLimitProviders: [long, "zai"],
            clientDisplayOrder: many,
            hiddenClients: ["Gemini", "GEMINI"],
            pinnedClients: ["\tcodex\n"],
            limitProviderOrder: many + ["claude"],
            hiddenServiceProviders: ["OpenAI"],
            serviceProviderDisplayOrder: ["deepseek", "Claude", "deepseek"]
        ).normalized()
        XCTAssertEqual(preferences.homeLimitProviderOrder, ["claude", "codex"])
        XCTAssertEqual(preferences.hiddenHomeLimitProviders, ["zai"])
        XCTAssertEqual(preferences.clientDisplayOrder, Array(many.prefix(64)))
        XCTAssertEqual(preferences.hiddenClients, ["gemini"])
        XCTAssertEqual(preferences.pinnedClients, ["codex"])
        XCTAssertEqual(preferences.limitProviderOrder.count, 64)
        XCTAssertFalse(preferences.limitProviderOrder.contains("claude"))
        XCTAssertEqual(preferences.hiddenServiceProviders, ["openai"])
        XCTAssertEqual(preferences.serviceProviderDisplayOrder, ["deepseek", "claude"])
    }

    func testHomeModulesFollowTheDesktopRules() {
        let preferences = DisplayPreferences(
            homeModuleOrder: [.trends, .trends, .model],
            hiddenHomeModules: HomeModule.allCases
        ).normalized()
        XCTAssertEqual(preferences.homeModuleOrder, [.trends, .model, .components, .limits, .tool, .session, .device])
        XCTAssertEqual(preferences.hiddenHomeModules, [], "hiding every module shows them all")
        XCTAssertEqual(DisplayPreferences(hiddenHomeModules: [.device, .tool, .device]).normalized().hiddenHomeModules, [.device, .tool])
    }

    func testCurrencyRatesKeepOnlyValidOverrides() {
        let preferences = DisplayPreferences(currencyRates: [
            "twd": 32.1, "USD": 2, "EUR": 0.9, "HKD": 0, "CNY": -7, " cny ": 7.2, "JPY": .infinity
        ]).normalized()
        XCTAssertEqual(preferences.currencyRates, ["TWD": 32.1, "CNY": 7.2])
        XCTAssertEqual(DisplayPreferences(currencyRates: ["HKD": .nan]).normalized().currencyRates, [:])
    }

    func testCurrencyRatesDecodeNumbersAndNumericStrings() throws {
        let decoded = try decode(#"{"currencyRates": {"TWD": "31.9", "HKD": 7.75, "CNY": true, "USD": 1}}"#)
        XCTAssertEqual(decoded.currencyRates, ["TWD": 31.9, "HKD": 7.75])
    }

    func testVendorColorsKeepValidHexAndMigrateRenamedIDs() {
        let preferences = DisplayPreferences(vendorColors: [
            "Claude": " #FF8800 ", "codex": "red", "cursor": "#12345", "kilocode": "#00aa00",
            "micode": "#111111", "mimo": "#222222", "default": "#abcdef", "": "#000000"
        ]).normalized()
        XCTAssertEqual(preferences.vendorColors, [
            "claude": "#ff8800", "kilo": "#00aa00", "mimo": "#222222", "default": "#abcdef"
        ])
    }

    func testVendorColorsAreCapped() {
        var colors: [String: String] = [:]
        for index in 0..<100 { colors[String(format: "mark-%03d", index)] = "#010203" }
        let normalized = DisplayPreferences(vendorColors: colors).normalized().vendorColors
        XCTAssertEqual(normalized.count, 64)
        XCTAssertEqual(normalized.keys.sorted().last, "mark-063")
    }

    func testHiddenLimitItemsAreNormalized() {
        let windowKey = #"["id","five_hour","session","",false,300]"#
        let tooLong = "[" + String(repeating: "a", count: 400) + "]"
        let exact = String(repeating: "b", count: 400)
        let many = (0..<80).map { "item-\($0)" }
        let preferences = DisplayPreferences(limitProviderHiddenItems: [
            " Claude ": [" \(windowKey) ", windowKey, "credits", "", tooLong, exact],
            "codex": [],
            "cursor": ["  "],
            "zai": many,
            "": ["spend"]
        ]).normalized()
        XCTAssertEqual(preferences.limitProviderHiddenItems, [
            "claude": [windowKey, "credits", exact],
            "zai": Array(many.prefix(64))
        ])
        // Item ids are JSON keys: their case is kept.
        let cased = DisplayPreferences(limitProviderHiddenItems: ["claude": ["Usage Credits"]]).normalized()
        XCTAssertEqual(cased.limitProviderHiddenItems["claude"], ["Usage Credits"])
    }

    func testHiddenLimitItemsDecodeLeniently() throws {
        let decoded = try decode(#"{"limitProviderHiddenItems": {"claude": ["spend", 4, null], "codex": "resets", "Cursor": ["credits"]}}"#)
        XCTAssertEqual(decoded.limitProviderHiddenItems, ["claude": ["spend"], "cursor": ["credits"]])
    }

    func testDeviceScopeDecoding() throws {
        XCTAssertEqual(try decode(#"{"deviceScope": "device:build-box"}"#).deviceScope, .device("build-box"))
        XCTAssertEqual(try decode(#"{"deviceScope": "device:"}"#).deviceScope, .all)
        XCTAssertEqual(try decode(#"{"deviceScope": 5}"#).deviceScope, .all)
        XCTAssertEqual(DisplayPreferences(deviceScope: .device("  ")).normalized().deviceScope, .all)
        XCTAssertEqual(DisplayPreferences(deviceScope: .device(" mac ")).normalized().deviceScope, .device("mac"))
    }

    func testNormalizationIsIdempotent() {
        let messy = DisplayPreferences(
            currencyRates: ["twd": 30, "USD": 3],
            vendorColors: ["Claude": "#FFFFFF", "kilocode": "#000001"],
            deviceScope: .device(" x "),
            homeModuleOrder: [.device],
            hiddenHomeModules: HomeModule.allCases,
            homeLimitAccountCount: 0,
            clientDisplayOrder: ["B", "a", "b"],
            limitProviderHiddenItems: [" Codex ": ["x", "x"]]
        )
        let once = messy.normalized()
        XCTAssertEqual(once.normalized(), once)
        XCTAssertEqual(try DisplayPreferences(jsonData: messy.jsonData()), once)
    }

    /// Every key away from its default, already in normalized form.
    static let everyKeyChanged = DisplayPreferences(
        showToolIcons: false,
        compactTokenUnits: .localized,
        showCompactTotalTokens: true,
        currency: .cny,
        currencyRates: ["CNY": 7.25, "TWD": 32.5],
        vendorColors: ["claude": "#ff8800", "default": "#336699"],
        showLiveTokenRate: true,
        tokenRateMode: .burn,
        liveTokenRateScope: .device,
        periodMonthMode: .last30,
        deviceScope: .device("studio-mac"),
        homeModuleOrder: [.trends, .session, .model, .tool, .limits, .device, .components],
        hiddenHomeModules: [.components],
        heatmapMetric: .tokens,
        homeActiveDaysWindow: .year,
        homeLimitAccountCount: 12,
        homeLimitDisplayMode: .bars,
        showHomeLimitBars: true,
        showHomeLimitProviderNames: true,
        homeLimitProviderOrder: ["codex", "claude"],
        hiddenHomeLimitProviders: ["cursor"],
        clientDisplayOrder: ["codex", "claude"],
        hiddenClients: ["gemini"],
        pinnedClients: ["hermes"],
        modelRankingMetric: .cost,
        showLimitUsed: true,
        limitProviderOrder: ["zai", "claude"],
        limitProviderHiddenItems: ["claude": ["spend", #"["id","five_hour","session","",false,300]"#]],
        showCodexAdditionalLimits: false,
        showLimitSource: true,
        maskLimitAccountEmails: true,
        sessionTitlesEnabled: false,
        sessionContextMetric: .remaining,
        appRefreshSeconds: .thirtyMinutes,
        widgetRefreshMinutes: .thirtyMinutes,
        watchRefreshSeconds: .fifteenMinutes,
        complicationRefreshMinutes: .oneHour,
        serviceStatusRefreshMs: .manual,
        showStatusTab: true,
        hiddenServiceProviders: ["cursor"],
        serviceProviderDisplayOrder: ["deepseek", "claude"]
    )
}

// MARK: - PreferencesStore

final class PreferencesStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var center: NotificationCenter!
    private var store: PreferencesStore!
    private var notifications = 0
    private var observer: NSObjectProtocol?

    override func setUp() {
        super.setUp()
        suiteName = "TokenMonitorKitTests.prefs.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        center = NotificationCenter()
        store = PreferencesStore(defaults: defaults, notificationCenter: center)
        notifications = 0
        observer = center.addObserver(forName: PreferencesStore.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.notifications += 1
        }
    }

    override func tearDown() {
        if let observer { center.removeObserver(observer) }
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testKey() {
        XCTAssertEqual(PreferencesStore.key, "displayPreferences.v1")
    }

    func testLoadWithoutAValueGivesDefaults() {
        XCTAssertEqual(store.load(), .defaults)
    }

    func testSaveLoadAndChangeNotification() throws {
        let custom = DisplayPreferencesCodingTests.everyKeyChanged
        XCTAssertTrue(store.save(custom))
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(store.load(), custom)
        XCTAssertEqual(defaults.data(forKey: PreferencesStore.key), try custom.jsonData())

        XCTAssertFalse(store.save(custom), "saving the same preferences is a no-op")
        XCTAssertEqual(notifications, 1)

        var changed = custom
        changed.showLimitUsed = false
        XCTAssertTrue(store.save(changed))
        XCTAssertEqual(notifications, 2)
        XCTAssertEqual(store.load(), changed)
    }

    func testSaveNormalizes() {
        store.save(DisplayPreferences(homeLimitAccountCount: 99, hiddenClients: ["Codex", "codex"]))
        XCTAssertEqual(store.load().hiddenClients, ["codex"])
        XCTAssertEqual(store.load().homeLimitAccountCount, 12)
        // The normalized form is what is compared: an equivalent spelling is
        // not a change.
        XCTAssertFalse(store.save(DisplayPreferences(homeLimitAccountCount: 12, hiddenClients: [" CODEX "])))
    }

    func testUpdate() {
        let result = store.update { $0.currency = .hkd; $0.pinnedClients = ["Claude"] }
        XCTAssertEqual(result.currency, .hkd)
        XCTAssertEqual(result.pinnedClients, ["claude"])
        XCTAssertEqual(store.load(), result)
        XCTAssertEqual(notifications, 1)
    }

    func testClear() {
        store.clear()
        XCTAssertEqual(notifications, 0, "nothing stored, nothing changed")
        store.save(DisplayPreferences(showStatusTab: true))
        store.clear()
        XCTAssertEqual(notifications, 2)
        XCTAssertNil(defaults.object(forKey: PreferencesStore.key))
        XCTAssertEqual(store.load(), .defaults)
    }

    func testCorruptOrForeignValuesLoadLeniently() {
        defaults.set(Data("garbage".utf8), forKey: PreferencesStore.key)
        XCTAssertEqual(store.load(), .defaults)
        defaults.set(#"{"currency": "HKD", "showToolIcons": "nope"}"#, forKey: PreferencesStore.key)
        XCTAssertEqual(store.load(), DisplayPreferences(currency: .hkd))
        defaults.set(42, forKey: PreferencesStore.key)
        XCTAssertEqual(store.load(), .defaults)
    }
}

// MARK: - PreferencesPayload

final class PreferencesPayloadTests: XCTestCase {
    func testRoundTrip() throws {
        let rateCache = Data(#"{"rates":{"CNY":7.1},"date":"2026-10-10"}"#.utf8)
        let payload = PreferencesPayload(preferences: DisplayPreferencesCodingTests.everyKeyChanged, rateCacheData: rateCache)
        let data = try payload.encoded()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["v"] as? Int, 1)
        XCTAssertNotNil(object["preferences"] as? [String: Any])
        XCTAssertNotNil(object["rateCacheData"] as? String)
        XCTAssertEqual(PreferencesPayload.decode(data), payload)

        let withoutRates = PreferencesPayload(preferences: .defaults)
        let plain = try withoutRates.encoded()
        XCTAssertNil((try JSONSerialization.jsonObject(with: plain) as? [String: Any])?["rateCacheData"])
        XCTAssertEqual(PreferencesPayload.decode(plain), withoutRates)
        XCTAssertEqual(PreferencesPayload.contextKey, "prefs")
    }

    func testDecodeRejectsOtherVersionsAndShapes() {
        XCTAssertNil(PreferencesPayload.decode(Data(#"{"v":2,"preferences":{}}"#.utf8)))
        XCTAssertNil(PreferencesPayload.decode(Data(#"{"preferences":{}}"#.utf8)))
        XCTAssertNil(PreferencesPayload.decode(Data(#"{"v":1}"#.utf8)))
        XCTAssertNil(PreferencesPayload.decode(Data(#"{"v":1,"preferences":"x"}"#.utf8)))
        XCTAssertNil(PreferencesPayload.decode(Data("nope".utf8)))
        XCTAssertEqual(PreferencesPayload.decode(Data(#"{"v":1,"preferences":{}}"#.utf8)), PreferencesPayload(preferences: .defaults))
        // A bad rate cache does not cost the preferences.
        let payload = PreferencesPayload.decode(Data(#"{"v":1,"preferences":{"currency":"TWD"},"rateCacheData":17}"#.utf8))
        XCTAssertEqual(payload, PreferencesPayload(preferences: DisplayPreferences(currency: .twd)))
    }

    func testRealisticPreferencesFitWithoutDropping() throws {
        var preferences = DisplayPreferencesCodingTests.everyKeyChanged
        let clients = ["claude", "codex", "opencode", "hermes", "openclaw", "cursor", "antigravity", "cline", "amp", "droid",
                       "kimi", "qwen", "grok", "copilot", "pi", "omp", "zed", "kilo", "commandcode", "mimo"]
        preferences.clientDisplayOrder = clients
        preferences.hiddenClients = Array(clients.suffix(8))
        preferences.pinnedClients = Array(clients.prefix(4))
        preferences.limitProviderOrder = VendorCatalog.limitProviders.map(\.id)
        preferences.homeLimitProviderOrder = Array(VendorCatalog.limitProviders.map(\.id).prefix(10))
        preferences.hiddenHomeLimitProviders = Array(VendorCatalog.limitProviders.map(\.id).suffix(10))
        preferences.vendorColors = Dictionary(uniqueKeysWithValues: VendorCatalog.marks.prefix(40).map { ($0.id, "#123456") })
        preferences.limitProviderHiddenItems = [
            "claude": ["spend", "resets", #"["id","seven_day_opus","weekly","",false,10080]"#],
            "codex": [#"["id","codex_other","session","",true,300]"#, #"["id","codex_other","weekly","",true,10080]"#],
            "cursor": ["credits"]
        ]
        let rateCache = Data(#"{"rates":{"USD":1,"TWD":32.1,"HKD":7.8,"CNY":7.1},"date":"2026-10-10","source":"https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json","fetchedAt":781000000}"#.utf8)
        let payload = PreferencesPayload(preferences: preferences, rateCacheData: rateCache)
        let data = try payload.encoded()
        XCTAssertLessThanOrEqual(data.count, PreferencesPayload.defaultMaxBytes)
        XCTAssertEqual(PreferencesPayload.decode(data), PreferencesPayload(preferences: preferences.normalized(), rateCacheData: rateCache))
    }

    func testOverBudgetDropsVendorColorsFirst() throws {
        var preferences = DisplayPreferences.defaults
        preferences.vendorColors = Dictionary(uniqueKeysWithValues: (0..<64).map {
            (String(format: "mark-%03d-", $0) + String(repeating: "v", count: 100), "#abcdef")
        })
        preferences.limitProviderHiddenItems = ["claude": ["spend"]]
        let full = try JSONEncoder().encode(PreferencesPayload(preferences: preferences))
        XCTAssertGreaterThan(full.count, 8192)

        let data = try PreferencesPayload(preferences: preferences).encoded()
        XCTAssertLessThanOrEqual(data.count, 8192)
        let decoded = try XCTUnwrap(PreferencesPayload.decode(data))
        XCTAssertEqual(decoded.preferences.vendorColors, [:])
        XCTAssertEqual(decoded.preferences.limitProviderHiddenItems, ["claude": ["spend"]])
    }

    func testStillOverBudgetDropsHiddenItemsNext() throws {
        var preferences = DisplayPreferences.defaults
        preferences.vendorColors = ["claude": "#ff8800"]
        preferences.limitProviderHiddenItems = Dictionary(uniqueKeysWithValues: (0..<10).map { provider in
            ("provider-\(provider)", (0..<5).map { "item-\($0)-" + String(repeating: "i", count: 300) })
        })
        preferences.showLimitUsed = true

        let data = try PreferencesPayload(preferences: preferences).encoded()
        XCTAssertLessThanOrEqual(data.count, 8192)
        let decoded = try XCTUnwrap(PreferencesPayload.decode(data))
        XCTAssertEqual(decoded.preferences.vendorColors, [:])
        XCTAssertEqual(decoded.preferences.limitProviderHiddenItems, [:])
        XCTAssertTrue(decoded.preferences.showLimitUsed, "everything else survives")
    }

    func testThrowsWhenNothingDroppableHelps() {
        XCTAssertThrowsError(try PreferencesPayload(preferences: .defaults).encoded(maxBytes: 100)) { error in
            let tooLarge = error as? PreferencesPayload.TooLargeError
            XCTAssertEqual(tooLarge?.maxBytes, 100)
            XCTAssertGreaterThan(tooLarge?.byteCount ?? 0, 100)
        }
    }
}

// MARK: - Ordering ports (tables rendered by the desktop JS)

/// Expected values rendered by running the desktop modules
/// (`limits/providerOrder.js`, `homeModulePreferences.js` on the iOS module
/// list, `clientDisplayPreferences.js`) over these inputs with Node.
private struct DesktopTables: Decodable {
    struct OrderCase: Decodable { var stored: [String]; var order: [String]; var selection: [String]; var ordered: [String] }
    struct MoveCase: Decodable { var stored: [String]; var id: String; var up: Bool; var result: [String] }
    struct ReorderCase: Decodable { var stored: [String]; var id: String; var index: Int; var result: [String] }
    struct HomeCase: Decodable {
        var order: [String]; var hidden: [String]
        var normalizedOrder: [String]; var normalizedHidden: [String]; var visible: [String]
    }
    struct HomeMoveCase: Decodable { var stored: [String]; var id: String; var up: Bool?; var index: Int?; var result: [String] }
    struct ApplyCase: Decodable {
        var order: [String]; var hidden: [String]; var pinned: [String]
        var result: [String]; var ordered: [String]; var hasPreferences: Bool; var hasCustomOrder: Bool
    }
    struct PinCase: Decodable {
        var pinned: [String]; var id: String
        var toggle: [String]; var up: [String]; var down: [String]; var reorder0: [String]; var reorder99: [String]
    }
    struct CommitCase: Decodable {
        var dropped: [String]; var order: [String]; var pinned: [String]; var id: String
        var resultOrder: [String]?; var resultPinned: [String]
    }

    var providerKnown: [String]
    var clientKnown: [String]
    var clientRows: [String]
    var orderCases: [OrderCase]
    var moveCases: [MoveCase]
    var reorderCases: [ReorderCase]
    var homeCases: [HomeCase]
    var homeMoveCases: [HomeMoveCase]
    var applyCases: [ApplyCase]
    var pinCases: [PinCase]
    var commitCases: [CommitCase]

    static func load() throws -> DesktopTables {
        try JSONDecoder().decode(DesktopTables.self, from: Data(json.utf8))
    }

    // Rendered by $SP/p1prefs/gen-tables.js (Node 22) from the worktree's
    // desktop sources; do not edit by hand.
    static let json = #"""
{
  "providerKnown": ["claude", "codex", "cursor", "antigravity"],
  "clientKnown": ["claude", "codex", "hermes", "opencode"],
  "clientRows": ["claude", "codex", "gemini", "opencode", "hermes", "__unattributed"],
  "orderCases": [
    {"stored": [], "order": ["claude", "codex", "cursor", "antigravity"], "selection": [], "ordered": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": [""], "order": ["claude", "codex", "cursor", "antigravity"], "selection": [], "ordered": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["codex", "unknown", "codex", "claude"], "order": ["codex", "claude", "cursor", "antigravity"], "selection": ["codex", "claude"], "ordered": ["codex", "claude", "cursor", "antigravity"]},
    {"stored": ["  Cursor ", "CODEX"], "order": ["cursor", "codex", "claude", "antigravity"], "selection": ["cursor", "codex"], "ordered": ["cursor", "codex", "claude", "antigravity"]},
    {"stored": ["antigravity", "cursor", "codex", "claude"], "order": ["antigravity", "cursor", "codex", "claude"], "selection": ["antigravity", "cursor", "codex", "claude"], "ordered": ["antigravity", "cursor", "codex", "claude"]},
    {"stored": ["unknown"], "order": ["claude", "codex", "cursor", "antigravity"], "selection": [], "ordered": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["claude", "claude", "claude"], "order": ["claude", "codex", "cursor", "antigravity"], "selection": ["claude"], "ordered": ["claude", "codex", "cursor", "antigravity"]}
  ],
  "moveCases": [
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "claude", "up": true, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "claude", "up": false, "result": ["codex", "claude", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "cursor", "up": true, "result": ["claude", "cursor", "codex", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "cursor", "up": false, "result": ["claude", "codex", "antigravity", "cursor"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "antigravity", "up": true, "result": ["claude", "codex", "antigravity", "cursor"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "antigravity", "up": false, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "unknown", "up": true, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "unknown", "up": false, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": " CODEX ", "up": true, "result": ["codex", "claude", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": " CODEX ", "up": false, "result": ["claude", "cursor", "codex", "antigravity"]},
    {"stored": [], "id": "claude", "up": true, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": [], "id": "claude", "up": false, "result": ["codex", "claude", "cursor", "antigravity"]},
    {"stored": [], "id": "cursor", "up": true, "result": ["claude", "cursor", "codex", "antigravity"]},
    {"stored": [], "id": "cursor", "up": false, "result": ["claude", "codex", "antigravity", "cursor"]},
    {"stored": [], "id": "antigravity", "up": true, "result": ["claude", "codex", "antigravity", "cursor"]},
    {"stored": [], "id": "antigravity", "up": false, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": [], "id": "unknown", "up": true, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": [], "id": "unknown", "up": false, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": [], "id": " CODEX ", "up": true, "result": ["codex", "claude", "cursor", "antigravity"]},
    {"stored": [], "id": " CODEX ", "up": false, "result": ["claude", "cursor", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "claude", "up": true, "result": ["claude", "cursor", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "claude", "up": false, "result": ["cursor", "codex", "claude", "antigravity"]},
    {"stored": ["cursor"], "id": "cursor", "up": true, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "cursor", "up": false, "result": ["claude", "cursor", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "antigravity", "up": true, "result": ["cursor", "claude", "antigravity", "codex"]},
    {"stored": ["cursor"], "id": "antigravity", "up": false, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "unknown", "up": true, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "unknown", "up": false, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": " CODEX ", "up": true, "result": ["cursor", "codex", "claude", "antigravity"]},
    {"stored": ["cursor"], "id": " CODEX ", "up": false, "result": ["cursor", "claude", "antigravity", "codex"]}
  ],
  "reorderCases": [
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "claude", "index": -3, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "claude", "index": 0, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "claude", "index": 1, "result": ["codex", "claude", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "claude", "index": 2, "result": ["codex", "cursor", "claude", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "claude", "index": 3, "result": ["codex", "cursor", "antigravity", "claude"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "claude", "index": 99, "result": ["codex", "cursor", "antigravity", "claude"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "cursor", "index": -3, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "cursor", "index": 0, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "cursor", "index": 1, "result": ["claude", "cursor", "codex", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "cursor", "index": 2, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "cursor", "index": 3, "result": ["claude", "codex", "antigravity", "cursor"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "cursor", "index": 99, "result": ["claude", "codex", "antigravity", "cursor"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "antigravity", "index": -3, "result": ["antigravity", "claude", "codex", "cursor"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "antigravity", "index": 0, "result": ["antigravity", "claude", "codex", "cursor"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "antigravity", "index": 1, "result": ["claude", "antigravity", "codex", "cursor"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "antigravity", "index": 2, "result": ["claude", "codex", "antigravity", "cursor"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "antigravity", "index": 3, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "antigravity", "index": 99, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "unknown", "index": -3, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "unknown", "index": 0, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "unknown", "index": 1, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "unknown", "index": 2, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "unknown", "index": 3, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["claude", "codex", "cursor", "antigravity"], "id": "unknown", "index": 99, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["cursor"], "id": "claude", "index": -3, "result": ["claude", "cursor", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "claude", "index": 0, "result": ["claude", "cursor", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "claude", "index": 1, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "claude", "index": 2, "result": ["cursor", "codex", "claude", "antigravity"]},
    {"stored": ["cursor"], "id": "claude", "index": 3, "result": ["cursor", "codex", "antigravity", "claude"]},
    {"stored": ["cursor"], "id": "claude", "index": 99, "result": ["cursor", "codex", "antigravity", "claude"]},
    {"stored": ["cursor"], "id": "cursor", "index": -3, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "cursor", "index": 0, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "cursor", "index": 1, "result": ["claude", "cursor", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "cursor", "index": 2, "result": ["claude", "codex", "cursor", "antigravity"]},
    {"stored": ["cursor"], "id": "cursor", "index": 3, "result": ["claude", "codex", "antigravity", "cursor"]},
    {"stored": ["cursor"], "id": "cursor", "index": 99, "result": ["claude", "codex", "antigravity", "cursor"]},
    {"stored": ["cursor"], "id": "antigravity", "index": -3, "result": ["antigravity", "cursor", "claude", "codex"]},
    {"stored": ["cursor"], "id": "antigravity", "index": 0, "result": ["antigravity", "cursor", "claude", "codex"]},
    {"stored": ["cursor"], "id": "antigravity", "index": 1, "result": ["cursor", "antigravity", "claude", "codex"]},
    {"stored": ["cursor"], "id": "antigravity", "index": 2, "result": ["cursor", "claude", "antigravity", "codex"]},
    {"stored": ["cursor"], "id": "antigravity", "index": 3, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "antigravity", "index": 99, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "unknown", "index": -3, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "unknown", "index": 0, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "unknown", "index": 1, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "unknown", "index": 2, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "unknown", "index": 3, "result": ["cursor", "claude", "codex", "antigravity"]},
    {"stored": ["cursor"], "id": "unknown", "index": 99, "result": ["cursor", "claude", "codex", "antigravity"]}
  ],
  "homeCases": [
    {"order": ["components", "limits", "tool", "model", "session", "device", "trends"], "hidden": ["tool", "device"], "normalizedOrder": ["components", "limits", "tool", "model", "session", "device", "trends"], "normalizedHidden": ["tool", "device"], "visible": ["components", "limits", "model", "session", "trends"]},
    {"order": ["device", "unknown", "device", "limits"], "hidden": ["tool", "unknown", "tool", "trends"], "normalizedOrder": ["device", "limits", "components", "tool", "model", "session", "trends"], "normalizedHidden": ["tool", "trends"], "visible": ["device", "limits", "components", "model", "session"]},
    {"order": ["model", "limits", "trends", "tool", "device"], "hidden": ["tool", "device"], "normalizedOrder": ["model", "limits", "trends", "tool", "device", "components", "session"], "normalizedHidden": ["tool", "device"], "visible": ["model", "limits", "trends", "components", "session"]},
    {"order": [], "hidden": [], "normalizedOrder": ["components", "limits", "tool", "model", "session", "device", "trends"], "normalizedHidden": [], "visible": ["components", "limits", "tool", "model", "session", "device", "trends"]},
    {"order": ["trends"], "hidden": ["components", "limits", "tool", "model", "session", "device", "trends"], "normalizedOrder": ["trends", "components", "limits", "tool", "model", "session", "device"], "normalizedHidden": [], "visible": ["trends", "components", "limits", "tool", "model", "session", "device"]},
    {"order": ["TRENDS", " model "], "hidden": ["components", "limits", "tool", "model", "session", "device"], "normalizedOrder": ["trends", "model", "components", "limits", "tool", "session", "device"], "normalizedHidden": ["components", "limits", "tool", "model", "session", "device"], "visible": ["trends"]}
  ],
  "homeMoveCases": [
    {"stored": ["limits", "tool", "device"], "id": "components", "up": true, "result": ["limits", "tool", "components", "device", "model", "session", "trends"]},
    {"stored": ["limits", "tool", "device"], "id": "components", "up": false, "result": ["limits", "tool", "device", "model", "components", "session", "trends"]},
    {"stored": ["limits", "tool", "device"], "id": "components", "index": 0, "result": ["components", "limits", "tool", "device", "model", "session", "trends"]},
    {"stored": ["limits", "tool", "device"], "id": "components", "index": 1, "result": ["limits", "components", "tool", "device", "model", "session", "trends"]},
    {"stored": ["limits", "tool", "device"], "id": "components", "index": 6, "result": ["limits", "tool", "device", "model", "session", "trends", "components"]},
    {"stored": ["limits", "tool", "device"], "id": "components", "index": 42, "result": ["limits", "tool", "device", "model", "session", "trends", "components"]},
    {"stored": ["limits", "tool", "device"], "id": "device", "up": true, "result": ["limits", "device", "tool", "components", "model", "session", "trends"]},
    {"stored": ["limits", "tool", "device"], "id": "device", "up": false, "result": ["limits", "tool", "components", "device", "model", "session", "trends"]},
    {"stored": ["limits", "tool", "device"], "id": "device", "index": 0, "result": ["device", "limits", "tool", "components", "model", "session", "trends"]},
    {"stored": ["limits", "tool", "device"], "id": "device", "index": 1, "result": ["limits", "device", "tool", "components", "model", "session", "trends"]},
    {"stored": ["limits", "tool", "device"], "id": "device", "index": 6, "result": ["limits", "tool", "components", "model", "session", "trends", "device"]},
    {"stored": ["limits", "tool", "device"], "id": "device", "index": 42, "result": ["limits", "tool", "components", "model", "session", "trends", "device"]},
    {"stored": ["limits", "tool", "device"], "id": "trends", "up": true, "result": ["limits", "tool", "device", "components", "model", "trends", "session"]},
    {"stored": ["limits", "tool", "device"], "id": "trends", "up": false, "result": ["limits", "tool", "device", "components", "model", "session", "trends"]},
    {"stored": ["limits", "tool", "device"], "id": "trends", "index": 0, "result": ["trends", "limits", "tool", "device", "components", "model", "session"]},
    {"stored": ["limits", "tool", "device"], "id": "trends", "index": 1, "result": ["limits", "trends", "tool", "device", "components", "model", "session"]},
    {"stored": ["limits", "tool", "device"], "id": "trends", "index": 6, "result": ["limits", "tool", "device", "components", "model", "session", "trends"]},
    {"stored": ["limits", "tool", "device"], "id": "trends", "index": 42, "result": ["limits", "tool", "device", "components", "model", "session", "trends"]}
  ],
  "applyCases": [
    {"order": [], "hidden": [], "pinned": [], "result": ["claude", "codex", "gemini", "opencode", "hermes", "__unattributed"], "ordered": ["claude", "codex", "hermes", "opencode"], "hasPreferences": false, "hasCustomOrder": false},
    {"order": [], "hidden": ["codex"], "pinned": [], "result": ["claude", "gemini", "opencode", "hermes", "__unattributed"], "ordered": ["claude", "codex", "hermes", "opencode"], "hasPreferences": true, "hasCustomOrder": false},
    {"order": [], "hidden": [], "pinned": ["hermes", "codex"], "result": ["hermes", "codex", "claude", "gemini", "opencode", "__unattributed"], "ordered": ["hermes", "codex", "claude", "opencode"], "hasPreferences": true, "hasCustomOrder": false},
    {"order": [], "hidden": ["hermes"], "pinned": ["hermes", "codex"], "result": ["codex", "claude", "gemini", "opencode", "__unattributed"], "ordered": ["hermes", "codex", "claude", "opencode"], "hasPreferences": true, "hasCustomOrder": false},
    {"order": ["hermes", "codex"], "hidden": ["claude"], "pinned": [], "result": ["hermes", "codex", "opencode", "gemini", "__unattributed"], "ordered": ["hermes", "codex", "claude", "opencode"], "hasPreferences": true, "hasCustomOrder": true},
    {"order": ["opencode", "claude", "hermes", "codex"], "hidden": [], "pinned": ["hermes", "codex"], "result": ["opencode", "claude", "hermes", "codex", "gemini", "__unattributed"], "ordered": ["opencode", "claude", "hermes", "codex"], "hasPreferences": true, "hasCustomOrder": true},
    {"order": ["unknown"], "hidden": [], "pinned": ["hermes"], "result": ["claude", "codex", "hermes", "opencode", "gemini", "__unattributed"], "ordered": ["claude", "codex", "hermes", "opencode"], "hasPreferences": true, "hasCustomOrder": true},
    {"order": [" "], "hidden": [], "pinned": ["hermes"], "result": ["hermes", "claude", "codex", "gemini", "opencode", "__unattributed"], "ordered": ["hermes", "claude", "codex", "opencode"], "hasPreferences": true, "hasCustomOrder": false},
    {"order": ["CODEX"], "hidden": ["GEMINI", "Opencode"], "pinned": ["unknown", "claude"], "result": ["codex", "claude", "hermes", "gemini", "__unattributed"], "ordered": ["codex", "claude", "hermes", "opencode"], "hasPreferences": true, "hasCustomOrder": true},
    {"order": [], "hidden": [], "pinned": ["unknown"], "result": ["claude", "codex", "gemini", "opencode", "hermes", "__unattributed"], "ordered": ["claude", "codex", "hermes", "opencode"], "hasPreferences": false, "hasCustomOrder": false}
  ],
  "pinCases": [
    {"pinned": ["hermes"], "id": "codex", "toggle": ["hermes", "codex"], "up": ["hermes"], "down": ["hermes"], "reorder0": ["hermes"], "reorder99": ["hermes"]},
    {"pinned": ["hermes"], "id": "hermes", "toggle": [], "up": ["hermes"], "down": ["hermes"], "reorder0": ["hermes"], "reorder99": ["hermes"]},
    {"pinned": ["hermes"], "id": "claude", "toggle": ["hermes", "claude"], "up": ["hermes"], "down": ["hermes"], "reorder0": ["hermes"], "reorder99": ["hermes"]},
    {"pinned": ["hermes"], "id": "opencode", "toggle": ["hermes", "opencode"], "up": ["hermes"], "down": ["hermes"], "reorder0": ["hermes"], "reorder99": ["hermes"]},
    {"pinned": ["hermes"], "id": "unknown", "toggle": ["hermes"], "up": ["hermes"], "down": ["hermes"], "reorder0": ["hermes"], "reorder99": ["hermes"]},
    {"pinned": ["hermes", "codex"], "id": "codex", "toggle": ["hermes"], "up": ["codex", "hermes"], "down": ["hermes", "codex"], "reorder0": ["codex", "hermes"], "reorder99": ["hermes", "codex"]},
    {"pinned": ["hermes", "codex"], "id": "hermes", "toggle": ["codex"], "up": ["hermes", "codex"], "down": ["codex", "hermes"], "reorder0": ["hermes", "codex"], "reorder99": ["codex", "hermes"]},
    {"pinned": ["hermes", "codex"], "id": "claude", "toggle": ["hermes", "codex", "claude"], "up": ["hermes", "codex"], "down": ["hermes", "codex"], "reorder0": ["hermes", "codex"], "reorder99": ["hermes", "codex"]},
    {"pinned": ["hermes", "codex"], "id": "opencode", "toggle": ["hermes", "codex", "opencode"], "up": ["hermes", "codex"], "down": ["hermes", "codex"], "reorder0": ["hermes", "codex"], "reorder99": ["hermes", "codex"]},
    {"pinned": ["hermes", "codex"], "id": "unknown", "toggle": ["hermes", "codex"], "up": ["hermes", "codex"], "down": ["hermes", "codex"], "reorder0": ["hermes", "codex"], "reorder99": ["hermes", "codex"]},
    {"pinned": ["hermes", "codex", "claude"], "id": "codex", "toggle": ["hermes", "claude"], "up": ["codex", "hermes", "claude"], "down": ["hermes", "claude", "codex"], "reorder0": ["codex", "hermes", "claude"], "reorder99": ["hermes", "claude", "codex"]},
    {"pinned": ["hermes", "codex", "claude"], "id": "hermes", "toggle": ["codex", "claude"], "up": ["hermes", "codex", "claude"], "down": ["codex", "hermes", "claude"], "reorder0": ["hermes", "codex", "claude"], "reorder99": ["codex", "claude", "hermes"]},
    {"pinned": ["hermes", "codex", "claude"], "id": "claude", "toggle": ["hermes", "codex"], "up": ["hermes", "claude", "codex"], "down": ["hermes", "codex", "claude"], "reorder0": ["claude", "hermes", "codex"], "reorder99": ["hermes", "codex", "claude"]},
    {"pinned": ["hermes", "codex", "claude"], "id": "opencode", "toggle": ["hermes", "codex", "claude", "opencode"], "up": ["hermes", "codex", "claude"], "down": ["hermes", "codex", "claude"], "reorder0": ["hermes", "codex", "claude"], "reorder99": ["hermes", "codex", "claude"]},
    {"pinned": ["hermes", "codex", "claude"], "id": "unknown", "toggle": ["hermes", "codex", "claude"], "up": ["hermes", "codex", "claude"], "down": ["hermes", "codex", "claude"], "reorder0": ["hermes", "codex", "claude"], "reorder99": ["hermes", "codex", "claude"]},
    {"pinned": [], "id": "codex", "toggle": ["codex"], "up": [], "down": [], "reorder0": [], "reorder99": []},
    {"pinned": [], "id": "hermes", "toggle": ["hermes"], "up": [], "down": [], "reorder0": [], "reorder99": []},
    {"pinned": [], "id": "claude", "toggle": ["claude"], "up": [], "down": [], "reorder0": [], "reorder99": []},
    {"pinned": [], "id": "opencode", "toggle": ["opencode"], "up": [], "down": [], "reorder0": [], "reorder99": []},
    {"pinned": [], "id": "unknown", "toggle": [], "up": [], "down": [], "reorder0": [], "reorder99": []},
    {"pinned": ["unknown", "Codex"], "id": "codex", "toggle": [], "up": ["codex"], "down": ["codex"], "reorder0": ["codex"], "reorder99": ["codex"]},
    {"pinned": ["unknown", "Codex"], "id": "hermes", "toggle": ["codex", "hermes"], "up": ["codex"], "down": ["codex"], "reorder0": ["codex"], "reorder99": ["codex"]},
    {"pinned": ["unknown", "Codex"], "id": "claude", "toggle": ["codex", "claude"], "up": ["codex"], "down": ["codex"], "reorder0": ["codex"], "reorder99": ["codex"]},
    {"pinned": ["unknown", "Codex"], "id": "opencode", "toggle": ["codex", "opencode"], "up": ["codex"], "down": ["codex"], "reorder0": ["codex"], "reorder99": ["codex"]},
    {"pinned": ["unknown", "Codex"], "id": "unknown", "toggle": ["codex"], "up": ["codex"], "down": ["codex"], "reorder0": ["codex"], "reorder99": ["codex"]}
  ],
  "commitCases": [
    {"dropped": ["codex", "hermes", "claude", "opencode"], "order": [], "pinned": ["hermes", "codex"], "id": "codex", "resultOrder": null, "resultPinned": ["codex", "hermes"]},
    {"dropped": ["codex", "claude", "hermes", "opencode"], "order": [], "pinned": ["hermes", "codex"], "id": "hermes", "resultOrder": ["codex", "claude", "hermes", "opencode"], "resultPinned": []},
    {"dropped": ["hermes", "codex", "opencode", "claude"], "order": [], "pinned": ["hermes", "codex"], "id": "opencode", "resultOrder": ["hermes", "codex", "opencode", "claude"], "resultPinned": []},
    {"dropped": ["codex", "hermes", "claude", "opencode"], "order": ["hermes", "codex", "claude", "opencode"], "pinned": ["hermes", "codex"], "id": "codex", "resultOrder": ["codex", "hermes", "claude", "opencode"], "resultPinned": []},
    {"dropped": ["codex", "claude", "hermes", "opencode"], "order": [], "pinned": [], "id": "codex", "resultOrder": ["codex", "claude", "hermes", "opencode"], "resultPinned": []},
    {"dropped": ["opencode", "claude", "codex", "hermes"], "order": [], "pinned": [], "id": "opencode", "resultOrder": ["opencode", "claude", "codex", "hermes"], "resultPinned": []},
    {"dropped": ["codex", "hermes"], "order": [], "pinned": ["hermes", "codex"], "id": "hermes", "resultOrder": null, "resultPinned": ["codex", "hermes"]}
  ]
}
"""#
}

final class OrderedIDsTests: XCTestCase {
    private var tables: DesktopTables!

    override func setUpWithError() throws {
        tables = try DesktopTables.load()
    }

    func testNormalizeOrderSelectionAndOrdered() {
        XCTAssertEqual(tables.orderCases.count, 7)
        for item in tables.orderCases {
            XCTAssertEqual(OrderedIDs.normalizeOrder(item.stored, known: tables.providerKnown), item.order, "\(item.stored)")
            XCTAssertEqual(OrderedIDs.normalizeSelection(item.stored, known: tables.providerKnown), item.selection, "\(item.stored)")
            XCTAssertEqual(OrderedIDs.ordered(tables.providerKnown, id: { $0 }, order: item.stored), item.ordered, "\(item.stored)")
        }
    }

    func testMove() {
        XCTAssertEqual(tables.moveCases.count, 30)
        for item in tables.moveCases {
            XCTAssertEqual(
                OrderedIDs.move(item.stored, id: item.id, up: item.up, known: tables.providerKnown), item.result,
                "\(item.stored) \(item.id) \(item.up ? "up" : "down")"
            )
        }
    }

    func testReorder() {
        XCTAssertEqual(tables.reorderCases.count, 48)
        for item in tables.reorderCases {
            XCTAssertEqual(
                OrderedIDs.reorder(item.stored, id: item.id, to: item.index, known: tables.providerKnown), item.result,
                "\(item.stored) \(item.id) → \(item.index)"
            )
        }
    }

    func testDesktopTestVectors() {
        // tests/electron/limitProviderOrder.test.js
        let providers = ["claude", "codex", "cursor", "antigravity"]
        XCTAssertEqual(OrderedIDs.normalizeOrder(["codex", "unknown", "codex", "claude"], known: providers), ["codex", "claude", "cursor", "antigravity"])
        XCTAssertEqual(OrderedIDs.normalizeSelection(["codex", "unknown", "codex"], known: providers), ["codex"])
        XCTAssertEqual(OrderedIDs.move(providers, id: "cursor", up: true, known: providers), ["claude", "cursor", "codex", "antigravity"])
        XCTAssertEqual(OrderedIDs.reorder(providers, id: "claude", to: 99, known: providers), ["codex", "cursor", "antigravity", "claude"])
        XCTAssertEqual(OrderedIDs.reorder(providers, id: "unknown", to: 1, known: providers), providers)
        XCTAssertTrue(OrderedIDs.hasCustomOrder(["unknown"]))
        XCTAssertFalse(OrderedIDs.hasCustomOrder(["", " "]))
    }

    func testOrderedKeepsAccountsOfOneProviderTogether() {
        struct Account: Equatable { var provider: String; var name: String }
        let accounts = [
            Account(provider: "codex", name: "a"), Account(provider: "Claude", name: "b"),
            Account(provider: "codex", name: "c"), Account(provider: "newcomer", name: "d"),
            Account(provider: "claude", name: "e")
        ]
        let catalog = ["claude", "codex", "cursor"]
        // Empty order: catalog order, unknown providers after it in Hub order.
        XCTAssertEqual(OrderedIDs.ordered(accounts, id: \.provider, order: [], known: catalog).map(\.name), ["b", "e", "a", "c", "d"])
        XCTAssertEqual(OrderedIDs.ordered(accounts, id: \.provider, order: ["newcomer", "codex"], known: catalog).map(\.name), ["d", "a", "c", "b", "e"])
        // Without a catalog the items' own order is the default.
        XCTAssertEqual(OrderedIDs.ordered(accounts, id: \.provider, order: []).map(\.name), ["a", "c", "b", "e", "d"])
    }
}

final class HomeModuleLayoutTests: XCTestCase {
    private func modules(_ ids: [String]) -> [HomeModule] { ids.compactMap(HomeModule.init(rawValue:)) }

    func testDefaultsShowTheDesktopDefaultModulesPlusComponents() {
        XCTAssertEqual(HomeModuleLayout.ordered(.defaults), HomeModule.defaultOrder)
        XCTAssertEqual(HomeModuleLayout.visible(.defaults), [.components, .limits, .model, .session, .trends])
    }

    func testDesktopTables() throws {
        let tables = try DesktopTables.load()
        XCTAssertEqual(tables.homeCases.count, 6)
        for item in tables.homeCases {
            // Unknown ids cannot be stored as `HomeModule`; the desktop drops
            // them, so feeding only the known ones is equivalent.
            let order = modules(item.order.map(OrderedIDs.normalizeID))
            let hidden = modules(item.hidden.map(OrderedIDs.normalizeID))
            let preferences = DisplayPreferences(homeModuleOrder: order, hiddenHomeModules: hidden)
            XCTAssertEqual(HomeModuleLayout.normalizedOrder(order).map(\.rawValue), item.normalizedOrder, "\(item.order)")
            XCTAssertEqual(HomeModuleLayout.normalizedHidden(hidden).map(\.rawValue), item.normalizedHidden, "\(item.hidden)")
            XCTAssertEqual(HomeModuleLayout.visible(preferences).map(\.rawValue), item.visible, "\(item.order) \(item.hidden)")
        }
        XCTAssertEqual(tables.homeMoveCases.count, 18)
        for item in tables.homeMoveCases {
            let stored = modules(item.stored)
            let module = try XCTUnwrap(HomeModule(rawValue: item.id))
            let result: [HomeModule]
            if let up = item.up {
                result = HomeModuleLayout.move(stored, module: module, up: up)
            } else {
                result = HomeModuleLayout.reorder(stored, module: module, to: try XCTUnwrap(item.index))
            }
            XCTAssertEqual(result.map(\.rawValue), item.result, "\(item.id) \(String(describing: item.up)) \(String(describing: item.index))")
        }
    }

    func testToggleHidden() {
        XCTAssertEqual(HomeModuleLayout.toggleHidden([.tool, .device], module: .tool), [.device])
        XCTAssertEqual(HomeModuleLayout.toggleHidden([.tool, .device], module: .trends), [.tool, .device, .trends])
        let allButOne = HomeModule.allCases.filter { $0 != .limits }
        XCTAssertEqual(HomeModuleLayout.toggleHidden(allButOne, module: .limits), [], "hiding the last module shows them all")
    }
}

final class ClientDisplayOrderTests: XCTestCase {
    func testDesktopTables() throws {
        let tables = try DesktopTables.load()
        let known = tables.clientKnown
        XCTAssertEqual(tables.applyCases.count, 10)
        for item in tables.applyCases {
            let label = "order \(item.order) hidden \(item.hidden) pinned \(item.pinned)"
            XCTAssertEqual(
                ClientDisplayOrder.apply(tables.clientRows, id: { $0 }, order: item.order, hidden: item.hidden, pinned: item.pinned, known: known),
                item.result, label
            )
            XCTAssertEqual(ClientDisplayOrder.orderedIDs(order: item.order, pinned: item.pinned, known: known), item.ordered, label)
            XCTAssertEqual(ClientDisplayOrder.hasPreferences(order: item.order, hidden: item.hidden, pinned: item.pinned, known: known), item.hasPreferences, label)
            XCTAssertEqual(ClientDisplayOrder.hasCustomOrder(item.order), item.hasCustomOrder, label)
        }
        XCTAssertEqual(tables.pinCases.count, 25)
        for item in tables.pinCases {
            let label = "\(item.pinned) \(item.id)"
            XCTAssertEqual(ClientDisplayOrder.togglePinned(item.pinned, id: item.id, known: known), item.toggle, label)
            XCTAssertEqual(ClientDisplayOrder.movePinned(item.pinned, id: item.id, up: true, known: known), item.up, label)
            XCTAssertEqual(ClientDisplayOrder.movePinned(item.pinned, id: item.id, up: false, known: known), item.down, label)
            XCTAssertEqual(ClientDisplayOrder.reorderPinned(item.pinned, id: item.id, to: 0, known: known), item.reorder0, label)
            XCTAssertEqual(ClientDisplayOrder.reorderPinned(item.pinned, id: item.id, to: 99, known: known), item.reorder99, label)
        }
        XCTAssertEqual(tables.commitCases.count, 7)
        for item in tables.commitCases {
            XCTAssertEqual(
                ClientDisplayOrder.commit(dropped: item.dropped, movedID: item.id, order: item.order, pinned: item.pinned, known: known),
                ClientDisplayOrder.Commit(clientDisplayOrder: item.resultOrder, pinnedClients: item.resultPinned),
                "\(item.dropped) \(item.id)"
            )
        }
    }

    func testCommitAppliesToPreferences() {
        var preferences = DisplayPreferences(clientDisplayOrder: ["claude"], pinnedClients: ["hermes"])
        ClientDisplayOrder.Commit(clientDisplayOrder: nil, pinnedClients: ["codex"]).apply(to: &preferences)
        XCTAssertEqual(preferences.clientDisplayOrder, ["claude"])
        XCTAssertEqual(preferences.pinnedClients, ["codex"])
        ClientDisplayOrder.Commit(clientDisplayOrder: ["codex", "claude"], pinnedClients: []).apply(to: &preferences)
        XCTAssertEqual(preferences.clientDisplayOrder, ["codex", "claude"])
        XCTAssertEqual(preferences.pinnedClients, [])
    }

    /// `attribution.json` `toolOrder`: `applyClientDisplayPreferences` over the
    /// fixture's usage-sorted tool rows with the desktop `KNOWN_CLIENT_LIST`
    /// (which leaves out gemini, so hiding gemini has no effect).
    func testAttributionGolden() throws {
        struct Golden: Decodable {
            struct Client: Decodable { var id: String }
            struct Row: Decodable { var key: String }
            struct Prefs: Decodable { var order: String; var hidden: String; var pinned: String }
            struct Scenario: Decodable { var prefs: Prefs; var keys: [String] }
            struct Scope: Decodable { var toolRows: [Row]; var toolOrder: [String: Scenario] }
            var knownClients: [Client]
            var scopes: [String: Scope]
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "attribution", withExtension: "json", subdirectory: "Fixtures/v2/golden"))
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
        let known = golden.knownClients.map(\.id)
        let csv = { (value: String) in value.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        var checked = 0
        for (scopeName, scope) in golden.scopes {
            let rows = scope.toolRows.map(\.key)
            for (name, scenario) in scope.toolOrder {
                let preferences = DisplayPreferences(
                    clientDisplayOrder: csv(scenario.prefs.order),
                    hiddenClients: csv(scenario.prefs.hidden),
                    pinnedClients: csv(scenario.prefs.pinned)
                )
                XCTAssertEqual(
                    ClientDisplayOrder.apply(rows, id: { $0 }, preferences: preferences, known: known),
                    scenario.keys, "\(scopeName) \(name)"
                )
                checked += 1
            }
        }
        XCTAssertEqual(checked, 12)
    }
}

// MARK: - RefreshPolicy

final class RefreshPolicyTests: XCTestCase {
    /// The fixed timings the defaults must reproduce: `WidgetTiming`
    /// (WidgetSupport.swift), `WatchStore` and `ComplicationProvider` /
    /// `ComplicationContent`.
    func testDefaultsReproduceTheFixedTimings() {
        let preferences = DisplayPreferences.defaults
        XCTAssertNil(RefreshPolicy.appPollInterval(preferences.appRefreshSeconds), "Live (SSE) by default")

        let widget = RefreshPolicy.widget(preferences.widgetRefreshMinutes)
        XCTAssertEqual(widget, WidgetRefreshTiming(refreshAfter: 10 * 60, reloadInterval: 15 * 60, staleAfter: 30 * 60))

        XCTAssertEqual(RefreshPolicy.watchPollInterval(preferences.watchRefreshSeconds), 60)
        XCTAssertEqual(RefreshPolicy.watch(preferences.watchRefreshSeconds), WatchRefreshTiming(pollInterval: 60, minimumRefreshAge: 30, staleAge: 15 * 60))

        XCTAssertEqual(
            RefreshPolicy.complication(preferences.complicationRefreshMinutes),
            ComplicationRefreshTiming(refreshAge: 20 * 60, reloadInterval: 20 * 60, unconfiguredReloadInterval: 60 * 60, staleAge: 60 * 60)
        )
        XCTAssertEqual(RefreshPolicy.serviceStatusInterval(preferences.serviceStatusRefreshMs), 60)
    }

    func testEveryChoice() {
        XCTAssertEqual(AppRefreshMode.allCases.map(RefreshPolicy.appPollInterval), [nil, 60, 120, 300, 900, 1800])
        XCTAssertEqual(
            WidgetRefreshInterval.allCases.map(RefreshPolicy.widget),
            [
                WidgetRefreshTiming(refreshAfter: 600, reloadInterval: 900, staleAfter: 1800),
                WidgetRefreshTiming(refreshAfter: 1500, reloadInterval: 1800, staleAfter: 3600),
                WidgetRefreshTiming(refreshAfter: 3300, reloadInterval: 3600, staleAfter: 7200)
            ]
        )
        XCTAssertEqual(WatchRefreshInterval.allCases.map(RefreshPolicy.watchPollInterval), [60, 120, 300, 900])
        XCTAssertEqual(WatchRefreshInterval.allCases.map { RefreshPolicy.watch($0).minimumRefreshAge }, [30, 30, 30, 30])
        XCTAssertEqual(WatchRefreshInterval.allCases.map { RefreshPolicy.watch($0).staleAge }, [900, 900, 900, 1800])
        XCTAssertEqual(ComplicationRefreshInterval.allCases.map { RefreshPolicy.complication($0).reloadInterval }, [1200, 1800, 3600])
        XCTAssertEqual(ComplicationRefreshInterval.allCases.map { RefreshPolicy.complication($0).refreshAge }, [1200, 1800, 3600])
        XCTAssertEqual(ComplicationRefreshInterval.allCases.map { RefreshPolicy.complication($0).staleAge }, [3600, 3600, 7200])
        XCTAssertEqual(ServiceStatusRefresh.allCases.map(RefreshPolicy.serviceStatusInterval), [nil, 60, 120, 300, 900, 1800])
    }
}

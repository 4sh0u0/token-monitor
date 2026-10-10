import Foundation

/// Every display preference the app, widgets, watch app and complications
/// share, stored as JSON in the App Group (`displayPreferences.v1`).
///
/// Property names are the desktop settings keys wherever the desktop has the
/// setting; `deviceScope`, the refresh intervals and `showStatusTab` are
/// iOS-only. Id lists (`hiddenClients`, provider orders, …) hold lowercased
/// ids. `limitProviderHiddenItems` maps a provider id to the item ids hidden
/// from its Limits rows. `vendorColors` maps a mark id to a `#rrggbb` override,
/// and `currencyRates` a currency code to a manual multiplier (USD ignored).
public struct DisplayPreferences: Sendable, Equatable {
    // Appearance, units and currency
    public var showToolIcons: Bool
    public var compactTokenUnits: CompactTokenUnits
    public var showCompactTotalTokens: Bool
    public var currency: DisplayCurrency
    public var currencyRates: [String: Double]
    public var vendorColors: [String: String]

    // Live rate, periods and scope
    public var showLiveTokenRate: Bool
    public var tokenRateMode: TokenRateMode
    public var liveTokenRateScope: LiveRateScope
    public var periodMonthMode: PeriodMonthMode
    public var deviceScope: DeviceScope

    // Overview (Home) modules and Activity
    public var homeModuleOrder: [HomeModule]
    public var hiddenHomeModules: [HomeModule]
    public var heatmapMetric: HeatmapMetric
    public var homeActiveDaysWindow: ActiveDaysWindow

    // Home limits module
    /// 1…12.
    public var homeLimitAccountCount: Int
    public var homeLimitDisplayMode: HomeLimitDisplayMode
    /// "Highlight low".
    public var showHomeLimitBars: Bool
    public var showHomeLimitProviderNames: Bool
    /// Empty: least remaining first.
    public var homeLimitProviderOrder: [String]
    public var hiddenHomeLimitProviders: [String]

    // Tools and models
    public var clientDisplayOrder: [String]
    public var hiddenClients: [String]
    public var pinnedClients: [String]
    public var modelRankingMetric: RankingMetric

    // Limits page
    public var showLimitUsed: Bool
    /// Empty: catalog order.
    public var limitProviderOrder: [String]
    public var limitProviderHiddenItems: [String: [String]]
    public var showCodexAdditionalLimits: Bool
    public var showLimitSource: Bool
    public var maskLimitAccountEmails: Bool

    // Sessions
    public var sessionTitlesEnabled: Bool
    public var sessionContextMetric: ContextMetric

    // Refresh
    public var appRefreshSeconds: AppRefreshMode
    public var widgetRefreshMinutes: WidgetRefreshInterval
    public var watchRefreshSeconds: WatchRefreshInterval
    public var complicationRefreshMinutes: ComplicationRefreshInterval
    public var serviceStatusRefreshMs: ServiceStatusRefresh

    // Status tab
    public var showStatusTab: Bool
    public var hiddenServiceProviders: [String]
    public var serviceProviderDisplayOrder: [String]

    /// Every preference at its default.
    public static let defaults = DisplayPreferences()

    public init(
        showToolIcons: Bool = true,
        compactTokenUnits: CompactTokenUnits = .western,
        showCompactTotalTokens: Bool = false,
        currency: DisplayCurrency = .usd,
        currencyRates: [String: Double] = [:],
        vendorColors: [String: String] = [:],
        showLiveTokenRate: Bool = false,
        tokenRateMode: TokenRateMode = .speed,
        liveTokenRateScope: LiveRateScope = .all,
        periodMonthMode: PeriodMonthMode = .month,
        deviceScope: DeviceScope = .all,
        homeModuleOrder: [HomeModule] = HomeModule.defaultOrder,
        hiddenHomeModules: [HomeModule] = HomeModule.defaultHidden,
        heatmapMetric: HeatmapMetric = .cost,
        homeActiveDaysWindow: ActiveDaysWindow = .all,
        homeLimitAccountCount: Int = 3,
        homeLimitDisplayMode: HomeLimitDisplayMode = .text,
        showHomeLimitBars: Bool = false,
        showHomeLimitProviderNames: Bool = false,
        homeLimitProviderOrder: [String] = [],
        hiddenHomeLimitProviders: [String] = [],
        clientDisplayOrder: [String] = [],
        hiddenClients: [String] = [],
        pinnedClients: [String] = [],
        modelRankingMetric: RankingMetric = .tokens,
        showLimitUsed: Bool = false,
        limitProviderOrder: [String] = [],
        limitProviderHiddenItems: [String: [String]] = [:],
        showCodexAdditionalLimits: Bool = true,
        showLimitSource: Bool = false,
        maskLimitAccountEmails: Bool = false,
        sessionTitlesEnabled: Bool = true,
        sessionContextMetric: ContextMetric = .used,
        appRefreshSeconds: AppRefreshMode = .live,
        widgetRefreshMinutes: WidgetRefreshInterval = .fifteenMinutes,
        watchRefreshSeconds: WatchRefreshInterval = .oneMinute,
        complicationRefreshMinutes: ComplicationRefreshInterval = .twentyMinutes,
        serviceStatusRefreshMs: ServiceStatusRefresh = .oneMinute,
        showStatusTab: Bool = false,
        hiddenServiceProviders: [String] = [],
        serviceProviderDisplayOrder: [String] = []
    ) {
        self.showToolIcons = showToolIcons
        self.compactTokenUnits = compactTokenUnits
        self.showCompactTotalTokens = showCompactTotalTokens
        self.currency = currency
        self.currencyRates = currencyRates
        self.vendorColors = vendorColors
        self.showLiveTokenRate = showLiveTokenRate
        self.tokenRateMode = tokenRateMode
        self.liveTokenRateScope = liveTokenRateScope
        self.periodMonthMode = periodMonthMode
        self.deviceScope = deviceScope
        self.homeModuleOrder = homeModuleOrder
        self.hiddenHomeModules = hiddenHomeModules
        self.heatmapMetric = heatmapMetric
        self.homeActiveDaysWindow = homeActiveDaysWindow
        self.homeLimitAccountCount = homeLimitAccountCount
        self.homeLimitDisplayMode = homeLimitDisplayMode
        self.showHomeLimitBars = showHomeLimitBars
        self.showHomeLimitProviderNames = showHomeLimitProviderNames
        self.homeLimitProviderOrder = homeLimitProviderOrder
        self.hiddenHomeLimitProviders = hiddenHomeLimitProviders
        self.clientDisplayOrder = clientDisplayOrder
        self.hiddenClients = hiddenClients
        self.pinnedClients = pinnedClients
        self.modelRankingMetric = modelRankingMetric
        self.showLimitUsed = showLimitUsed
        self.limitProviderOrder = limitProviderOrder
        self.limitProviderHiddenItems = limitProviderHiddenItems
        self.showCodexAdditionalLimits = showCodexAdditionalLimits
        self.showLimitSource = showLimitSource
        self.maskLimitAccountEmails = maskLimitAccountEmails
        self.sessionTitlesEnabled = sessionTitlesEnabled
        self.sessionContextMetric = sessionContextMetric
        self.appRefreshSeconds = appRefreshSeconds
        self.widgetRefreshMinutes = widgetRefreshMinutes
        self.watchRefreshSeconds = watchRefreshSeconds
        self.complicationRefreshMinutes = complicationRefreshMinutes
        self.serviceStatusRefreshMs = serviceStatusRefreshMs
        self.showStatusTab = showStatusTab
        self.hiddenServiceProviders = hiddenServiceProviders
        self.serviceProviderDisplayOrder = serviceProviderDisplayOrder
    }
}

// MARK: - Normalization

extension DisplayPreferences {
    /// Id lists and maps keep at most this many entries.
    public static let maxListCount = 64
    /// Longer ids are dropped from id lists and map keys (no real tool,
    /// provider, mark or device id comes close).
    public static let maxIDLength = 128
    /// Longer hidden Limits item ids are dropped (`usageItems.js`
    /// `parseWindowKey`).
    public static let maxHiddenItemLength = 400
    /// `homeLimitAccountCount` bounds (`main.js:532-544`).
    public static let homeLimitAccountCountRange = 1...12

    /// The stored form of every value, so equal settings compare and encode
    /// equal:
    /// - id lists: trimmed, lowercased, blanks and over-long ids dropped,
    ///   de-duplicated (first wins), at most `maxListCount`;
    /// - `homeModuleOrder` lists every module once and `hiddenHomeModules`
    ///   never hides all of them (`homeModulePreferences.js`);
    /// - `homeLimitAccountCount` is clamped to 1…12;
    /// - `currencyRates` keeps TWD/HKD/CNY multipliers that are finite and
    ///   > 0 (`normalizeCurrencyOverrides`; USD is the base);
    /// - `vendorColors` keeps valid `#rrggbb` values, lowercased, with the
    ///   desktop's `kilocode` → `kilo` and `micode` → `mimo` renames;
    /// - `limitProviderHiddenItems` keeps non-blank item ids up to 400
    ///   characters (case kept: they are JSON keys), at most 64 per
    ///   provider, and drops providers with nothing hidden;
    /// - a device scope with a blank id is `.all`.
    public func normalized() -> DisplayPreferences {
        var result = self
        result.currencyRates = Self.normalizedCurrencyRates(currencyRates)
        result.vendorColors = Self.normalizedVendorColors(vendorColors)
        result.deviceScope = DeviceScope(storageValue: deviceScope.storageValue) ?? .all
        result.homeModuleOrder = HomeModuleLayout.normalizedOrder(homeModuleOrder)
        result.hiddenHomeModules = HomeModuleLayout.normalizedHidden(hiddenHomeModules)
        result.homeLimitAccountCount = min(
            Self.homeLimitAccountCountRange.upperBound,
            max(Self.homeLimitAccountCountRange.lowerBound, homeLimitAccountCount)
        )
        result.homeLimitProviderOrder = Self.normalizedIDs(homeLimitProviderOrder)
        result.hiddenHomeLimitProviders = Self.normalizedIDs(hiddenHomeLimitProviders)
        result.clientDisplayOrder = Self.normalizedIDs(clientDisplayOrder)
        result.hiddenClients = Self.normalizedIDs(hiddenClients)
        result.pinnedClients = Self.normalizedIDs(pinnedClients)
        result.limitProviderOrder = Self.normalizedIDs(limitProviderOrder)
        result.limitProviderHiddenItems = Self.normalizedHiddenItems(limitProviderHiddenItems)
        result.hiddenServiceProviders = Self.normalizedIDs(hiddenServiceProviders)
        result.serviceProviderDisplayOrder = Self.normalizedIDs(serviceProviderDisplayOrder)
        return result
    }

    /// An id list in stored form (see `normalized()`).
    public static func normalizedIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in ids {
            let id = OrderedIDs.normalizeID(raw)
            guard !id.isEmpty, id.count <= maxIDLength, seen.insert(id).inserted else { continue }
            result.append(id)
            if result.count == maxListCount { break }
        }
        return result
    }

    static func normalizedCurrencyRates(_ rates: [String: Double]) -> [String: Double] {
        var result: [String: Double] = [:]
        for key in rates.keys.sorted() {
            let code = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard let currency = DisplayCurrency(rawValue: code), currency != .usd,
                  result[code] == nil, let rate = rates[key], rate.isFinite, rate > 0 else { continue }
            result[code] = rate
        }
        return result
    }

    static func normalizedVendorColors(_ colors: [String: String]) -> [String: String] {
        var source = colors
        // `main.js` `migrateVendorColors`: ids that were renamed on the desktop.
        for (old, new) in [("kilocode", "kilo"), ("micode", "mimo")] {
            if source[new] == nil, let value = source[old] { source[new] = value }
            source[old] = nil
        }
        var result: [String: String] = [:]
        for key in source.keys.sorted() {
            let id = OrderedIDs.normalizeID(key)
            guard !id.isEmpty, id.count <= maxIDLength, result[id] == nil,
                  let hex = source[key].flatMap(VendorPalette.normalizedHex) else { continue }
            result[id] = hex
            if result.count == maxListCount { break }
        }
        return result
    }

    static func normalizedHiddenItems(_ items: [String: [String]]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for key in items.keys.sorted() {
            let provider = OrderedIDs.normalizeID(key)
            guard !provider.isEmpty, provider.count <= maxIDLength, result[provider] == nil else { continue }
            var seen = Set<String>()
            var list: [String] = []
            for raw in items[key] ?? [] {
                let item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !item.isEmpty, item.utf16.count <= maxHiddenItemLength, seen.insert(item).inserted else { continue }
                list.append(item)
                if list.count == maxListCount { break }
            }
            guard !list.isEmpty else { continue }
            result[provider] = list
            if result.count == maxListCount { break }
        }
        return result
    }
}

// MARK: - Codable

/// Encodes every key; decodes leniently: a missing key, a value of the wrong
/// type or one outside its allowed set takes that key's default, unknown keys
/// are ignored, and the result is `normalized()`. Only a top level that is not
/// a JSON object fails to decode. Enum values may be stored with stray
/// whitespace or case, numbers as numeric strings, and id lists as the
/// desktop's comma-separated strings.
extension DisplayPreferences: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case showToolIcons, compactTokenUnits, showCompactTotalTokens, currency, currencyRates, vendorColors
        case showLiveTokenRate, tokenRateMode, liveTokenRateScope, periodMonthMode, deviceScope
        case homeModuleOrder, hiddenHomeModules, heatmapMetric, homeActiveDaysWindow
        case homeLimitAccountCount, homeLimitDisplayMode, showHomeLimitBars, showHomeLimitProviderNames
        case homeLimitProviderOrder, hiddenHomeLimitProviders
        case clientDisplayOrder, hiddenClients, pinnedClients, modelRankingMetric
        case showLimitUsed, limitProviderOrder, limitProviderHiddenItems, showCodexAdditionalLimits
        case showLimitSource, maskLimitAccountEmails
        case sessionTitlesEnabled, sessionContextMetric
        case appRefreshSeconds, widgetRefreshMinutes, watchRefreshSeconds, complicationRefreshMinutes
        case serviceStatusRefreshMs
        case showStatusTab, hiddenServiceProviders, serviceProviderDisplayOrder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys) -> PreferenceValue? {
            (try? container.decodeIfPresent(PreferenceValue.self, forKey: key)) ?? nil
        }
        let base = DisplayPreferences.defaults
        func bool(_ key: CodingKeys, _ fallback: Bool) -> Bool { value(key)?.boolValue ?? fallback }
        func text<E: RawRepresentable>(_ key: CodingKeys, _ fallback: E) -> E where E.RawValue == String {
            value(key)?.stringEnum() ?? fallback
        }
        func number<E: RawRepresentable>(_ key: CodingKeys, _ fallback: E) -> E where E.RawValue == Int {
            value(key)?.intEnum() ?? fallback
        }
        func ids(_ key: CodingKeys, _ fallback: [String]) -> [String] { value(key)?.stringList ?? fallback }
        func modules(_ key: CodingKeys, _ fallback: [HomeModule]) -> [HomeModule] {
            guard let list = value(key)?.stringList else { return fallback }
            return list.compactMap { HomeModule(rawValue: OrderedIDs.normalizeID($0)) }
        }

        var result = DisplayPreferences()
        result.showToolIcons = bool(.showToolIcons, base.showToolIcons)
        result.compactTokenUnits = text(.compactTokenUnits, base.compactTokenUnits)
        result.showCompactTotalTokens = bool(.showCompactTotalTokens, base.showCompactTotalTokens)
        result.currency = text(.currency, base.currency)
        result.currencyRates = value(.currencyRates)?.objectValue.map { object in
            object.compactMapValues(\.numberValue)
        } ?? base.currencyRates
        result.vendorColors = value(.vendorColors)?.objectValue.map { object in
            object.compactMapValues(\.stringValue)
        } ?? base.vendorColors
        result.showLiveTokenRate = bool(.showLiveTokenRate, base.showLiveTokenRate)
        result.tokenRateMode = text(.tokenRateMode, base.tokenRateMode)
        result.liveTokenRateScope = text(.liveTokenRateScope, base.liveTokenRateScope)
        result.periodMonthMode = text(.periodMonthMode, base.periodMonthMode)
        result.deviceScope = value(.deviceScope)?.stringValue.flatMap(DeviceScope.init(storageValue:)) ?? base.deviceScope
        result.homeModuleOrder = modules(.homeModuleOrder, base.homeModuleOrder)
        result.hiddenHomeModules = modules(.hiddenHomeModules, base.hiddenHomeModules)
        result.heatmapMetric = text(.heatmapMetric, base.heatmapMetric)
        result.homeActiveDaysWindow = text(.homeActiveDaysWindow, base.homeActiveDaysWindow)
        result.homeLimitAccountCount = value(.homeLimitAccountCount)?.numberValue.map { number in
            // `Math.trunc(Number(value))`, clamped before the Int conversion.
            let bounds = Self.homeLimitAccountCountRange
            return Int(min(Double(bounds.upperBound), max(Double(bounds.lowerBound), number.rounded(.towardZero))))
        } ?? base.homeLimitAccountCount
        result.homeLimitDisplayMode = text(.homeLimitDisplayMode, base.homeLimitDisplayMode)
        result.showHomeLimitBars = bool(.showHomeLimitBars, base.showHomeLimitBars)
        result.showHomeLimitProviderNames = bool(.showHomeLimitProviderNames, base.showHomeLimitProviderNames)
        result.homeLimitProviderOrder = ids(.homeLimitProviderOrder, base.homeLimitProviderOrder)
        result.hiddenHomeLimitProviders = ids(.hiddenHomeLimitProviders, base.hiddenHomeLimitProviders)
        result.clientDisplayOrder = ids(.clientDisplayOrder, base.clientDisplayOrder)
        result.hiddenClients = ids(.hiddenClients, base.hiddenClients)
        result.pinnedClients = ids(.pinnedClients, base.pinnedClients)
        result.modelRankingMetric = text(.modelRankingMetric, base.modelRankingMetric)
        result.showLimitUsed = bool(.showLimitUsed, base.showLimitUsed)
        result.limitProviderOrder = ids(.limitProviderOrder, base.limitProviderOrder)
        result.limitProviderHiddenItems = value(.limitProviderHiddenItems)?.objectValue.map { object in
            object.compactMapValues { $0.arrayValue?.compactMap(\.stringValue) }
        } ?? base.limitProviderHiddenItems
        result.showCodexAdditionalLimits = bool(.showCodexAdditionalLimits, base.showCodexAdditionalLimits)
        result.showLimitSource = bool(.showLimitSource, base.showLimitSource)
        result.maskLimitAccountEmails = bool(.maskLimitAccountEmails, base.maskLimitAccountEmails)
        result.sessionTitlesEnabled = bool(.sessionTitlesEnabled, base.sessionTitlesEnabled)
        result.sessionContextMetric = text(.sessionContextMetric, base.sessionContextMetric)
        result.appRefreshSeconds = number(.appRefreshSeconds, base.appRefreshSeconds)
        result.widgetRefreshMinutes = number(.widgetRefreshMinutes, base.widgetRefreshMinutes)
        result.watchRefreshSeconds = number(.watchRefreshSeconds, base.watchRefreshSeconds)
        result.complicationRefreshMinutes = number(.complicationRefreshMinutes, base.complicationRefreshMinutes)
        result.serviceStatusRefreshMs = number(.serviceStatusRefreshMs, base.serviceStatusRefreshMs)
        result.showStatusTab = bool(.showStatusTab, base.showStatusTab)
        result.hiddenServiceProviders = ids(.hiddenServiceProviders, base.hiddenServiceProviders)
        result.serviceProviderDisplayOrder = ids(.serviceProviderDisplayOrder, base.serviceProviderDisplayOrder)
        self = result.normalized()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showToolIcons, forKey: .showToolIcons)
        try container.encode(compactTokenUnits, forKey: .compactTokenUnits)
        try container.encode(showCompactTotalTokens, forKey: .showCompactTotalTokens)
        try container.encode(currency, forKey: .currency)
        try container.encode(currencyRates, forKey: .currencyRates)
        try container.encode(vendorColors, forKey: .vendorColors)
        try container.encode(showLiveTokenRate, forKey: .showLiveTokenRate)
        try container.encode(tokenRateMode, forKey: .tokenRateMode)
        try container.encode(liveTokenRateScope, forKey: .liveTokenRateScope)
        try container.encode(periodMonthMode, forKey: .periodMonthMode)
        try container.encode(deviceScope, forKey: .deviceScope)
        try container.encode(homeModuleOrder, forKey: .homeModuleOrder)
        try container.encode(hiddenHomeModules, forKey: .hiddenHomeModules)
        try container.encode(heatmapMetric, forKey: .heatmapMetric)
        try container.encode(homeActiveDaysWindow, forKey: .homeActiveDaysWindow)
        try container.encode(homeLimitAccountCount, forKey: .homeLimitAccountCount)
        try container.encode(homeLimitDisplayMode, forKey: .homeLimitDisplayMode)
        try container.encode(showHomeLimitBars, forKey: .showHomeLimitBars)
        try container.encode(showHomeLimitProviderNames, forKey: .showHomeLimitProviderNames)
        try container.encode(homeLimitProviderOrder, forKey: .homeLimitProviderOrder)
        try container.encode(hiddenHomeLimitProviders, forKey: .hiddenHomeLimitProviders)
        try container.encode(clientDisplayOrder, forKey: .clientDisplayOrder)
        try container.encode(hiddenClients, forKey: .hiddenClients)
        try container.encode(pinnedClients, forKey: .pinnedClients)
        try container.encode(modelRankingMetric, forKey: .modelRankingMetric)
        try container.encode(showLimitUsed, forKey: .showLimitUsed)
        try container.encode(limitProviderOrder, forKey: .limitProviderOrder)
        try container.encode(limitProviderHiddenItems, forKey: .limitProviderHiddenItems)
        try container.encode(showCodexAdditionalLimits, forKey: .showCodexAdditionalLimits)
        try container.encode(showLimitSource, forKey: .showLimitSource)
        try container.encode(maskLimitAccountEmails, forKey: .maskLimitAccountEmails)
        try container.encode(sessionTitlesEnabled, forKey: .sessionTitlesEnabled)
        try container.encode(sessionContextMetric, forKey: .sessionContextMetric)
        try container.encode(appRefreshSeconds, forKey: .appRefreshSeconds)
        try container.encode(widgetRefreshMinutes, forKey: .widgetRefreshMinutes)
        try container.encode(watchRefreshSeconds, forKey: .watchRefreshSeconds)
        try container.encode(complicationRefreshMinutes, forKey: .complicationRefreshMinutes)
        try container.encode(serviceStatusRefreshMs, forKey: .serviceStatusRefreshMs)
        try container.encode(showStatusTab, forKey: .showStatusTab)
        try container.encode(hiddenServiceProviders, forKey: .hiddenServiceProviders)
        try container.encode(serviceProviderDisplayOrder, forKey: .serviceProviderDisplayOrder)
    }

    /// The JSON the App Group store and the watch payload carry: sorted keys,
    /// so equal preferences give equal bytes.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Lenient decode of `jsonData()` (see the `Codable` conformance).
    public init(jsonData: Data) throws {
        self = try JSONDecoder().decode(DisplayPreferences.self, from: jsonData)
    }
}

/// Any JSON value, so each preference can be read without one bad value
/// failing the whole decode.
private enum PreferenceValue: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([PreferenceValue])
    case object([String: PreferenceValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([PreferenceValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: PreferenceValue].self))
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// A finite number, or a numeric string (`Number(value)`); blank strings
    /// are not numbers here.
    var numberValue: Double? {
        switch self {
        case .number(let value):
            return value.isFinite ? value : nil
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite else { return nil }
            return value
        default:
            return nil
        }
    }

    var arrayValue: [PreferenceValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: PreferenceValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// An array's strings (other elements dropped), or a comma-separated
    /// string split into its items (the desktop's CSV settings form).
    var stringList: [String]? {
        switch self {
        case .array(let items): return items.compactMap(\.stringValue)
        case .string(let csv): return csv.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        default: return nil
        }
    }

    /// The case whose raw value matches exactly, else after trimming, else
    /// ignoring case.
    func stringEnum<E: RawRepresentable>() -> E? where E.RawValue == String {
        guard let raw = stringValue else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return E(rawValue: raw) ?? E(rawValue: trimmed) ?? E(rawValue: trimmed.lowercased()) ?? E(rawValue: trimmed.uppercased())
    }

    /// The case whose raw value equals this integral number.
    func intEnum<E: RawRepresentable>() -> E? where E.RawValue == Int {
        guard let number = numberValue, number == number.rounded(), abs(number) <= Double(Int32.max) else { return nil }
        return E(rawValue: Int(number))
    }
}

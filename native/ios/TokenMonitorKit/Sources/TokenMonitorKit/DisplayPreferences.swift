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

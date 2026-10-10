import Foundation
import TokenMonitorKit

/// Representative data for placeholders, the widget gallery and previews.
/// Never shown on a placed widget (see `TokenTimeline.gallery`).
enum SampleSnapshot {
    /// - Parameter scoped: the numbers follow one device (`deviceScope`),
    ///   which has no trend in a snapshot.
    static func make(now: Date = Date(), fetchedAt: Date? = nil, scoped: Bool = false, calendar: Calendar = .current) -> TokenSnapshot {
        TokenSnapshot(
            fetchedAt: fetchedAt ?? now,
            sourceUpdatedAt: now.addingTimeInterval(-90),
            today: today,
            month: month,
            allTime: allTime,
            limits: limits(now: now),
            devices: DeviceCounts(online: 2, total: 3),
            trend: scoped ? [] : trend(endingAt: now, todayTokens: today.totalTokens, calendar: calendar),
            scope: scoped ? scope : nil
        )
    }

    static let scope = SnapshotScope(deviceID: "studio-mac", deviceName: "Studio Mac")

    static let today = PeriodSummary(
        kind: .today,
        totalTokens: 18_420_000,
        costUsd: 31.84,
        outputTokens: 412_000,
        cacheReadTokens: 15_100_000,
        cacheWriteTokens: 960_000,
        outputTokensPerSecond: 62.4,
        tools: [
            tool("claude", label: "Claude", tokens: 11_200_000, cost: 21.36),
            tool("codex", label: "Codex", tokens: 4_900_000, cost: 7.12),
            tool("opencode", label: "OpenCode", tokens: 1_300_000, cost: 2.11),
            tool("cursor", label: "Cursor", tokens: 620_000, cost: 1.25)
        ],
        models: [
            model("claude-sonnet-4-5", vendor: "claude", tokens: 9_100_000, cost: 15.02),
            model("gpt-5-codex", vendor: "codex", tokens: 4_900_000, cost: 7.12),
            model("claude-opus-4-1", vendor: "claude", tokens: 2_100_000, cost: 6.34),
            model("deepseek-chat", vendor: "deepseek", tokens: 1_100_000, cost: 1.06)
        ],
        otherToolTokens: 400_000,
        otherModelTokens: 1_220_000
    )

    static let month = PeriodSummary(
        kind: .month,
        totalTokens: 412_600_000,
        costUsd: 684.20,
        outputTokens: 9_480_000,
        cacheReadTokens: 341_000_000,
        cacheWriteTokens: 21_300_000,
        outputTokensPerSecond: 58.1,
        tools: [
            tool("claude", label: "Claude", tokens: 248_000_000, cost: 431.90),
            tool("codex", label: "Codex", tokens: 109_000_000, cost: 171.35),
            tool("opencode", label: "OpenCode", tokens: 31_000_000, cost: 48.70),
            tool("cursor", label: "Cursor", tokens: 14_000_000, cost: 22.05)
        ],
        models: [
            model("claude-sonnet-4-5", vendor: "claude", tokens: 201_000_000, cost: 318.40),
            model("gpt-5-codex", vendor: "codex", tokens: 109_000_000, cost: 171.35),
            model("claude-opus-4-1", vendor: "claude", tokens: 47_000_000, cost: 113.50),
            model("deepseek-chat", vendor: "deepseek", tokens: 26_000_000, cost: 24.60)
        ],
        otherToolTokens: 10_600_000,
        otherModelTokens: 29_600_000,
        unpricedTokens: 1_250_000
    )

    static let allTime = PeriodSummary(
        kind: .allTime,
        totalTokens: 2_870_000_000,
        costUsd: 4_918.55,
        outputTokens: 66_100_000,
        cacheReadTokens: 2_370_000_000,
        cacheWriteTokens: 148_000_000,
        outputTokensPerSecond: 55.7,
        tools: [
            tool("claude", label: "Claude", tokens: 1_640_000_000, cost: 2_975.10),
            tool("codex", label: "Codex", tokens: 812_000_000, cost: 1_296.40),
            tool("opencode", label: "OpenCode", tokens: 236_000_000, cost: 371.25),
            tool("cursor", label: "Cursor", tokens: 121_000_000, cost: 190.80)
        ],
        models: [
            model("claude-sonnet-4-5", vendor: "claude", tokens: 1_310_000_000, cost: 2_120.00),
            model("gpt-5-codex", vendor: "codex", tokens: 812_000_000, cost: 1_296.40),
            model("claude-opus-4-1", vendor: "claude", tokens: 330_000_000, cost: 855.10),
            model("deepseek-chat", vendor: "deepseek", tokens: 214_000_000, cost: 201.30)
        ],
        otherToolTokens: 61_000_000,
        otherModelTokens: 204_000_000
    )

    static func limits(now: Date) -> [LimitProvider] {
        [
            LimitProvider(
                id: "claude-sample",
                provider: "claude",
                planLabel: "Max",
                updatedAt: now,
                windows: [
                    LimitWindow(kind: .session, usedPercent: 77, remainingPercent: 23, resetsAt: now.addingTimeInterval(2 * 3600 + 13 * 60), windowMinutes: 300),
                    LimitWindow(kind: .weekly, usedPercent: 36, remainingPercent: 64, resetsAt: now.addingTimeInterval(3 * 86_400 + 22 * 3600))
                ]
            ),
            LimitProvider(
                id: "codex-sample",
                provider: "codex",
                planLabel: "Plus",
                updatedAt: now,
                windows: [
                    LimitWindow(kind: .session, usedPercent: 8, remainingPercent: 92, resetsAt: now.addingTimeInterval(4 * 3600 + 5 * 60)),
                    LimitWindow(kind: .weekly, usedPercent: 61, remainingPercent: 39, resetsAt: now.addingTimeInterval(2 * 86_400 + 3 * 3600))
                ]
            ),
            LimitProvider(
                id: "openrouter-sample",
                provider: "openrouter",
                planLabel: "API key",
                updatedAt: now,
                windows: [
                    LimitWindow(kind: .billing, label: "Credits", metric: .credits, usedPercent: 31, remainingPercent: 69, used: 6.2, limit: 20, remaining: 13.8, currency: "USD")
                ],
                balance: LimitBalance(amount: 13.8, currency: "USD", monthSpend: 6.2)
            ),
            LimitProvider(
                id: "deepseek-sample",
                provider: "deepseek",
                planLabel: "Pay-as-you-go",
                updatedAt: now,
                windows: [
                    LimitWindow(kind: .billing, metric: .credits, remaining: 86.42, currency: "CNY")
                ],
                balance: LimitBalance(amount: 86.42, currency: "CNY", monthSpend: 23.6)
            ),
            LimitProvider(
                id: "cursor-sample",
                provider: "cursor",
                planLabel: "Pro",
                status: .unauthorized,
                updatedAt: now.addingTimeInterval(-3 * 3600),
                windows: [
                    LimitWindow(kind: .billing, usedPercent: 54, remainingPercent: 46, resetsAt: now.addingTimeInterval(11 * 86_400))
                ]
            )
        ]
    }

    /// 30 days of a plausible working rhythm, ending on today's total.
    static func trend(endingAt now: Date, todayTokens: Int, calendar: Calendar) -> [HistoryDay] {
        let days = 30
        let today = calendar.startOfDay(for: now)
        return (0..<days).compactMap { index -> HistoryDay? in
            let offset = index - (days - 1)
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let wave = 1 + sin(Double(index) / 2.4)
            let weekday = calendar.component(.weekday, from: day)
            let weekendFactor = (weekday == 1 || weekday == 7) ? 0.45 : 1
            let tokens = offset == 0 ? todayTokens : Int((7_500_000 + 6_800_000 * wave) * weekendFactor)
            return HistoryDay(date: DayKey.string(from: day, calendar: calendar), tokens: tokens, costUsd: Double(tokens) / 580_000)
        }
    }

    /// A year of daily activity in the same rhythm, with quiet weekends and
    /// a few days off, as the app writes it for the Activity widget.
    static func activity(now: Date = Date(), generatedAt: Date? = nil, scoped: Bool = false, calendar: Calendar = .current) -> ActivitySnapshot {
        let today = calendar.startOfDay(for: now)
        let days = (0..<365).compactMap { index -> HistoryDay? in
            let offset = index - 364
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let weekday = calendar.component(.weekday, from: day)
            let weekend = weekday == 1 || weekday == 7
            // A slow ramp over the year, a weekly wave, and some days off.
            if index % 23 == 5 || (weekend && index % 3 == 0) { return nil }
            let ramp = 0.35 + 0.65 * Double(index) / 364
            let wave = 1 + sin(Double(index) / 3.1)
            let tokens = Int((4_000_000 + 9_000_000 * wave) * ramp * (weekend ? 0.4 : 1))
            return HistoryDay(date: DayKey.string(from: day, calendar: calendar), tokens: tokens, costUsd: Double(tokens) / 610_000)
        }
        return ActivitySnapshot(
            daily: days,
            hubKey: nil,
            scopeDeviceID: scoped ? scope.deviceID : nil,
            generatedAt: generatedAt ?? now,
            calendar: calendar
        )
    }

    private static func tool(_ id: String, label: String, tokens: Int, cost: Double) -> UsageShare {
        UsageShare(kind: .client, id: id, label: label, tokens: tokens, costUsd: cost, vendorID: id)
    }

    private static func model(_ name: String, vendor: String, tokens: Int, cost: Double) -> UsageShare {
        UsageShare(kind: .model, id: name, label: name, tokens: tokens, costUsd: cost, vendorID: vendor)
    }
}

// Entries for `#Preview` timelines.
extension TokenEntry {
    static func preview(
        period: UsagePeriodKind = .today,
        breakdown: BreakdownOption = .tools,
        pinnedLimitID: String? = nil,
        fetchedMinutesAgo: Double = 0,
        scoped: Bool = false,
        preferences: DisplayPreferences = .defaults
    ) -> TokenEntry {
        let now = Date()
        let snapshot = SampleSnapshot.make(now: now, fetchedAt: now.addingTimeInterval(-fetchedMinutesAgo * 60), scoped: scoped)
        return TokenEntry(
            date: now,
            state: .ready(snapshot),
            period: period,
            breakdown: breakdown,
            pinnedLimitID: pinnedLimitID,
            context: PresentationContext(preferences: preferences)
        )
    }

    static func previewState(_ state: WidgetDataState) -> TokenEntry {
        TokenEntry(date: Date(), state: state)
    }
}

extension ActivityEntry {
    static func preview(metric: HeatmapMetric = .cost, scoped: Bool = false, generatedDaysAgo: Double = 0) -> ActivityEntry {
        let now = Date()
        let snapshot = SampleSnapshot.activity(now: now, generatedAt: now.addingTimeInterval(-generatedDaysAgo * 86_400), scoped: scoped)
        return ActivityEntry(
            date: now,
            state: .ready(snapshot),
            metric: metric,
            scopeName: scoped ? SampleSnapshot.scope.deviceName : nil
        )
    }
}

// Preferences for previews of the user's display choices.
extension DisplayPreferences {
    /// Tool icons off (vendor-colour dots) and a vendor colour override.
    static var previewIconsOff: DisplayPreferences {
        var preferences = DisplayPreferences.defaults
        preferences.showToolIcons = false
        preferences.vendorColors = ["claude": "#ff8a3d"]
        return preferences
    }

    /// Quotas read as used, costs in New Taiwan dollars.
    static var previewUsedTWD: DisplayPreferences {
        var preferences = DisplayPreferences.defaults
        preferences.showLimitUsed = true
        preferences.currency = .twd
        return preferences
    }
}

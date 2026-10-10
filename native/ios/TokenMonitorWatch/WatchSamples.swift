import Foundation
import TokenMonitorKit

extension TokenSnapshot {
    /// Representative numbers for previews only; never shown as real data.
    static var watchSample: TokenSnapshot {
        let now = Date()
        let tools = [
            UsageShare(kind: .client, id: "claude", label: "Claude", tokens: 41_200_000, costUsd: 71.4, vendorID: "claude"),
            UsageShare(kind: .client, id: "codex", label: "Codex", tokens: 18_900_000, costUsd: 32.1, vendorID: "codex"),
            UsageShare(kind: .client, id: "opencode", label: "OpenCode", tokens: 7_600_000, costUsd: 12.9, vendorID: "opencode"),
            UsageShare(kind: .client, id: "gemini", label: "Gemini", tokens: 3_100_000, costUsd: 4.2, vendorID: "gemini")
        ]
        let today = PeriodSummary(
            kind: .today,
            totalTokens: 72_250_000,
            costUsd: 122.83,
            outputTokens: 1_450_000,
            cacheReadTokens: 61_000_000,
            outputTokensPerSecond: 62,
            tools: tools,
            otherToolTokens: 1_450_000
        )
        let month = PeriodSummary(kind: .month, totalTokens: 1_284_000_000, costUsd: 2_210.5, tools: tools.map { share in
            var scaled = share
            scaled.tokens *= 17
            return scaled
        }, unpricedTokens: 2_400_000)
        // `Int` is 32-bit on Apple Watch hardware: every count here, and
        // every product below, stays under `Int32.max` (2_147_483_647).
        let allTime = PeriodSummary(kind: .allTime, totalTokens: 1_933_100_000, costUsd: 3_286.27, tools: tools.map { share in
            var scaled = share
            scaled.tokens *= 26
            return scaled
        })
        let calendar = Calendar.current
        let trend: [HistoryDay] = (0..<14).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            let tokens = 30_000_000 + ((offset * 7_919) % 13) * 4_000_000
            return HistoryDay(date: DayKey.string(from: day, calendar: calendar), tokens: offset == 0 ? 72_250_000 : tokens, costUsd: Double(tokens) / 600_000)
        }
        return TokenSnapshot(
            fetchedAt: now.addingTimeInterval(-90),
            sourceUpdatedAt: now.addingTimeInterval(-150),
            today: today,
            month: month,
            allTime: allTime,
            limits: watchSampleLimits(now: now),
            devices: DeviceCounts(online: 2, total: 3),
            trend: trend
        )
    }

    /// `watchSample` scoped to one device that went offline: no trend (a
    /// device's history is not part of stats), smaller numbers.
    static var watchScopedSample: TokenSnapshot {
        var snapshot = watchSample
        snapshot.scope = SnapshotScope(deviceID: "studio-mac", deviceName: "Studio Mac", isStale: true)
        snapshot.trend = []
        for kind in UsagePeriodKind.allCases {
            var summary = snapshot[kind]
            summary.totalTokens /= 3
            summary.costUsd /= 3
            summary.tools = summary.tools.prefix(2).map { share in
                var scaled = share
                scaled.tokens /= 3
                return scaled
            }
            summary.otherToolTokens = summary.tokens(notIn: summary.tools)
            switch kind {
            case .today: snapshot.today = summary
            case .month: snapshot.month = summary
            case .allTime: snapshot.allTime = summary
            }
        }
        return snapshot
    }

    private static func watchSampleLimits(now: Date) -> [LimitProvider] {
        [
            LimitProvider(
                id: "claude-sample",
                provider: "claude",
                planLabel: "Max",
                updatedAt: now.addingTimeInterval(-240),
                windows: [
                    LimitWindow(kind: .session, usedPercent: 42, remainingPercent: 58, resetsAt: now.addingTimeInterval(2.5 * 3600)),
                    LimitWindow(kind: .weekly, usedPercent: 20.5, remainingPercent: 79.5, resetsAt: now.addingTimeInterval(4 * 86_400))
                ]
            ),
            LimitProvider(
                id: "codex-sample-work",
                provider: "codex",
                accountEmail: "d***v@example.com",
                accountName: "Work",
                planLabel: "Plus",
                updatedAt: now.addingTimeInterval(-60),
                windows: [
                    LimitWindow(kind: .session, usedPercent: 8, remainingPercent: 92, resetsAt: now.addingTimeInterval(4 * 3600)),
                    LimitWindow(kind: .weekly, usedPercent: 81, remainingPercent: 19, resetsAt: now.addingTimeInterval(2 * 86_400))
                ]
            ),
            LimitProvider(
                id: "codex-sample-personal",
                provider: "codex",
                accountEmail: "d***v@example.com",
                planLabel: "Pro",
                updatedAt: now.addingTimeInterval(-3 * 3600),
                isStale: true,
                windows: [
                    LimitWindow(kind: .session, usedPercent: 55, remainingPercent: 45, resetsAt: now.addingTimeInterval(3600))
                ],
                workspaceKind: "personal"
            ),
            LimitProvider(
                id: "openrouter-sample",
                provider: "openrouter",
                updatedAt: now,
                windows: [LimitWindow(kind: .billing, metric: .credits, remaining: 12.75, currency: "USD")],
                balance: LimitBalance(amount: 12.75, currency: "USD", monthSpend: 7.25)
            ),
            LimitProvider(
                id: "cursor-sample",
                provider: "cursor",
                status: .unauthorized,
                updatedAt: now.addingTimeInterval(-600),
                windows: [
                    LimitWindow(kind: .billing, usedPercent: 64, remainingPercent: 36, resetsAt: now.addingTimeInterval(12 * 86_400))
                ]
            )
        ]
    }
}

extension PresentationContext {
    /// Previews only: Traditional Chinese units in TWD, used mode, no tool
    /// icons, Codex listed first.
    static var watchSample: PresentationContext {
        var preferences = DisplayPreferences.defaults
        preferences.compactTokenUnits = .localized
        preferences.currency = .twd
        preferences.showLimitUsed = true
        preferences.showToolIcons = false
        preferences.limitProviderOrder = ["codex"]
        return PresentationContext(preferences: preferences, languageIdentifier: "zh-Hant")
    }
}

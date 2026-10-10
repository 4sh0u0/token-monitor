import Foundation
import TokenMonitorKit

extension ComplicationEntry {
    /// The face gallery and previews; never shown on a configured face.
    static var sample: ComplicationEntry {
        sample(context: .standard)
    }

    /// The sample numbers presented with `context` (the user's units and
    /// currency in the face gallery).
    static func sample(context: PresentationContext, snapshot: TokenSnapshot = .complicationSample) -> ComplicationEntry {
        ComplicationEntry(date: Date(), snapshot: snapshot, isConfigured: true, context: context)
    }
}

extension TokenSnapshot {
    static var complicationSample: TokenSnapshot {
        let now = Date()
        let today = PeriodSummary(
            kind: .today,
            totalTokens: 72_250_000,
            costUsd: 122.83,
            outputTokensPerSecond: 62,
            tools: [
                UsageShare(kind: .client, id: "claude", label: "Claude", tokens: 41_200_000, costUsd: 71.4, vendorID: "claude"),
                UsageShare(kind: .client, id: "codex", label: "Codex", tokens: 18_900_000, costUsd: 32.1, vendorID: "codex")
            ],
            otherToolTokens: 12_150_000
        )
        let limits = [
            LimitProvider(
                id: "claude-sample",
                provider: "claude",
                planLabel: "Max",
                updatedAt: now,
                windows: [
                    LimitWindow(kind: .session, usedPercent: 42, remainingPercent: 58, resetsAt: now.addingTimeInterval(2.5 * 3600)),
                    LimitWindow(kind: .weekly, usedPercent: 20.5, remainingPercent: 79.5, resetsAt: now.addingTimeInterval(4 * 86_400))
                ]
            ),
            LimitProvider(
                id: "codex-sample",
                provider: "codex",
                planLabel: "Plus",
                updatedAt: now,
                windows: [
                    LimitWindow(kind: .session, usedPercent: 8, remainingPercent: 92, resetsAt: now.addingTimeInterval(4 * 3600)),
                    LimitWindow(kind: .weekly, usedPercent: 81, remainingPercent: 19, resetsAt: now.addingTimeInterval(2 * 86_400))
                ]
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
                updatedAt: now
            )
        ]
        let calendar = Calendar.current
        let trend: [HistoryDay] = (0..<14).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            let tokens = offset == 0 ? 72_250_000 : 30_000_000 + ((offset * 7_919) % 13) * 4_000_000
            return HistoryDay(date: DayKey.string(from: day, calendar: calendar), tokens: tokens, costUsd: Double(tokens) / 600_000)
        }
        return TokenSnapshot(
            fetchedAt: now,
            today: today,
            month: PeriodSummary(kind: .month, totalTokens: 1_284_000_000, costUsd: 2_210.5),
            allTime: PeriodSummary(kind: .allTime, totalTokens: 4_233_100_000, costUsd: 7_196.27),
            limits: limits,
            devices: DeviceCounts(online: 2, total: 3),
            trend: trend
        )
    }

    /// One device's numbers: no trend, a scope to label.
    static var complicationScopedSample: TokenSnapshot {
        var snapshot = complicationSample
        snapshot.scope = SnapshotScope(deviceID: "studio-mac", deviceName: "Studio Mac")
        snapshot.trend = []
        snapshot.today.totalTokens = 24_100_000
        snapshot.today.costUsd = 40.95
        snapshot.today.unpricedTokens = 1_200_000
        return snapshot
    }
}

extension PresentationContext {
    /// Previews only: Japanese units in CNY, used mode, Claude hidden from
    /// the Quota complication.
    static var complicationSample: PresentationContext {
        var preferences = DisplayPreferences.defaults
        preferences.compactTokenUnits = .localized
        preferences.currency = .cny
        preferences.showLimitUsed = true
        preferences.hiddenHomeLimitProviders = ["claude"]
        return PresentationContext(preferences: preferences, languageIdentifier: "ja")
    }
}

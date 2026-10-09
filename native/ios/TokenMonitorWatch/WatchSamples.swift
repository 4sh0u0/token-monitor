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
        })
        let allTime = PeriodSummary(kind: .allTime, totalTokens: 4_233_100_000, costUsd: 7_196.27, tools: tools.map { share in
            var scaled = share
            scaled.tokens *= 58
            return scaled
        })
        let limits = [
            LimitProvider(
                id: "claude-sample",
                provider: "claude",
                planLabel: "Max",
                updatedAt: now,
                windows: [
                    LimitWindow(kind: .session, usedPercent: 42, remainingPercent: 58, resetsAt: now.addingTimeInterval(2.5 * 3600)),
                    LimitWindow(kind: .weekly, usedPercent: 20.5, remainingPercent: 79.5, resetsAt: now.addingTimeInterval(4 * 86_400)),
                    LimitWindow(kind: .billing, label: "Balance", metric: .credits, remaining: 37.5, currency: "USD", showMeter: false)
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
            )
        ]
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
            limits: limits,
            devices: DeviceCounts(online: 2, total: 3),
            trend: trend
        )
    }
}

import Foundation
import SwiftUI
import TokenMonitorKit

/// User-facing text of the widgets. Numbers come from `TokenFormat`; the
/// words around them come from this target's String Catalog, with the macOS
/// widget's terminology.
enum WidgetText {
    // MARK: Periods

    /// Section headers and the circular gauge ("TODAY").
    static func shortPeriod(_ period: UsagePeriodKind) -> String {
        switch period {
        case .today: return String(localized: "TODAY")
        case .month: return String(localized: "MONTH")
        case .allTime: return String(localized: "TOTAL")
        }
    }

    static func period(_ period: UsagePeriodKind) -> String {
        switch period {
        case .today: return String(localized: "Today")
        case .month: return String(localized: "This Month")
        case .allTime: return String(localized: "All Time")
        }
    }

    // MARK: Usage

    static func tokens(_ value: Int) -> String {
        TokenFormat.compactTokens(value)
    }

    /// Whole cents up to $100K ("$4,918.55"); compact beyond, where the cents
    /// stop mattering and the width starts to.
    static func cost(_ usd: Double) -> String {
        usd >= 100_000 ? TokenFormat.compactUSD(usd) : TokenFormat.usd(usd)
    }

    /// The period's cost, or `noValue` when its figures are unknown.
    static func cost(_ summary: PeriodSummary?) -> String {
        summary.map { cost($0.costUsd) } ?? noValue
    }

    /// In place of a figure that is not known, e.g. today's total while the
    /// cache is still yesterday's.
    static let noValue = "—"

    static func tokenCount(_ value: Int) -> String {
        let count = tokens(value)
        return String(localized: "\(count) tokens")
    }

    static func rate(_ perSecond: Double) -> String {
        let rate = TokenFormat.tokensPerSecond(perSecond)
        return String(localized: "\(rate) tok/s")
    }

    static func share(_ fraction: Double) -> String {
        TokenFormat.percent(fraction * 100)
    }

    static func updated(_ date: Date, now: Date) -> String {
        let moment = TokenFormat.moment(date, relativeTo: now)
        return String(localized: "Updated \(moment)")
    }

    static var other: String { String(localized: "Other") }

    static func breakdownTitle(_ breakdown: BreakdownOption) -> String {
        switch breakdown {
        case .tools: return String(localized: "Tools")
        case .models: return String(localized: "Models")
        }
    }

    // MARK: Limits

    static var limits: String { String(localized: "Limits") }

    /// The provider's label when it sent one ("Credits", a Codex model
    /// bucket), else the window kind. Provider labels are shown as sent.
    static func windowTitle(_ window: LimitWindow) -> String {
        if let label = window.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        if window.isCredits { return String(localized: "Balance") }
        if window.isSpend { return String(localized: "Spend") }
        switch window.kind {
        case .session: return String(localized: "Session")
        case .daily: return String(localized: "Daily")
        case .weekly: return String(localized: "Weekly")
        case .billing: return String(localized: "Billing")
        }
    }

    /// The headline of a window: money for balance/spend windows (keyed off
    /// `metric`, never the provider), else the percentage left.
    static func windowValue(_ window: LimitWindow, in provider: LimitProvider, compact: Bool, withLeft: Bool) -> String {
        if window.isUnlimited { return compact ? "∞" : String(localized: "Unlimited") }
        if window.isMoney {
            let amount = window.moneyAmount ?? (window.isCredits ? provider.balance?.amount : nil)
            if let amount {
                let currency = window.currency ?? provider.balance?.currency
                let money = compact
                    ? TokenFormat.compactMoney(amount, currency: currency)
                    : TokenFormat.money(amount, currency: currency)
                return withLeft && window.isCredits ? String(localized: "\(money) left") : money
            }
        }
        if let remaining = window.remainingPercent {
            let percent = TokenFormat.percent(remaining)
            return withLeft ? String(localized: "\(percent) left") : percent
        }
        return "—"
    }

    static func status(_ provider: LimitProvider) -> String {
        switch provider.status {
        case .ok: return String(localized: "Available")
        case .disabled: return String(localized: "Disabled")
        case .notConfigured: return String(localized: "Not configured")
        case .unauthorized: return String(localized: "Sign in again")
        case .rateLimited, .sourceRateLimited: return String(localized: "Rate limited")
        case .unavailable: return String(localized: "Unavailable")
        case .error: return String(localized: "Temporarily unavailable")
        }
    }

    /// "Reset in 2 hr, 13 min", counting down live. Nil once the boundary has
    /// passed at `now` (the entry date): a relative date style would start
    /// counting up again.
    static func boundary(_ window: LimitWindow, now: Date) -> Text? {
        guard let date = window.resetsAt, date > now else { return nil }
        let countdown = Text(date, style: .relative)
        switch window.boundaryKind {
        case .reset: return Text("Reset in \(countdown)")
        case .expiry: return Text("Expires in \(countdown)")
        case .mixed: return Text("Changes in \(countdown)")
        }
    }

    // MARK: States

    static var staleHint: String { String(localized: "Data may be stale") }
}

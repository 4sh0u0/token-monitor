import Foundation
import TokenMonitorKit

/// Localized wording for values the Kit hands over as data. Every string
/// literal here is a key in this target's `Localizable.xcstrings`.
enum WatchText {
    static func periodTitle(_ period: UsagePeriodKind) -> String {
        switch period {
        case .today: return String(localized: "Today")
        case .month: return String(localized: "This month")
        case .allTime: return String(localized: "All time")
        }
    }

    static func errorMessage(_ error: HubClientError) -> String {
        switch error {
        case .notConfigured: return String(localized: "Open Token Monitor on your iPhone to connect a Hub")
        case .invalidURL: return String(localized: "Check the Hub URL on your iPhone")
        case .unauthorized: return String(localized: "Wrong or missing secret")
        case .http: return String(localized: "Hub returned an error")
        case .transport: return String(localized: "Can't reach the Hub")
        case .decoding: return String(localized: "Unexpected response from the Hub")
        }
    }

    static func status(_ status: LimitStatus) -> String {
        switch status {
        case .ok: return String(localized: "Available")
        case .disabled: return String(localized: "Disabled")
        case .notConfigured: return String(localized: "Not configured")
        case .unauthorized: return String(localized: "Sign in again")
        case .rateLimited, .sourceRateLimited: return String(localized: "Rate limited")
        case .unavailable: return String(localized: "Temporarily unavailable")
        case .error: return String(localized: "Unavailable")
        }
    }

    /// The provider's own label ("Credits", a Codex model bucket), else the
    /// window's kind.
    static func windowTitle(_ window: LimitWindow) -> String {
        if let label = window.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        switch window.metric {
        case .credits: return String(localized: "Balance")
        case .spend: return String(localized: "Spend")
        case nil: break
        }
        switch window.kind {
        case .session: return String(localized: "Session")
        case .daily: return String(localized: "Daily")
        case .weekly: return String(localized: "Weekly")
        case .billing: return String(localized: "Billing")
        }
    }

    /// "58% left", "$37.50 left" for a balance, "$12.40" for spend. Money
    /// display keys off `metric`, never off the provider.
    static func windowValue(_ window: LimitWindow, in provider: LimitProvider) -> String {
        if window.isCredits, window.isUnlimited {
            return String(localized: "Unlimited")
        }
        if window.isCredits, let amount = window.remaining ?? provider.balance?.amount {
            let money = TokenFormat.money(amount, currency: window.currency ?? provider.balance?.currency)
            return String(localized: "\(money) left")
        }
        if window.isSpend, let used = window.used {
            return TokenFormat.money(used, currency: window.currency)
        }
        if let remaining = window.remainingPercent {
            return String(localized: "\(Int(remaining.rounded()))% left")
        }
        return "—"
    }

    /// The number inside a quota ring: "58%", or a compact amount.
    static func ringValue(_ window: LimitWindow?, in provider: LimitProvider) -> String {
        guard let window else { return "—" }
        if window.isMoney {
            if window.isUnlimited { return "∞" }
            let amount = window.isCredits ? (window.remaining ?? provider.balance?.amount) : window.used
            return amount.map { TokenFormat.compactMoney($0, currency: window.currency ?? provider.balance?.currency) } ?? "—"
        }
        return window.remainingPercent.map { TokenFormat.percent($0) } ?? "—"
    }
}

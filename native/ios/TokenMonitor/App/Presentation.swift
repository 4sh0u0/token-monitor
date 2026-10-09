import Foundation
import TokenMonitorKit

// Localized names and formatted values for Kit models. Kept free of SwiftUI so
// the wording lives in one place for every screen.

extension UsagePeriodKind {
    /// The hero card's title.
    var title: String {
        switch self {
        case .today: return String(localized: "Today")
        case .month: return String(localized: "This month")
        case .allTime: return String(localized: "All time")
        }
    }

    /// The period picker's segment.
    var shortTitle: String {
        switch self {
        case .today: return String(localized: "Today")
        case .month: return String(localized: "Month")
        case .allTime: return String(localized: "All time")
        }
    }
}

extension LimitProvider {
    var statusTitle: String {
        switch status {
        case .ok: return String(localized: "Available")
        case .unauthorized: return String(localized: "Sign in again")
        case .rateLimited, .sourceRateLimited: return String(localized: "Rate limited")
        case .unavailable: return String(localized: "Temporarily unavailable")
        case .error: return String(localized: "Unavailable")
        case .disabled: return String(localized: "Disabled")
        case .notConfigured: return String(localized: "Not configured")
        }
    }
}

extension LimitWindow {
    /// The provider's own label, else a name for the window's kind.
    var displayTitle: String {
        if let label { return label }
        if isCredits { return String(localized: "Balance") }
        switch kind {
        case .session: return String(localized: "Session")
        case .daily: return String(localized: "Daily")
        case .weekly: return String(localized: "Weekly")
        case .billing: return isSpend ? String(localized: "Spend") : String(localized: "Billing")
        }
    }

    /// The window's headline: money for balance and spend windows (keyed off
    /// `metric`, never the provider), otherwise what is left in percent.
    var headline: String {
        if isUnlimited { return String(localized: "Unlimited") }
        if isSpend, let used = moneyAmount {
            let usedText = TokenFormat.money(used, currency: currency)
            if let limit, limit > 0 {
                let limitText = TokenFormat.money(limit, currency: currency)
                return String(localized: "\(usedText) of \(limitText) used")
            }
            return String(localized: "\(usedText) used")
        }
        if isCredits, let remaining = moneyAmount {
            let amount = TokenFormat.money(remaining, currency: currency)
            return String(localized: "\(amount) left")
        }
        if let remainingPercent {
            let percent = TokenFormat.percent(remainingPercent)
            return String(localized: "\(percent) left")
        }
        return "—"
    }

    /// "Resets in 2h 30m" / "Expires in 3d 4h" / "Changes in …", worded by
    /// `boundaryKind`; nil without a boundary.
    func boundaryText(now: Date) -> String? {
        guard let resetsAt else { return nil }
        guard resetsAt > now else {
            switch boundaryKind {
            case .reset: return String(localized: "Resetting now")
            case .expiry: return String(localized: "Expired")
            case .mixed: return String(localized: "Changes now")
            }
        }
        let countdown = TokenFormat.countdown(to: resetsAt, from: now)
        switch boundaryKind {
        case .reset: return String(localized: "Resets in \(countdown)")
        case .expiry: return String(localized: "Expires in \(countdown)")
        case .mixed: return String(localized: "Changes in \(countdown)")
        }
    }
}

extension DeviceSummary {
    /// Today's tokens, zero once the device's day has ended (the Hub no
    /// longer counts it).
    var todayTokens: Int { today.isExpired ? 0 : today.tokens }
    var todayCost: Double { today.isExpired ? 0 : today.costUsd }

    var platformSymbol: String {
        switch platformFamily {
        case .macOS: return "laptopcomputer"
        case .windows: return "pc"
        case .linux: return "server.rack"
        case .other: return "desktopcomputer"
        }
    }
}

enum AppFormat {
    /// A row's share of its period: one decimal under 10 %, whole above.
    static func share(_ fraction: Double) -> String {
        let percent = fraction * 100
        return TokenFormat.percent(percent, fractionDigits: percent > 0 && percent < 10 ? 1 : 0)
    }

    /// "5 min. ago", never "in …": a timestamp later than `now` (data newer
    /// than the last TimelineView tick, or a device clock running ahead)
    /// reads as just now, and so does anything under a minute, which the
    /// views only re-render every 30 s anyway.
    static func ago(_ date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return String(localized: "just now") }
        return TokenFormat.relative(date, to: now)
    }

    /// "62 tok/s" (the unit is not translated, as on the desktop).
    static func outputSpeed(_ rate: Double) -> String {
        let value = TokenFormat.tokensPerSecond(rate)
        return String(localized: "\(value) tok/s")
    }

    /// The Hub runtime a health check reported, for "Connected to …".
    static func runtimeName(_ runtime: String?) -> String {
        switch runtime {
        case "node-hub": return String(localized: "Node hub")
        case "cloudflare-worker": return String(localized: "Cloudflare Worker")
        default: return String(localized: "Token Monitor Hub")
        }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty, build != version else { return version }
        return "\(version) (\(build))"
    }
}

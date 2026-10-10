import Foundation
import TokenMonitorKit

/// Localized wording for values the Kit hands over as data. Every string
/// literal here is a key in this target's `Localizable.xcstrings`; numbers
/// and money come formatted from the user's `DisplayFormatter`.
enum ComplicationText {
    /// A compact cost: "$1.23 + ?" when unpriced tokens are left out, "—"
    /// when none of the usage is priced (desktop `compactUsageCostLabel`).
    static func cost(_ label: CostLabel) -> String {
        switch label {
        case .plain(let cost): return cost
        case .compactPartial(let cost), .partial(let cost, _): return "\(cost) + ?"
        case .compactUnknown, .unknown: return "—"
        }
    }

    /// "just now", "5m ago" (`settings.age.*`).
    static func age(_ bucket: LimitPresentation.AgeBucket) -> String {
        switch bucket {
        case .justNow: return String(localized: "just now")
        case .minutes(let minutes): return String(localized: "\(minutes)m ago")
        case .hours(let hours): return String(localized: "\(hours)h ago")
        case .days(let days): return String(localized: "\(days)d ago")
        }
    }

    /// The age of `date` at `now`, in the same buckets as the Limits meta line.
    static func age(of date: Date, at now: Date) -> String {
        age(LimitPresentation.ageBucket(milliseconds: now.timeIntervalSince(date) * 1000))
    }

    /// The status chip wording (`LimitStatusLabel.desktopKey`).
    static func statusLabel(_ label: LimitStatusLabel) -> String {
        switch label {
        case .stale: return String(localized: "Stale")
        case .verifyInAntigravity: return String(localized: "Open Antigravity to verify")
        case .encryptedByApp: return String(localized: "Encrypted by app")
        case .live: return String(localized: "Live")
        case .linked: return String(localized: "Linked")
        case .disabled: return String(localized: "Disabled")
        case .noSyncedData: return String(localized: "No synced data")
        case .updateCredential: return String(localized: "Update credential")
        case .updateApiKey: return String(localized: "Update API key")
        case .openCline: return String(localized: "Open Cline")
        case .signInAgain: return String(localized: "Sign in again")
        case .relogin: return String(localized: "Re-login")
        case .limited: return String(localized: "Limited")
        case .usageApiLimited: return String(localized: "Usage API limited")
        case .unavailable: return String(localized: "Unavailable")
        case .addCredential: return String(localized: "Add credential")
        case .notSetUp: return String(localized: "Not set up")
        case .signIn: return String(localized: "Sign in")
        case .addApiKey: return String(localized: "Add API key")
        case .runGrokLogin: return String(localized: "Run grok login")
        case .runKiroLogin: return String(localized: "Run kiro-cli login")
        case .error: return String(localized: "Error")
        }
    }

    /// What a window is called on the Limits page.
    static func windowName(_ name: LimitWindowName) -> String {
        switch name {
        case .title(let title):
            switch title {
            case .label(let text), .rawKind(let text): return text
            case .kind(let kind): return kindName(kind)
            }
        case let .pool(name, period?):
            return name + " · " + periodName(period)
        case let .pool(name, nil):
            return name
        case let .group(name, period):
            return name + " · " + kindName(period)
        case .additionalLimit:
            return String(localized: "Additional limit")
        }
    }

    static func kindName(_ kind: LimitWindowKindName) -> String {
        switch kind {
        case .session: return String(localized: "Session")
        case .fiveHour: return String(localized: "5-hour")
        case .daily: return String(localized: "Daily")
        case .weekly: return String(localized: "Weekly")
        case .monthly: return String(localized: "Monthly")
        }
    }

    static func periodName(_ period: LimitPeriodName) -> String {
        switch period {
        case .named(let kind): return kindName(kind)
        case .hours(let value): return String(localized: "\(value)-hour")
        case .days(let value): return String(localized: "\(value)-day")
        case .weeks(let value): return String(localized: "\(value)-week")
        case .minutes(let value): return String(localized: "\(value)-minute")
        }
    }

    /// The number a gauge or a narrow row shows: "58%" in the user's
    /// used/remaining mode (the gauge itself always fills by what is left),
    /// or a compact amount.
    static func shortValue(_ headline: LimitPresentation.Headline, format: DisplayFormatter) -> String {
        switch headline {
        case .percent(let value, _):
            return format.percent(value)
        case let .money(amount, currency):
            return format.compactBalance(amount, currency: currency)
        case .amountLeft(let amount), .amount(let amount), .cap(let amount):
            return format.compactBalance(amount, currency: "USD")
        case let .spend(used, _, currency):
            return format.compactBalance(used, currency: currency)
        case let .overage(credits, cost):
            if let cost { return format.compactBalance(cost, currency: "USD") }
            return credits.map(format.compactNumber) ?? "—"
        case .unlimited:
            return "∞"
        case .planExpired, .none:
            return "—"
        case .text(let text):
            return text
        }
    }

    /// The inline family's value: "58% left" / "42% used", else the short
    /// value.
    static func longValue(_ headline: LimitPresentation.Headline, format: DisplayFormatter) -> String {
        guard case let .percent(value, mode) = headline else { return shortValue(headline, format: format) }
        let percent = format.percent(value)
        return mode == .used ? String(localized: "\(percent) used") : String(localized: "\(percent) left")
    }
}

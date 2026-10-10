import Foundation
import TokenMonitorKit

/// Localized wording for values the Kit hands over as data. Every string
/// literal here is a key in this target's `Localizable.xcstrings`; numbers
/// and money come formatted from the user's `DisplayFormatter`, and text the
/// Hub supplies (plan names, window labels, account names) is shown as is.
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
        case .transport: return String(localized: "Can’t reach the Hub")
        case .decoding: return String(localized: "Unexpected response from the Hub")
        }
    }

    // MARK: Usage

    /// A compact cost, "$1.23 + ?" when unpriced tokens are left out, "—"
    /// when none of the usage is priced (the desktop's
    /// `compactUsageCostLabel`, which is not translated).
    static func cost(_ label: CostLabel) -> String {
        switch label {
        case .plain(let cost): return cost
        case .compactPartial(let cost), .partial(let cost, _): return "\(cost) + ?"
        case .compactUnknown, .unknown: return "—"
        }
    }

    // MARK: Limits status and freshness

    /// The status chip (`LimitPresentation.statusChip`), in the desktop's
    /// Settings-tag wording (`LimitStatusLabel.desktopKey`).
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

    /// The line under Antigravity's chip while Google wants the account
    /// verified (`LimitPresentation.antigravityNeedsVerification`).
    static var antigravityVerificationDetail: String {
        String(localized: "Google requires account verification. Open Antigravity, complete verification, then refresh.")
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

    /// A provider's meta line: "Updated 5m ago", "Stale · 2h ago" or
    /// "Stale"; nil without a timestamp.
    static func freshness(_ freshness: LimitPresentation.Freshness) -> String? {
        switch freshness {
        case .updated(let bucket):
            let age = age(bucket)
            return String(localized: "Updated \(age)")
        case .stale(let bucket?):
            let age = age(bucket)
            return String(localized: "Stale · \(age)")
        case .stale(nil):
            return statusLabel(.stale)
        case .unknown:
            return nil
        }
    }

    // MARK: Limits names

    /// A provider row's plan ("Max", "New API · Account"); nil for a status
    /// (the chip shows it) or no plan.
    static func plan(_ cell: LimitPlanCell) -> String? {
        switch cell {
        case .plan(let text): return text
        case .thirdParty(let plan): return thirdPartyPlan(plan)
        case .status, .none: return nil
        }
    }

    static func thirdPartyPlan(_ plan: LimitThirdPartyPlan) -> String {
        switch plan {
        case .newAPIAccount: return String(localized: "New API · Account")
        case .newAPIKey: return String(localized: "New API · API key")
        case .sub2APIAccount: return String(localized: "Sub2API · Account")
        case .custom: return String(localized: "Custom")
        case .account: return String(localized: "Account")
        case .apiKey: return String(localized: "API key")
        }
    }

    /// An account's title among its provider's rows, parts joined by " · ".
    static func accountTitle(_ title: LimitAccountTitle) -> String {
        title.parts.map { part -> String in
            switch part {
            case .text(let text): return text
            case .personalWorkspace: return String(localized: "Personal")
            case .environment: return String(localized: "Environment")
            case .accountNumber(let number): return String(localized: "Account \(number)")
            case .disambiguator(let value): return "#" + value
            }
        }.joined(separator: " · ")
    }

    /// What a Limits window row is called.
    static func windowName(_ name: LimitWindowName) -> String {
        switch name {
        case .title(let title):
            return windowTitle(title)
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

    static func windowTitle(_ title: LimitWindowTitle) -> String {
        switch title {
        case .label(let text), .rawKind(let text): return text
        case .kind(let kind): return kindName(kind)
        }
    }

    /// The desktop's window kind names (`windowLabels.js`).
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

    // MARK: Limits values

    /// A window's value cell: "58% left" or "42% used" (the user's
    /// `showLimitUsed`), a balance in its own currency, spend, …
    static func headline(_ headline: LimitPresentation.Headline, format: DisplayFormatter) -> String {
        switch headline {
        case let .percent(value, mode):
            let percent = format.percent(value)
            return mode == .used ? String(localized: "\(percent) used") : String(localized: "\(percent) left")
        case let .money(amount, currency):
            return format.balance(amount, currency: currency)
        case .amountLeft(let amount):
            let money = format.balance(amount, currency: "USD")
            return String(localized: "\(money) left")
        case .amount(let amount):
            return format.balance(amount, currency: "USD")
        case .cap(let amount):
            let money = format.balance(amount, currency: "USD")
            return String(localized: "\(money) cap")
        case let .spend(used, limit, currency):
            let spent = format.balance(used, currency: currency)
            if let limit, limit > 0 {
                return spent + " / " + format.balance(limit, currency: currency)
            }
            return String(localized: "\(spent) spent")
        case let .overage(credits, cost):
            var parts: [String] = []
            if let credits {
                let amount = format.compactNumber(credits)
                parts.append(String(localized: "\(amount) credits"))
            }
            if let cost { parts.append(format.balance(cost, currency: "USD")) }
            return parts.isEmpty ? "--" : parts.joined(separator: " · ")
        case .unlimited:
            return String(localized: "Unlimited")
        case .planExpired:
            return String(localized: "Expired")
        case .text(let text):
            return text
        case .none:
            return "--"
        }
    }

    /// The number inside a quota ring: "58%" (in the text mode, while the
    /// ring itself always fills by what is left), or a compact amount.
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
}

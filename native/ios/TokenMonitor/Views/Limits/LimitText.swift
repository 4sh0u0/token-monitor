import Foundation
import TokenMonitorKit

/// Localized wording for what `LimitPresentation` hands over as data: status
/// chips, freshness and provenance, window names, values, boundaries, and the
/// balance, usage and reset-credit rows.
///
/// Every literal here is a key in the app's `Localizable.xcstrings`. Numbers
/// and money come from the user's `DisplayFormatter`; text the Hub supplies
/// (plan names, window labels, account names, grant captions) is shown as is.
/// Where the desktop has a translated key (the Settings status tags, ages,
/// "From {device}", the third-party detail labels) the catalog reuses its
/// translations; the Limits page's English-only wording gets our own.
enum LimitText {
    // MARK: Status

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

    // MARK: Freshness and provenance

    /// "just now", "5m ago" (`settings.age.*`).
    static func age(_ bucket: LimitPresentation.AgeBucket) -> String {
        switch bucket {
        case .justNow: return String(localized: "just now")
        case .minutes(let minutes): return String(localized: "\(minutes)m ago")
        case .hours(let hours): return String(localized: "\(hours)h ago")
        case .days(let days): return String(localized: "\(days)d ago")
        }
    }

    /// "Updated 5m ago", "Stale · 2h ago", "Stale" or "Update unknown".
    static func freshness(_ freshness: LimitPresentation.Freshness) -> String {
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
            return String(localized: "Update unknown")
        }
    }

    /// "From MacBook Pro" (`settings.limits.device.from`): the device whose
    /// reading won, by its Devices name when the Hub lists it.
    static func device(_ provenance: LimitPresentation.Provenance) -> String {
        let name = provenance.deviceName ?? provenance.deviceID
        return String(localized: "From \(name)")
    }

    /// The line under a provider's name: freshness, then (with Show Source)
    /// the source and the device. Source names ("OAuth", "CLI", "Web") are
    /// protocol and product terms the desktop shows untranslated.
    static func metaLine(_ meta: LimitPresentation.MetaLine) -> String {
        var parts = [freshness(meta.freshness)]
        if let source = meta.source { parts.append(source.desktopText) }
        if let provenance = meta.provenance { parts.append(device(provenance)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Names

    /// A row's plan cell ("Max", "New API · Account", or the status of a row
    /// that is not healthy); nil when it is empty.
    static func plan(_ cell: LimitPlanCell) -> String? {
        switch cell {
        case .plan(let text): return text
        case .thirdParty(let plan): return thirdPartyPlan(plan)
        case .status(let label): return statusLabel(label)
        case .none: return nil
        }
    }

    static func thirdPartyPlan(_ plan: LimitThirdPartyPlan) -> String {
        switch plan {
        case .newAPIAccount: return String(localized: "New API · Account")
        case .newAPIKey: return String(localized: "New API · API key")
        case .sub2APIAccount: return String(localized: "Sub2API · Account")
        case .custom: return String(localized: "Custom plan", comment: "A third-party relay's preset plan (desktop settings.thirdparty.presetCustom), shown as “Custom”.")
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

    /// "4 accounts" on a provider group's header ("2 plans" for Volcengine,
    /// whose rows are plans of one account).
    static func groupCount(providerID: String, count: Int) -> String {
        if providerID == "volcengine" { return String(localized: "\(count) plans") }
        return String(localized: "\(count) accounts")
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
        case .label(let text), .rawKind(let text):
            return text
        case .kind(let kind):
            return kindName(kind)
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

    /// A pool's cadence ("5-hour", "2-week").
    static func periodName(_ period: LimitPeriodName) -> String {
        switch period {
        case .named(let kind): return kindName(kind)
        case .hours(let value): return String(localized: "\(value)-hour")
        case .days(let value): return String(localized: "\(value)-day")
        case .weeks(let value): return String(localized: "\(value)-week")
        case .minutes(let value): return String(localized: "\(value)-minute")
        }
    }

    /// The fixed rows of the visible-items checklist.
    static func fixedItem(_ item: LimitUsageFixedItem) -> String {
        switch item {
        case .credits: return String(localized: "Balance")
        case .spend: return String(localized: "Spend")
        case .resets: return String(localized: "Resets")
        }
    }

    /// A visible-items checklist entry (`LimitPresentation.usageItems`).
    static func usageItemLabel(_ label: LimitUsageItemLabel) -> String {
        switch label {
        case .fixed(let item): return fixedItem(item)
        case .window(let title): return windowTitle(title)
        case let .additional(limitID, title): return limitID + " · " + windowTitle(title)
        }
    }

    /// A Home window's name: provider text, or Session / Daily / Weekly /
    /// Billing.
    static func homeWindowLabel(_ label: LimitPresentation.HomeLimitWindowLabel) -> String {
        switch label {
        case .text(let text):
            return text
        case .kind(let kind):
            switch kind {
            case .session: return String(localized: "Session")
            case .daily: return String(localized: "Daily")
            case .weekly: return String(localized: "Weekly")
            case .billing: return String(localized: "Billing")
            }
        }
    }

    /// A Home row's name: the provider, the account or product, or both.
    static func homeRowName(_ name: LimitPresentation.HomeLimitRowName) -> String {
        let detail: String?
        switch name.detail {
        case .account(let title): detail = accountTitle(title)
        case .product(let product): detail = product
        case nil: detail = nil
        }
        return [name.providerName, detail].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Values

    /// A window's value cell: "58% left" or "42% used" (the user's
    /// `showLimitUsed`), a balance in its own currency, spend, …
    /// `compactMoney` writes balances the Home module's way ("$123.46K").
    static func headline(_ headline: LimitPresentation.Headline, format: DisplayFormatter, compactMoney: Bool = false) -> String {
        switch headline {
        case let .percent(value, mode):
            let percent = format.percent(value)
            return mode == .used ? String(localized: "\(percent) used") : String(localized: "\(percent) left")
        case let .money(amount, currency):
            return compactMoney ? format.compactBalance(amount, currency: currency) : format.balance(amount, currency: currency)
        case .amountLeft(let amount):
            // The desktop always writes dollars for these.
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

    /// The figure beside a window's boundary line ("$47.42 / $70.00",
    /// "120/500", "124M / 305M", "Gift ¥2.00 · Cash ¥10.00").
    static func windowDetail(_ detail: LimitPresentation.WindowDetail, format: DisplayFormatter) -> String {
        switch detail {
        case let .giftCash(gift, cash, currency):
            var parts: [String] = []
            if let gift {
                let money = format.balance(gift, currency: currency)
                parts.append(String(localized: "Gift \(money)"))
            }
            if let cash {
                let money = format.balance(cash, currency: currency)
                parts.append(String(localized: "Cash \(money)"))
            }
            return parts.joined(separator: " · ")
        case let .tokenPair(shown, limit):
            return format.compactTokens(shown) + " / " + format.compactTokens(limit)
        default:
            // Money, raw counts and provider text: numbers and punctuation.
            return detail.desktopText(tokenFormatter: { format.compactTokens($0) })
        }
    }

    // MARK: Durations and boundaries

    /// "2d 4h", "4h 26m", "26m" or "<1m" (`limitDurationText`), with the unit
    /// letters in the user's language.
    static func duration(_ parts: LimitPresentation.DurationParts) -> String {
        switch parts.style {
        case let .daysHours(days, hours):
            return units(seconds: days * 86_400 + hours * 3_600, allowed: [.days, .hours])
        case let .hoursMinutes(hours, minutes):
            return units(seconds: hours * 3_600 + minutes * 60, allowed: [.hours, .minutes])
        case .minutes(let minutes):
            return units(seconds: minutes * 60, allowed: [.minutes])
        case .lessThanAMinute:
            return "<" + units(seconds: 60, allowed: [.minutes])
        }
    }

    private static func units(seconds: Int, allowed: Set<Duration.UnitsFormatStyle.Unit>) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: allowed, width: .narrow, zeroValueUnits: .show(length: 1)))
    }

    /// The line under a meter: "Reset in 2h 30m", "Expires in 3d 4h",
    /// "Changes in 5m", "Reset now" inside the minute after, or the
    /// provider's own wording ("Reset on the 1st", `home.reset`).
    static func boundary(_ line: LimitPresentation.BoundaryLine) -> String {
        switch line {
        case .boundary(let boundary):
            if boundary.isNow {
                switch boundary.kind {
                case .reset: return String(localized: "Reset now")
                case .expiry: return String(localized: "Expires now")
                case .mixed: return String(localized: "Changes now")
                }
            }
            let duration = duration(boundary.duration)
            switch boundary.kind {
            case .reset: return String(localized: "Reset in \(duration)")
            case .expiry: return String(localized: "Expires in \(duration)")
            case .mixed: return String(localized: "Changes in \(duration)")
            }
        case .description(let text):
            return String(localized: "Reset \(text)")
        }
    }

    /// A grant's or a balance's expiry date ("10/14, 3:00 PM"), as the
    /// desktop's `expiryDateLabel`.
    static func expiryDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.defaultDigits).day().hour().minute())
    }

    /// A calendar day ("Oct 14, 2026").
    static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: Balance, spend and usage

    static func spendPeriod(_ period: LimitPresentation.SpendPeriod) -> String {
        switch period {
        case .today: return String(localized: "Today")
        case .week: return String(localized: "Week")
        case .month: return String(localized: "Month")
        case .allTime: return String(localized: "All time")
        }
    }

    /// "Expires 10/14, 3:00 PM · 3d 4h", "Expired" or "No expiry" for one
    /// prepaid grant.
    static func trancheExpiry(_ expiresAt: Date?, now: Date) -> String {
        guard let expiresAt else { return String(localized: "No expiry") }
        let remaining = expiresAt.timeIntervalSince(now) * 1000
        guard remaining > 0 else { return String(localized: "Expired") }
        let date = expiryDate(expiresAt)
        let left = duration(LimitPresentation.DurationParts(milliseconds: remaining))
        return String(localized: "Expires \(date)") + " · " + left
    }

    /// The name of a usage-summary figure; month figures say so, as the
    /// desktop's third-party rows do.
    static func usageSummaryLabel(_ row: LimitPresentation.UsageSummaryRow, period: LimitUsageSummaryPeriod?) -> String {
        switch row {
        case .todayTokens: return String(localized: "Today")
        case .weekTokens: return String(localized: "Last 7 days")
        case .requests: return period == .month ? String(localized: "Month requests") : String(localized: "Requests")
        case .totalTokens: return period == .month ? String(localized: "Month tokens") : String(localized: "Total tokens")
        case .inputTokens: return String(localized: "Input tokens")
        case .outputTokens: return String(localized: "Output tokens")
        case .cacheTokens: return String(localized: "Cache tokens")
        case .averageDuration: return String(localized: "Avg response")
        case .standardCost: return String(localized: "Standard cost")
        case .actualCost: return String(localized: "Actual cost")
        }
    }

    /// A usage-summary figure: full counts, "850 ms" / "2.4 s", or money in
    /// the balance's currency.
    static func usageSummaryValue(_ row: LimitPresentation.UsageSummaryRow, format: DisplayFormatter) -> String {
        switch row {
        case .todayTokens(let value), .weekTokens(let value), .requests(let value), .totalTokens(let value),
             .inputTokens(let value), .outputTokens(let value), .cacheTokens(let value):
            return format.fullTokens(value)
        case .averageDuration(let milliseconds):
            return LimitPresentation.averageDurationDesktopText(milliseconds)
        case let .standardCost(amount, currency), let .actualCost(amount, currency):
            return format.balance(amount, currency: currency)
        }
    }

    // MARK: Reset credits

    /// "1 reset" / "3 resets".
    static func resetCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 reset") : String(localized: "\(count) resets")
    }

    /// The expiry timeline after the count: "now · 2d 4h · 5d 1h · +2".
    static func resetTimeline(_ line: LimitPresentation.ResetCreditsLine) -> String? {
        var parts = line.expiries.map { expiry -> String in
            switch expiry {
            case .now: return String(localized: "now")
            case .duration(let parts): return duration(parts)
            }
        }
        if line.overflow > 0 { parts.append("+\(line.overflow)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A window a Claude reset grant clears.
    static func resetClear(_ label: LimitPresentation.ResetClearLabel) -> String {
        switch label {
        case .session: return String(localized: "Session")
        case .weekly: return String(localized: "Weekly")
        case .fableWeekly: return weekly("Fable")
        case .opusWeekly: return weekly("Opus")
        case .sonnetWeekly: return weekly("Sonnet")
        case .oauthAppsWeekly: return weekly("OAuth apps")
        case .coworkWeekly: return weekly("Cowork")
        case .omeletteWeekly: return weekly("Omelette")
        case .other(let text): return text
        }
    }

    /// "Opus weekly": a model's or product's own weekly window.
    private static func weekly(_ name: String) -> String {
        String(localized: "\(name) weekly")
    }

    /// When one Claude grant runs out: its date and time left, "Paused",
    /// "Expired" or "No expiry".
    static func grantExpiry(_ grant: LimitPresentation.ResetGrantRow) -> String {
        let remaining: String?
        switch grant.remaining {
        case .paused: remaining = String(localized: "Paused")
        case .expired: remaining = String(localized: "Expired")
        case .duration(let parts): remaining = duration(parts)
        case nil: remaining = nil
        }
        guard let endsAt = grant.endsAt else { return remaining ?? String(localized: "No expiry") }
        return [expiryDate(endsAt), remaining].compactMap { $0 }.joined(separator: " · ")
    }

    /// When a grant can be spent, if not freely.
    static func usability(_ usability: LimitPresentation.ResetGrantRow.Usability) -> String {
        switch usability {
        case .atLimitOnly: return String(localized: "At a limit only")
        case .notRightNow: return String(localized: "Not right now")
        }
    }
}

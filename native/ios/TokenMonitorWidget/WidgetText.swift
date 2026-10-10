import Foundation
import SwiftUI
import TokenMonitorKit

/// User-facing text of the widgets. Every number, cost, percentage and
/// balance comes from the user's `DisplayFormatter` (the desktop's formats in
/// the chosen units, currency and rates); the words around them come from
/// this target's String Catalog.
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

    /// In place of a figure that is not known, e.g. today's total while the
    /// cache is still yesterday's.
    static let noValue = "—"

    /// "18.4M tokens".
    static func tokenCount(_ value: Int, _ format: DisplayFormatter) -> String {
        let count = format.compactTokens(value)
        return String(localized: "\(count) tokens")
    }

    /// The period's cost in the display currency, compact above the unit
    /// threshold; "$1.23 + ?" when some tokens had no price, "—" when none
    /// did (the desktop's compact cost label). `noValue` when the period's
    /// figures are unknown.
    static func cost(_ summary: PeriodSummary?, _ format: DisplayFormatter) -> String {
        guard let summary else { return noValue }
        return cost(summary.costUsd, unpricedTokens: summary.unpricedTokens, format)
    }

    static func cost(_ usd: Double, unpricedTokens: Int?, _ format: DisplayFormatter) -> String {
        switch format.costLabel(usd, unpricedTokens: unpricedTokens, compact: true, compactAmount: true) {
        case .plain(let cost):
            return cost
        case .compactPartial(let cost), .partial(let cost, _):
            return cost + " + ?"
        case .compactUnknown, .unknown:
            return noValue
        }
    }

    /// "62 tok/s" (the desktop's live-rate format).
    static func rate(_ perSecond: Double, _ format: DisplayFormatter) -> String {
        let rate = format.liveTokenRate(perSecond)
        return String(localized: "\(rate) tok/s")
    }

    static func share(_ fraction: Double, _ format: DisplayFormatter) -> String {
        format.percent(fraction * 100)
    }

    /// "Updated 14:05" — when this phone last read the Hub.
    static func updated(_ date: Date, now: Date) -> String {
        let time = moment(date, relativeTo: now)
        return String(localized: "Updated \(time)")
    }

    /// A past moment as short as it can be read: the time today, weekday and
    /// time within the past week, else the date.
    static func moment(_ date: Date, relativeTo now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let style = Date.FormatStyle(locale: .autoupdatingCurrent, calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(style.hour().minute())
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if (1...6).contains(days) {
            return date.formatted(style.weekday(.abbreviated).hour().minute())
        }
        return date.formatted(style.month(.abbreviated).day())
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

    /// What a window is called (`LimitPresentation.windowName`): the
    /// provider's own label as sent, else the kind's name; a balance or spend
    /// window without a label is named for what it shows.
    static func windowName(_ window: LimitWindow, provider: LimitProvider) -> String {
        switch LimitPresentation.windowName(window, provider: provider) {
        case .title(let title):
            return windowTitle(title, window: window)
        case .pool(let name, _):
            return name
        case let .group(name, period):
            return [name, kindName(period)].joined(separator: " · ")
        case .additionalLimit:
            return windowTitle(LimitWindowTitle.of(window, provider: provider.provider), window: window)
        }
    }

    private static func windowTitle(_ title: LimitWindowTitle, window: LimitWindow) -> String {
        switch title {
        case .label(let text), .rawKind(let text):
            return text
        case .kind(let name):
            if window.isCredits { return String(localized: "Balance") }
            if window.isSpend { return String(localized: "Spend") }
            return kindName(name)
        }
    }

    /// The desktop's window-kind names (`windowLabels.js`).
    static func kindName(_ name: LimitWindowKindName) -> String {
        switch name {
        case .session: return String(localized: "Session")
        case .fiveHour: return String(localized: "5-hour")
        case .daily: return String(localized: "Daily")
        case .weekly: return String(localized: "Weekly")
        case .monthly: return String(localized: "Monthly")
        }
    }

    /// A window's value (`LimitPresentation.headline`): "23% left" or
    /// "77% used" in the user's mode, a balance in its own currency, money
    /// spent, and the desktop's other value forms. `compact` is for rings and
    /// gauges: the bare percentage (the ring labels its mode with
    /// `modeWord`) and compact money.
    static func headline(_ headline: LimitPresentation.Headline, _ format: DisplayFormatter, compact: Bool) -> String {
        switch headline {
        case let .percent(value, mode):
            let percent = format.percent(value)
            if compact { return percent }
            return mode == .used ? String(localized: "\(percent) used") : String(localized: "\(percent) left")
        case let .money(amount, currency):
            return compact ? format.compactBalance(amount, currency: currency) : format.balance(amount, currency: currency)
        case .amountLeft(let amount):
            let money = format.balance(amount, currency: "USD")
            return compact ? money : String(localized: "\(money) left")
        case .amount(let amount):
            return format.balance(amount, currency: "USD")
        case .cap(let amount):
            let money = format.balance(amount, currency: "USD")
            return compact ? money : String(localized: "\(money) cap")
        case let .spend(used, limit, currency):
            if compact { return format.compactBalance(used, currency: currency) }
            let spent = format.balance(used, currency: currency)
            if let limit, limit > 0 {
                return [spent, format.balance(limit, currency: currency)].joined(separator: " / ")
            }
            return String(localized: "\(spent) spent")
        case let .overage(credits, cost):
            var parts: [String] = []
            if let credits {
                let amount = format.compactNumber(credits)
                parts.append(String(localized: "\(amount) credits"))
            }
            if let cost { parts.append(format.balance(cost, currency: "USD")) }
            return parts.isEmpty ? noValue : parts.joined(separator: " · ")
        case .unlimited:
            return compact ? "∞" : String(localized: "Unlimited")
        case .planExpired:
            return String(localized: "Expired")
        case .text(let text):
            return text
        case .none:
            return noValue
        }
    }

    /// What a ring's percentage counts, under the number.
    static func modeWord(_ mode: MeterMode) -> String {
        switch mode {
        case .used: return String(localized: "used")
        case .remaining: return String(localized: "left")
        }
    }

    /// A provider's status chip (`LimitPresentation.statusChip`), in the
    /// desktop's Settings-tag wording.
    static func status(_ label: LimitStatusLabel) -> String {
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

    /// The header's plan cell (`LimitPresentation.planCell`): the status of a
    /// row that is not healthy, else the plan; nil when there is neither.
    static func planCell(_ provider: LimitProvider) -> String? {
        switch LimitPresentation.planCell(provider) {
        case .none: return nil
        case .status(let label): return status(label)
        case .plan(let text): return text
        case .thirdParty(let plan): return thirdPartyPlan(plan)
        }
    }

    private static func thirdPartyPlan(_ plan: LimitThirdPartyPlan) -> String {
        switch plan {
        case .newAPIAccount: return ["New API", String(localized: "Account")].joined(separator: " · ")
        case .newAPIKey: return ["New API", String(localized: "API key")].joined(separator: " · ")
        case .sub2APIAccount: return ["Sub2API", String(localized: "Account")].joined(separator: " · ")
        case .custom: return String(localized: "Custom")
        case .account: return String(localized: "Account")
        case .apiKey: return String(localized: "API key")
        }
    }

    /// "Reset in 2 hr, 13 min", counting down live. Nil once the boundary has
    /// passed at `now` (the entry date): a relative date style would start
    /// counting up again. A window without a timestamp shows the provider's
    /// own wording ("Reset {value}").
    static func boundary(_ window: LimitWindow, now: Date) -> Text? {
        if let date = window.resetsAt {
            guard date > now else { return nil }
            let countdown = Text(date, style: .relative)
            switch window.boundaryKind {
            case .reset: return Text("Reset in \(countdown)")
            case .expiry: return Text("Expires in \(countdown)")
            case .mixed: return Text("Changes in \(countdown)")
            }
        }
        guard let description = window.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty else { return nil }
        return Text("Reset \(description)")
    }

    // MARK: Activity

    static var activity: String { String(localized: "Activity") }

    static func metric(_ metric: HeatmapMetric) -> String {
        switch metric {
        case .tokens: return String(localized: "Tokens")
        case .cost: return String(localized: "Cost")
        }
    }

    /// The active-days chip (`home.activeDays` / `home.activeDaysYear`).
    static func activeDays(_ count: Int, window: ActiveDaysWindow) -> String {
        switch window {
        case .all: return String(localized: "\(count) active days")
        case .year: return String(localized: "\(count) active days in the last 12 months")
        }
    }

    /// "Peak 12.3M": the busiest day's tokens.
    static func peak(_ tokens: Int, _ format: DisplayFormatter) -> String {
        let value = format.compactTokens(tokens)
        return String(localized: "Peak \(value)")
    }

    static var less: String { String(localized: "Less") }
    static var more: String { String(localized: "More") }

    /// A heatmap month label: `yyyy-MM` → the localized short month ("Jun",
    /// "6月").
    static func monthLabel(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return key }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return key }
        let style = Date.FormatStyle(locale: .autoupdatingCurrent, calendar: calendar, timeZone: calendar.timeZone)
        return date.formatted(style.month(.abbreviated))
    }

    // MARK: States

    static var staleHint: String { String(localized: "Data may be stale") }
}

import Foundation

// The Hub's shared subscription list (`GET /api/subscriptions`) and a port of
// the desktop's derivations over it (`src/shared/subscriptionDisplay.js`, plus
// the number-only parts of `subscriptionText.js`). Read-only: the iOS app never
// writes the list, so the write path (`PUT`, binding, staleness tokens) is not
// ported.
//
// Dates are plain `yyyy-MM-dd` strings throughout, exactly as on the desktop: a
// subscription date is a square on a calendar, not an instant, and the
// fixed-width format makes string order chronological order. Functions that
// return "no date" return nil where the desktop returns `''`.

// MARK: - Wire model

/// One record of the Hub's subscription list.
///
/// Decoding re-normalizes the record exactly as the desktop's
/// `normalizeSubscription()` does with the display-currency table, so a record
/// the desktop would discard (no provider, a subscription without a valid start
/// date, a ledger without a valid top-up) fails to decode and is dropped by
/// `SubscriptionDocument`.
///
/// The binding's `accountKey` is deliberately not kept (round-2 decision
/// D-TOPUP): account matching uses the binding email, the profile name and the
/// sole-account rule only.
public struct HubSubscription: Sendable, Hashable, Identifiable {
    /// What the user recorded: one recurring charge, or a ledger of irregular
    /// top-ups.
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        case subscription
        case topup
    }

    public enum Interval: String, Sendable, Hashable, Codable, CaseIterable {
        case month
        case year
    }

    /// One payment into a top-up ledger.
    public struct TopUp: Sendable, Hashable, Identifiable {
        public var id: String
        /// `yyyy-MM-dd`.
        public var date: String
        /// Hundredths of a unit in the record's `currency`.
        public var amountMinor: Int

        public init(id: String, date: String, amountMinor: Int) {
            self.id = id
            self.date = date
            self.amountMinor = amountMinor
        }
    }

    public var id: String
    /// Lowercased limits-provider id (`claude`, `openrouter`, …).
    public var provider: String
    public var kind: Kind
    /// The bound account's email, lowercased; nil when the binding has none.
    public var bindingEmail: String?
    /// The bound account's profile name; nil when the binding has none.
    public var bindingProfileName: String?
    public var planName: String
    /// Hundredths of a unit in `currency` (every display currency has two
    /// decimals). Unused by a top-up ledger, whose money is in `topUps`.
    public var amountMinor: Int
    /// One of the display-currency codes (`USD`, `TWD`, `HKD`, `CNY`); anything
    /// else decodes as `USD`, as on the desktop.
    public var currency: String
    public var interval: Interval
    /// Clamped to `1...24`.
    public var intervalCount: Int
    /// The first real charge (`yyyy-MM-dd`); always set for a subscription.
    public var startDate: String?
    /// Newest first; never empty for a top-up ledger.
    public var topUps: [TopUp]
    /// Off means the plan was paid for and stops at its coverage boundary.
    public var autoRenew: Bool
    /// A one-off correction of the next renewal date, ignored once past.
    public var nextRenewalOverride: String?
    /// When coverage actually lapses, for a plan cancelled after renewals.
    public var endDate: String?
    public var note: String
    /// The record's own ISO timestamp, when the Hub sent one.
    public var updatedAt: String?

    public init(
        id: String,
        provider: String,
        kind: Kind = .subscription,
        bindingEmail: String? = nil,
        bindingProfileName: String? = nil,
        planName: String = "",
        amountMinor: Int = 0,
        currency: String = DisplayCurrency.usd.rawValue,
        interval: Interval = .month,
        intervalCount: Int = 1,
        startDate: String? = nil,
        topUps: [TopUp] = [],
        autoRenew: Bool = true,
        nextRenewalOverride: String? = nil,
        endDate: String? = nil,
        note: String = "",
        updatedAt: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.kind = kind
        self.bindingEmail = bindingEmail
        self.bindingProfileName = bindingProfileName
        self.planName = planName
        self.amountMinor = amountMinor
        self.currency = currency
        self.interval = interval
        self.intervalCount = intervalCount
        self.startDate = startDate
        self.topUps = topUps
        self.autoRenew = autoRenew
        self.nextRenewalOverride = nextRenewalOverride
        self.endDate = endDate
        self.note = note
        self.updatedAt = updatedAt
    }

    /// `isTopUp(record)`.
    public var isTopUp: Bool { kind == .topup }

    /// The record's currency as a display currency (`USD` for anything else).
    public var displayCurrency: DisplayCurrency { SubscriptionMath.normalizedCurrency(currency) }
}

/// The body of `GET /api/subscriptions`: `{ok, version, updatedAt, subscriptions}`.
public struct SubscriptionDocument: Sendable, Hashable {
    public var version: Int
    /// The Hub's version token for the whole list, compared against
    /// `HubStats.subscriptionsUpdatedAt`; `""` for a Hub that has never been
    /// written to.
    public var updatedAt: String
    /// Normalized, with later duplicates of an id dropped.
    public var subscriptions: [HubSubscription]

    public init(version: Int = 1, updatedAt: String = "", subscriptions: [HubSubscription] = []) {
        self.version = version
        self.updatedAt = updatedAt
        self.subscriptions = subscriptions
    }

    /// A Hub that has never been written to (`emptySubscriptionDocument()`).
    public static let empty = SubscriptionDocument()

    /// Decodes a response body, mapping failures to `HubClientError.decoding`.
    public static func decode(from data: Data) throws -> SubscriptionDocument {
        do {
            return try JSONDecoder().decode(SubscriptionDocument.self, from: data)
        } catch {
            throw HubClientError.decoding(String(describing: error))
        }
    }
}

extension HubClient {
    /// `GET /api/subscriptions`: the Hub's shared list. An older Hub answers
    /// `HubClientError.http(status: 404)`.
    public func subscriptions() async throws -> SubscriptionDocument {
        try SubscriptionDocument.decode(from: try await data(for: .subscriptions))
    }
}

/// `topUpProjection()`: the burn rate across the whole ledger and the day the
/// current balance runs out at that rate.
public struct TopUpProjection: Sendable, Hashable {
    /// Balance-currency units per day; 0 when nothing has been spent yet.
    public var dailyBurn: Double
    /// `yyyy-MM-dd`; nil when nothing has been spent (the desktop's `''`).
    public var exhaustDate: String?
    /// Whole days until `exhaustDate`; nil when nothing has been spent.
    public var daysRemaining: Int?

    public init(dailyBurn: Double, exhaustDate: String?, daysRemaining: Int?) {
        self.dailyBurn = dailyBurn
        self.exhaustDate = exhaustDate
        self.daysRemaining = daysRemaining
    }
}

// MARK: - Derivations

/// Ports `subscriptionDisplay.js` (lines 53-640) over normalized records.
///
/// `today` is a `yyyy-MM-dd` string and defaults to the local calendar day,
/// like the desktop. Money functions take the effective USD → currency
/// multipliers (`CurrencyRates.multipliers`); a missing or invalid entry falls
/// back to the built-in floor, as `currency.js` `configureRates()` does.
public enum SubscriptionMath {
    /// A calendar day's parts (`parseDate()`).
    struct Day: Hashable {
        var year: Int
        var month: Int
        var day: Int
    }

    /// `providerRollup()`: the active records of one provider and what they
    /// cost per month together.
    public struct ProviderRollup: Sendable, Hashable {
        public var count: Int
        public var monthlyUsd: Double

        public init(count: Int, monthlyUsd: Double) {
            self.count = count
            self.monthlyUsd = monthlyUsd
        }
    }

    /// A credits account's live balance, as the desktop pairs it with a ledger
    /// (`windowsView.js` `topUpTooltipRows`).
    public struct TopUpBalance: Sendable, Hashable {
        public var amount: Double
        /// The currency the provider reports the balance in.
        public var currency: String

        public init(amount: Double, currency: String) {
            self.amount = amount
            self.currency = currency
        }
    }

    /// `subscriptionText.elapsedText()` without its wording.
    public enum Elapsed: Sendable, Hashable {
        /// The start date has not arrived yet.
        case notStarted
        /// Whole months of coverage (≥ 1).
        case months(Int)
        /// Under a month: days since the start date.
        case days(Int)
    }

    // MARK: Calendar dates

    /// `todayString()`: the local calendar day (Gregorian, whatever calendar
    /// the user has chosen), as `yyyy-MM-dd`.
    public static func todayString(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return formatDate(Day(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1))
    }

    /// `isDateString()`: the `yyyy-MM-dd` shape (ASCII digits), after trimming.
    public static func isDateString(_ value: String?) -> Bool {
        let units = Array(SubscriptionJS.trim(value ?? "").utf16)
        guard units.count == 10 else { return false }
        for (index, unit) in units.enumerated() {
            if index == 4 || index == 7 {
                guard unit == 0x2D else { return false }
            } else {
                guard (0x30...0x39).contains(unit) else { return false }
            }
        }
        return true
    }

    /// `normalizeDateField()`: the trimmed string when it names a real
    /// calendar day, else nil.
    public static func normalizedDate(_ value: String?) -> String? {
        parseDate(value) == nil ? nil : SubscriptionJS.trim(value ?? "")
    }

    /// `daysBetween()`: whole days from one calendar day to another; nil when
    /// either is not a valid date.
    public static func daysBetween(_ from: String?, _ to: String?) -> Int? {
        guard let from = parseDate(from), let to = parseDate(to) else { return nil }
        return utcDayNumber(to) - utcDayNumber(from)
    }

    /// Local midnight of a `yyyy-MM-dd` day, for formatting it
    /// (`subscriptionText.localDate()`); nil when the string is not a valid day.
    public static func localDate(_ value: String?, timeZone: TimeZone = .current) -> Date? {
        guard let day = parseDate(value) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: jsYear(day.year), month: day.month, day: day.day))
    }

    // MARK: Renewal schedule

    /// `intervalMonths()`: months per billing period.
    public static func intervalMonths(_ subscription: HubSubscription) -> Int {
        let count = normalizedIntervalCount(subscription.intervalCount)
        return subscription.interval == .year ? count * 12 : count
    }

    /// `scheduledRenewalDate()`: the period boundary on or after `today`,
    /// whether or not it will be charged; nil for a ledger.
    public static func scheduledRenewalDate(_ subscription: HubSubscription, today: String = todayString()) -> String? {
        if subscription.isTopUp { return nil }
        // An override already in the past is ignored rather than rolled.
        if let override = normalizedDate(subscription.nextRenewalOverride), !SubscriptionJS.less(override, today) {
            return override
        }
        guard let anchor = parseDate(subscription.startDate), let todayParts = parseDate(today) else { return nil }
        let step = intervalMonths(subscription)
        let monthsElapsed = (todayParts.year - anchor.year) * 12 + (todayParts.month - anchor.month)
        var periods = max(0, floorDivide(monthsElapsed, step))
        var candidate = formatDate(addMonthsAnchored(anchor, periods * step))
        while SubscriptionJS.less(candidate, today) {
            periods += 1
            candidate = formatDate(addMonthsAnchored(anchor, periods * step))
        }
        while periods > 0 {
            let previous = formatDate(addMonthsAnchored(anchor, (periods - 1) * step))
            if SubscriptionJS.less(previous, today) { break }
            periods -= 1
            candidate = previous
        }
        return candidate
    }

    /// `nextRenewalDate()`: the next charge, which only exists while the plan
    /// renews.
    public static func nextRenewalDate(_ subscription: HubSubscription, today: String = todayString()) -> String? {
        subscription.autoRenew ? scheduledRenewalDate(subscription, today: today) : nil
    }

    /// `coverageStopDate()`: the boundary where charges stop for good —
    /// `endDate`, or one period after the start when auto-renew is off; nil
    /// while the plan renews.
    public static func coverageStopDate(_ subscription: HubSubscription) -> String? {
        if subscription.isTopUp { return nil }
        if let end = normalizedDate(subscription.endDate) { return end }
        if subscription.autoRenew { return nil }
        guard let anchor = parseDate(subscription.startDate) else { return nil }
        return formatDate(addMonthsAnchored(anchor, intervalMonths(subscription)))
    }

    /// `coverageEndDate()`: how long the current money lasts — the stop date
    /// once there is one, else the next renewal.
    public static func coverageEndDate(_ subscription: HubSubscription, today: String = todayString()) -> String? {
        if subscription.isTopUp { return nil }
        return coverageStopDate(subscription) ?? scheduledRenewalDate(subscription, today: today)
    }

    /// `daysUntilRenewal()`: days from `today` to `coverageEndDate`, negative
    /// once coverage has lapsed; nil when there is no end date.
    public static func daysUntilRenewal(_ subscription: HubSubscription, today: String = todayString()) -> Int? {
        guard let target = coverageEndDate(subscription, today: today) else { return nil }
        return daysBetween(today, target)
    }

    /// `elapsedPeriods()`: charges taken so far, counting the first on the
    /// start date and none at or after the coverage stop.
    public static func elapsedPeriods(_ subscription: HubSubscription, today: String = todayString()) -> Int {
        if subscription.isTopUp { return 0 }
        guard let anchor = parseDate(subscription.startDate), let todayParts = parseDate(today) else { return 0 }
        if SubscriptionJS.less(today, formatDate(anchor)) { return 0 }
        let step = intervalMonths(subscription)
        let monthsElapsed = (todayParts.year - anchor.year) * 12 + (todayParts.month - anchor.month)
        var periods = max(0, floorDivide(monthsElapsed, step))
        while !SubscriptionJS.less(today, formatDate(addMonthsAnchored(anchor, (periods + 1) * step))) { periods += 1 }
        while periods > 0 && SubscriptionJS.less(today, formatDate(addMonthsAnchored(anchor, periods * step))) { periods -= 1 }
        if let end = coverageStopDate(subscription) {
            while periods > 0 && !SubscriptionJS.less(formatDate(addMonthsAnchored(anchor, periods * step)), end) { periods -= 1 }
        }
        return periods + 1
    }

    /// `paidToDateMinor()`: the price times the charges taken.
    public static func paidToDateMinor(_ subscription: HubSubscription, today: String = todayString()) -> Int {
        saturatingMultiply(normalizedAmountMinor(subscription.amountMinor), elapsedPeriods(subscription, today: today))
    }

    /// `subscribedMonths()`: whole months since the start date.
    public static func subscribedMonths(_ subscription: HubSubscription, today: String = todayString()) -> Int {
        if subscription.isTopUp { return 0 }
        guard let anchor = parseDate(subscription.startDate), let todayParts = parseDate(today) else { return 0 }
        var months = (todayParts.year - anchor.year) * 12 + (todayParts.month - anchor.month)
        if todayParts.day < anchor.day { months -= 1 }
        return max(0, months)
    }

    /// `subscriptionText.elapsedText()`'s choice of unit: the clock stops at a
    /// lapsed plan's coverage boundary, under a month counts days, and a start
    /// date still ahead is `.notStarted`. Pair it with `paidToDateMinor`.
    public static func elapsed(_ subscription: HubSubscription, today: String = todayString()) -> Elapsed {
        let stop = coverageStopDate(subscription)
        let asOf = stop.map { SubscriptionJS.less($0, today) ? $0 : today } ?? today
        let daysSinceStart = daysBetween(subscription.startDate, asOf)
        if let daysSinceStart, daysSinceStart < 0 { return .notStarted }
        let months = subscribedMonths(subscription, today: asOf)
        return months >= 1 ? .months(months) : .days(max(0, daysSinceStart ?? 0))
    }

    // MARK: Money

    /// `amountUnits()`: the price in whole currency units.
    public static func amountUnits(_ subscription: HubSubscription) -> Double {
        Double(normalizedAmountMinor(subscription.amountMinor)) / 100
    }

    /// `amountUsd()`: the price converted to USD at the active rates.
    public static func amountUsd(_ subscription: HubSubscription, rates: [String: Double]) -> Double {
        amountUsd(minor: subscription.amountMinor, currency: subscription.currency, rates: rates)
    }

    /// `convertMinor()`: minor units moved between two display currencies via
    /// USD, rounded like `Math.round`.
    public static func convertMinor(_ amountMinor: Int, from: String, to: String, rates: [String: Double]) -> Int {
        let usd = amountUsd(minor: amountMinor, currency: from, rates: rates)
        let target = normalizedCurrency(to)
        let converted = target == .usd ? usd : convertUsd(usd, to: target, rates: rates)
        return SubscriptionMath.integer(JSCompat.round(converted * 100))
    }

    /// `monthlyAmountUsd()`: a plan's price per month (a yearly plan ÷ 12), or
    /// what a ledger took in `today`'s calendar month, in USD.
    public static func monthlyAmountUsd(_ subscription: HubSubscription, rates: [String: Double], today: String = todayString()) -> Double {
        if subscription.isTopUp {
            return amountUsd(minor: topUpMonthMinor(subscription, today: today), currency: subscription.currency, rates: rates)
        }
        let months = intervalMonths(subscription)
        return months > 0 ? amountUsd(subscription, rates: rates) / Double(months) : 0
    }

    /// `activeSubscriptions()`: records still being paid for — a plan whose
    /// coverage stopped on or before `today` drops out of every total.
    public static func activeSubscriptions(_ subscriptions: [HubSubscription], today: String = todayString()) -> [HubSubscription] {
        subscriptions.filter { subscription in
            guard let stop = coverageStopDate(subscription) else { return true }
            return SubscriptionJS.less(today, stop)
        }
    }

    /// `monthlyTotalUsd()`: the active records' monthly amounts summed, in USD.
    public static func monthlyTotalUsd(_ subscriptions: [HubSubscription], rates: [String: Double], today: String = todayString()) -> Double {
        activeSubscriptions(subscriptions, today: today)
            .reduce(0) { $0 + monthlyAmountUsd($1, rates: rates, today: today) }
    }

    /// `providerRollup()`: the active records of `provider` and their monthly
    /// total in USD.
    public static func providerRollup(_ subscriptions: [HubSubscription], provider: String, rates: [String: Double], today: String = todayString()) -> ProviderRollup {
        let id = SubscriptionJS.trim(provider).lowercased()
        let matching = activeSubscriptions(subscriptions, today: today)
            .filter { SubscriptionJS.trim($0.provider).lowercased() == id }
        return ProviderRollup(
            count: matching.count,
            monthlyUsd: matching.reduce(0) { $0 + monthlyAmountUsd($1, rates: rates, today: today) }
        )
    }

    /// `valueMultiple()`: how many times over the month's equivalent API cost
    /// covers what was paid; nil unless both are positive.
    public static func valueMultiple(monthlyUsd: Double?, usageCostUsd: Double?) -> Double? {
        guard let paid = monthlyUsd, let usage = usageCostUsd, paid.isFinite, usage.isFinite, paid > 0, usage > 0 else { return nil }
        return usage / paid
    }

    /// `subscriptionText.topUpMinorText()` / `amountText()`: the currency
    /// symbol and the amount with two decimals (`"HK$39.00"`, `"$-2.50"`).
    public static func moneyText(minor: Int, currency: String) -> String {
        "\(normalizedCurrency(currency).symbol)\(JSCompat.toFixed(Double(minor) / 100, 2))"
    }

    /// `subscriptionText.amountText()`: the record's price.
    public static func amountText(_ subscription: HubSubscription) -> String {
        moneyText(minor: normalizedAmountMinor(subscription.amountMinor), currency: subscription.currency)
    }

    // MARK: Top-up ledger

    /// `topUpEntries()`: valid entries, newest first (stable for equal dates).
    public static func topUpEntries(_ record: HubSubscription) -> [HubSubscription.TopUp] {
        let entries = record.topUps.enumerated().compactMap { index, entry -> (Int, HubSubscription.TopUp)? in
            guard let date = normalizedDate(entry.date) else { return nil }
            let id = SubscriptionJS.trim(entry.id)
            return (index, HubSubscription.TopUp(
                id: id.isEmpty ? "top_\(index)" : id,
                date: date,
                amountMinor: normalizedAmountMinor(entry.amountMinor)
            ))
        }
        return sortedNewestFirst(entries)
    }

    /// `lastTopUp()`: the newest entry.
    public static func lastTopUp(_ record: HubSubscription) -> HubSubscription.TopUp? {
        topUpEntries(record).first
    }

    /// `firstTopUpDate()`: the oldest entry's date.
    public static func firstTopUpDate(_ record: HubSubscription) -> String? {
        topUpEntries(record).last?.date
    }

    /// `topUpTotalMinor()`: everything ever put in, in the record's currency.
    public static func topUpTotalMinor(_ record: HubSubscription) -> Int {
        topUpEntries(record).reduce(0) { saturatingAdd($0, $1.amountMinor) }
    }

    /// `topUpMonthMinor()`: what was put in during `today`'s calendar month.
    public static func topUpMonthMinor(_ record: HubSubscription, today: String = todayString()) -> Int {
        let month = Array(SubscriptionJS.trim(today).utf16.prefix(7))
        return topUpEntries(record)
            .filter { Array($0.date.utf16.prefix(7)) == month }
            .reduce(0) { saturatingAdd($0, $1.amountMinor) }
    }

    /// `topUpProjection()`: the burn rate measured from the first top-up (the
    /// balance assumed zero just before it) to `today`, and when `balance` runs
    /// out at that rate. `balanceCurrency` defaults to the record's currency.
    /// Nil without a ledger, a finite balance, money put in, or a day elapsed;
    /// `dailyBurn` 0 when nothing has been spent yet.
    public static func topUpProjection(
        _ record: HubSubscription,
        balance: Double,
        balanceCurrency: String? = nil,
        today: String = todayString(),
        rates: [String: Double]
    ) -> TopUpProjection? {
        guard let from = firstTopUpDate(record), balance.isFinite else { return nil }
        let currency = balanceCurrency.flatMap { $0.isEmpty ? nil : $0 } ?? record.currency
        let poured = Double(convertMinor(topUpTotalMinor(record), from: record.currency, to: currency, rates: rates)) / 100
        guard poured > 0 else { return nil }
        guard let elapsedDays = daysBetween(from, today), elapsedDays > 0 else { return nil }
        let spent = poured - balance
        if spent <= 0 { return TopUpProjection(dailyBurn: 0, exhaustDate: nil, daysRemaining: nil) }
        let dailyBurn = spent / Double(elapsedDays)
        let daysRemaining = (balance / dailyBurn).rounded(.down)
        let exhaustDate = parseDate(today).flatMap { shiftDays($0, daysRemaining) }.map(formatDate)
        return TopUpProjection(dailyBurn: dailyBurn, exhaustDate: exhaustDate, daysRemaining: SubscriptionMath.integer(daysRemaining))
    }

    /// The projection for a ledger against its matched account's live balance
    /// (`matchBalanceAccount` → `topUpBalance` → `topUpProjection`); nil when
    /// no account matches or it reports no balance.
    public static func topUpProjection(
        _ record: HubSubscription,
        providers: [LimitProvider],
        today: String = todayString(),
        rates: [String: Double]
    ) -> TopUpProjection? {
        guard let account = matchBalanceAccount(record, providers: providers),
              let balance = topUpBalance(of: account, for: record) else { return nil }
        return topUpProjection(record, balance: balance.amount, balanceCurrency: balance.currency, today: today, rates: rates)
    }

    // MARK: Accounts

    /// `matchProviderAccount()` without its `accountKey` rung (D-TOPUP): the
    /// provider's account whose email equals the binding email, else the one
    /// account carrying the binding's profile name, else the provider's sole
    /// account; nil when the provider has none or the choice is ambiguous.
    public static func matchBalanceAccount(_ subscription: HubSubscription, providers: [LimitProvider]) -> LimitProvider? {
        let id = SubscriptionJS.trim(subscription.provider).lowercased()
        let accounts = providers.filter { SubscriptionJS.trim($0.provider).lowercased() == id }
        guard !accounts.isEmpty else { return nil }
        let email = SubscriptionJS.trim(subscription.bindingEmail ?? "").lowercased()
        if !email.isEmpty,
           let byEmail = accounts.first(where: { SubscriptionJS.trim($0.accountEmail ?? "").lowercased() == email }) {
            return byEmail
        }
        let profileName = SubscriptionJS.trim(subscription.bindingProfileName ?? "")
        if !profileName.isEmpty {
            let named = accounts.filter { SubscriptionJS.trim($0.accountName ?? "") == profileName }
            if named.count == 1 { return named[0] }
        }
        return accounts.count == 1 ? accounts[0] : nil
    }

    /// The balance a ledger is measured against: the first credits window's
    /// `remaining`, else the provider balance, in the window's currency, else
    /// the balance's, else the record's (`windowsView.js` `topUpTooltipRows`).
    public static func topUpBalance(of account: LimitProvider, for record: HubSubscription) -> TopUpBalance? {
        let creditsWindow = account.windows.first { $0.metric == .credits }
        let fromWindow = creditsWindow?.remaining.flatMap { $0.isFinite ? $0 : nil }
        guard let amount = fromWindow ?? account.balance?.amount.flatMap({ $0.isFinite ? $0 : nil }) else { return nil }
        let currency = [creditsWindow?.currency, account.balance?.currency]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? record.currency
        return TopUpBalance(amount: amount, currency: currency)
    }

    /// `isBalanceOnlyAccount()`: the account's entire quota is money (a
    /// credits window, and no window that is neither credits nor spend).
    public static func isBalanceOnlyAccount(_ account: LimitProvider) -> Bool {
        guard account.windows.contains(where: { $0.metric == .credits }) else { return false }
        return !account.windows.contains { $0.metric != .credits && $0.metric != .spend }
    }

    // MARK: Internals

    /// `normalizeSubscriptionCurrency()` with the display-currency table.
    static func normalizedCurrency(_ value: String?) -> DisplayCurrency {
        DisplayCurrency(rawValue: SubscriptionJS.trim(value ?? "").uppercased()) ?? .usd
    }

    static func normalizedIntervalCount(_ value: Int) -> Int {
        max(1, min(24, value))
    }

    static func normalizedAmountMinor(_ value: Int) -> Int {
        max(0, value)
    }

    /// `parseDate()`.
    static func parseDate(_ value: String?) -> Day? {
        guard isDateString(value) else { return nil }
        let parts = SubscriptionJS.trim(value ?? "").split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let day = Day(year: parts[0], month: parts[1], day: parts[2])
        guard (1...12).contains(day.month), day.day >= 1, day.day <= daysInMonth(year: day.year, month: day.month) else { return nil }
        return day
    }

    /// `formatDate()`: the year is not zero-padded, as on the desktop.
    static func formatDate(_ day: Day) -> String {
        "\(day.year)-\(pad2(day.month))-\(pad2(day.day))"
    }

    /// `daysInMonth()`, which goes through `Date.UTC` and so reads years
    /// 0–99 as 1900–1999.
    static func daysInMonth(year: Int, month: Int) -> Int {
        let utcYear = jsYear(year)
        let leap = utcYear % 4 == 0 && (utcYear % 100 != 0 || utcYear % 400 == 0)
        switch month {
        case 2: return leap ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// `addMonthsAnchored()`: months added to the ORIGINAL anchor day, clamped
    /// to the target month's last day (Jan-31 → Feb-28 → Mar-31).
    static func addMonthsAnchored(_ anchor: Day, _ monthsToAdd: Int) -> Day {
        let totalMonths = anchor.year * 12 + (anchor.month - 1) + monthsToAdd
        let year = floorDivide(totalMonths, 12)
        let month = totalMonths % 12 + 1
        return Day(year: year, month: month, day: min(anchor.day, daysInMonth(year: year, month: month)))
    }

    /// `shiftDays()`; nil where `Date.UTC` would leave its ±10⁸-day range (the
    /// desktop prints `NaN-NaN-NaN` there and then shows no date).
    static func shiftDays(_ day: Day, _ days: Double) -> Day? {
        let target = Double(utcDayNumber(day)) + days
        guard target.isFinite, abs(target) <= 100_000_000 else { return nil }
        return civilDay(fromDayNumber: Int(target))
    }

    // `Date.UTC(y, …)` maps a year in 0...99 to 1900 + y.
    private static func jsYear(_ year: Int) -> Int {
        (0...99).contains(year) ? 1900 + year : year
    }

    /// Days since 1970-01-01 of the day `Date.UTC` would build from these
    /// parts (proleptic Gregorian).
    private static func utcDayNumber(_ day: Day) -> Int {
        let year = jsYear(day.year) - (day.month <= 2 ? 1 : 0)
        let era = floorDivide(year, 400)
        let yearOfEra = year - era * 400
        let monthIndex = (day.month + 9) % 12
        let dayOfYear = (153 * monthIndex + 2) / 5 + day.day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func civilDay(fromDayNumber number: Int) -> Day {
        let shifted = number + 719_468
        let era = floorDivide(shifted, 146_097)
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        return Day(year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
    }

    private static func amountUsd(minor: Int, currency: String, rates: [String: Double]) -> Double {
        let units = Double(normalizedAmountMinor(minor)) / 100
        let code = normalizedCurrency(currency)
        if code == .usd { return units }
        let oneUnitInCurrency = convertUsd(1, to: code, rates: rates)
        return oneUnitInCurrency > 0 ? units / oneUnitInCurrency : units
    }

    /// `currency.js` `convertUsd()`: `Number((amount * rate).toFixed(6))`.
    private static func convertUsd(_ value: Double, to currency: DisplayCurrency, rates: [String: Double]) -> Double {
        let amount = value.isNaN ? 0 : value
        return Double(JSCompat.toFixed(amount * rate(for: currency, rates: rates), 6)) ?? 0
    }

    private static func rate(for currency: DisplayCurrency, rates: [String: Double]) -> Double {
        if let value = rates[currency.rawValue], value.isFinite, value > 0 { return value }
        return CurrencyRates.floors[currency.rawValue] ?? 1
    }

    /// `Array.prototype.sort` (stable) with the desktop's newest-first comparator.
    private static func sortedNewestFirst(_ entries: [(Int, HubSubscription.TopUp)]) -> [HubSubscription.TopUp] {
        entries.sorted { left, right in
            if left.1.date != right.1.date { return SubscriptionJS.less(right.1.date, left.1.date) }
            return left.0 < right.0
        }
        .map(\.1)
    }

    /// A Double that is already integral, as an `Int` (saturating, 0 for NaN).
    static func integer(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        if value >= 9.2e18 { return Int.max }
        if value <= -9.2e18 { return Int.min }
        return Int(value.rounded())
    }

    private static func pad2(_ value: Int) -> String {
        value >= 0 && value < 10 ? "0\(value)" : "\(value)"
    }

    private static func floorDivide(_ value: Int, _ divisor: Int) -> Int {
        let quotient = value / divisor
        return (value % divisor != 0 && (value < 0) != (divisor < 0)) ? quotient - 1 : quotient
    }

    private static func saturatingAdd(_ left: Int, _ right: Int) -> Int {
        let (sum, overflow) = left.addingReportingOverflow(right)
        return overflow ? (right > 0 ? Int.max : Int.min) : sum
    }

    private static func saturatingMultiply(_ left: Int, _ right: Int) -> Int {
        let (product, overflow) = left.multipliedReportingOverflow(by: right)
        return overflow ? ((left < 0) == (right < 0) ? Int.max : Int.min) : product
    }
}

// MARK: - Normalization (`normalizeSubscription`)

extension HubSubscription: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, provider, kind, binding, planName, amountMinor, currency, interval, intervalCount
        case startDate, topUps, autoRenew, nextRenewalOverride, endDate, note, updatedAt
    }

    private enum BindingKeys: String, CodingKey {
        case profileName, accountEmail
    }

    /// Normalizes like `normalizeSubscription()`; throws for a record the
    /// desktop would discard. A record without an id gets `sub_<index>` (its
    /// position in the list) instead of the desktop's random one, so it keeps
    /// its identity across refetches.
    public init(from decoder: Decoder) throws {
        let value = try SubscriptionWireValue(from: decoder)
        guard let record = HubSubscription.normalized(value, index: decoder.codingPath.last?.intValue ?? 0) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a usable subscription record"))
        }
        self = record
    }

    /// Writes the Hub's record shape (with a binding that has no `accountKey`).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(provider, forKey: .provider)
        try container.encode(kind, forKey: .kind)
        var binding = container.nestedContainer(keyedBy: BindingKeys.self, forKey: .binding)
        try binding.encode(bindingProfileName ?? "", forKey: .profileName)
        try binding.encode(bindingEmail ?? "", forKey: .accountEmail)
        try container.encode(planName, forKey: .planName)
        try container.encode(amountMinor, forKey: .amountMinor)
        try container.encode(currency, forKey: .currency)
        try container.encode(interval, forKey: .interval)
        try container.encode(intervalCount, forKey: .intervalCount)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(topUps, forKey: .topUps)
        try container.encode(autoRenew, forKey: .autoRenew)
        try container.encode(nextRenewalOverride, forKey: .nextRenewalOverride)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(note, forKey: .note)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    fileprivate static func normalized(_ input: SubscriptionWireValue, index: Int) -> HubSubscription? {
        guard case .object = input else { return nil }
        let provider = input["provider"].cleanText.lowercased()
        let kind = Kind(rawValue: input["kind"].cleanText.lowercased()) ?? .subscription
        let startDate = SubscriptionMath.normalizedDate(input["startDate"].cleanText)
        let topUps = TopUp.normalizedList(input["topUps"])
        guard !provider.isEmpty else { return nil }
        // Each kind has its own anchor, and a record without one derives nothing.
        if kind == .topup ? topUps.isEmpty : startDate == nil { return nil }

        let binding = input["binding"]
        let email = binding["accountEmail"].cleanText.lowercased()
        let profileName = binding["profileName"].cleanText
        let id = input["id"].cleanText
        let updatedAt = input["updatedAt"].cleanText
        return HubSubscription(
            id: id.isEmpty ? "sub_\(index)" : id,
            provider: provider,
            kind: kind,
            bindingEmail: email.isEmpty ? nil : email,
            bindingProfileName: profileName.isEmpty ? nil : profileName,
            planName: input["planName"].cleanText,
            amountMinor: input["amountMinor"].amountMinor,
            currency: SubscriptionMath.normalizedCurrency(input["currency"].currencyText).rawValue,
            interval: Interval(rawValue: input["interval"].cleanText.lowercased()) ?? .month,
            intervalCount: input["intervalCount"].finiteNumber
                .map { SubscriptionMath.normalizedIntervalCount(SubscriptionMath.integer(JSCompat.round($0))) } ?? 1,
            startDate: startDate,
            topUps: topUps,
            autoRenew: input["autoRenew"] != .bool(false),
            nextRenewalOverride: SubscriptionMath.normalizedDate(input["nextRenewalOverride"].cleanText),
            endDate: SubscriptionMath.normalizedDate(input["endDate"].cleanText),
            note: input["note"].cleanText,
            updatedAt: updatedAt.isEmpty ? nil : updatedAt
        )
    }
}

extension HubSubscription.TopUp: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, date, amountMinor
    }

    /// Normalizes like `normalizeTopUp()`; throws for an entry without a valid
    /// date. An entry without an id gets `top_<index>`.
    public init(from decoder: Decoder) throws {
        let value = try SubscriptionWireValue(from: decoder)
        guard let entry = Self.normalized(value, index: decoder.codingPath.last?.intValue ?? 0) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a usable top-up"))
        }
        self = entry
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(amountMinor, forKey: .amountMinor)
    }

    fileprivate static func normalized(_ input: SubscriptionWireValue, index: Int) -> HubSubscription.TopUp? {
        guard let date = SubscriptionMath.normalizedDate(input["date"].cleanText) else { return nil }
        let id = input["id"].cleanText
        return HubSubscription.TopUp(id: id.isEmpty ? "top_\(index)" : id, date: date, amountMinor: input["amountMinor"].amountMinor)
    }

    /// `normalizeTopUps()`: valid entries, newest first, stable for equal dates.
    fileprivate static func normalizedList(_ input: SubscriptionWireValue) -> [HubSubscription.TopUp] {
        guard case .array(let items) = input else { return [] }
        let entries = items.enumerated().compactMap { index, item in normalized(item, index: index).map { (index, $0) } }
        return entries.sorted { left, right in
            if left.1.date != right.1.date { return SubscriptionJS.less(right.1.date, left.1.date) }
            return left.0 < right.0
        }
        .map(\.1)
    }
}

extension SubscriptionDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, updatedAt, subscriptions
    }

    /// Lenient: a missing or malformed list is empty, malformed records are
    /// dropped, and a repeated id keeps its first record
    /// (`normalizeSubscriptions()`). Throws only when the body is not a JSON
    /// object.
    public init(from decoder: Decoder) throws {
        let root = try SubscriptionWireValue(from: decoder)
        guard case .object = root else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "subscription document is not an object"))
        }
        version = root["version"].finiteNumber.map { SubscriptionMath.integer(JSCompat.round($0)) } ?? 1
        // The version token is compared verbatim, as `String(doc.updatedAt || '')`.
        updatedAt = root["updatedAt"].isFalsy ? "" : root["updatedAt"].jsString
        var seen = Set<String>()
        var records: [HubSubscription] = []
        if case .array(let items) = root["subscriptions"] {
            for (index, item) in items.enumerated() {
                guard let record = HubSubscription.normalized(item, index: index), seen.insert(record.id).inserted else { continue }
                records.append(record)
            }
        }
        subscriptions = records
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(subscriptions, forKey: .subscriptions)
    }
}

// MARK: - JavaScript coercions

/// A JSON value, read the way the desktop's JavaScript reads record fields
/// (`String(value)`, `Number(value)`, `value !== false`), so normalization
/// matches it for numbers sent as strings, strings sent as numbers and the
/// like.
private enum SubscriptionWireValue: Decodable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SubscriptionWireValue])
    case object([String: SubscriptionWireValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SubscriptionWireValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: SubscriptionWireValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "unsupported JSON value")
        }
    }

    /// `value?.[key]`, with `undefined` read as `.null`.
    subscript(key: String) -> SubscriptionWireValue {
        if case .object(let fields) = self { return fields[key] ?? .null }
        return .null
    }

    /// `String(value)` for a defined value.
    var jsString: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return JSCompat.numberString(value)
        case .string(let value): return value
        case .array(let items): return items.map { $0 == .null ? "" : $0.jsString }.joined(separator: ",")
        case .object: return "[object Object]"
        }
    }

    /// `cleanText(value)`: `String(value ?? '').trim()`.
    var cleanText: String {
        self == .null ? "" : SubscriptionJS.trim(jsString)
    }

    /// `currency.js` `normalizeCurrency()`'s `String(value || '')`.
    var currencyText: String {
        isFalsy ? "" : jsString
    }

    var isFalsy: Bool {
        switch self {
        case .null: return true
        case .bool(let value): return !value
        case .number(let value): return value == 0 || value.isNaN
        case .string(let value): return value.isEmpty
        case .array, .object: return false
        }
    }

    /// `finiteNumber(value)`: nil for null/undefined/`''`, else `Number(value)`
    /// when finite.
    var finiteNumber: Double? {
        let number: Double
        switch self {
        case .null: return nil
        case .bool(let value): number = value ? 1 : 0
        case .number(let value): number = value
        case .string(let value):
            if value.isEmpty { return nil }
            number = SubscriptionJS.toNumber(value)
        case .array, .object: number = SubscriptionJS.toNumber(jsString)
        }
        return number.isFinite ? number : nil
    }

    /// `normalizeAmountMinor(value)`: `max(0, Math.round(n))`, 0 when not a number.
    var amountMinor: Int {
        guard let number = finiteNumber else { return 0 }
        return max(0, SubscriptionMath.integer(JSCompat.round(number)))
    }
}

/// JavaScript string primitives the normalization relies on.
private enum SubscriptionJS {
    /// `String.prototype.trim`'s whitespace: WhiteSpace and LineTerminator,
    /// which (unlike Foundation's set) includes U+FEFF and excludes U+0085.
    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    static func trim(_ value: String) -> String {
        let scalars = value.unicodeScalars
        guard let first = scalars.firstIndex(where: { !isWhitespace($0) }),
              let last = scalars.lastIndex(where: { !isWhitespace($0) }) else { return "" }
        return String(String.UnicodeScalarView(scalars[first...last]))
    }

    /// `a < b` on strings: UTF-16 code-unit order.
    static func less(_ left: String, _ right: String) -> Bool {
        left.utf16.lexicographicallyPrecedes(right.utf16)
    }

    /// `Number(string)`: trimmed; empty is 0; `0x`/`0o`/`0b` integers;
    /// `Infinity` with an optional sign; otherwise a decimal literal or NaN.
    static func toNumber(_ value: String) -> Double {
        let text = trim(value)
        if text.isEmpty { return 0 }
        let bytes = Array(text.utf8)
        if bytes.count > 2, bytes[0] == UInt8(ascii: "0") {
            let radix: Double?
            switch bytes[1] {
            case UInt8(ascii: "x"), UInt8(ascii: "X"): radix = 16
            case UInt8(ascii: "o"), UInt8(ascii: "O"): radix = 8
            case UInt8(ascii: "b"), UInt8(ascii: "B"): radix = 2
            default: radix = nil
            }
            if let radix {
                var result = 0.0
                for byte in bytes.dropFirst(2) {
                    guard let digit = hexDigit(byte), Double(digit) < radix else { return .nan }
                    result = result * radix + Double(digit)
                }
                return result
            }
        }
        switch text {
        case "Infinity", "+Infinity": return .infinity
        case "-Infinity": return -.infinity
        default: break
        }
        guard isDecimalLiteral(bytes) else { return .nan }
        let unsigned = bytes.first == UInt8(ascii: "+") ? String(text.dropFirst()) : text
        return Double(unsigned) ?? .nan
    }

    /// `[+-]? (digits [. digits?] | . digits) ([eE] [+-]? digits)?`, ASCII only.
    private static func isDecimalLiteral(_ bytes: [UInt8]) -> Bool {
        var index = 0
        func digits() -> Int {
            let start = index
            while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
            return index - start
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
        var mantissa = digits()
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            mantissa += digits()
        }
        guard mantissa > 0 else { return false }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard digits() > 0 else { return false }
        }
        return index == bytes.count
    }

    private static func hexDigit(_ byte: UInt8) -> Int? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return Int(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return Int(byte - UInt8(ascii: "a")) + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return Int(byte - UInt8(ascii: "A")) + 10
        default: return nil
        }
    }
}

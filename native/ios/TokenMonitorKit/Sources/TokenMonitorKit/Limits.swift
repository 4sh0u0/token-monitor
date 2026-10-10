import Foundation

/// A provider row's status, as normalized by the Hub (`limits/core.js`).
/// Unknown values decode as `.error`, the macOS widget's rule.
public enum LimitStatus: String, Sendable, Codable, CaseIterable {
    case ok
    case disabled
    case notConfigured
    case unauthorized
    case rateLimited
    case sourceRateLimited
    case unavailable
    case error

    /// The coarse bucket UI code maps to a localized label and colour. The
    /// macOS widget's labels for these are "Available", "Sign in again",
    /// "Rate limited", "Temporarily unavailable"/"Unavailable" and
    /// "Disabled"/"Not configured".
    public var category: LimitStatusCategory {
        switch self {
        case .ok: return .available
        case .unauthorized: return .needsSignIn
        case .rateLimited, .sourceRateLimited: return .rateLimited
        case .unavailable, .error: return .unavailable
        case .disabled, .notConfigured: return .inactive
        }
    }

    init(wire: String?) {
        self = wire.flatMap(LimitStatus.init(rawValue:)) ?? .error
    }
}

public enum LimitStatusCategory: String, Sendable, Codable {
    case available
    case needsSignIn
    case rateLimited
    case unavailable
    case inactive
}

/// `windows[].kind`. The Hub folds `monthly`/`billingCycle` into `billing`
/// and drops any other kind.
public enum LimitWindowKind: String, Sendable, Codable, CaseIterable {
    case session
    case daily
    case weekly
    case billing

    init?(wire: String?) {
        guard let wire else { return nil }
        let folded = wire.lowercased().filter { !"_- \t".contains($0) }
        switch folded {
        case "session": self = .session
        case "daily": self = .daily
        case "weekly": self = .weekly
        case "billing", "billingcycle", "monthly": self = .billing
        default: return nil
        }
    }
}

/// `windows[].metric`: the window's headline is money, not a percentage.
public enum LimitWindowMetric: String, Sendable, Codable {
    /// A balance: `remaining` money in `currency` (OpenRouter credits,
    /// DeepSeek balance, Claude prepaid credits, …).
    case credits
    /// Money already consumed: `used` (and `limit` when a cap is set).
    case spend
}

/// `windows[].boundaryKind`: what `resetsAt` means. Changes wording only.
public enum LimitBoundaryKind: String, Sendable, Codable {
    /// The quota refills at `resetsAt` ("Resets in …"). Also the legacy default.
    case reset
    /// The allowance lapses at `resetsAt` ("Expires in …").
    case expiry
    /// A simultaneous reset and expiry ("Changes in …").
    case mixed
}

/// One quota window of a limits provider.
///
/// Display rules (docs/architecture.md, Balance quotas): key money display off
/// `metric`, never off the provider; honour `showMeter == false`; a meter
/// fills by what is *left*.
public struct LimitWindow: Sendable, Equatable, Identifiable {
    /// Unique within its provider.
    public var id: String
    public var kind: LimitWindowKind
    /// Provider-supplied display label ("Credits", a Codex model bucket, …).
    /// When nil the UI names the window by `kind`.
    public var label: String?
    public var metric: LimitWindowMetric?
    /// 0...100, nil when the window has no percentage (most balances).
    public var usedPercent: Double?
    /// 0...100, nil when the window has no percentage.
    public var remainingPercent: Double?
    /// Absolute amounts in `currency` (money windows) or provider units.
    public var used: Double?
    public var limit: Double?
    public var remaining: Double?
    /// Uppercase code for `used`/`limit`/`remaining` (`USD`, `CNY`, or
    /// `CREDITS` for provider points).
    public var currency: String?
    public var resetsAt: Date?
    public var boundaryKind: LimitBoundaryKind
    public var windowMinutes: Double?
    /// False when no meter may be drawn (e.g. Claude's prepaid balance has no
    /// denominator). The headline value is still shown.
    public var showMeter: Bool
    /// A separately metered Codex bucket; compact surfaces leave these out.
    public var isAdditional: Bool
    public var limitId: String?
    /// Bounded display-only description from the provider.
    public var detail: String?
    /// Provider wording for the boundary, shown when `resetsAt` is absent
    /// (`resetDescription`).
    public var resetDescription: String?

    public init(
        id: String? = nil,
        kind: LimitWindowKind,
        label: String? = nil,
        metric: LimitWindowMetric? = nil,
        usedPercent: Double? = nil,
        remainingPercent: Double? = nil,
        used: Double? = nil,
        limit: Double? = nil,
        remaining: Double? = nil,
        currency: String? = nil,
        resetsAt: Date? = nil,
        boundaryKind: LimitBoundaryKind = .reset,
        windowMinutes: Double? = nil,
        showMeter: Bool = true,
        isAdditional: Bool = false,
        limitId: String? = nil,
        detail: String? = nil,
        resetDescription: String? = nil
    ) {
        self.kind = kind
        self.label = label
        self.metric = metric
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.used = used
        self.limit = limit
        self.remaining = remaining
        self.currency = currency
        self.resetsAt = resetsAt
        self.boundaryKind = boundaryKind
        self.windowMinutes = windowMinutes
        self.showMeter = showMeter
        self.isAdditional = isAdditional
        self.limitId = limitId
        self.detail = detail
        self.resetDescription = resetDescription
        self.id = id ?? Self.baseID(kind: kind, metric: metric, limitId: limitId, label: label)
    }

    static func baseID(kind: LimitWindowKind, metric: LimitWindowMetric?, limitId: String?, label: String?) -> String {
        [kind.rawValue, metric?.rawValue ?? "", limitId ?? "", label ?? ""].joined(separator: "|")
    }

    /// The headline is an amount of money (or provider credits), not a percentage.
    public var isMoney: Bool { metric != nil }
    public var isCredits: Bool { metric == .credits }
    public var isSpend: Bool { metric == .spend }

    /// The provider marks the allowance as unlimited.
    public var isUnlimited: Bool { detail?.lowercased() == "unlimited" }

    /// The money headline: `remaining` for a balance, `used` for spend.
    public var moneyAmount: Double? {
        switch metric {
        case .credits: return remaining
        case .spend: return used
        case nil: return nil
        }
    }

    /// The meter fill in 0...1, measured as what is *left* (like the desktop
    /// and the macOS widget). Nil when the window must not draw a meter or
    /// carries no percentage — for a balance without one use
    /// `LimitProvider.meterFraction(for:)`, which applies the desktop's
    /// display-only derivation.
    public var displayFraction: Double? {
        guard showMeter else { return nil }
        if let remainingPercent { return min(1, max(0, remainingPercent / 100)) }
        if let usedPercent { return min(1, max(0, 1 - usedPercent / 100)) }
        return nil
    }
}

extension LimitWindow: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, type, label, displayLabel, title, metric
        case usedPercent, used_percent, utilization, percent, remainingPercent
        case used, limit, remaining, currency
        case resetsAt, resets_at, resetAt, reset_at
        case boundaryKind, boundary_kind, windowMinutes, window_minutes
        case showMeter, meter, additional, limitId, limit_id, detail, resetDescription
    }

    /// Lenient, mirroring `normalizeLimitWindow()`; throws only when the kind
    /// is missing or unknown (the Hub drops those windows too).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let kind = LimitWindowKind(wire: container.lenientString(.kind) ?? container.lenientString(.type)) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "unknown limit window kind")
        }
        let used = container.lenientDouble(.used)
        let limit = container.lenientDouble(.limit)
        let explicitUsed = container.lenientDouble(.usedPercent)
            ?? container.lenientDouble(.used_percent)
            ?? container.lenientDouble(.utilization)
            ?? container.lenientDouble(.percent)
        var usedPercent = explicitUsed.map { min(100, max(0, $0)) }
        if usedPercent == nil, let used, let limit, limit > 0 {
            usedPercent = min(100, max(0, used / limit * 100))
        }
        let remainingPercent = container.lenientDouble(.remainingPercent).map { min(100, max(0, $0)) }
            ?? usedPercent.map { 100 - $0 }
        let currency = container.lenientString(.currency).map { String($0.uppercased().prefix(8)) }
        self.init(
            kind: kind,
            label: container.lenientString(.label) ?? container.lenientString(.displayLabel) ?? container.lenientString(.title),
            metric: container.lenientString(.metric).flatMap { LimitWindowMetric(rawValue: $0.lowercased()) },
            usedPercent: usedPercent,
            remainingPercent: remainingPercent,
            used: used,
            limit: limit,
            remaining: container.lenientDouble(.remaining),
            currency: currency,
            resetsAt: container.lenientDate(.resetsAt)
                ?? container.lenientDate(.resets_at)
                ?? container.lenientDate(.resetAt)
                ?? container.lenientDate(.reset_at),
            boundaryKind: (container.lenientString(.boundaryKind) ?? container.lenientString(.boundary_kind))
                .flatMap { LimitBoundaryKind(rawValue: $0.lowercased()) } ?? .reset,
            windowMinutes: container.lenientDouble(.windowMinutes) ?? container.lenientDouble(.window_minutes),
            showMeter: container.lenientBool(.showMeter) != false && container.lenientBool(.meter) != false,
            isAdditional: container.lenientBool(.additional) == true,
            limitId: container.lenientString(.limitId) ?? container.lenientString(.limit_id),
            detail: container.lenientString(.detail),
            resetDescription: container.lenientString(.resetDescription)
        )
    }

    /// Writes the wire field names, so a stored copy decodes through the same
    /// lenient path.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(metric?.rawValue, forKey: .metric)
        try container.encodeIfPresent(usedPercent, forKey: .usedPercent)
        try container.encodeIfPresent(remainingPercent, forKey: .remainingPercent)
        try container.encodeIfPresent(used, forKey: .used)
        try container.encodeIfPresent(limit, forKey: .limit)
        try container.encodeIfPresent(remaining, forKey: .remaining)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeISODate(resetsAt, forKey: .resetsAt)
        if boundaryKind != .reset { try container.encode(boundaryKind.rawValue, forKey: .boundaryKind) }
        try container.encodeIfPresent(windowMinutes, forKey: .windowMinutes)
        if !showMeter { try container.encode(false, forKey: .showMeter) }
        if isAdditional { try container.encode(true, forKey: .additional) }
        try container.encodeIfPresent(limitId, forKey: .limitId)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(resetDescription, forKey: .resetDescription)
    }
}

/// `balance.planStatus`: whether a provider's token plan (MiMo) is current.
public enum LimitPlanStatus: String, Sendable, Codable, CaseIterable {
    case active
    case expired
}

/// One prepaid credit grant with its own expiry (`balance.tranches[]`).
public struct LimitBalanceTranche: Sendable, Hashable {
    public var amount: Double
    /// Uppercase code, nil when the grant names none (use the balance's).
    public var currency: String?
    public var expiresAt: Date?

    public init(amount: Double, currency: String? = nil, expiresAt: Date? = nil) {
        self.amount = amount
        self.currency = currency
        self.expiresAt = expiresAt
    }
}

extension LimitBalanceTranche: Codable {
    private enum CodingKeys: String, CodingKey {
        case amount, currency, expiresAt, expires_at
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let amount = container.lenientDouble(.amount) else {
            throw DecodingError.dataCorruptedError(forKey: .amount, in: container, debugDescription: "tranche without amount")
        }
        self.init(
            amount: amount,
            currency: container.lenientString(.currency).map(LimitBalance.currencyCode),
            expiresAt: container.lenientDate(.expiresAt) ?? container.lenientDate(.expires_at)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(amount, forKey: .amount)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeISODate(expiresAt, forKey: .expiresAt)
    }
}

/// `limits.providers[].balance` (`normalizeProviderBalance`, limits/core.js):
/// a provider-level money balance plus the spend and plan figures the desktop
/// card shows around it.
public struct LimitBalance: Sendable, Equatable {
    public var amount: Double?
    /// Uppercase code; `CREDITS` means provider points rather than money.
    public var currency: String?
    public var todaySpend: Double?
    public var weekSpend: Double?
    public var monthSpend: Double?
    public var allTimeSpend: Double?
    public var expiresAt: Date?
    /// Requests counted by a relay (third-party APIs), truncated, ≥ 0.
    public var requestCount: Int?
    /// A relay's quota group name.
    public var quotaGroup: String?
    /// When Token Monitor started recording this balance's spend.
    public var trackingSince: Date?
    /// The month spend counts only from `trackingSince` (a partial month).
    public var monthSinceTracking: Bool
    public var giftBalance: Double?
    public var cashBalance: Double?
    public var planUsed: Double?
    public var planLimit: Double?
    public var planPercent: Double?
    public var planStatus: LimitPlanStatus?
    /// Prepaid grants, soonest expiry first, grants without one last.
    public var tranches: [LimitBalanceTranche]

    public init(
        amount: Double? = nil,
        currency: String? = nil,
        todaySpend: Double? = nil,
        weekSpend: Double? = nil,
        monthSpend: Double? = nil,
        allTimeSpend: Double? = nil,
        expiresAt: Date? = nil,
        requestCount: Int? = nil,
        quotaGroup: String? = nil,
        trackingSince: Date? = nil,
        monthSinceTracking: Bool = false,
        giftBalance: Double? = nil,
        cashBalance: Double? = nil,
        planUsed: Double? = nil,
        planLimit: Double? = nil,
        planPercent: Double? = nil,
        planStatus: LimitPlanStatus? = nil,
        tranches: [LimitBalanceTranche] = []
    ) {
        self.amount = amount
        self.currency = currency
        self.todaySpend = todaySpend
        self.weekSpend = weekSpend
        self.monthSpend = monthSpend
        self.allTimeSpend = allTimeSpend
        self.expiresAt = expiresAt
        self.requestCount = requestCount
        self.quotaGroup = quotaGroup
        self.trackingSince = trackingSince
        self.monthSinceTracking = monthSinceTracking
        self.giftBalance = giftBalance
        self.cashBalance = cashBalance
        self.planUsed = planUsed
        self.planLimit = planLimit
        self.planPercent = planPercent
        self.planStatus = planStatus
        self.tranches = tranches
    }

    /// Nothing worth keeping (the currency alone does not count).
    var isEmpty: Bool {
        amount == nil && todaySpend == nil && weekSpend == nil && monthSpend == nil && allTimeSpend == nil
            && expiresAt == nil && requestCount == nil && quotaGroup == nil && trackingSince == nil
            && !monthSinceTracking && giftBalance == nil && cashBalance == nil && planUsed == nil
            && planLimit == nil && planPercent == nil && planStatus == nil && tranches.isEmpty
    }

    /// Any spend figure the card's Spend row would show.
    public var hasSpend: Bool {
        todaySpend != nil || weekSpend != nil || monthSpend != nil || allTimeSpend != nil
    }

    /// The copy kept in shared containers: per-grant detail and the relay's
    /// group name dropped (the desktop's `publicLimits` drops both too).
    func compacted() -> LimitBalance {
        var copy = self
        copy.tranches = []
        copy.quotaGroup = nil
        return copy
    }

    static func currencyCode(_ raw: String) -> String {
        String(raw.uppercased().prefix(8))
    }

    /// `normalizeBalanceTranches`' order: by expiry, undated last, ties stable.
    static func sortedTranches(_ tranches: [LimitBalanceTranche]) -> [LimitBalanceTranche] {
        tranches.enumerated().sorted { left, right in
            switch (left.element.expiresAt, right.element.expiresAt) {
            case let (leftDate?, rightDate?) where leftDate != rightDate: return leftDate < rightDate
            case (.some, nil): return true
            case (nil, .some): return false
            default: return left.offset < right.offset
            }
        }.map(\.element)
    }
}

extension LimitBalance: Codable {
    private enum CodingKeys: String, CodingKey {
        case amount, currency, todaySpend, weekSpend, monthSpend, allTimeSpend, expiresAt
        case requestCount, quotaGroup, trackingSince, monthSinceTracking, giftBalance, cashBalance
        case planUsed, planLimit, planPercent, planStatus, tranches
        case today_spend, week_spend, month_spend, all_time_spend, expires_at, request_count, quota_group
        case tracking_since, month_since_tracking, gift_balance, cash_balance
        case plan_used, plan_limit, plan_percent, plan_status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let requestCount = (container.lenientDouble(.requestCount) ?? container.lenientDouble(.request_count))
            .map { clampedInt(max(0, $0.rounded(.towardZero))) }
        let quotaGroup = (container.lenientString(.quotaGroup) ?? container.lenientString(.quota_group))
            .map { String($0.prefix(64)) }
        let planStatus = (container.lenientString(.planStatus) ?? container.lenientString(.plan_status))
            .flatMap { LimitPlanStatus(rawValue: $0.lowercased()) }
        self.init(
            amount: container.lenientDouble(.amount),
            currency: container.lenientString(.currency).map(Self.currencyCode),
            todaySpend: container.lenientDouble(.todaySpend) ?? container.lenientDouble(.today_spend),
            weekSpend: container.lenientDouble(.weekSpend) ?? container.lenientDouble(.week_spend),
            monthSpend: container.lenientDouble(.monthSpend) ?? container.lenientDouble(.month_spend),
            allTimeSpend: container.lenientDouble(.allTimeSpend) ?? container.lenientDouble(.all_time_spend),
            expiresAt: container.lenientDate(.expiresAt) ?? container.lenientDate(.expires_at),
            requestCount: requestCount,
            quotaGroup: quotaGroup,
            trackingSince: container.lenientDate(.trackingSince) ?? container.lenientDate(.tracking_since),
            monthSinceTracking: container.lenientBool(.monthSinceTracking) ?? container.lenientBool(.month_since_tracking) ?? false,
            giftBalance: container.lenientDouble(.giftBalance) ?? container.lenientDouble(.gift_balance),
            cashBalance: container.lenientDouble(.cashBalance) ?? container.lenientDouble(.cash_balance),
            planUsed: container.lenientDouble(.planUsed) ?? container.lenientDouble(.plan_used),
            planLimit: container.lenientDouble(.planLimit) ?? container.lenientDouble(.plan_limit),
            planPercent: container.lenientDouble(.planPercent) ?? container.lenientDouble(.plan_percent),
            planStatus: planStatus,
            tranches: Self.sortedTranches(container.lenientArray(.tranches, of: LimitBalanceTranche.self))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(amount, forKey: .amount)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(todaySpend, forKey: .todaySpend)
        try container.encodeIfPresent(weekSpend, forKey: .weekSpend)
        try container.encodeIfPresent(monthSpend, forKey: .monthSpend)
        try container.encodeIfPresent(allTimeSpend, forKey: .allTimeSpend)
        try container.encodeISODate(expiresAt, forKey: .expiresAt)
        try container.encodeIfPresent(requestCount, forKey: .requestCount)
        try container.encodeIfPresent(quotaGroup, forKey: .quotaGroup)
        try container.encodeISODate(trackingSince, forKey: .trackingSince)
        if monthSinceTracking { try container.encode(true, forKey: .monthSinceTracking) }
        try container.encodeIfPresent(giftBalance, forKey: .giftBalance)
        try container.encodeIfPresent(cashBalance, forKey: .cashBalance)
        try container.encodeIfPresent(planUsed, forKey: .planUsed)
        try container.encodeIfPresent(planLimit, forKey: .planLimit)
        try container.encodeIfPresent(planPercent, forKey: .planPercent)
        try container.encodeIfPresent(planStatus?.rawValue, forKey: .planStatus)
        if !tranches.isEmpty { try container.encode(tranches, forKey: .tranches) }
    }
}

/// One labelled reset grant (`resetCredits.grants[]`): why it was issued,
/// what it clears and whether it is spendable now. Only Claude sends these.
public struct LimitResetGrant: Sendable, Hashable {
    public var id: String?
    /// Provider text ("Outage credit"), shown as is.
    public var label: String?
    public var resetsLeft: Int?
    public var resetsTotal: Int?
    public var startsAt: Date?
    public var endsAt: Date?
    /// Window kinds the reset clears (`session`, `weekly`, …), de-duplicated.
    public var clears: [String]
    public var usableNow: Bool?
    public var useRequiresLimit: Bool?
    public var paused: Bool?

    public init(
        id: String? = nil,
        label: String? = nil,
        resetsLeft: Int? = nil,
        resetsTotal: Int? = nil,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        clears: [String] = [],
        usableNow: Bool? = nil,
        useRequiresLimit: Bool? = nil,
        paused: Bool? = nil
    ) {
        self.id = id
        self.label = label
        self.resetsLeft = resetsLeft
        self.resetsTotal = resetsTotal
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.clears = clears
        self.usableNow = usableNow
        self.useRequiresLimit = useRequiresLimit
        self.paused = paused
    }
}

extension LimitResetGrant: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, label, resetsLeft, resetsTotal, startsAt, endsAt, clears, usableNow, useRequiresLimit, paused
        case resets_left, resets_total, starts_at, ends_at, usable_now, use_requires_limit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys, _ alias: CodingKeys) -> Int? {
            (container.lenientDouble(key) ?? container.lenientDouble(alias)).map { clampedInt(max(0, $0.rounded(.down))) }
        }
        var clears: [String] = []
        for value in container.lenientStringArray(.clears) where !clears.contains(value) { clears.append(value) }
        self.init(
            id: container.lenientString(.id),
            label: container.lenientString(.label),
            resetsLeft: count(.resetsLeft, .resets_left),
            resetsTotal: count(.resetsTotal, .resets_total),
            startsAt: container.lenientDate(.startsAt) ?? container.lenientDate(.starts_at),
            endsAt: container.lenientDate(.endsAt) ?? container.lenientDate(.ends_at),
            clears: clears,
            usableNow: container.lenientBool(.usableNow) ?? container.lenientBool(.usable_now),
            useRequiresLimit: container.lenientBool(.useRequiresLimit) ?? container.lenientBool(.use_requires_limit),
            paused: container.lenientBool(.paused)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(resetsLeft, forKey: .resetsLeft)
        try container.encodeIfPresent(resetsTotal, forKey: .resetsTotal)
        try container.encodeISODate(startsAt, forKey: .startsAt)
        try container.encodeISODate(endsAt, forKey: .endsAt)
        if !clears.isEmpty { try container.encode(clears, forKey: .clears) }
        try container.encodeIfPresent(usableNow, forKey: .usableNow)
        try container.encodeIfPresent(useRequiresLimit, forKey: .useRequiresLimit)
        try container.encodeIfPresent(paused, forKey: .paused)
    }
}

/// `resetCredits` (`normalizeProviderResetCredits`): banked quota resets
/// (Codex, Claude) and when they lapse.
public struct LimitResetCredits: Sendable, Hashable {
    public var availableCount: Int?
    /// The soonest of the wire `nextExpiresAt` and the first expiration.
    public var nextExpiresAt: Date?
    /// Available credits' expiries, de-duplicated, soonest first.
    public var expirations: [Date]
    public var grants: [LimitResetGrant]

    public init(availableCount: Int? = nil, nextExpiresAt: Date? = nil, expirations: [Date] = [], grants: [LimitResetGrant] = []) {
        self.availableCount = availableCount
        self.nextExpiresAt = nextExpiresAt
        self.expirations = expirations
        self.grants = grants
    }
}

extension LimitResetCredits: Codable {
    private enum CodingKeys: String, CodingKey {
        case availableCount, available_count, available, remainingCount, remaining_count
        case nextExpiresAt, next_expires_at, nextExpirationAt, next_expiration_at, expiresAt, expires_at
        case expirations, expirationTimes, expiresAtList, expires_at_list, credits
        case grants
    }

    /// One `expirations[]` entry: a timestamp, or an object whose `status`
    /// (when set) must be `available`.
    private struct Expiration: Decodable {
        let date: Date?

        private enum Keys: String, CodingKey {
            case status, expiresAt, expires_at, nextExpiresAt, next_expires_at
        }

        init(from decoder: Decoder) throws {
            if let container = try? decoder.container(keyedBy: Keys.self) {
                if let status = container.lenientString(.status), status.lowercased() != "available" {
                    date = nil
                    return
                }
                date = container.lenientDate(.expiresAt) ?? container.lenientDate(.expires_at)
                    ?? container.lenientDate(.nextExpiresAt) ?? container.lenientDate(.next_expires_at)
                return
            }
            let single = try decoder.singleValueContainer()
            if let string = try? single.decode(String.self) {
                date = ISODate.parse(string)
            } else if let number = try? single.decode(Double.self) {
                date = ISODate.fromEpoch(number)
            } else {
                date = nil
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let available = container.lenientDouble(.availableCount) ?? container.lenientDouble(.available_count)
            ?? container.lenientDouble(.available) ?? container.lenientDouble(.remainingCount)
            ?? container.lenientDouble(.remaining_count)
        let wireNext = container.lenientDate(.nextExpiresAt) ?? container.lenientDate(.next_expires_at)
            ?? container.lenientDate(.nextExpirationAt) ?? container.lenientDate(.next_expiration_at)
            ?? container.lenientDate(.expiresAt) ?? container.lenientDate(.expires_at)
        let listKey = [CodingKeys.expirations, .expirationTimes, .expiresAtList, .expires_at_list, .credits]
            .first { !container.isNullOrMissing($0) }
        var expirations: [Date] = []
        var seen: Set<String> = []
        for entry in listKey.map({ container.lenientArray($0, of: Expiration.self) }) ?? [] {
            // Identity at millisecond precision, as the desktop compares ISO strings.
            guard let date = entry.date, seen.insert(ISODate.string(from: date)).inserted else { continue }
            expirations.append(date)
        }
        expirations.sort()
        let next = [wireNext, expirations.first].compactMap { $0 }.min()
        let grants = container.lenientArray(.grants, of: LimitResetGrant.self)
        guard available != nil || next != nil || !expirations.isEmpty || !grants.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .availableCount, in: container, debugDescription: "empty reset credits")
        }
        self.init(
            availableCount: available.map { clampedInt(max(0, $0.rounded(.down))) },
            nextExpiresAt: next,
            expirations: expirations,
            grants: grants
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(availableCount, forKey: .availableCount)
        try container.encodeISODate(nextExpiresAt, forKey: .nextExpiresAt)
        if !expirations.isEmpty { try container.encode(expirations.map(ISODate.string(from:)), forKey: .expirations) }
        if !grants.isEmpty { try container.encode(grants, forKey: .grants) }
    }
}

/// `usageSummary.period`: what the summary's totals cover.
public enum LimitUsageSummaryPeriod: String, Sendable, Codable, CaseIterable {
    case today
    case week
    case month
    case allTime
}

/// `usageSummary` (`normalizeProviderUsageSummary`): a relay's or TypeSafe's
/// own token and request totals. Counts are truncated and ≥ 0.
public struct LimitUsageSummary: Sendable, Hashable {
    public var period: LimitUsageSummaryPeriod?
    public var requests: Int?
    public var todayTokens: Int?
    public var weekTokens: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cacheReadTokens: Int?
    public var cacheCreationTokens: Int?
    public var totalTokens: Int?
    /// Cost at list prices, in the balance currency.
    public var standardCost: Double?
    /// What the relay charged.
    public var actualCost: Double?
    public var averageDurationMs: Double?

    public init(
        period: LimitUsageSummaryPeriod? = nil,
        requests: Int? = nil,
        todayTokens: Int? = nil,
        weekTokens: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        cacheCreationTokens: Int? = nil,
        totalTokens: Int? = nil,
        standardCost: Double? = nil,
        actualCost: Double? = nil,
        averageDurationMs: Double? = nil
    ) {
        self.period = period
        self.requests = requests
        self.todayTokens = todayTokens
        self.weekTokens = weekTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.totalTokens = totalTokens
        self.standardCost = standardCost
        self.actualCost = actualCost
        self.averageDurationMs = averageDurationMs
    }

    var isEmpty: Bool {
        period == nil && requests == nil && todayTokens == nil && weekTokens == nil && inputTokens == nil
            && outputTokens == nil && cacheReadTokens == nil && cacheCreationTokens == nil && totalTokens == nil
            && standardCost == nil && actualCost == nil && averageDurationMs == nil
    }
}

extension LimitUsageSummary: Codable {
    private enum CodingKeys: String, CodingKey {
        case period, requests, todayTokens, weekTokens, inputTokens, outputTokens, cacheReadTokens
        case cacheCreationTokens, totalTokens, standardCost, actualCost, averageDurationMs
        case today_tokens, week_tokens, input_tokens, output_tokens, cache_read_tokens
        case cache_creation_tokens, total_tokens, standard_cost, actual_cost, average_duration_ms
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys, _ alias: CodingKeys? = nil) -> Int? {
            (container.lenientDouble(key) ?? alias.flatMap { container.lenientDouble($0) })
                .map { clampedInt(max(0, $0.rounded(.towardZero))) }
        }
        func amount(_ key: CodingKeys, _ alias: CodingKeys) -> Double? {
            (container.lenientDouble(key) ?? container.lenientDouble(alias)).map { max(0, $0) }
        }
        let summary = LimitUsageSummary(
            period: container.lenientString(.period).flatMap(LimitUsageSummaryPeriod.init(rawValue:)),
            requests: count(.requests),
            todayTokens: count(.todayTokens, .today_tokens),
            weekTokens: count(.weekTokens, .week_tokens),
            inputTokens: count(.inputTokens, .input_tokens),
            outputTokens: count(.outputTokens, .output_tokens),
            cacheReadTokens: count(.cacheReadTokens, .cache_read_tokens),
            cacheCreationTokens: count(.cacheCreationTokens, .cache_creation_tokens),
            totalTokens: count(.totalTokens, .total_tokens),
            standardCost: amount(.standardCost, .standard_cost),
            actualCost: amount(.actualCost, .actual_cost),
            averageDurationMs: amount(.averageDurationMs, .average_duration_ms)
        )
        guard !summary.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .period, in: container, debugDescription: "empty usage summary")
        }
        self = summary
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(period?.rawValue, forKey: .period)
        try container.encodeIfPresent(requests, forKey: .requests)
        try container.encodeIfPresent(todayTokens, forKey: .todayTokens)
        try container.encodeIfPresent(weekTokens, forKey: .weekTokens)
        try container.encodeIfPresent(inputTokens, forKey: .inputTokens)
        try container.encodeIfPresent(outputTokens, forKey: .outputTokens)
        try container.encodeIfPresent(cacheReadTokens, forKey: .cacheReadTokens)
        try container.encodeIfPresent(cacheCreationTokens, forKey: .cacheCreationTokens)
        try container.encodeIfPresent(totalTokens, forKey: .totalTokens)
        try container.encodeIfPresent(standardCost, forKey: .standardCost)
        try container.encodeIfPresent(actualCost, forKey: .actualCost)
        try container.encodeIfPresent(averageDurationMs, forKey: .averageDurationMs)
    }
}

/// One AI Tool Limits row of `limits.providers` — a provider account the Hub
/// aggregated across devices (the freshest valid reading wins).
///
/// The raw `accountKey` is deliberately not kept: `id` is derived from it by
/// hashing, so lists stay stable without the identifier reaching the UI.
public struct LimitProvider: Sendable, Equatable, Identifiable {
    /// Stable per provider account: `<provider>-<hash>` (or
    /// `<provider>-anonymous-<n>` for rows without an account key).
    public var id: String
    /// Provider id (`claude`, `codex`, `openrouter`, …); also the mark id.
    public var provider: String
    /// `VendorCatalog.limitProviderLabel(provider)`.
    public var displayName: String
    /// Third-party adapter (`newapi-account`, `sub2api`, …), when any.
    public var adapterId: String?
    public var accountEmail: String?
    public var accountName: String?
    /// The wire `planLabel` alone ("Max", "GLM Coding Pro"), nil when the
    /// producer sent none. `planLabel` adds the legacy fallback.
    public var explicitPlanLabel: String?
    /// The wire `accountLabel`: a legacy plan name, a product (MiMo
    /// "Console"), or a key's label ("API key"). Never an email or URL.
    public var accountLabel: String?
    /// `personal` for a personal workspace, else nil.
    public var workspaceKind: String?
    public var status: LimitStatus
    /// `accountVerification` or `appSessionEncrypted`, when the provider needs
    /// the user to act outside Token Monitor.
    public var actionRequired: String?
    /// `oauth`, `cli`, `web`, `rpc`, `local` or `api`.
    public var source: String?
    /// Which login a Codex reading came from: `app`, `cli`, `ide`, `managed`
    /// or `unknown`.
    public var sourceDetail: String?
    /// Provider region or plan variant (`cn`, `global`, `cn-personal`, …).
    public var region: String?
    /// The Hub device whose reading won the aggregation.
    public var sourceDeviceId: String?
    public var updatedAt: Date?
    /// The Hub's freshness verdict for this reading ("Data may be stale").
    public var isStale: Bool
    /// In the Hub's order (canonical lanes before additional Codex buckets).
    public var windows: [LimitWindow]
    public var balance: LimitBalance?
    public var resetCredits: LimitResetCredits?
    public var usageSummary: LimitUsageSummary?

    public init(
        id: String,
        provider: String,
        displayName: String? = nil,
        adapterId: String? = nil,
        accountEmail: String? = nil,
        accountName: String? = nil,
        planLabel: String? = nil,
        status: LimitStatus = .ok,
        actionRequired: String? = nil,
        source: String? = nil,
        updatedAt: Date? = nil,
        isStale: Bool = false,
        windows: [LimitWindow] = [],
        balance: LimitBalance? = nil,
        accountLabel: String? = nil,
        workspaceKind: String? = nil,
        sourceDetail: String? = nil,
        region: String? = nil,
        sourceDeviceId: String? = nil,
        resetCredits: LimitResetCredits? = nil,
        usageSummary: LimitUsageSummary? = nil
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName ?? VendorCatalog.limitProviderLabel(provider)
        self.adapterId = adapterId
        self.accountEmail = accountEmail
        self.accountName = accountName
        self.explicitPlanLabel = planLabel
        self.accountLabel = accountLabel
        self.workspaceKind = workspaceKind
        self.status = status
        self.actionRequired = actionRequired
        self.source = source
        self.sourceDetail = sourceDetail
        self.region = region
        self.sourceDeviceId = sourceDeviceId
        self.updatedAt = updatedAt
        self.isStale = isStale
        self.windows = windows
        self.balance = balance
        self.resetCredits = resetCredits
        self.usageSummary = usageSummary
    }

    /// The plan ("Max", "Plus", "Zen"); falls back to the legacy
    /// `accountLabel` for producers that predate `planLabel`. Setting it sets
    /// `explicitPlanLabel`.
    public var planLabel: String? {
        get { explicitPlanLabel ?? accountLabel }
        set { explicitPlanLabel = newValue }
    }

    public var statusCategory: LimitStatusCategory { status.category }

    /// Who the row belongs to, for display: the account email, else the
    /// profile name.
    public var accountDisplayName: String? {
        accountEmail ?? accountName
    }

    /// The account identity with the email masked (`d***v@example.com`), as
    /// the macOS widget writes it into shared containers.
    public var maskedAccountDisplayName: String? {
        if let email = accountEmail, let masked = Self.maskedEmail(email) { return masked }
        return accountName.flatMap(Self.safeDisplayName)
    }

    public var hasData: Bool { !windows.isEmpty || balance?.amount != nil }

    /// Usable quota data from a healthy, fresh reading.
    public var isReady: Bool { status == .ok && hasData && !isStale }

    /// Windows for compact surfaces: additional Codex buckets left out.
    public var primaryWindows: [LimitWindow] { windows.filter { !$0.isAdditional } }

    /// The window a one-number surface (a complication) should show: the
    /// first percentage window with the least left, else the first balance.
    public var headlineWindow: LimitWindow? {
        let candidates = primaryWindows
        let percentWindows = candidates.filter { !$0.isMoney && $0.remainingPercent != nil }
        if let tightest = percentWindows.min(by: { ($0.remainingPercent ?? 100) < ($1.remainingPercent ?? 100) }) {
            return tightest
        }
        return candidates.first(where: \.isCredits) ?? candidates.first
    }

    /// The meter fill (0...1, what is left) for one of this provider's
    /// windows. A balance without a percentage is visualized against this
    /// month's inferred starting funds — `amount / (amount + monthSpend)` —
    /// the desktop's display-only rule (`creditsMeterPercent`), never a wire
    /// value. Nil when the window must not draw a meter.
    public func meterFraction(for window: LimitWindow) -> Double? {
        guard window.showMeter else { return nil }
        if let fraction = window.displayFraction { return fraction }
        guard window.isCredits, let amount = window.remaining ?? balance?.amount else { return nil }
        let funds = max(0, amount)
        if funds == 0 { return 0 }
        let spend = max(0, balance?.monthSpend ?? 0)
        return min(1, max(0, funds / (funds + spend)))
    }

    /// The visible-items checklist id of one of this provider's windows
    /// (`LimitUsageItems.itemID(for:provider:)`).
    public func usageItemID(for window: LimitWindow) -> String {
        LimitUsageItems.itemID(for: window, provider: provider)
    }

    /// Whether the user hid `window` in the `limitProviderHiddenItems` setting.
    public func isHidden(_ window: LimitWindow, hiddenItems: [String: [String]]) -> Bool {
        LimitUsageItems.isHidden(window, provider: provider, hiddenItems: hiddenItems)
    }

    /// `windows` minus the ones hidden in `limitProviderHiddenItems`, in order.
    public func visibleWindows(hiddenItems: [String: [String]]) -> [LimitWindow] {
        let hidden = LimitUsageItems.hiddenSet(hiddenItems, provider: provider)
        guard !hidden.isEmpty else { return windows }
        return windows.filter { !hidden.contains(usageItemID(for: $0)) }
    }

    /// A copy safe and small enough for shared containers (App Group,
    /// WatchConnectivity): the email masked, path- or URL-like names
    /// dropped, only primary windows the user has not hidden (at most
    /// `maxWindows`), and the extras only the app shows stripped —
    /// `resetCredits`, `usageSummary`, the balance's `tranches` and
    /// `quotaGroup`, and `sourceDeviceId`. The account key was never kept.
    ///
    /// Hidden items remove windows only; the balance stays, so a credits
    /// meter keeps measuring against the month's spend.
    public func compacted(maxWindows: Int = 4, hiddenItems: [String: [String]] = [:]) -> LimitProvider {
        var copy = self
        copy.accountEmail = accountEmail.flatMap(Self.maskedEmail)
        copy.accountName = accountName.flatMap(Self.safeDisplayName)
        copy.accountLabel = accountLabel.flatMap(Self.safeDisplayName)
        let hidden = LimitUsageItems.hiddenSet(hiddenItems, provider: provider)
        let visible = primaryWindows.filter { hidden.isEmpty || !hidden.contains(usageItemID(for: $0)) }
        copy.windows = Array(visible.prefix(max(0, maxWindows)))
        copy.balance = balance?.compacted()
        copy.sourceDeviceId = nil
        copy.resetCredits = nil
        copy.usageSummary = nil
        return copy
    }

    /// Ready rows first, then the desktop's provider order, then account.
    public static func sortedForDisplay(_ providers: [LimitProvider]) -> [LimitProvider] {
        providers.enumerated().sorted { left, right in
            let leftReady = left.element.isReady ? 0 : 1
            let rightReady = right.element.isReady ? 0 : 1
            if leftReady != rightReady { return leftReady < rightReady }
            let leftIndex = VendorCatalog.limitProviderSortIndex(left.element.provider)
            let rightIndex = VendorCatalog.limitProviderSortIndex(right.element.provider)
            if leftIndex != rightIndex { return leftIndex < rightIndex }
            if left.element.provider != right.element.provider { return left.element.provider < right.element.provider }
            return left.offset < right.offset
        }.map(\.element)
    }

    /// Most constrained first, for surfaces that lead with "the tightest
    /// quota": healthy, fresh readings (`isReady`) first; among them the least
    /// left first, by `meterFraction(for: headlineWindow)`; providers without
    /// a meter after every measured one; ties keep the input order, so equal
    /// rows never swap between refreshes.
    public static func sortedByUrgency(_ providers: [LimitProvider]) -> [LimitProvider] {
        providers.enumerated().sorted { left, right in
            let leftReady = left.element.isReady ? 0 : 1
            let rightReady = right.element.isReady ? 0 : 1
            if leftReady != rightReady { return leftReady < rightReady }
            switch (left.element.headlineFraction, right.element.headlineFraction) {
            case let (leftRemaining?, rightRemaining?) where leftRemaining != rightRemaining:
                return leftRemaining < rightRemaining
            case (.some, nil): return true
            case (nil, .some): return false
            default: return left.offset < right.offset
            }
        }.map(\.element)
    }

    /// What is left of the headline window (0...1), nil without a meter.
    var headlineFraction: Double? {
        headlineWindow.flatMap { meterFraction(for: $0) }
    }

    // Port of `maskedWidgetEmail()` in src/shared/macWidgetSnapshot.js.
    static func maskedEmail(_ value: String) -> String? {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let at = email.lastIndex(of: "@"), at != email.startIndex else { return nil }
        let local = email[..<at]
        let domain = email[email.index(after: at)...]
        // Same test as the JavaScript `/^[^\s@]+\.[^\s@]+$/`: a dot with
        // something on both sides, no whitespace and no second `@`.
        guard !domain.contains("@"), !domain.contains(where: \.isWhitespace),
              domain.dropFirst().dropLast().contains(".") else { return nil }
        let first = local.first.map(String.init) ?? ""
        let last = local.count > 1 ? (local.last.map(String.init) ?? "") : ""
        return "\(first)***\(last)@\(domain)"
    }

    // Port of `safeDisplayName()`: no paths, URLs, emails or control characters.
    static func safeDisplayName(_ value: String) -> String? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.count <= 80, !raw.contains("@") else { return nil }
        guard !raw.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else { return nil }
        let lowered = raw.lowercased()
        let looksLikePath = raw.hasPrefix("/") || raw.hasPrefix("\\\\") || raw.hasPrefix("~/") || raw.hasPrefix("./")
            || raw.hasPrefix("../") || lowered.hasPrefix("file://") || lowered.hasPrefix("http://")
            || lowered.hasPrefix("https://") || raw.range(of: #"^[A-Za-z]:[\\/]"#, options: .regularExpression) != nil
        guard !looksLikePath else { return nil }
        return raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

extension LimitProvider: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, provider, displayName, adapterId, adapter_id, accountKey, accountEmail, accountName, accountLabel, planLabel
        case workspaceKind, status, actionRequired, source, sourceDetail, source_detail, region, sourceDeviceId
        case updatedAt, checkedAt, stale, windows, balance, balanceUsd
        case resetCredits, rateLimitResetCredits, rate_limit_reset_credits, usageSummary, usage_summary
    }

    /// Decodes both the Hub's wire row and the Kit's own encoding. On the wire
    /// `id` is absent and derived from `accountKey`; `HubStats` then numbers
    /// rows that share an id.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let provider = container.lenientString(.provider)?.lowercased() else {
            throw DecodingError.dataCorruptedError(forKey: .provider, in: container, debugDescription: "limits row without provider")
        }
        let accountKey = container.lenientString(.accountKey)
        let derivedID = accountKey.map { "\(provider)-\(StableHash.hex("\(provider)|key:\($0)"))" } ?? "\(provider)-anonymous"
        var windows = container.lenientArray(.windows, of: LimitWindow.self)
        var seen: [String: Int] = [:]
        for index in windows.indices {
            let base = windows[index].id
            let count = (seen[base] ?? 0) + 1
            seen[base] = count
            if count > 1 { windows[index].id = "\(base)#\(count)" }
        }
        var balance = container.lenientObject(.balance, as: LimitBalance.self)
        if balance?.isEmpty == true, balance?.currency == nil { balance = nil }
        // `balanceUsd` predates the credits window and the balance block.
        if balance == nil, let usd = container.lenientDouble(.balanceUsd) {
            balance = LimitBalance(amount: usd, currency: "USD")
        }
        let resetCredits = container.lenientObject(.resetCredits, as: LimitResetCredits.self)
            ?? container.lenientObject(.rateLimitResetCredits, as: LimitResetCredits.self)
            ?? container.lenientObject(.rate_limit_reset_credits, as: LimitResetCredits.self)
        self.init(
            id: container.lenientString(.id) ?? derivedID,
            provider: provider,
            displayName: container.lenientString(.displayName),
            adapterId: (container.lenientString(.adapterId) ?? container.lenientString(.adapter_id))?.lowercased(),
            accountEmail: container.lenientString(.accountEmail),
            accountName: container.lenientString(.accountName),
            planLabel: container.lenientString(.planLabel),
            status: LimitStatus(wire: container.lenientString(.status)),
            actionRequired: container.lenientString(.actionRequired),
            source: container.lenientString(.source)?.lowercased(),
            updatedAt: container.lenientDate(.updatedAt) ?? container.lenientDate(.checkedAt),
            isStale: container.lenientBool(.stale) ?? false,
            windows: windows,
            balance: balance,
            accountLabel: container.lenientString(.accountLabel),
            workspaceKind: container.lenientString(.workspaceKind)?.lowercased(),
            sourceDetail: (container.lenientString(.sourceDetail) ?? container.lenientString(.source_detail))?.lowercased(),
            region: container.lenientString(.region)?.lowercased(),
            sourceDeviceId: container.lenientString(.sourceDeviceId),
            resetCredits: resetCredits,
            usageSummary: container.lenientObject(.usageSummary, as: LimitUsageSummary.self)
                ?? container.lenientObject(.usage_summary, as: LimitUsageSummary.self)
        )
    }

    /// Writes the wire field names, so a stored copy decodes through the same
    /// lenient path; an older reader still finds the plan under `planLabel`
    /// or `accountLabel`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(provider, forKey: .provider)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(adapterId, forKey: .adapterId)
        try container.encodeIfPresent(accountEmail, forKey: .accountEmail)
        try container.encodeIfPresent(accountName, forKey: .accountName)
        try container.encodeIfPresent(explicitPlanLabel, forKey: .planLabel)
        try container.encodeIfPresent(accountLabel, forKey: .accountLabel)
        try container.encodeIfPresent(workspaceKind, forKey: .workspaceKind)
        try container.encode(status.rawValue, forKey: .status)
        try container.encodeIfPresent(actionRequired, forKey: .actionRequired)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(sourceDetail, forKey: .sourceDetail)
        try container.encodeIfPresent(region, forKey: .region)
        try container.encodeIfPresent(sourceDeviceId, forKey: .sourceDeviceId)
        try container.encodeISODate(updatedAt, forKey: .updatedAt)
        if isStale { try container.encode(true, forKey: .stale) }
        try container.encode(windows, forKey: .windows)
        try container.encodeIfPresent(balance, forKey: .balance)
        try container.encodeIfPresent(resetCredits, forKey: .resetCredits)
        try container.encodeIfPresent(usageSummary, forKey: .usageSummary)
    }
}

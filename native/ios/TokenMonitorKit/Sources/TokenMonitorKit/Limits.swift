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
        detail: String? = nil
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
        case showMeter, meter, additional, limitId, limit_id, detail
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
            detail: container.lenientString(.detail)
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
    }
}

/// `limits.providers[].balance`, reduced to what a phone shows.
public struct LimitBalance: Sendable, Equatable {
    public var amount: Double?
    /// Uppercase code; `CREDITS` means provider points rather than money.
    public var currency: String?
    public var todaySpend: Double?
    public var weekSpend: Double?
    public var monthSpend: Double?
    public var allTimeSpend: Double?
    public var expiresAt: Date?

    public init(
        amount: Double? = nil,
        currency: String? = nil,
        todaySpend: Double? = nil,
        weekSpend: Double? = nil,
        monthSpend: Double? = nil,
        allTimeSpend: Double? = nil,
        expiresAt: Date? = nil
    ) {
        self.amount = amount
        self.currency = currency
        self.todaySpend = todaySpend
        self.weekSpend = weekSpend
        self.monthSpend = monthSpend
        self.allTimeSpend = allTimeSpend
        self.expiresAt = expiresAt
    }

    var isEmpty: Bool {
        amount == nil && todaySpend == nil && weekSpend == nil && monthSpend == nil && allTimeSpend == nil
    }
}

extension LimitBalance: Codable {
    private enum CodingKeys: String, CodingKey {
        case amount, currency, todaySpend, weekSpend, monthSpend, allTimeSpend, expiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            amount: container.lenientDouble(.amount),
            currency: container.lenientString(.currency).map { String($0.uppercased().prefix(8)) },
            todaySpend: container.lenientDouble(.todaySpend),
            weekSpend: container.lenientDouble(.weekSpend),
            monthSpend: container.lenientDouble(.monthSpend),
            allTimeSpend: container.lenientDouble(.allTimeSpend),
            expiresAt: container.lenientDate(.expiresAt)
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
    /// The plan ("Max", "Plus", "Zen"); falls back to the legacy
    /// `accountLabel` for producers that predate `planLabel`.
    public var planLabel: String?
    public var status: LimitStatus
    /// `accountVerification` or `appSessionEncrypted`, when the provider needs
    /// the user to act outside Token Monitor.
    public var actionRequired: String?
    /// `oauth`, `cli`, `web`, `rpc`, `local` or `api`.
    public var source: String?
    public var updatedAt: Date?
    /// The Hub's freshness verdict for this reading ("Data may be stale").
    public var isStale: Bool
    /// In the Hub's order (canonical lanes before additional Codex buckets).
    public var windows: [LimitWindow]
    public var balance: LimitBalance?

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
        balance: LimitBalance? = nil
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName ?? VendorCatalog.limitProviderLabel(provider)
        self.adapterId = adapterId
        self.accountEmail = accountEmail
        self.accountName = accountName
        self.planLabel = planLabel
        self.status = status
        self.actionRequired = actionRequired
        self.source = source
        self.updatedAt = updatedAt
        self.isStale = isStale
        self.windows = windows
        self.balance = balance
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

    /// A copy safe for shared containers (App Group, WatchConnectivity): the
    /// email masked, path- or URL-like names dropped, and only the first
    /// `maxWindows` primary windows kept.
    public func compacted(maxWindows: Int = 4) -> LimitProvider {
        var copy = self
        copy.accountEmail = accountEmail.flatMap(Self.maskedEmail)
        copy.accountName = accountName.flatMap(Self.safeDisplayName)
        copy.windows = Array(primaryWindows.prefix(max(0, maxWindows)))
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
        case id, provider, displayName, adapterId, accountKey, accountEmail, accountName, accountLabel, planLabel
        case status, actionRequired, source, updatedAt, checkedAt, stale, windows, balance, balanceUsd
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
        self.init(
            id: container.lenientString(.id) ?? derivedID,
            provider: provider,
            displayName: container.lenientString(.displayName),
            adapterId: container.lenientString(.adapterId),
            accountEmail: container.lenientString(.accountEmail),
            accountName: container.lenientString(.accountName),
            planLabel: container.lenientString(.planLabel) ?? container.lenientString(.accountLabel),
            status: LimitStatus(wire: container.lenientString(.status)),
            actionRequired: container.lenientString(.actionRequired),
            source: container.lenientString(.source),
            updatedAt: container.lenientDate(.updatedAt) ?? container.lenientDate(.checkedAt),
            isStale: container.lenientBool(.stale) ?? false,
            windows: windows,
            balance: balance
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(provider, forKey: .provider)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(adapterId, forKey: .adapterId)
        try container.encodeIfPresent(accountEmail, forKey: .accountEmail)
        try container.encodeIfPresent(accountName, forKey: .accountName)
        try container.encodeIfPresent(planLabel, forKey: .planLabel)
        try container.encode(status.rawValue, forKey: .status)
        try container.encodeIfPresent(actionRequired, forKey: .actionRequired)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeISODate(updatedAt, forKey: .updatedAt)
        if isStale { try container.encode(true, forKey: .stale) }
        try container.encode(windows, forKey: .windows)
        try container.encodeIfPresent(balance, forKey: .balance)
    }
}

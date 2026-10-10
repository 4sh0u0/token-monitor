import Foundation

// How Limits rows are presented on every surface: the status chip, the
// freshness line, quota meters and their headline values, plan cells, account
// titles, the Home limits module, balance/spend/reset-credit rows and the
// visible-items checklist.
//
// Ports, function by function, of the desktop renderer:
// - `src/electron/renderer/limits/providerPresentation.js` (status tags,
//   freshness, boundary text, plan display labels, compact windows, sources)
// - `src/electron/renderer/limits/displayMode.js` (used/remaining fill)
// - `src/electron/renderer/limits/windowsView.js` (plan cell, meter tones,
//   headline values, reset credits, spend rows, account titles)
// - `src/shared/limits/balanceDisplay.js` and `windowText.js`
// - `src/electron/renderer/homeOverview.js` and the Home module in `app.js`
// - `src/electron/renderer/accountIdentity.js` (account titles)
//
// Everything a target shows to a user is returned as a structured value (an
// enum case, a number, a date, or provider-supplied text such as a plan name);
// targets localize. The `desktopText` members reproduce the desktop's English
// byte for byte and exist for the golden tests.

/// Namespace for how Limits rows are presented on every surface (status
/// chip, freshness, meters, Home rows); presentation types that need no other
/// name live inside it.
public enum LimitPresentation {}

/// A limits provider's status chip: the desktop Settings-tag vocabulary
/// (`providerPresentation.js` `limitProviderStatusLabel`). Each case maps to
/// one desktop i18n key (`settings.limits.status.<case>`, with the two
/// exceptions `verifyInAntigravity` and `encryptedByApp`); targets localize it.
public enum LimitStatusLabel: String, Sendable, Codable, CaseIterable {
    case stale
    case verifyInAntigravity
    case encryptedByApp
    case live
    case linked
    case disabled
    case noSyncedData
    case updateCredential
    case updateApiKey
    case openCline
    case signInAgain
    case relogin
    case limited
    case usageApiLimited
    case unavailable
    case addCredential
    case notSetUp
    case signIn
    case addApiKey
    case runGrokLogin
    case runKiroLogin
    case error
}

/// The status chip's colour family (`styles.css` tag tones).
public enum LimitStatusTone: String, Sendable, Codable, CaseIterable {
    case ok
    case setup
    case warn
    case stale
    case sync
    case muted
}

/// Whether a meter reads what is left or what is used.
public enum MeterMode: String, Sendable, Codable, CaseIterable {
    case remaining
    case used
}

/// How to draw one quota meter.
public struct MeterFill: Sendable, Hashable {
    /// Bar fill 0–1; nil when the window has no meter.
    public var fraction: Double?
    /// The percentage the text shows (in `mode`), nil when unknown.
    public var percent: Double?
    /// What `fraction` and `percent` measure.
    public var mode: MeterMode
    /// Opacity of the provider colour for the fill, by tone.
    public var toneOpacity: Double

    public init(fraction: Double?, percent: Double?, mode: MeterMode, toneOpacity: Double) {
        self.fraction = fraction
        self.percent = percent
        self.mode = mode
        self.toneOpacity = toneOpacity
    }

    /// A `showMeter: false` window: a note row with no bar and no percent.
    public var isNoteRow: Bool { fraction == nil }
}

// MARK: - Status label wording keys

extension LimitStatusLabel {
    /// The desktop i18n key the target's string catalog reuses.
    public var desktopKey: String {
        switch self {
        case .verifyInAntigravity: return "settings.antigravity.verificationRequired"
        case .encryptedByApp: return "settings.limits.status.appSessionEncrypted"
        default: return "settings.limits.status.\(rawValue)"
        }
    }

    /// The desktop's English text.
    public var desktopText: String {
        switch self {
        case .stale: return "Stale"
        case .verifyInAntigravity: return "Open Antigravity to verify"
        case .encryptedByApp: return "Encrypted by app"
        case .live: return "Live"
        case .linked: return "Linked"
        case .disabled: return "Disabled"
        case .noSyncedData: return "No synced data"
        case .updateCredential: return "Update credential"
        case .updateApiKey: return "Update API key"
        case .openCline: return "Open Cline"
        case .signInAgain: return "Sign in again"
        case .relogin: return "Re-login"
        case .limited: return "Limited"
        case .usageApiLimited: return "Usage API limited"
        case .unavailable: return "Unavailable"
        case .addCredential: return "Add credential"
        case .notSetUp: return "Not set up"
        case .signIn: return "Sign in"
        case .addApiKey: return "Add API key"
        case .runGrokLogin: return "Run grok login"
        case .runKiroLogin: return "Run kiro-cli login"
        case .error: return "Error"
        }
    }
}

// MARK: - Status chip

extension LimitPresentation {
    /// One provider row's status chip.
    public struct StatusChip: Sendable, Hashable {
        public var label: LimitStatusLabel
        public var tone: LimitStatusTone
        /// The 6 pt mint `status-dot`: a healthy (`ok`), fresh reading.
        public var showsLiveDot: Bool

        public init(label: LimitStatusLabel, tone: LimitStatusTone, showsLiveDot: Bool = false) {
            self.label = label
            self.tone = tone
            self.showsLiveDot = showsLiveDot
        }

        /// The renderer-only placeholder for a provider the Hub has no row for.
        public static let noSyncedData = StatusChip(label: .noSyncedData, tone: .sync)
    }

    /// `limitProviderStatusLabel`: the Settings-tag precedence — stale, then
    /// Antigravity's account verification, then WorkBuddy's encrypted app
    /// session, then the status with its per-provider variants. The label is
    /// never nil for a decoded row (an unknown wire status decodes as `error`).
    public static func status(_ provider: LimitProvider) -> (label: LimitStatusLabel?, tone: LimitStatusTone) {
        let chip = statusChip(provider)
        return (chip.label, chip.tone)
    }

    /// `status(_:)` as a value, with the live dot.
    public static func statusChip(_ provider: LimitProvider) -> StatusChip {
        statusChip(provider, ignoringStale: false)
    }

    /// The detail line only Antigravity has (desktop
    /// `settings.antigravity.verificationRequiredDetail`): Google wants the
    /// account verified in Antigravity before quotas can be read again.
    public static func antigravityNeedsVerification(_ provider: LimitProvider) -> Bool {
        normalizedID(provider.provider) == "antigravity" && provider.actionRequired == "accountVerification"
    }

    /// The status chip as if the reading were fresh: what the plan cell shows
    /// for a stale row that is not `ok`.
    static func statusChip(_ provider: LimitProvider, ignoringStale: Bool) -> StatusChip {
        let id = normalizedID(provider.provider)
        if provider.isStale && !ignoringStale { return StatusChip(label: .stale, tone: .stale) }
        if id == "antigravity" && provider.actionRequired == "accountVerification" {
            return StatusChip(label: .verifyInAntigravity, tone: .setup)
        }
        if id == "workbuddy" && provider.actionRequired == "appSessionEncrypted" {
            return StatusChip(label: .encryptedByApp, tone: .warn)
        }
        let showsDot = provider.status == .ok && !provider.isStale
        switch provider.status {
        case .ok:
            return StatusChip(label: isLinkedStatus(provider) ? .linked : .live, tone: .ok, showsLiveDot: showsDot)
        case .disabled:
            return StatusChip(label: .disabled, tone: .muted)
        case .unauthorized:
            return StatusChip(label: unauthorizedLabel(id, source: normalizedID(provider.source ?? "")), tone: .setup)
        case .rateLimited:
            return StatusChip(label: .limited, tone: .warn)
        case .sourceRateLimited:
            return StatusChip(label: .usageApiLimited, tone: .warn)
        case .unavailable:
            return StatusChip(label: .unavailable, tone: .warn)
        case .notConfigured:
            return StatusChip(label: notConfiguredLabel(id), tone: .setup)
        case .error:
            return StatusChip(label: id == "mimo" ? .unavailable : .error, tone: .warn)
        }
    }

    private static let updateApiKeyProviders: Set<String> = [
        "openrouter", "deepseek", "minimax", "copilot", "factory", "zai", "zaiteam", "volcengine", "kimi"
    ]
    private static let signInProviders: Set<String> = [
        "cursor", "copilot", "zed", "typesafe", "stepfun", "qoder", "trae", "workbuddy", "commandcode", "ollama", "alibaba"
    ]
    private static let addApiKeyProviders: Set<String> = [
        "openrouter", "deepseek", "minimax", "factory", "zai", "zaiteam", "volcengine", "kimi", "cline"
    ]

    private static func unauthorizedLabel(_ id: String, source: String) -> LimitStatusLabel {
        if id == "kimi" || id == "thirdparty" { return .updateCredential }
        if id == "cline" { return source == "api" ? .updateApiKey : .openCline }
        if updateApiKeyProviders.contains(id) { return .updateApiKey }
        if id == "qoder" || id == "trae" { return .signInAgain }
        if id == "grok" { return .relogin }
        return .signInAgain
    }

    private static func notConfiguredLabel(_ id: String) -> LimitStatusLabel {
        if id == "kimi" { return .addCredential }
        if id == "antigravity" { return .notSetUp }
        if signInProviders.contains(id) { return .signIn }
        if id == "thirdparty" { return .addCredential }
        if addApiKeyProviders.contains(id) { return .addApiKey }
        if id == "grok" { return .runGrokLogin }
        if id == "kiro" { return .runKiroLogin }
        return .notSetUp
    }

    /// `isLinkedStatus`: a healthy reading through a signed-in browser session
    /// reads "Linked" rather than "Live".
    static func isLinkedStatus(_ provider: LimitProvider) -> Bool {
        let id = normalizedID(provider.provider)
        let source = normalizedID(provider.source ?? "")
        return (id == "claude" && source == "web")
            || id == "cursor"
            || (id == "opencode" && source == "web")
            || (id == "mimo" && source == "web")
            || (id == "zed" && source == "web")
    }
}

// MARK: - Freshness

extension LimitPresentation {
    /// How long ago, in the desktop's coarse buckets (`limitProviderFreshness`).
    /// Targets localize with the `settings.age.*` family.
    public enum AgeBucket: Sendable, Hashable {
        /// Under 45 seconds.
        case justNow
        /// Rounded minutes, 1…59.
        case minutes(Int)
        /// Rounded hours, 1…23.
        case hours(Int)
        /// Rounded days.
        case days(Int)

        /// `just now`, `5m ago`, `3h ago`, `2d ago`.
        public var desktopText: String {
            switch self {
            case .justNow: return "just now"
            case .minutes(let value): return "\(value)m ago"
            case .hours(let value): return "\(value)h ago"
            case .days(let value): return "\(value)d ago"
            }
        }
    }

    /// The freshness decoration's tone (`ok`, `stale`, or `unknown` when the
    /// row carries no timestamp and is not stale).
    public enum FreshnessTone: String, Sendable, Hashable {
        case ok
        case stale
        case unknown
    }

    /// The meta line's first part: "Updated {age}", "Stale · {age}", "Stale"
    /// or "Update unknown".
    public enum Freshness: Sendable, Hashable {
        /// The Hub marked the reading stale; `age` is nil without a timestamp.
        case stale(age: AgeBucket?)
        case updated(AgeBucket)
        /// No timestamp and not stale.
        case unknown

        public var age: AgeBucket? {
            switch self {
            case .stale(let age): return age
            case .updated(let age): return age
            case .unknown: return nil
            }
        }

        public var tone: FreshnessTone {
            switch self {
            case .stale: return .stale
            case .updated: return .ok
            case .unknown: return .unknown
            }
        }

        public var desktopText: String {
            switch self {
            case .stale(let age?): return "Stale · \(age.desktopText)"
            case .stale(nil): return "Stale"
            case .updated(let age): return "Updated \(age.desktopText)"
            case .unknown: return "Update unknown"
            }
        }
    }

    /// The age bucket for `milliseconds` elapsed (negative counts as 0).
    public static func ageBucket(milliseconds: Double) -> AgeBucket {
        let diff = max(0, milliseconds)
        if diff < 45_000 { return .justNow }
        let minutes = jsRoundInt(diff / 60_000)
        if minutes < 60 { return .minutes(minutes) }
        let hours = jsRoundInt(Double(minutes) / 60)
        if hours < 24 { return .hours(hours) }
        return .days(jsRoundInt(Double(hours) / 24))
    }

    /// `limitProviderFreshness(provider, {nowMs})`, reading `updatedAt` (the
    /// decoder already fell back to `checkedAt`).
    public static func freshness(_ provider: LimitProvider, now: Date) -> Freshness {
        guard let updatedAt = provider.updatedAt else {
            return provider.isStale ? .stale(age: nil) : .unknown
        }
        let age = ageBucket(milliseconds: milliseconds(from: updatedAt, to: now))
        return provider.isStale ? .stale(age: age) : .updated(age)
    }
}

// MARK: - Durations and boundaries

extension LimitPresentation {
    /// `limitDurationText`: whole minutes (rounded), shown as "{d}d {h}h",
    /// "{h}h {m}m", "{m}m" or "<1m".
    public struct DurationParts: Sendable, Hashable {
        public enum Style: Sendable, Hashable {
            case daysHours(days: Int, hours: Int)
            case hoursMinutes(hours: Int, minutes: Int)
            case minutes(Int)
            case lessThanAMinute
        }

        public var totalMinutes: Int
        public var days: Int { totalMinutes / 1440 }
        public var hours: Int { (totalMinutes % 1440) / 60 }
        public var minutes: Int { totalMinutes % 60 }

        public init(milliseconds: Double) {
            let value = milliseconds.isFinite ? milliseconds : 0
            totalMinutes = max(0, jsRoundInt(value / 60_000))
        }

        public init(totalMinutes: Int) {
            self.totalMinutes = max(0, totalMinutes)
        }

        public var style: Style {
            if days > 0 { return .daysHours(days: days, hours: hours) }
            if hours > 0 { return .hoursMinutes(hours: hours, minutes: minutes) }
            if minutes > 0 { return .minutes(minutes) }
            return .lessThanAMinute
        }

        public var desktopText: String {
            switch style {
            case let .daysHours(days, hours): return "\(days)d \(hours)h"
            case let .hoursMinutes(hours, minutes): return "\(hours)h \(minutes)m"
            case .minutes(let minutes): return "\(minutes)m"
            case .lessThanAMinute: return "<1m"
            }
        }
    }

    /// The line under a quota meter (`limitBoundaryText`): "Reset {dur}",
    /// "Expires {dur}" or "Changes in {dur}"; at zero "Reset now", "Expires
    /// now" or "Changes now".
    public struct Boundary: Sendable, Hashable {
        public var kind: LimitBoundaryKind
        /// Milliseconds until the boundary; 0 within the 60 s grace after it.
        public var remainingMs: Double
        public var duration: DurationParts

        public init(kind: LimitBoundaryKind, remainingMs: Double) {
            self.kind = kind
            self.remainingMs = remainingMs
            self.duration = DurationParts(milliseconds: remainingMs)
        }

        /// The boundary has arrived (the grace window included).
        public var isNow: Bool { remainingMs == 0 }
        /// Rounded whole minutes left (`limitDurationText` rounding).
        public var remainingMinutes: Int { duration.totalMinutes }

        public var desktopText: String {
            let prefix: String
            switch kind {
            case .reset: prefix = "Reset"
            case .expiry: prefix = "Expires"
            case .mixed: prefix = "Changes in"
            }
            if isNow { return kind == .mixed ? "Changes now" : "\(prefix) now" }
            return "\(prefix) \(duration.desktopText)"
        }
    }

    /// What sits under a meter: the boundary countdown, or the provider's own
    /// wording when the window has no timestamp (`resetDescription`; Home
    /// wraps it as "Reset {value}").
    public enum BoundaryLine: Sendable, Hashable {
        case boundary(Boundary)
        case description(String)
    }

    /// `limitResetRemainingMs`: milliseconds until `date`; 0 within `graceMs`
    /// after it; nil without a date or once the grace has passed.
    public static func resetRemainingMs(_ date: Date?, now: Date, graceMs: Double = 60_000) -> Double? {
        guard let date else { return nil }
        let remaining = milliseconds(from: now, to: date)
        if remaining > 0 { return remaining }
        return remaining >= -max(0, graceMs) ? 0 : nil
    }

    /// The window's boundary countdown at `now`, nil when it has none or it
    /// passed more than a minute ago.
    public static func boundary(window: LimitWindow, now: Date) -> Boundary? {
        guard let remaining = resetRemainingMs(window.resetsAt, now: now) else { return nil }
        return Boundary(kind: window.boundaryKind, remainingMs: remaining)
    }

    /// `resetsAt ? limitBoundaryText(window) : resetDescription`: nil when the
    /// line would be empty (a timestamp past its grace shows nothing).
    public static func boundaryLine(window: LimitWindow, now: Date) -> BoundaryLine? {
        if window.resetsAt != nil { return boundary(window: window, now: now).map(BoundaryLine.boundary) }
        return window.resetDescription.map(BoundaryLine.description)
    }
}

// MARK: - Meters

extension LimitPresentation {
    /// `limitFillPercent(remaining, used, showUsed)`: the percent a meter fills
    /// with and its text shows, anchored on `remainingPercent`. A nil argument
    /// is the wire's `null`, which the desktop reads as 0 (`Number(null)`), so
    /// `(nil, 40, false)` is 0 exactly as on the desktop. Not clamped.
    public static func fillPercent(remaining: Double?, used: Double?, showUsed: Bool) -> Double {
        let remaining = jsNumber(remaining)
        let used = jsNumber(used)
        if showUsed {
            if let remaining { return 100 - remaining }
            if let used { return used }
            return 0
        }
        if let remaining { return remaining }
        if let used { return 100 - used }
        return 0
    }

    /// `limitModeSuffix`: the text mode for `showLimitUsed` ("% used" / "% left").
    public static func mode(showUsed: Bool) -> MeterMode {
        showUsed ? .used : .remaining
    }

    /// One Limits-page meter (`limitWindowNode`). Linear bars and their text
    /// follow `showUsed`; windows whose headline is money (`metric` credits or
    /// spend) stay in remaining mode so bar and value agree; a balance without
    /// a percentage is metered against this month's inferred funds
    /// (`creditsMeterPercent`, display-only) when its provider's card meters
    /// it (`balanceHasMeter`). `showMeter: false` gives a note row: no
    /// fraction, no percent (`MeterFill.isNoteRow`).
    ///
    /// Unlike the desktop, a non-money window with no percentage at all draws
    /// no meter (the desktop reads the wire's `null` as 0 and paints "0% left").
    public static func meterFill(window: LimitWindow, provider: LimitProvider, showUsed: Bool) -> MeterFill {
        let tone = toneOpacity(window: window, provider: provider)
        let note = MeterFill(fraction: nil, percent: nil, mode: .remaining, toneOpacity: tone)
        if window.isCredits {
            guard balanceHasMeter(window: window, provider: provider),
                  let percent = creditsMeterPercent(provider, window: window) else { return note }
            return MeterFill(fraction: clampPercent(percent) / 100, percent: percent, mode: .remaining, toneOpacity: tone)
        }
        guard window.showMeter, window.remainingPercent != nil || window.usedPercent != nil else { return note }
        let fillMode = mode(showUsed: showUsed && !window.isMoney)
        let fill = fillPercent(remaining: window.remainingPercent, used: window.usedPercent, showUsed: fillMode == .used)
        return MeterFill(fraction: clampPercent(fill) / 100, percent: fill, mode: fillMode, toneOpacity: tone)
    }

    /// A ring or gauge (watch, complications, widget circles): it always fills
    /// by what is left — "a ring that emptied as a quota recovered would read
    /// backwards" (`edgeDock/dock.js`) — while its number follows the text mode.
    public struct GaugeFill: Sendable, Hashable {
        /// What is left, 0–1; nil when there is no meter.
        public var remainingFraction: Double?
        /// The number to print, in `mode`.
        public var percent: Double?
        public var mode: MeterMode

        public init(remainingFraction: Double?, percent: Double?, mode: MeterMode) {
            self.remainingFraction = remainingFraction
            self.percent = percent
            self.mode = mode
        }
    }

    /// Whether the Limits card draws a meter for a balance (`credits`)
    /// window. Each provider's card decides: DeepSeek, TypeSafe, Z.ai, MiMo
    /// and relays always meter their balance against the month's funds;
    /// OpenCode, Devin, Factory and Cline show it as a note row; everyone
    /// else follows the window's `showMeter`.
    public static func balanceHasMeter(window: LimitWindow, provider: LimitProvider) -> Bool {
        switch normalizedID(provider.provider) {
        case "deepseek", "typesafe", "zai", "zaiteam", "mimo", "thirdparty": return true
        case "opencode", "devin", "factory", "cline": return false
        default: return window.showMeter
        }
    }

    /// The ring for `window` (see `GaugeFill`).
    public static func gaugeFill(window: LimitWindow, provider: LimitProvider, showUsed: Bool) -> GaugeFill {
        let remaining: Double?
        if window.isCredits {
            guard balanceHasMeter(window: window, provider: provider) else {
                return GaugeFill(remainingFraction: nil, percent: nil, mode: .remaining)
            }
            remaining = creditsMeterPercent(provider, window: window)
        } else {
            guard window.showMeter else { return GaugeFill(remainingFraction: nil, percent: nil, mode: .remaining) }
            remaining = window.remainingPercent.map(clampPercent) ?? window.usedPercent.map { clampPercent(100 - $0) }
        }
        guard let remaining else { return GaugeFill(remainingFraction: nil, percent: nil, mode: .remaining) }
        let textMode = mode(showUsed: showUsed && !window.isMoney)
        return GaugeFill(remainingFraction: remaining / 100, percent: textMode == .used ? 100 - remaining : remaining, mode: textMode)
    }

    /// The fill opacity `windowsView.js` gives each window of each provider:
    /// 0.95 for the leading (session) lane, 0.68 for the secondary lanes, 0.78
    /// for additional pools and daily lanes, 0.5 for monthly spend pools.
    public static func toneOpacity(window: LimitWindow, provider: LimitProvider) -> Double {
        let id = normalizedID(provider.provider)
        let kind = window.kind
        switch id {
        case "codex":
            if window.isAdditional { return 0.78 }
            return kind == .session ? 0.95 : 0.68
        case "cursor", "grok", "copilot", "qoder", "mimo":
            return 0.68
        case "antigravity":
            if !antigravityGroups(provider).isEmpty, kind == .session { return 0.95 }
            return 0.78
        case "opencode":
            if window.isCredits { return 0.68 }
            switch kind {
            case .session: return 0.95
            case .weekly: return 0.68
            default: return 0.5
            }
        case "openrouter":
            if window.isCredits { return 0.95 }
            return window.showMeter ? 0.85 : 0.6
        case "thirdparty", "deepseek", "typesafe", "workbuddy", "trae", "zed":
            return 0.95
        case "zai", "zaiteam":
            if window.isCredits { return 0.95 }
            switch kind {
            case .session: return 0.95
            case .daily: return 0.78
            default: return 0.68
            }
        case "volcengine":
            switch kind {
            case .session: return 0.95
            case .daily: return 0.78
            default: return 0.68
            }
        case "devin":
            return kind == .daily && !window.isCredits ? 0.95 : 0.68
        case "factory":
            if window.isCredits { return 0.68 }
            switch kind {
            case .session: return 0.95
            case .billing: return 0.5
            default: return 0.68
            }
        case "kiro":
            return window.showMeter ? 0.68 : 0.6
        case "commandcode", "kimi", "cline":
            switch kind {
            case .session: return 0.95
            case .weekly: return 0.68
            default: return 0.5
            }
        case "claude":
            if window.isMoney || window.kind == .billing { return 0.5 }
            return kind == .session ? 0.95 : 0.68
        default:
            return kind == .session ? 0.95 : 0.68
        }
    }
}

// MARK: - Headline values

extension LimitPresentation {
    /// What a window's value cell reads (`formatLimitWindowValue`,
    /// `windowText.js`, the per-provider value overrides). Money is formatted
    /// with `BalanceFormat` in the provider's own currency (D-MONEY).
    public enum Headline: Sendable, Hashable {
        /// "N% left" / "N% used" (`Math.round`; targets localize "%@ left" /
        /// "%@ used").
        case percent(Double, MeterMode)
        /// A balance: `BalanceFormat.format` (Limits page) or `.compact` (Home).
        case money(Double, currency: String)
        /// "$x.xx left" — the desktop always writes dollars here.
        case amountLeft(Double)
        /// "$x.xx" for a meter-less window's remaining amount.
        case amount(Double)
        /// "$x.xx cap".
        case cap(Double)
        /// Money consumed: "$used / $limit" with a cap, "$used spent" without.
        case spend(used: Double, limit: Double?, currency: String)
        /// Kiro overage: "12.5 credits · $3.20" (either half optional).
        case overage(credits: Double?, costUSD: Double?)
        /// `settings.thirdparty.unlimited`.
        case unlimited
        /// MiMo's lapsed token plan (`limits.mimo.planExpired`).
        case planExpired
        /// Provider-supplied detail, shown as is.
        case text(String)
        /// Nothing to show ("--").
        case none

        public var desktopText: String {
            switch self {
            case let .percent(value, mode):
                return "\(JSCompat.numberString(JSCompat.round(value)))% \(mode == .used ? "used" : "left")"
            case let .money(amount, currency): return BalanceFormat.format(amount: amount, currency: currency)
            case .amountLeft(let amount): return "$\(JSCompat.toFixed(amount, 2)) left"
            case .amount(let amount): return "$\(JSCompat.toFixed(amount, 2))"
            case .cap(let amount): return "$\(JSCompat.toFixed(amount, 2)) cap"
            case let .spend(used, limit, currency):
                let usedText = BalanceFormat.format(amount: used, currency: currency)
                if let limit, limit > 0 { return "\(usedText) / \(BalanceFormat.format(amount: limit, currency: currency))" }
                return "\(usedText) spent"
            case let .overage(credits, cost):
                return [
                    credits.map { "\(JSCompat.numberString(Double(JSCompat.toFixed($0, 2)) ?? $0)) credits" },
                    cost.map { "$\(JSCompat.toFixed($0, 2))" }
                ].compactMap { $0 }.joined(separator: " · ")
            case .unlimited: return "Unlimited"
            case .planExpired: return "Expired"
            case .text(let text): return text
            case .none: return "--"
            }
        }
    }

    /// The Limits-page value of one window. Spend windows read their money,
    /// balances their amount, Kiro's meter-less overage its credits and cost,
    /// windows with a percentage the percentage in the text mode, and the
    /// rest the desktop's fallbacks (unlimited, "$x left", "$x cap", detail).
    public static func headline(window: LimitWindow, provider: LimitProvider, showUsed: Bool) -> Headline {
        let id = normalizedID(provider.provider)
        if window.isSpend || isLegacySpendWindow(window) {
            guard let used = window.used else { return .none }
            return .spend(used: used, limit: window.limit, currency: window.currency ?? "USD")
        }
        if window.isCredits {
            if let amount = creditsAmount(provider, window: window) {
                return .money(amount, currency: creditsCurrency(provider, window: window))
            }
            if window.isUnlimited { return .unlimited }
            return window.detail.map(Headline.text) ?? .none
        }
        if isExpiredTokenPlan(window, provider: provider) { return .planExpired }
        if id == "kiro", window.kind == .billing, !window.showMeter {
            return .overage(credits: window.used, costUSD: window.remaining)
        }
        let fill = meterFill(window: window, provider: provider, showUsed: showUsed)
        if fill.fraction != nil, let percent = fill.percent { return .percent(percent, fill.mode) }
        if window.isUnlimited { return .unlimited }
        if let remaining = window.remaining { return window.showMeter ? .amountLeft(remaining) : .amount(remaining) }
        if let limit = window.limit { return .cap(limit) }
        return window.detail.map(Headline.text) ?? .none
    }

    /// The absolute figure beside a window's boundary line (`windowText.js`
    /// `detail`). Pairs follow the text mode so they never contradict the bar.
    public enum WindowDetail: Sendable, Hashable {
        /// "$47.42 / $70.00" (`BalanceFormat`, the window's currency).
        case moneyPair(shown: Double, limit: Double, currency: String)
        /// "120/500": raw units trimmed to two decimals.
        case countPair(shown: Double, limit: Double)
        /// "124M / 305M": token counts; targets compact them.
        case tokenPair(shown: Double, limit: Double)
        /// Provider text, shown as is.
        case text(String)
        /// TypeSafe: the next grant to expire, when it is not the whole
        /// balance ("$25.00").
        case expiringAmount(Double, currency: String)
        /// MiMo: "Gift ¥2.00 · Cash ¥10.00" (either half optional).
        case giftCash(gift: Double?, cash: Double?, currency: String)

        /// The desktop's text; `tokenFormatter` compacts token counts.
        public func desktopText(tokenFormatter: (Double) -> String = { CompactNumberFormat.format($0) }) -> String {
            switch self {
            case let .moneyPair(shown, limit, currency):
                return "\(BalanceFormat.format(amount: shown, currency: currency)) / \(BalanceFormat.format(amount: limit, currency: currency))"
            case let .countPair(shown, limit):
                return "\(trimmedCount(shown))/\(trimmedCount(limit))"
            case let .tokenPair(shown, limit):
                return "\(tokenFormatter(shown)) / \(tokenFormatter(limit))"
            case .text(let text):
                return text
            case let .expiringAmount(amount, currency):
                return BalanceFormat.format(amount: amount, currency: currency)
            case let .giftCash(gift, cash, currency):
                return [
                    gift.map { "Gift \(BalanceFormat.format(amount: $0, currency: currency))" },
                    cash.map { "Cash \(BalanceFormat.format(amount: $0, currency: currency))" }
                ].compactMap { $0 }.joined(separator: " · ")
            }
        }

        private func trimmedCount(_ value: Double) -> String {
            let fixed = JSCompat.toFixed(max(0, value), 2)
            return JSCompat.numberString(Double(fixed) ?? value)
        }
    }

    /// `limitWindowText(provider, window).detail`: Command Code, Kiro, Qoder,
    /// Zed, Z.ai and Kimi carry a second figure under the bar; TypeSafe's
    /// balance names its next expiring grant and MiMo's its gift and cash
    /// parts; every other provider has none.
    public static func windowDetail(window: LimitWindow, provider: LimitProvider, showUsed: Bool, now: Date = Date()) -> WindowDetail? {
        let id = normalizedID(provider.provider)
        if window.isSpend { return nil }
        if window.isCredits {
            guard let balance = provider.balance else { return nil }
            if id == "typesafe" {
                guard let amount = finite(balance.amount),
                      let grant = balance.tranches.first(where: { ($0.expiresAt.map { milliseconds(from: now, to: $0) } ?? 0) > 0 }),
                      abs(grant.amount - amount) >= 0.005 else { return nil }
                return .expiringAmount(grant.amount, currency: BalanceFormat.normalizeCode(grant.currency ?? balance.currency))
            }
            if id == "mimo" {
                let gift = finite(balance.giftBalance)
                let cash = finite(balance.cashBalance)
                guard gift != nil || cash != nil else { return nil }
                return .giftCash(gift: gift, cash: cash, currency: creditsCurrency(provider, window: window))
            }
            return nil
        }
        let billing = window.kind == .billing
        switch id {
        case "commandcode":
            guard billing else { return nil }
            return moneyOfRemaining(window, showUsed: showUsed)
        case "kiro":
            guard billing, window.showMeter else { return nil }
            return rawCount(window, showUsed: showUsed)
        case "qoder":
            return billing ? rawCount(window, showUsed: showUsed) : nil
        case "zed":
            guard billing else { return nil }
            if window.limitId == "zed.edit-predictions" { return rawCount(window, showUsed: showUsed) }
            return moneyOfUsed(window, showUsed: showUsed)
        case "zai", "zaiteam":
            let pool = window.kind == .daily || (billing && window.limitId != nil)
            guard pool else { return nil }
            if let detail = window.detail { return .text(detail) }
            guard let remaining = window.remaining, let limit = window.limit, limit > 0 else { return nil }
            return .tokenPair(shown: showUsed ? max(0, limit - remaining) : remaining, limit: limit)
        case "kimi":
            return billing ? window.detail.map(WindowDetail.text) : nil
        default:
            return nil
        }
    }

    private static func rawCount(_ window: LimitWindow, showUsed: Bool) -> WindowDetail? {
        guard let used = window.used, let limit = window.limit, limit > 0 else { return nil }
        return .countPair(shown: showUsed ? used : limit - used, limit: limit)
    }

    private static func moneyOfRemaining(_ window: LimitWindow, showUsed: Bool) -> WindowDetail? {
        guard let remaining = window.remaining, let limit = window.limit, limit > 0 else { return nil }
        return .moneyPair(shown: showUsed ? max(0, limit - remaining) : remaining, limit: limit, currency: window.currency ?? "USD")
    }

    private static func moneyOfUsed(_ window: LimitWindow, showUsed: Bool) -> WindowDetail? {
        guard let used = window.used, let limit = window.limit, limit > 0 else { return nil }
        return .moneyPair(shown: showUsed ? used : max(0, limit - used), limit: limit, currency: window.currency ?? "USD")
    }
}

// MARK: - Balances (balanceDisplay.js)

extension LimitPresentation {
    /// `spendWindow`: the spend meter, or an older Hub's metric-less
    /// "Usage credits" billing window.
    public static func spendWindow(_ provider: LimitProvider) -> LimitWindow? {
        provider.windows.first(where: \.isSpend) ?? provider.windows.first(where: isLegacySpendWindow)
    }

    /// `creditsAmount`: the window's `remaining`, else the provider balance.
    public static func creditsAmount(_ provider: LimitProvider, window: LimitWindow?) -> Double? {
        finite(window?.remaining) ?? finite(provider.balance?.amount)
    }

    /// `creditsCurrency`: the window's code, else the balance's, else USD.
    public static func creditsCurrency(_ provider: LimitProvider, window: LimitWindow?) -> String {
        if let code = window?.currency, !code.isEmpty { return BalanceFormat.normalizeCode(code) }
        return BalanceFormat.normalizeCode(provider.balance?.currency)
    }

    /// `creditsMeterPercent`: the window's own percentage when it has one,
    /// else the balance against this month's inferred starting funds,
    /// `funds / (funds + monthSpend)`; 0 when nothing is left. Display-only.
    public static func creditsMeterPercent(_ provider: LimitProvider, window: LimitWindow?) -> Double? {
        if let used = finite(window?.usedPercent) { return clampPercent(100 - used) }
        if let remaining = finite(window?.remainingPercent) { return clampPercent(remaining) }
        guard let amount = creditsAmount(provider, window: window) else { return nil }
        let funds = max(0, amount)
        if funds == 0 { return 0 }
        let spend = max(0, finite(provider.balance?.monthSpend) ?? 0)
        return clampPercent(funds / (funds + spend) * 100)
    }

    static func isLegacySpendWindow(_ window: LimitWindow) -> Bool {
        window.metric == nil && window.kind == .billing && window.label == "Usage credits"
    }
}

// MARK: - Plan cell

/// The adapter-named plan of a third-party relay row (`thirdPartyGroupPlanText`).
public enum LimitThirdPartyPlan: String, Sendable, Hashable, CaseIterable {
    /// "New API · Account"
    case newAPIAccount
    /// "New API · API key"
    case newAPIKey
    /// "Sub2API · Account"
    case sub2APIAccount
    /// "Custom"
    case custom
    /// "Account"
    case account
    /// "API key"
    case apiKey

    public var desktopText: String {
        switch self {
        case .newAPIAccount: return "New API · Account"
        case .newAPIKey: return "New API · API key"
        case .sub2APIAccount: return "Sub2API · Account"
        case .custom: return "Custom"
        case .account: return "Account"
        case .apiKey: return "API key"
        }
    }
}

/// The right-hand cell of a provider row's header (`limitProviderPlan`,
/// `limitAccountPlan`).
public enum LimitPlanCell: Sendable, Hashable {
    case none
    /// A row that is not healthy shows its status chip's wording instead.
    case status(LimitStatusLabel)
    /// The plan as the provider names it (already display-cleaned).
    case plan(String)
    case thirdParty(LimitThirdPartyPlan)

    public var desktopText: String {
        switch self {
        case .none: return ""
        case .status(let label): return label.desktopText
        case .plan(let text): return text
        case .thirdParty(let plan): return plan.desktopText
        }
    }
}

extension LimitPresentation {
    /// MiMo's product names, kept in `accountLabel` (`windowLabels.js`).
    static let mimoProducts: Set<String> = ["Console", "Desktop Membership", "Membership"]

    /// `mimoProductLabel`: the MiMo product a row stands for, nil otherwise.
    public static func mimoProduct(_ provider: LimitProvider) -> String? {
        guard normalizedID(provider.provider) == "mimo" else { return nil }
        let label = LimitUsageItems.jsTrim(provider.accountLabel ?? "")
        return mimoProducts.contains(label) ? label : nil
    }

    /// `limitProviderPlanDisplayLabel`: trimmed, first ASCII letter
    /// capitalised unless it is an address; Z.ai drops "GLM Coding " and Zed
    /// drops "Zed " (the heading already says so).
    public static func planDisplayLabel(provider: String, label: String) -> String {
        var text = LimitUsageItems.jsTrim(label)
        var scalars = text.unicodeScalars
        if !text.contains("@"), let first = scalars.first, first.value >= 0x61, first.value <= 0x7A {
            scalars.removeFirst()
            text = first.properties.uppercaseMapping + String(scalars)
        }
        switch normalizedID(provider) {
        case "zai": return strippedPrefix(text, pattern: #"^GLM\s+Coding\s+"#)
        case "zed": return strippedPrefix(text, pattern: #"^Zed\s+"#)
        default: return text
        }
    }

    /// The plan text of a row (`limitProviderPlan` without its status
    /// branches): MiMo product rows use the explicit plan only; Cursor never
    /// shows an address; everything else the plan or the legacy account
    /// label. Nil when there is none.
    public static func planLabel(_ provider: LimitProvider) -> String? {
        let plan = LimitUsageItems.jsTrim(provider.explicitPlanLabel ?? "")
        if mimoProduct(provider) != nil {
            return plan.isEmpty ? nil : nonEmpty(planDisplayLabel(provider: provider.provider, label: plan))
        }
        var legacy = LimitUsageItems.jsTrim(provider.accountLabel ?? "")
        if normalizedID(provider.provider) == "cursor", plan.isEmpty {
            let email = LimitUsageItems.jsTrim(provider.accountEmail ?? "")
            if (!email.isEmpty && legacy.lowercased() == email.lowercased()) || looksLikeEmail(legacy) { legacy = "" }
        }
        let label = plan.isEmpty ? legacy : plan
        return label.isEmpty ? nil : nonEmpty(planDisplayLabel(provider: provider.provider, label: label))
    }

    /// The header's plan cell (`limitAccountPlan(provider, {grouped})`): the
    /// provider's row policy first (third-party adapters name the plan; a
    /// grouped Volcengine, OpenCode or OpenRouter row clears a cell that
    /// would repeat its title), then `limitProviderPlan` — the status for a
    /// row that is not healthy and not stale, else the plan, else the status
    /// of a stale row that is not `ok`.
    ///
    /// The status uses the Settings-tag vocabulary (D-STATUSWORDING), where
    /// the desktop Limits page has its own English-only words.
    public static func planCell(_ provider: LimitProvider, grouped: Bool = false) -> LimitPlanCell {
        let id = normalizedID(provider.provider)
        let healthyOrStale = provider.status == .ok || provider.isStale
        let explicitPlan = LimitUsageItems.jsTrim(provider.explicitPlanLabel ?? "")
        switch id {
        case "thirdparty":
            if let plan = thirdPartyPlan(provider) { return .thirdParty(plan) }
        case "volcengine":
            if grouped && provider.status == .ok { return .none }
        case "opencode":
            if grouped && healthyOrStale && explicitPlan.isEmpty && isLegacyOpencodeProfileLabel(provider) { return .none }
        case "openrouter":
            let name = LimitUsageItems.jsTrim(provider.accountName ?? "")
            if grouped && healthyOrStale && explicitPlan.isEmpty && !name.isEmpty
                && name == LimitUsageItems.jsTrim(provider.accountLabel ?? "") {
                return .none
            }
        default:
            break
        }
        if provider.status != .ok && !provider.isStale { return .status(statusChip(provider).label) }
        if let plan = planLabel(provider) { return .plan(plan) }
        if provider.status != .ok { return .status(statusChip(provider, ignoringStale: true).label) }
        return .none
    }

    /// `thirdPartyGroupPlanText`: healthy relay rows are named by the adapter
    /// the user picked.
    public static func thirdPartyPlan(_ provider: LimitProvider) -> LimitThirdPartyPlan? {
        guard provider.status == .ok else { return nil }
        switch normalizedID(provider.adapterId ?? "") {
        case "newapi-account": return .newAPIAccount
        case "newapi-token": return .newAPIKey
        case "sub2api": return .sub2APIAccount
        case "custom": return .custom
        default: break
        }
        switch (provider.explicitPlanLabel ?? "").lowercased() {
        case "account": return .account
        case "api key": return .apiKey
        case "custom": return .custom
        default: return nil
        }
    }

    /// `thirdPartyAdapterVisual(...).markId`: the mark a relay row wears.
    public static func iconID(_ provider: LimitProvider) -> String {
        let id = normalizedID(provider.provider)
        guard id == "thirdparty" else { return id }
        switch normalizedID(provider.adapterId ?? "") {
        case "newapi-account", "newapi-token": return "newapi"
        case "sub2api": return "sub2api"
        default: return "thirdparty"
        }
    }

    /// `legacyOpencodeProfileLabel`.
    static func isLegacyOpencodeProfileLabel(_ provider: LimitProvider) -> Bool {
        let label = LimitUsageItems.jsTrim(provider.accountLabel ?? "")
        return LimitUsageItems.jsTrim(provider.accountName ?? "").isEmpty && !label.isEmpty && label != "Go" && label != "Zen"
    }

    private static func strippedPrefix(_ text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let stripped = LimitUsageItems.jsTrim(regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: ""))
        return stripped.isEmpty ? text : stripped
    }

    /// `/^[^\s@]+@[^\s@]+$/`.
    private static func looksLikeEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty && !value.contains(where: \.isWhitespace)
    }
}

// MARK: - Source, meta line and provenance

/// Where a reading came from (`limitProviderSourceLabel`): protocol and
/// product terms the desktop shows untranslated.
public enum LimitSourceKind: String, Sendable, Hashable, CaseIterable {
    case oauth
    case cli
    case web
    case rpc
    case local
    case api
    /// Codex RPC through the desktop app.
    case app
    /// A Codex account managed inside Token Monitor.
    case managed
    /// Volcengine's `arkcli`.
    case arkcli

    public var desktopText: String {
        switch self {
        case .oauth: return "OAuth"
        case .cli: return "CLI"
        case .web: return "Web"
        case .rpc: return "RPC"
        case .local: return "Local"
        case .api: return "API"
        case .app: return "App"
        case .managed: return "Managed"
        case .arkcli: return "arkcli"
        }
    }
}

extension LimitPresentation {
    private static let providerSources: [String: [String: LimitSourceKind]] = [
        "claude": ["oauth": .oauth, "cli": .cli, "web": .web],
        "codex": ["rpc": .rpc],
        "opencode": ["local": .local, "web": .web, "api": .api],
        "cursor": ["web": .web],
        "antigravity": ["oauth": .oauth, "rpc": .rpc],
        "factory": ["api": .api],
        "kimi": ["api": .api, "web": .web],
        "grok": ["rpc": .cli, "web": .web],
        "copilot": ["api": .api],
        "zed": ["web": .web],
        "commandcode": ["web": .web],
        "mimo": ["web": .web],
        "zai": ["api": .api],
        "zaiteam": ["api": .api],
        "kiro": ["cli": .cli],
        "workbuddy": ["local": .local, "api": .api],
        "qoder": ["web": .web],
        "deepseek": ["api": .api],
        "devin": ["web": .web],
        "minimax": ["api": .api],
        "openrouter": ["api": .api],
        "volcengine": ["api": .api, "cli": .arkcli],
        "ollama": ["web": .web],
        "trae": ["api": .web],
        "alibaba": ["web": .web],
        "stepfun": ["web": .web],
        "thirdparty": ["api": .api]
    ]
    private static let codexRPCDetails: [String: LimitSourceKind] = ["app": .app, "cli": .cli, "managed": .managed, "unknown": .rpc]

    /// `limitProviderSourceLabel`, with the generic source names as fallback.
    public static func sourceKind(_ provider: LimitProvider) -> LimitSourceKind? {
        let id = normalizedID(provider.provider)
        let source = normalizedID(provider.source ?? "")
        if id == "codex", source == "rpc", let detail = codexRPCDetails[normalizedID(provider.sourceDetail ?? "")] {
            return detail
        }
        return providerSources[id]?[source] ?? LimitSourceKind(rawValue: source)
    }

    /// The meta line shows only for a healthy or stale reading
    /// (`limitProviderMeta` is called for `status === 'ok' || stale`).
    public static func showsMetaLine(_ provider: LimitProvider) -> Bool {
        provider.status == .ok || provider.isStale
    }

    /// Which Hub device a reading came from ("From {device}").
    public struct Provenance: Sendable, Hashable {
        /// The winning device (`sourceDeviceId`).
        public var deviceID: String
        /// The device's Devices-view name, when the Hub lists it. The desktop
        /// prints the device id (`deviceLabel`); targets may prefer this.
        public var deviceName: String?
        public var source: LimitSourceKind?

        public init(deviceID: String, deviceName: String? = nil, source: LimitSourceKind? = nil) {
            self.deviceID = deviceID
            self.deviceName = deviceName
            self.source = source
        }
    }

    /// The device and source behind a row, nil when the Hub named no device.
    /// The phone is never the reading device, so every source device counts
    /// as remote (the desktop shows it only when the record is not its own).
    public static func provenance(_ provider: LimitProvider, devices: [DeviceSummary]) -> Provenance? {
        let id = LimitUsageItems.jsTrim(provider.sourceDeviceId ?? "")
        guard !id.isEmpty else { return nil }
        let device = devices.first { $0.id == id }
        return Provenance(deviceID: id, deviceName: device?.displayName, source: sourceKind(provider))
    }

    /// The line under a provider's name (`limitProviderMeta`): freshness,
    /// then — with `showLimitSource` — the source (healthy rows only) and the
    /// device the reading came from.
    public struct MetaLine: Sendable, Hashable {
        public var freshness: Freshness
        public var source: LimitSourceKind?
        public var provenance: Provenance?

        public init(freshness: Freshness, source: LimitSourceKind? = nil, provenance: Provenance? = nil) {
            self.freshness = freshness
            self.source = source
            self.provenance = provenance
        }

        public var desktopText: String {
            var parts = [freshness.desktopText]
            if let source { parts.append(source.desktopText) }
            if let provenance { parts.append(provenance.deviceID) }
            return parts.joined(separator: " · ")
        }
    }

    /// The meta line, nil when `showsMetaLine` is false.
    public static func metaLine(_ provider: LimitProvider, now: Date, showSource: Bool, devices: [DeviceSummary] = []) -> MetaLine? {
        guard showsMetaLine(provider) else { return nil }
        let device = showSource ? provenance(provider, devices: devices) : nil
        if provider.isStale { return MetaLine(freshness: freshness(provider, now: now), provenance: device) }
        return MetaLine(
            freshness: freshness(provider, now: now),
            source: showSource ? sourceKind(provider) : nil,
            provenance: device
        )
    }
}

// MARK: - Account titles (accountIdentity.js)

/// The title of one account row. Parts join with " · ".
public struct LimitAccountTitle: Sendable, Hashable {
    public enum Part: Sendable, Hashable {
        /// Account data shown as is: an address (masked when asked), a
        /// profile or workspace name, a MiMo product.
        case text(String)
        /// Codex's personal workspace, which has no name ("Personal").
        case personalWorkspace
        /// A key-based relay profile read from the environment
        /// (`settings.<provider>.environment`).
        case environment
        /// "Account {n}" (1-based) when nothing names the account.
        case accountNumber(Int)
        /// "#3f9a2c": what tells otherwise identical titles apart.
        case disambiguator(String)
    }

    public var parts: [Part]

    public init(parts: [Part]) {
        self.parts = parts
    }

    /// Only the "Account {n}" fallback: nothing names the account.
    public var isFallback: Bool {
        if parts.count == 1, case .accountNumber = parts[0] { return true }
        return false
    }

    public var desktopText: String {
        parts.map { part -> String in
            switch part {
            case .text(let text): return text
            case .personalWorkspace: return "Personal"
            case .environment: return "Environment"
            case .accountNumber(let number): return "Account \(number)"
            case .disambiguator(let value): return "#\(value)"
            }
        }.joined(separator: " · ")
    }
}

extension LimitPresentation {
    /// `maskEmailAddress`: `d***v@example.com`; anything that is not an
    /// address (no local part or no domain) unchanged.
    public static func maskedEmail(_ value: String) -> String {
        let email = LimitUsageItems.jsTrim(value)
        guard let at = email.lastIndex(of: "@"), at != email.startIndex, email.index(after: at) != email.endIndex else {
            return email
        }
        let local = email[..<at]
        let domain = email[email.index(after: at)...]
        let first = local.first.map(String.init) ?? ""
        let last = local.count > 1 ? (local.last.map(String.init) ?? "") : ""
        return "\(first)***\(last)@\(domain)"
    }

    /// The title of `provider`, the account at `index` among `peers` (every row
    /// of its provider, in Hub order), `limitAccountTitle`: Codex by address and
    /// workspace, OpenCode by profile, relays by profile name, Volcengine by
    /// plan, MiMo by address and product, everyone else by address or name.
    /// Repeated titles get a short fingerprint ("· #3f9a2c") and, failing
    /// that, the row number; nothing at all gives "Account {n}". `mask` is
    /// the display-only `maskLimitAccountEmails` setting.
    ///
    /// The fingerprint is derived from the Kit's hashed row id, because the
    /// raw account key never reaches the app; it differs from the desktop's
    /// but is just as stable.
    public static func accountTitle(_ provider: LimitProvider, peers: [LimitProvider], index: Int, mask: Bool) -> LimitAccountTitle {
        let peers = peers.isEmpty ? [provider] : peers
        let fallback = LimitAccountTitle(parts: [.accountNumber(index + 1)])
        let trimmedName = LimitUsageItems.jsTrim(provider.accountName ?? "")
        switch normalizedID(provider.provider) {
        case "codex":
            let title = uniqueTitle(provider, peers: peers, index: index) { codexBaseTitle($0, peers: peers, mask: mask) }
            return title.isEmpty ? fallback : LimitAccountTitle(parts: title)
        case "opencode":
            if !trimmedName.isEmpty { return LimitAccountTitle(parts: [.text(trimmedName)]) }
            let legacy = LimitUsageItems.jsTrim(provider.accountLabel ?? "")
            return !legacy.isEmpty && legacy != "Go" && legacy != "Zen" ? LimitAccountTitle(parts: [.text(legacy)]) : fallback
        case "openrouter", "thirdparty":
            let name = LimitUsageItems.jsTrim(provider.accountName ?? provider.accountLabel ?? "")
            if name.lowercased() == "environment" { return LimitAccountTitle(parts: [.environment]) }
            return name.isEmpty ? fallback : LimitAccountTitle(parts: [.text(name)])
        case "volcengine":
            let label = LimitUsageItems.jsTrim(provider.accountLabel ?? "")
            if !label.isEmpty { return LimitAccountTitle(parts: [.text(label)]) }
            return defaultTitle(provider, peers: peers, index: index, mask: mask)
        case "mimo":
            if let product = mimoProduct(provider) {
                let identity = emailLabel(provider, peers: peers, mask: mask, suffix: trimmedName)
                    ?? (trimmedName.isEmpty ? [] : [.text(trimmedName)])
                return LimitAccountTitle(parts: identity + [.text(product)])
            }
            // Rows from versions that put the product in accountName.
            var renamed = peers
            for position in renamed.indices {
                let name = LimitUsageItems.jsTrim(renamed[position].accountName ?? "")
                renamed[position].accountName = name.isEmpty ? LimitUsageItems.jsTrim(renamed[position].accountLabel ?? "") : name
            }
            let subject = renamed.indices.contains(index) ? renamed[index] : provider
            return defaultTitle(subject, peers: renamed, index: index, mask: mask)
        default:
            return defaultTitle(provider, peers: peers, index: index, mask: mask)
        }
    }

    /// The plan's single-account form: the title when the account has one,
    /// nil for the "Account 1" fallback.
    public static func accountTitle(_ provider: LimitProvider, mask: Bool) -> String? {
        let title = accountTitle(provider, peers: [provider], index: 0, mask: mask)
        return title.isFallback ? nil : title.desktopText
    }

    /// `accountTitleLabel` with the "Account {n}" fallback.
    private static func defaultTitle(_ provider: LimitProvider, peers: [LimitProvider], index: Int, mask: Bool) -> LimitAccountTitle {
        let parts = uniqueTitle(provider, peers: peers, index: index) { peer in
            let name = LimitUsageItems.jsTrim(peer.accountName ?? "")
            return emailLabel(peer, peers: peers, mask: mask, suffix: name) ?? (name.isEmpty ? [] : [.text(name)])
        }
        return parts.isEmpty ? LimitAccountTitle(parts: [.accountNumber(index + 1)]) : LimitAccountTitle(parts: parts)
    }

    /// `codexAccountBaseDisplayLabel`.
    private static func codexBaseTitle(_ account: LimitProvider, peers: [LimitProvider], mask: Bool) -> [LimitAccountTitle.Part] {
        let name = LimitUsageItems.jsTrim(account.accountName ?? "")
        let workspace: [LimitAccountTitle.Part]
        if !name.isEmpty {
            workspace = [.text(name)]
        } else if account.workspaceKind == "personal" {
            workspace = [.personalWorkspace]
        } else {
            workspace = []
        }
        return emailLabel(account, peers: peers, mask: mask, suffixParts: workspace) ?? workspace
    }

    /// `accountEmailLabel`: the visible address, with `suffix` appended when
    /// another peer's visible address is the same; nil without an address.
    private static func emailLabel(_ account: LimitProvider, peers: [LimitProvider], mask: Bool, suffix: String) -> [LimitAccountTitle.Part]? {
        emailLabel(account, peers: peers, mask: mask, suffixParts: suffix.isEmpty ? [] : [.text(suffix)])
    }

    private static func emailLabel(
        _ account: LimitProvider,
        peers: [LimitProvider],
        mask: Bool,
        suffixParts: [LimitAccountTitle.Part]
    ) -> [LimitAccountTitle.Part]? {
        let email = LimitUsageItems.jsTrim(account.accountEmail ?? "")
        guard !email.isEmpty else { return nil }
        func visible(_ value: String) -> String { mask ? maskedEmail(value) : value }
        let shown = visible(email)
        let collisions = peers.filter { peer in
            let peerEmail = LimitUsageItems.jsTrim(peer.accountEmail ?? "")
            return !peerEmail.isEmpty && visible(peerEmail).lowercased() == shown.lowercased()
        }.count
        if collisions <= 1 { return [.text(shown)] }
        return [.text(shown)] + suffixParts
    }

    /// `uniqueAccountLabel`: the base title, then a fingerprint prefix, then
    /// the row number, whichever first tells the colliding peers apart.
    private static func uniqueTitle(
        _ account: LimitProvider,
        peers: [LimitProvider],
        index: Int,
        base: (LimitProvider) -> [LimitAccountTitle.Part]
    ) -> [LimitAccountTitle.Part] {
        let label = base(account)
        guard !label.isEmpty else { return [] }
        let key = LimitAccountTitle(parts: label).desktopText.lowercased()
        let colliding = peers.filter { LimitAccountTitle(parts: base($0)).desktopText.lowercased() == key }
        if colliding.count <= 1 { return label }
        if let suffix = uniqueFingerprint(account, among: colliding) { return label + [.disambiguator(suffix)] }
        return label + [.disambiguator(String(index + 1))]
    }

    /// `accountUniqueStableSuffix`: the shortest prefix (6 characters or
    /// more) of the account's fingerprint no colliding peer shares.
    private static func uniqueFingerprint(_ account: LimitProvider, among peers: [LimitProvider]) -> String? {
        let print = fingerprint(account)
        guard !print.isEmpty else { return nil }
        let peerPrints = peers.map(fingerprint)
        var length = min(6, print.count)
        while length <= print.count {
            let prefix = String(print.prefix(length))
            if peerPrints.filter({ $0.hasPrefix(prefix) }).count == 1 { return prefix }
            length += 1
        }
        return nil
    }

    /// The hashed account key inside the row id (`<provider>-<hash>[-n]`);
    /// empty for rows without an account key.
    static func fingerprint(_ provider: LimitProvider) -> String {
        let prefix = "\(provider.provider)-"
        guard provider.id.hasPrefix(prefix) else { return "" }
        let rest = provider.id.dropFirst(prefix.count)
        guard !rest.hasPrefix("anonymous") else { return "" }
        return String(rest.split(separator: "-").first ?? "").lowercased()
    }
}

// MARK: - Ordering and visible windows

extension LimitPresentation {
    /// The limits provider ids in catalog order (`LIMIT_PROVIDER_IDS`).
    public static var catalogProviderIDs: [String] { VendorCatalog.limitProviders.map(\.id) }

    /// The Limits page order (`orderedLimitProviders` over
    /// `limitProviderOrder`; `[]` is catalog order). A provider's accounts
    /// stay together in Hub order; providers the catalog does not know (a
    /// newer Hub) follow the known ones instead of disappearing.
    public static func ordered(_ providers: [LimitProvider], order: [String]) -> [LimitProvider] {
        OrderedIDs.ordered(providers, id: { $0.provider }, order: order, known: catalogProviderIDs)
    }

    /// The windows a Limits-page row draws: the user's hidden items removed
    /// (`limitProviderHiddenItems`), Codex's additional pools dropped while
    /// `showCodexAdditionalLimits` is off, and MiMo's token plan synthesized
    /// from the balance when no quota window names it — or its meter-less
    /// "Expired" placeholder once the plan lapsed — before the balance.
    public static func visibleWindows(_ provider: LimitProvider, prefs: DisplayPreferences) -> [LimitWindow] {
        let windows = cardWindows(provider, showCodexAdditional: prefs.showCodexAdditionalLimits)
        let hidden = LimitUsageItems.hiddenSet(prefs.limitProviderHiddenItems, provider: provider.provider)
        guard !hidden.isEmpty else { return windows }
        return windows.filter { !hidden.contains(provider.usageItemID(for: $0)) }
    }

    /// `windows` in the card's order plus MiMo's synthesized plan row,
    /// Codex's additional pools left out unless `showCodexAdditional`.
    static func cardWindows(_ provider: LimitProvider, showCodexAdditional: Bool) -> [LimitWindow] {
        var windows = cardOrder(provider)
        if normalizedID(provider.provider) == "codex" && !showCodexAdditional {
            windows.removeAll(where: \.isAdditional)
        }
        let plan = mimoTokenPlanWindow(provider) ?? (showsExpiredTokenPlan(provider) ? expiredTokenPlanWindow : nil)
        if let plan {
            windows.insert(plan, at: windows.firstIndex(where: \.isCredits) ?? windows.endIndex)
        }
        return windows
    }

    /// The order `renderProviderWindows` draws a provider's windows in: lanes
    /// before monthly pools before balances, with the providers that lay out
    /// differently — OpenRouter's balance first, Alibaba's and StepFun's plan
    /// credit first, Codex's and Factory's additional pools after the
    /// canonical ones, Z.ai's plan buckets before its MCP bucket, and
    /// Antigravity's lanes grouped by model. Ties keep the Hub's order. Unlike
    /// the desktop, which leaves out kinds a provider's card has no slot for,
    /// every window is kept.
    public static func cardOrder(_ provider: LimitProvider) -> [LimitWindow] {
        let id = normalizedID(provider.provider)
        let groups = antigravityGroups(provider)
        func kindRank(_ kind: LimitWindowKind) -> Int {
            switch kind {
            case .session: return 0
            case .daily: return 1
            case .weekly: return 2
            case .billing: return 3
            }
        }
        func rank(_ window: LimitWindow) -> Int {
            if id == "antigravity", !groups.isEmpty, let lane = antigravityLane(window),
               let group = groups.firstIndex(where: { $0.name == lane.group }) {
                return group
            }
            if window.isCredits { return id == "openrouter" ? -1 : 100 }
            switch id {
            case "codex", "factory":
                let pool = window.isAdditional ? 10 : 0
                return pool + (id == "factory" && window.kind == .billing ? 5 : kindRank(window.kind))
            case "alibaba", "stepfun":
                return window.kind == .billing ? -1 : kindRank(window.kind)
            case "zai", "zaiteam":
                if window.kind == .billing { return window.limitId != nil && window.metric == nil ? 3 : 4 }
                return kindRank(window.kind)
            default:
                return kindRank(window.kind)
            }
        }
        return provider.windows.enumerated().sorted { left, right in
            let leftRank = rank(left.element)
            let rightRank = rank(right.element)
            return leftRank != rightRank ? leftRank < rightRank : left.offset < right.offset
        }.map(\.element)
    }

    /// The row MiMo draws for a lapsed token plan: no meter, value "Expired".
    static let expiredTokenPlanWindow = LimitWindow(kind: .billing, label: "Token Plan", showMeter: false)

    /// Whether `window` is MiMo's lapsed-plan row on `provider`.
    public static func isExpiredTokenPlan(_ window: LimitWindow, provider: LimitProvider) -> Bool {
        showsExpiredTokenPlan(provider) && window.kind == .billing && !window.showMeter
            && window.metric == nil && window.label == "Token Plan"
    }

    /// MiMo's "Token Plan" quota built from `balance.plan*`
    /// (`mimoTokenPlanWindowFromBalance`) when no quota window carries a label
    /// and the plan has not expired; nil otherwise and for other providers.
    public static func mimoTokenPlanWindow(_ provider: LimitProvider) -> LimitWindow? {
        guard normalizedID(provider.provider) == "mimo" else { return nil }
        let quotaWindows = provider.windows.filter { !$0.isCredits }
        guard !quotaWindows.contains(where: { !LimitUsageItems.jsTrim($0.label ?? "").isEmpty }) else { return nil }
        return tokenPlanWindow(provider.balance, includeAmounts: true)
    }

    /// Whether a MiMo row's token plan has lapsed (`planStatus: expired`) and
    /// no labelled quota window replaces it: the "Token Plan · Expired" row.
    public static func showsExpiredTokenPlan(_ provider: LimitProvider) -> Bool {
        guard normalizedID(provider.provider) == "mimo", provider.balance?.planStatus == .expired else { return false }
        return !provider.windows.contains { !$0.isCredits && !LimitUsageItems.jsTrim($0.label ?? "").isEmpty }
    }

    static func tokenPlanWindow(_ balance: LimitBalance?, includeAmounts: Bool) -> LimitWindow? {
        guard let balance, balance.planStatus != .expired else { return nil }
        let used = finite(balance.planUsed)
        let limit = finite(balance.planLimit)
        let percent = finite(balance.planPercent)
        guard used != nil || limit != nil || percent != nil else { return nil }
        var usedPercent: Double?
        if let percent {
            usedPercent = clampPercent(percent)
        } else if let used, let limit, limit > 0 {
            usedPercent = clampPercent(used / limit * 100)
        }
        var remaining: Double?
        if includeAmounts, let used, let limit { remaining = max(0, limit - used) }
        return LimitWindow(
            kind: .billing,
            label: "Token Plan",
            usedPercent: usedPercent,
            remainingPercent: usedPercent.map { clampPercent(100 - $0) },
            used: includeAmounts ? used : nil,
            limit: includeAmounts ? limit : nil,
            remaining: remaining,
            showMeter: true
        )
    }

    /// `codexAdditionalQuotaDisplayName`: the reserve pool's product name.
    public static func codexAdditionalDisplayName(_ label: String) -> String {
        let name = LimitUsageItems.jsTrim(label)
        return name.lowercased() == "gpt-reserve" ? "Luna Reserve" : name
    }
}

// MARK: - Window names

/// A pool's cadence (`codexAdditionalWindowPeriodLabel`).
public enum LimitPeriodName: Sendable, Hashable {
    /// Session, 5-hour, Daily, Weekly or Monthly.
    case named(LimitWindowKindName)
    /// "{n}-hour"
    case hours(Int)
    /// "{n}-day"
    case days(Int)
    /// "{n}-week"
    case weeks(Int)
    /// "{n}-minute"
    case minutes(Int)

    public var desktopText: String {
        switch self {
        case .named(let name): return name.desktopText
        case .hours(let value): return "\(value)-hour"
        case .days(let value): return "\(value)-day"
        case .weeks(let value): return "\(value)-week"
        case .minutes(let value): return "\(value)-minute"
        }
    }

    /// The cadence of a window: its `windowMinutes` when whole and positive,
    /// else its kind.
    public static func of(_ window: LimitWindow) -> LimitPeriodName {
        if let minutes = window.windowMinutes, minutes.isFinite, minutes > 0, minutes == minutes.rounded(), minutes < 1e15 {
            let value = Int(minutes)
            if value == 30 * 24 * 60 { return .named(.monthly) }
            if value == 5 * 60 { return .named(.fiveHour) }
            if value % (7 * 24 * 60) == 0 {
                let weeks = value / (7 * 24 * 60)
                return weeks == 1 ? .named(.weekly) : .weeks(weeks)
            }
            if value % (24 * 60) == 0 {
                let days = value / (24 * 60)
                return days == 1 ? .named(.daily) : .days(days)
            }
            if value % 60 == 0 { return .hours(value / 60) }
            return .minutes(value)
        }
        switch window.kind {
        case .daily: return .named(.daily)
        case .weekly: return .named(.weekly)
        case .billing: return .named(.monthly)
        case .session: return .named(.session)
        }
    }
}

/// What a Limits-page window row is called.
public enum LimitWindowName: Sendable, Hashable {
    /// The usual name (`windowLabels.js`).
    case title(LimitWindowTitle)
    /// A Codex additional pool, by product name, with its cadence when two
    /// pools share the name ("GPT-5.3-Codex-Spark · 5-hour").
    case pool(name: String, period: LimitPeriodName?)
    /// An Antigravity model group's lane ("Gemini Pro" › "5-hour").
    case group(name: String, period: LimitWindowKindName)
    /// An unnamed additional pool without a cadence ("Additional limit").
    case additionalLimit

    public var desktopText: String {
        switch self {
        case .title(let title): return title.desktopText
        case let .pool(name, period?): return "\(name) · \(period.desktopText)"
        case let .pool(name, nil): return name
        case let .group(name, period): return "\(name) · \(period.desktopText)"
        case .additionalLimit: return "Additional limit"
        }
    }

    /// The same name as a checklist label.
    public var usageItemLabel: LimitUsageItemLabel {
        switch self {
        case .title(let title): return .window(title)
        case let .pool(name, nil): return .window(.label(name))
        case let .pool(name, period?):
            if case .named(let kindName) = period { return .additional(limitID: name, title: .kind(kindName)) }
            return .additional(limitID: name, title: .label(period.desktopText))
        case let .group(name, period): return .additional(limitID: name, title: .kind(period))
        case .additionalLimit: return .window(.label("Additional limit"))
        }
    }
}

extension LimitPresentation {
    /// An Antigravity model group and its lanes (`antigravityQuotaGroups`).
    public struct AntigravityGroup: Sendable, Equatable {
        public var name: String
        public var windows: [LimitWindow]
    }

    /// Antigravity's windows grouped by model group, in first-seen order;
    /// empty for legacy pools (any session/weekly window without a
    /// "<group> 5-hour" / "<group> Weekly" label) and other providers.
    public static func antigravityGroups(_ provider: LimitProvider) -> [AntigravityGroup] {
        guard normalizedID(provider.provider) == "antigravity" else { return [] }
        let lanes = provider.windows.filter { $0.kind == .session || $0.kind == .weekly }
        var groups: [AntigravityGroup] = []
        for window in lanes {
            guard let lane = antigravityLane(window) else { return [] }
            if let index = groups.firstIndex(where: { $0.name == lane.group }) {
                groups[index].windows.append(window)
            } else {
                groups.append(AntigravityGroup(name: lane.group, windows: [window]))
            }
        }
        return groups
    }

    /// The name of `window` on `provider`'s Limits row.
    public static func windowName(_ window: LimitWindow, provider: LimitProvider) -> LimitWindowName {
        let id = normalizedID(provider.provider)
        if id == "codex", window.isAdditional {
            let name = LimitUsageItems.jsTrim(window.label ?? "")
            let period = LimitPeriodName.of(window)
            guard !name.isEmpty else { return .title(LimitWindowTitle.of(window, provider: provider.provider)) }
            let siblings = provider.windows.filter { $0.isAdditional && LimitUsageItems.jsTrim($0.label ?? "").lowercased() == name.lowercased() }
            return .pool(name: codexAdditionalDisplayName(name), period: siblings.count > 1 ? period : nil)
        }
        if id == "antigravity", let lane = antigravityLane(window), !antigravityGroups(provider).isEmpty {
            return .group(name: lane.group, period: lane.period)
        }
        return .title(LimitWindowTitle.of(window, provider: provider.provider))
    }

    /// `antigravityQuotaWindow`: "<group> 5-hour" sessions and "<group>
    /// Weekly" weeklies.
    static func antigravityLane(_ window: LimitWindow) -> (group: String, period: LimitWindowKindName)? {
        let label = LimitUsageItems.jsTrim(window.label ?? "")
        let suffix: String
        let period: LimitWindowKindName
        switch window.kind {
        case .session: suffix = "5-hour"; period = .fiveHour
        case .weekly: suffix = "weekly"; period = .weekly
        default: return nil
        }
        guard label.count > suffix.count, label.lowercased().hasSuffix(suffix) else { return nil }
        let head = label.dropLast(suffix.count)
        guard let last = head.unicodeScalars.last, isJSWhitespace(last) else { return nil }
        let group = LimitUsageItems.jsTrim(String(head))
        return group.isEmpty ? nil : (group, period)
    }
}

// MARK: - Compact windows (Home, widgets)

extension LimitPresentation {
    /// `limitProviderCompactWindows`: Codex keeps its canonical lanes;
    /// Antigravity keeps, per model group, the session lane (or the weekly one
    /// once it runs lower and is critical, under 20%), then the two tightest
    /// groups in group order; everyone else keeps every window.
    public static func compactWindows(_ provider: LimitProvider, windows: [LimitWindow]) -> [LimitWindow] {
        switch normalizedID(provider.provider) {
        case "codex":
            return windows.filter { !$0.isAdditional }
        case "antigravity":
            return antigravityCompact(windows)
        default:
            return windows
        }
    }

    /// Zed's unlimited edit predictions read "Unlimited" on compact surfaces
    /// and drop their reset line.
    static func isUnlimitedValue(_ window: LimitWindow, provider: String) -> Bool {
        normalizedID(provider) == "zed" && window.limitId == "zed.edit-predictions" && window.isUnlimited
    }

    private static func antigravityCompact(_ windows: [LimitWindow]) -> [LimitWindow] {
        struct Entry {
            let window: LimitWindow
            let index: Int
            let group: String
        }
        var entries: [Entry] = []
        for (index, window) in windows.enumerated() {
            guard let lane = antigravityLane(window) else { return windows }
            entries.append(Entry(window: window, index: index, group: lane.group))
        }
        guard !entries.isEmpty else { return windows }
        var groupOrder: [String] = []
        for entry in entries where !groupOrder.contains(entry.group) { groupOrder.append(entry.group) }
        func tightest(_ candidates: [Entry]) -> Entry? {
            candidates.min { left, right in
                let leftRemaining = compactRemaining(left.window)
                let rightRemaining = compactRemaining(right.window)
                return leftRemaining != rightRemaining ? leftRemaining < rightRemaining : left.index < right.index
            }
        }
        var selected: [(entry: Entry, groupIndex: Int, remaining: Double)] = []
        for (groupIndex, group) in groupOrder.enumerated() {
            let members = entries.filter { $0.group == group }
            let session = tightest(members.filter { $0.window.kind == .session })
            let weekly = tightest(members.filter { $0.window.kind == .weekly })
            let sessionRemaining = session.map { compactRemaining($0.window) } ?? .infinity
            let weeklyRemaining = weekly.map { compactRemaining($0.window) } ?? .infinity
            let chosen: Entry?
            if session == nil {
                chosen = weekly
            } else if weekly == nil {
                chosen = session
            } else if weeklyRemaining < sessionRemaining && (weeklyRemaining < criticalPercent || !sessionRemaining.isFinite) {
                chosen = weekly
            } else {
                chosen = session
            }
            if let chosen { selected.append((chosen, groupIndex, compactRemaining(chosen.window))) }
        }
        let tightestTwo = selected.sorted { left, right in
            left.remaining != right.remaining ? left.remaining < right.remaining : left.groupIndex < right.groupIndex
        }.prefix(2)
        return tightestTwo.sorted { $0.groupIndex < $1.groupIndex }.map(\.entry.window)
    }

    /// `compactWindowRemaining`: what is left, clamped; +∞ without a percentage.
    static func compactRemaining(_ window: LimitWindow) -> Double {
        if let remaining = finite(window.remainingPercent) { return clampPercent(remaining) }
        if let used = finite(window.usedPercent) { return clampPercent(100 - used) }
        return .infinity
    }

    /// `COMPACT_LIMIT_CRITICAL_PERCENT`.
    public static let criticalPercent: Double = 20
}

// MARK: - Home limits module

extension LimitPresentation {
    /// How the Home module orders accounts: least remaining first, or the
    /// user's provider order (`homeLimitAccounts` `sort`).
    public enum HomeLimitSort: String, Sendable, Hashable {
        case remaining
        case configured
    }

    /// A Home window's name (`homeLimitWindowLabel`).
    public enum HomeLimitWindowLabel: Sendable, Hashable {
        /// Provider text: an Antigravity group, a Z.ai daily pool, a billing
        /// window's own label.
        case text(String)
        /// `home.limit.<kind>`: Session, Daily, Weekly or Billing.
        case kind(LimitWindowKind)

        public var desktopText: String {
            switch self {
            case .text(let text): return text
            case .kind(let kind):
                switch kind {
                case .session: return "Session"
                case .daily: return "Daily"
                case .weekly: return "Weekly"
                case .billing: return "Billing"
                }
            }
        }
    }

    /// Low-limit emphasis (`showHomeLimitBars`): always keyed on what is left,
    /// in both text modes.
    public enum HomeSeverity: String, Sendable, Hashable {
        /// Under 20% left: red with a dot.
        case critical
        /// Under 50% left: yellow or the provider accent.
        case low
    }

    /// One window of a Home account (`homeLimitAccounts`' window objects).
    public struct HomeLimitWindow: Sendable, Equatable, Identifiable {
        /// The source window (MiMo's token plan is synthesized).
        public var window: LimitWindow
        /// What is left, 0–100: the window's own percentage, or a balance's
        /// display-only meter. Nil without a meter.
        public var remainingPercent: Double?
        /// A balance's amount (credits windows only).
        public var remaining: Double?
        /// A balance's normalized currency (credits windows only).
        public var currency: String?
        /// MiMo's lapsed plan placeholder.
        public var planExpired: Bool
        /// Zed's unlimited edit predictions.
        public var isUnlimitedValue: Bool
        public var label: HomeLimitWindowLabel
        /// Antigravity's lane under a group label ("5-hour · Reset 2h").
        public var periodLabel: LimitWindowKindName?

        public var id: String { window.id }
        public var kind: LimitWindowKind { window.kind }
        public var metric: LimitWindowMetric? { window.metric }
        public var showMeter: Bool { window.showMeter }
        public var isCredits: Bool { window.isCredits }

        /// The wire label, else the kind (`window.label || window.kind`).
        public var rawLabel: String { window.label ?? window.kind.rawValue }
    }

    /// One Home account before the row decorations
    /// (`homeLimitAccounts` output).
    public struct HomeLimitAccount: Sendable, Equatable {
        public var key: String
        public var providerID: String
        /// The least left over the shown windows (100 for a window without a
        /// percentage).
        public var lowestRemaining: Double
        public var windows: [HomeLimitWindow]
    }

    /// One account fed to `homeAccounts`.
    public struct HomeLimitAccountInput: Sendable, Equatable {
        public var key: String
        public var providerID: String
        public var windows: [LimitWindow]
        public var balance: LimitBalance?
        /// The windows went through `compactWindows`, which gives Zed's
        /// unlimited edit predictions their "Unlimited" value.
        public var isCompact: Bool

        public init(key: String, providerID: String, windows: [LimitWindow], balance: LimitBalance?, isCompact: Bool = false) {
            self.key = key
            self.providerID = providerID
            self.windows = windows
            self.balance = balance
            self.isCompact = isCompact
        }
    }

    /// `homeLimitAccounts(accounts, limit, {sort, isWindowHidden})`: MiMo's
    /// plan synthesized (or replaced by its expired placeholder), hidden
    /// windows dropped, windows without anything to show dropped, the rest by
    /// lane priority (session, daily, weekly, billing; Antigravity keeps its
    /// order) and at most two; accounts with nothing left dropped; then the
    /// least remaining first (or input order) and at most `limit`.
    public static func homeAccounts(
        _ accounts: [HomeLimitAccountInput],
        limit: Int,
        sort: HomeLimitSort = .remaining,
        isWindowHidden: ((String, LimitWindow) -> Bool)? = nil
    ) -> [HomeLimitAccount] {
        let priority: [LimitWindowKind: Int] = [.session: 0, .daily: 1, .weekly: 2, .billing: 3]
        var built: [(account: HomeLimitAccount, index: Int)] = []
        for (index, account) in accounts.enumerated() {
            let providerID = normalizedID(account.providerID)
            let shell = LimitProvider(id: account.key, provider: providerID, windows: account.windows, balance: account.balance)
            var windows: [(window: HomeLimitWindow, index: Int)] = []
            for (windowIndex, entry) in homeSourceWindows(account, providerID: providerID).enumerated() {
                if let isWindowHidden, isWindowHidden(providerID, entry.window) { continue }
                let window = entry.window
                let credits = window.isCredits
                let home = HomeLimitWindow(
                    window: window,
                    remainingPercent: credits ? creditsMeterPercent(shell, window: window) : homeRemainingPercent(window),
                    remaining: credits ? creditsAmount(shell, window: window) : finite(window.remaining),
                    currency: credits ? creditsCurrency(shell, window: window) : nil,
                    planExpired: entry.planExpired,
                    isUnlimitedValue: account.isCompact && isUnlimitedValue(window, provider: providerID),
                    label: .kind(window.kind),
                    periodLabel: nil
                )
                let keep = home.remainingPercent != nil || home.planExpired || home.isUnlimitedValue
                    || (credits && (home.remaining != nil || window.detail != nil))
                if keep { windows.append((home, windowIndex)) }
            }
            if providerID != "antigravity" {
                windows.sort { left, right in
                    let leftPriority = priority[left.window.kind] ?? 10
                    let rightPriority = priority[right.window.kind] ?? 10
                    return leftPriority != rightPriority ? leftPriority < rightPriority : left.index < right.index
                }
            }
            let shown = windows.prefix(2).map(\.window)
            guard !shown.isEmpty else { continue }
            let lowest = shown.map { $0.remainingPercent ?? 100 }.min() ?? 100
            built.append((HomeLimitAccount(key: account.key, providerID: account.providerID, lowestRemaining: lowest, windows: shown), index))
        }
        let sorted = built.sorted { left, right in
            if sort == .configured { return left.index < right.index }
            if left.account.lowestRemaining != right.account.lowestRemaining {
                return left.account.lowestRemaining < right.account.lowestRemaining
            }
            return left.index < right.index
        }
        return sorted.prefix(max(0, limit)).map(\.account)
    }

    /// `homeOverview.remainingPercent(window)`: nil without a meter.
    public static func homeRemainingPercent(_ window: LimitWindow) -> Double? {
        guard window.showMeter else { return nil }
        if let remaining = finite(window.remainingPercent) { return clampPercent(remaining) }
        return finite(window.usedPercent).map { clampPercent(100 - $0) }
    }

    /// `accountWindows`: MiMo's synthesized plan first.
    private static func homeSourceWindows(_ account: HomeLimitAccountInput, providerID: String) -> [(window: LimitWindow, planExpired: Bool)] {
        var windows = account.windows.map { (window: $0, planExpired: false) }
        guard providerID == "mimo" else { return windows }
        let isPlan: (LimitWindow) -> Bool = { $0.kind == .billing && !$0.isCredits }
        if account.balance?.planStatus == .expired {
            windows.removeAll { isPlan($0.window) }
            let placeholder = LimitWindow(kind: .billing, label: "Token Plan", showMeter: false)
            windows.insert((placeholder, true), at: 0)
            return windows
        }
        if !windows.contains(where: { isPlan($0.window) }), let plan = tokenPlanWindow(account.balance, includeAmounts: false) {
            windows.insert((plan, false), at: 0)
        }
        return windows
    }

    /// A Home row's name (the `accountName` callback of `homeLimitRows`).
    public struct HomeLimitRowName: Sendable, Hashable {
        public enum Detail: Sendable, Hashable {
            case account(LimitAccountTitle)
            /// A MiMo product ("Console").
            case product(String)
        }

        /// The provider's name, when the row shows it.
        public var providerName: String?
        public var detail: Detail?

        public init(providerName: String?, detail: Detail?) {
            self.providerName = providerName
            self.detail = detail
        }

        public var desktopText: String {
            let detailText: String?
            switch detail {
            case .account(let title): detailText = title.desktopText
            case .product(let product): detailText = product
            case nil: detailText = nil
            }
            return [providerName, detailText].compactMap { $0 }.joined(separator: " · ")
        }
    }

    /// One account row of the Home limits module.
    public struct HomeLimitRow: Sendable, Equatable, Identifiable {
        /// `<provider>:<index within provider>`.
        public var id: String
        public var providerID: String
        /// The mark to draw (a relay's adapter mark).
        public var iconID: String
        public var name: HomeLimitRowName
        public var plan: LimitPlanCell
        public var lowestRemaining: Double
        public var windows: [HomeLimitWindow]
        /// The account the row stands for.
        public var provider: LimitProvider
    }

    /// The Home order setting as the desktop stores it
    /// (`migrateHomeLimitProviderOrder`): known ids, once each; an order equal
    /// to the catalog order clears to `[]` (least remaining first).
    public static func normalizedHomeProviderOrder(_ order: [String]) -> [String] {
        let parsed = OrderedIDs.normalizeSelection(order, known: catalogProviderIDs)
        return parsed == catalogProviderIDs ? [] : parsed
    }

    /// The order Home lists providers in: its own, else the Limits page's
    /// (`homeLimitProviderOrder || limitProviderOrder`).
    public static func homeProviderOrder(_ prefs: DisplayPreferences) -> [String] {
        let home = normalizedHomeProviderOrder(prefs.homeLimitProviderOrder)
        return home.isEmpty ? prefs.limitProviderOrder : home
    }

    /// Home ranks by least remaining unless the user set a Home order.
    public static func homeSort(_ prefs: DisplayPreferences) -> HomeLimitSort {
        normalizedHomeProviderOrder(prefs.homeLimitProviderOrder).isEmpty ? .remaining : .configured
    }

    /// The Home limits module (`homeLimitRows` → `homeLimitAccountsForProviders`):
    /// providers in the Home order minus `hiddenHomeLimitProviders`, every
    /// account with its visible windows narrowed to the compact pick, then
    /// `homeAccounts` with `homeLimitAccountCount` (1–12). Names show the
    /// provider unless several accounts need telling apart, and always when
    /// `showHomeLimitProviderNames` is on or tool icons are off.
    public static func homeRows(_ providers: [LimitProvider], prefs: DisplayPreferences) -> [HomeLimitRow] {
        let hiddenProviders = Set(prefs.hiddenHomeLimitProviders.map(OrderedIDs.normalizeID))
        let byProvider = Dictionary(grouping: providers) { normalizedID($0.provider) }
        var providerIDs = OrderedIDs.normalizeOrder(homeProviderOrder(prefs), known: catalogProviderIDs)
        for provider in providers {
            let id = normalizedID(provider.provider)
            if !id.isEmpty, !providerIDs.contains(id) { providerIDs.append(id) }
        }
        let showProviderName = prefs.showHomeLimitProviderNames || !prefs.showToolIcons
        let hiddenItems = prefs.limitProviderHiddenItems
        let isHidden: (String, LimitWindow) -> Bool = { provider, window in
            LimitUsageItems.isHidden(window, provider: provider, hiddenItems: hiddenItems)
        }
        var inputs: [HomeLimitAccountInput] = []
        var context: [String: (provider: LimitProvider, name: HomeLimitRowName, plan: LimitPlanCell)] = [:]
        for id in providerIDs where !hiddenProviders.contains(id) {
            let entries = byProvider[id] ?? []
            let accountCount = id == "mimo" ? mimoAccountGroupCount(entries) : entries.count
            for (index, provider) in entries.enumerated() {
                let key = "\(id):\(index)"
                let visible = provider.windows.filter { !isHidden(id, $0) }
                inputs.append(HomeLimitAccountInput(
                    key: key,
                    providerID: id,
                    windows: compactWindows(provider, windows: visible),
                    balance: provider.balance,
                    isCompact: true
                ))
                let providerName = provider.displayName
                let name: HomeLimitRowName
                if accountCount > 1 {
                    let title = accountTitle(provider, peers: entries, index: index, mask: prefs.maskLimitAccountEmails)
                    name = HomeLimitRowName(providerName: showProviderName ? providerName : nil, detail: .account(title))
                } else if let product = mimoProduct(provider) {
                    name = HomeLimitRowName(providerName: showProviderName ? providerName : nil, detail: .product(product))
                } else {
                    name = HomeLimitRowName(providerName: providerName, detail: nil)
                }
                context[key] = (provider, name, planCell(provider, grouped: entries.count > 1))
            }
        }
        let count = min(DisplayPreferences.homeLimitAccountCountRange.upperBound,
                        max(DisplayPreferences.homeLimitAccountCountRange.lowerBound, prefs.homeLimitAccountCount))
        return homeAccounts(inputs, limit: count, sort: homeSort(prefs), isWindowHidden: isHidden).compactMap { account in
            guard let entry = context[account.key] else { return nil }
            return HomeLimitRow(
                id: account.key,
                providerID: account.providerID,
                iconID: iconID(entry.provider),
                name: entry.name,
                plan: entry.plan,
                lowestRemaining: account.lowestRemaining,
                windows: decorateHomeWindows(account.windows, providerID: account.providerID),
                provider: entry.provider
            )
        }
    }

    /// `homeLimitWindowLabel` and the Antigravity period labels.
    private static func decorateHomeWindows(_ windows: [HomeLimitWindow], providerID: String) -> [HomeLimitWindow] {
        let id = normalizedID(providerID)
        let groupLabels = windows.map { antigravityLane($0.window)?.group ?? "" }
        let antigravityLabelled = id == "antigravity" && windows.count >= 2
            && !groupLabels.contains("") && Set(groupLabels).count == groupLabels.count
        return windows.enumerated().map { index, home in
            var home = home
            let window = home.window
            if antigravityLabelled, let lane = antigravityLane(window) {
                home.label = .text(groupLabels[index])
                home.periodLabel = lane.period
            } else if (id == "zai" && window.kind == .daily), let label = nonEmpty(LimitUsageItems.jsTrim(window.label ?? "")) {
                home.label = .text(label)
            } else if window.kind == .billing, let label = nonEmpty(LimitUsageItems.jsTrim(window.label ?? "")) {
                home.label = .text(label)
            } else {
                home.label = .kind(window.kind)
            }
            return home
        }
    }

    /// `mimoAccountGroups(...).length`: MiMo's two products of one Xiaomi
    /// account count as one account.
    static func mimoAccountGroupCount(_ providers: [LimitProvider]) -> Int {
        var keys: [String] = []
        for (index, provider) in providers.enumerated() {
            let name = LimitUsageItems.jsTrim(provider.accountName ?? "")
            let email = LimitUsageItems.jsTrim(provider.accountEmail ?? "").lowercased()
            let key: String
            if let suffix = mimoIdentitySuffix(name) {
                key = "suffix:\(suffix.lowercased())"
            } else if !email.isEmpty {
                key = "email:\(email)"
            } else if !name.isEmpty {
                key = "name:\(name.lowercased())"
            } else {
                key = "row:\(provider.id)#\(index)"
            }
            if !keys.contains(key) { keys.append(key) }
        }
        return keys.count
    }

    /// `/(?:^|\s(?:·\s)?)(MiMo [a-f0-9]{7})$/i`.
    private static func mimoIdentitySuffix(_ name: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|\s(?:·\s)?)(MiMo [a-f0-9]{7})$"#, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name) else { return nil }
        return String(name[range])
    }

    /// The value cell of a Home window (`formatHomeLimitWindowValue`): MiMo's
    /// expired plan, "Unlimited", a balance in compact money (targets use
    /// `BalanceFormat.compact`), else the percentage in the text mode.
    public static func homeValue(_ window: HomeLimitWindow, showUsed: Bool) -> Headline {
        if window.planExpired { return .planExpired }
        if window.window.isUnlimited || window.isUnlimitedValue { return .unlimited }
        if window.isCredits {
            guard let remaining = window.remaining else { return window.window.detail.map(Headline.text) ?? .none }
            return .money(remaining, currency: window.currency ?? "USD")
        }
        return .percent(fillPercent(remaining: window.remainingPercent, used: nil, showUsed: showUsed), mode(showUsed: showUsed))
    }

    /// The bar under a Home window in `bars` mode: nil without a meter; fill
    /// flips with `showUsed` except for balances and fixed values; 0.95 for
    /// session and daily lanes, else 0.68.
    public static func homeMeter(_ window: HomeLimitWindow, showUsed: Bool) -> MeterFill? {
        guard window.showMeter, let remaining = window.remainingPercent else { return nil }
        let fillMode = mode(showUsed: showUsed && !window.isCredits && !window.isUnlimitedValue)
        let fill = fillPercent(remaining: remaining, used: nil, showUsed: fillMode == .used)
        let tone = window.kind == .session || window.kind == .daily ? 0.95 : 0.68
        return MeterFill(fraction: clampPercent(fill) / 100, percent: fill, mode: fillMode, toneOpacity: tone)
    }

    /// The line under a Home window: the boundary, or "Reset {value}" around
    /// the provider's wording; Zed's unlimited pool has none.
    public static func homeBoundaryLine(_ window: HomeLimitWindow, now: Date) -> BoundaryLine? {
        if window.isUnlimitedValue { return nil }
        return boundaryLine(window: window.window, now: now)
    }

    /// Low-limit emphasis for `remainingPercent` (`showHomeLimitBars`): under
    /// 20% critical, under 50% low.
    public static func homeSeverity(remainingPercent: Double?) -> HomeSeverity? {
        guard let remainingPercent else { return nil }
        let value = clampPercent(remainingPercent.isFinite ? remainingPercent : 0)
        if value < 20 { return .critical }
        if value < 50 { return .low }
        return nil
    }
}

// MARK: - Balance, spend, reset credits and usage summaries

extension LimitPresentation {
    /// A spend line's period.
    public enum SpendPeriod: String, Sendable, Hashable, CaseIterable {
        case today
        case week
        case month
        case allTime

        public var desktopText: String {
            switch self {
            case .today: return "Today"
            case .week: return "Week"
            case .month: return "Month"
            case .allTime: return "All time"
            }
        }
    }

    /// One line of a provider's balance details (the card's Balance, Spend
    /// and relay detail rows, plus "tracking since").
    public enum BalanceRow: Sendable, Hashable {
        /// The provider balance when no credits window carries it.
        case balance(amount: Double, currency: String)
        case gift(amount: Double, currency: String)
        case cash(amount: Double, currency: String)
        case spend(period: SpendPeriod, amount: Double, currency: String)
        /// Since when Token Monitor records spend; `partialMonth` when the
        /// month figure only counts from then.
        case trackingSince(Date, partialMonth: Bool)
        /// One prepaid grant, soonest expiry first.
        case tranche(amount: Double, currency: String, expiresAt: Date?)
        /// A relay's request count.
        case requests(Int)
        /// A relay's quota group.
        case quotaGroup(String)
        /// When the balance lapses.
        case expires(Date)
    }

    /// The balance details of `provider`, in card order: balance, gift and
    /// cash, prepaid grants (the `credits` item); spend by
    /// period, tracking since, relay request count, group and expiry (the
    /// `spend` item). Rows of an item the user hid are left out.
    public static func balanceRows(_ provider: LimitProvider, hiddenItems: [String: [String]] = [:]) -> [BalanceRow] {
        let hidden = LimitUsageItems.hiddenSet(hiddenItems, provider: provider.provider)
        var rows: [BalanceRow] = []
        let balance = provider.balance
        let currency = BalanceFormat.normalizeCode(balance?.currency)
        if !hidden.contains(LimitUsageFixedItem.credits.rawValue), let balance {
            if !provider.windows.contains(where: \.isCredits), let amount = finite(balance.amount) {
                rows.append(.balance(amount: amount, currency: currency))
            }
            if let gift = finite(balance.giftBalance) { rows.append(.gift(amount: gift, currency: currency)) }
            if let cash = finite(balance.cashBalance) { rows.append(.cash(amount: cash, currency: currency)) }
            for tranche in balance.tranches where tranche.amount.isFinite {
                rows.append(.tranche(
                    amount: tranche.amount,
                    currency: BalanceFormat.normalizeCode(tranche.currency ?? balance.currency),
                    expiresAt: tranche.expiresAt
                ))
            }
        }
        if !hidden.contains(LimitUsageFixedItem.spend.rawValue), let balance {
            for (period, amount) in spendEntries(balance) {
                rows.append(.spend(period: period, amount: amount, currency: currency))
            }
            if let since = balance.trackingSince { rows.append(.trackingSince(since, partialMonth: balance.monthSinceTracking)) }
            if let requests = balance.requestCount { rows.append(.requests(requests)) }
            if let group = balance.quotaGroup.flatMap({ nonEmpty(LimitUsageItems.jsTrim($0)) }) { rows.append(.quotaGroup(group)) }
            if let expires = balance.expiresAt { rows.append(.expires(expires)) }
        }
        return rows
    }

    /// `providerSpendEntries`: the spend figures present, Today → All time.
    public static func spendEntries(_ balance: LimitBalance) -> [(period: SpendPeriod, amount: Double)] {
        [
            (SpendPeriod.today, balance.todaySpend),
            (.week, balance.weekSpend),
            (.month, balance.monthSpend),
            (.allTime, balance.allTimeSpend)
        ].compactMap { period, value in finite(value).map { (period, $0) } }
    }

    /// The Spend row's summary: Today and Month when present, else the first
    /// two figures (`providerSpendNode`).
    public static func spendSummary(_ balance: LimitBalance) -> [SpendPeriod] {
        let periods = spendEntries(balance).map(\.period)
        let preferred = periods.filter { $0 == .today || $0 == .month }
        return preferred.isEmpty ? Array(periods.prefix(2)) : preferred
    }

    /// When one reset expires.
    public enum ResetExpiry: Sendable, Hashable {
        case now
        case duration(DurationParts)

        public var desktopText: String {
            switch self {
            case .now: return "now"
            case .duration(let parts): return parts.desktopText
            }
        }
    }

    /// The window a Claude grant clears (`claudeResetClearLabel`).
    public enum ResetClearLabel: Sendable, Hashable {
        case session
        case weekly
        case fableWeekly
        case opusWeekly
        case sonnetWeekly
        case oauthAppsWeekly
        case coworkWeekly
        case omeletteWeekly
        /// An id the table does not know, underscores read as spaces.
        case other(String)

        public init?(key: String) {
            switch key {
            case "five_hour": self = .session
            case "seven_day": self = .weekly
            case "seven_day_overage_included": self = .fableWeekly
            case "seven_day_opus": self = .opusWeekly
            case "seven_day_sonnet": self = .sonnetWeekly
            case "seven_day_oauth_apps": self = .oauthAppsWeekly
            case "seven_day_cowork": self = .coworkWeekly
            case "seven_day_omelette": self = .omeletteWeekly
            default:
                let text = LimitUsageItems.jsTrim(key.replacingOccurrences(of: "_", with: " "))
                guard !text.isEmpty else { return nil }
                self = .other(text)
            }
        }

        public var desktopText: String {
            switch self {
            case .session: return "Session"
            case .weekly: return "Weekly"
            case .fableWeekly: return "Fable weekly"
            case .opusWeekly: return "Opus weekly"
            case .sonnetWeekly: return "Sonnet weekly"
            case .oauthAppsWeekly: return "OAuth apps weekly"
            case .coworkWeekly: return "Cowork weekly"
            case .omeletteWeekly: return "Omelette weekly"
            case .other(let text): return text
            }
        }
    }

    /// One Claude reset grant (`claudeResetGrantRows`).
    public struct ResetGrantRow: Sendable, Hashable {
        public enum Remaining: Sendable, Hashable {
            case paused
            case expired
            case duration(DurationParts)
        }

        public enum Usability: Sendable, Hashable {
            /// "at a limit only"
            case atLimitOnly
            /// "not right now"
            case notRightNow
        }

        /// Anthropic's caption, shown as is.
        public var label: String?
        public var resetsLeft: Int?
        public var endsAt: Date?
        /// Paused, expired or time left; nil without a date unless paused
        /// ("No expiry").
        public var remaining: Remaining?
        public var clears: [ResetClearLabel]
        public var usability: Usability?
    }

    /// The "N resets" line (`codexResetCreditsNode`, `claudeResetCreditsNode`).
    public struct ResetCreditsLine: Sendable, Hashable {
        public var count: Int
        /// The first three expiries.
        public var expiries: [ResetExpiry]
        /// How many more ("+N").
        public var overflow: Int
        /// Every expiry, soonest first (the detail tooltip).
        public var expirationDates: [Date]
        /// Claude's grants (the detail tooltip); empty for Codex.
        public var grants: [ResetGrantRow]

        /// `N reset(s)` plus the timeline, as the desktop writes it.
        public var desktopText: String {
            var parts = ["\(count) reset\(count == 1 ? "" : "s")"]
            var timeline = expiries.map(\.desktopText)
            if overflow > 0 { timeline.append("+\(overflow)") }
            if !timeline.isEmpty { parts.append(timeline.joined(separator: " · ")) }
            return parts.joined(separator: " ")
        }
    }

    /// The reset-credit line of `provider`, nil without a spendable reset or
    /// when the user hid `resets`.
    public static func resetCredits(_ provider: LimitProvider, now: Date, hiddenItems: [String: [String]] = [:]) -> ResetCreditsLine? {
        guard let credits = provider.resetCredits, let available = credits.availableCount, available > 0 else { return nil }
        if LimitUsageItems.hiddenSet(hiddenItems, provider: provider.provider).contains(LimitUsageFixedItem.resets.rawValue) {
            return nil
        }
        let dates = credits.expirations.isEmpty ? [credits.nextExpiresAt].compactMap { $0 } : credits.expirations.sorted()
        let expiries = dates.prefix(3).map { date -> ResetExpiry in
            let diff = milliseconds(from: now, to: date)
            return diff <= 0 ? .now : .duration(DurationParts(milliseconds: diff))
        }
        let grants = credits.grants.map { grant -> ResetGrantRow in
            let remaining: ResetGrantRow.Remaining?
            if grant.paused == true {
                remaining = .paused
            } else if let endsAt = grant.endsAt {
                let diff = milliseconds(from: now, to: endsAt)
                remaining = diff <= 0 ? .expired : .duration(DurationParts(milliseconds: diff))
            } else {
                remaining = nil
            }
            let keys = grant.clears.filter { $0 != "seven_day_overage_included" || !grant.clears.contains("seven_day") }
            let usability: ResetGrantRow.Usability?
            if grant.useRequiresLimit == true {
                usability = .atLimitOnly
            } else if grant.usableNow == false {
                usability = .notRightNow
            } else {
                usability = nil
            }
            return ResetGrantRow(
                label: grant.label,
                resetsLeft: grant.resetsLeft,
                endsAt: grant.endsAt,
                remaining: remaining,
                clears: keys.compactMap(ResetClearLabel.init(key:)),
                usability: usability
            )
        }
        return ResetCreditsLine(
            count: available,
            expiries: Array(expiries),
            overflow: max(0, dates.count - expiries.count),
            expirationDates: dates,
            grants: grants
        )
    }

    /// One figure of a relay's or TypeSafe's own usage summary.
    public enum UsageSummaryRow: Sendable, Hashable {
        case todayTokens(Int)
        /// TypeSafe's last seven days.
        case weekTokens(Int)
        case requests(Int)
        case totalTokens(Int)
        case inputTokens(Int)
        case outputTokens(Int)
        /// Cache read plus cache creation, when above zero.
        case cacheTokens(Int)
        /// Milliseconds ("850 ms", "2.4 s").
        case averageDuration(Double)
        /// List-price cost in the balance currency.
        case standardCost(Double, currency: String)
        /// What the relay charged.
        case actualCost(Double, currency: String)
    }

    /// The usage summary's rows (`thirdPartySpendNode`, the TypeSafe token
    /// row), in a fixed order: today, week, requests, total, input, output,
    /// cache, average response, standard cost, actual cost. Empty without a
    /// summary or when the user hid `spend`.
    public static func usageSummaryRows(_ provider: LimitProvider, hiddenItems: [String: [String]] = [:]) -> [UsageSummaryRow] {
        guard let usage = provider.usageSummary,
              !LimitUsageItems.hiddenSet(hiddenItems, provider: provider.provider).contains(LimitUsageFixedItem.spend.rawValue)
        else { return [] }
        let currency = BalanceFormat.normalizeCode(provider.balance?.currency)
        var rows: [UsageSummaryRow] = []
        if let value = usage.todayTokens { rows.append(.todayTokens(value)) }
        if let value = usage.weekTokens { rows.append(.weekTokens(value)) }
        if let value = usage.requests { rows.append(.requests(value)) }
        if let value = usage.totalTokens { rows.append(.totalTokens(value)) }
        if let value = usage.inputTokens { rows.append(.inputTokens(value)) }
        if let value = usage.outputTokens { rows.append(.outputTokens(value)) }
        let cache = [usage.cacheReadTokens, usage.cacheCreationTokens].compactMap { $0 }.reduce(0, +)
        if cache > 0 { rows.append(.cacheTokens(cache)) }
        if let value = usage.averageDurationMs, value.isFinite { rows.append(.averageDuration(value)) }
        if let value = usage.standardCost, value.isFinite { rows.append(.standardCost(value, currency: currency)) }
        if let value = usage.actualCost, value.isFinite { rows.append(.actualCost(value, currency: currency)) }
        return rows
    }

    /// The desktop's average-response wording: "850 ms" under a second, else
    /// seconds with one decimal under ten ("2.4 s"), whole above ("12 s").
    public static func averageDurationDesktopText(_ milliseconds: Double) -> String {
        if milliseconds < 1000 { return "\(JSCompat.numberString(JSCompat.round(milliseconds))) ms" }
        return "\(JSCompat.toFixed(milliseconds / 1000, milliseconds < 10_000 ? 1 : 0)) s"
    }
}

// MARK: - Visible-items checklist

extension LimitPresentation {
    /// The rows a provider's card can draw, each once, in card order — the
    /// Settings visible-items checklist (`limitProviderUsageItems`): every
    /// window (Codex's additional pools only while `showCodexAdditional`),
    /// MiMo's token plan, then the balance (`credits`), spend and usage
    /// summary (`spend`) and reset credits (`resets`) rows.
    public static func usageItems(for provider: LimitProvider, showCodexAdditional: Bool = true) -> [LimitUsageItem] {
        var items: [LimitUsageItem] = []
        func add(_ id: String, _ label: LimitUsageItemLabel) {
            guard !id.isEmpty, !items.contains(where: { $0.id == id }) else { return }
            items.append(LimitUsageItem(id: id, label: label))
        }
        for window in cardWindows(provider, showCodexAdditional: showCodexAdditional) {
            let id = provider.usageItemID(for: window)
            switch id {
            case LimitUsageFixedItem.credits.rawValue:
                // These cards title the balance row "Balance" whatever the
                // window calls it; the others keep the window's own name.
                let fixedName: Set<String> = ["openrouter", "deepseek", "typesafe", "mimo", "zai", "zaiteam"]
                add(id, fixedName.contains(normalizedID(provider.provider)) ? .fixed(.credits)
                    : window.label.map { .window(.label($0)) } ?? .fixed(.credits))
            case LimitUsageFixedItem.spend.rawValue:
                add(id, window.label.map { .window(.label($0)) } ?? .fixed(.spend))
            default:
                add(id, windowName(window, provider: provider).usageItemLabel)
            }
        }
        if let balance = provider.balance, finite(balance.amount) != nil || finite(balance.giftBalance) != nil
            || finite(balance.cashBalance) != nil || !balance.tranches.isEmpty {
            add(LimitUsageFixedItem.credits.rawValue, .fixed(.credits))
        }
        if provider.balance?.hasSpend == true || provider.usageSummary != nil {
            add(LimitUsageFixedItem.spend.rawValue, .fixed(.spend))
        }
        if let available = provider.resetCredits?.availableCount, available > 0 {
            add(LimitUsageFixedItem.resets.rawValue, .fixed(.resets))
        }
        return items
    }
}

// MARK: - Helpers

extension LimitPresentation {
    static func normalizedID(_ value: String) -> String {
        LimitUsageItems.normalizedID(value)
    }

    static func clampPercent(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// `Number(value)` for a wire value that is a number or `null`: nil is 0.
    private static func jsNumber(_ value: Double?) -> Double? {
        guard let value else { return 0 }
        return value.isFinite ? value : nil
    }

    static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    /// Whole milliseconds from `start` to `end`, as the desktop's integer
    /// `Date` arithmetic sees them.
    static func milliseconds(from start: Date, to end: Date) -> Double {
        ((end.timeIntervalSince1970 - start.timeIntervalSince1970) * 1000).rounded()
    }

    static func isJSWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        LimitUsageItems.jsTrim(String(scalar)).isEmpty
    }
}

/// `Math.round` as an Int, saturating.
private func jsRoundInt(_ value: Double) -> Int {
    let rounded = JSCompat.round(value)
    guard rounded.isFinite else { return rounded > 0 ? Int.max : 0 }
    if rounded >= Double(Int.max) { return Int.max }
    if rounded <= Double(Int.min) { return Int.min }
    return Int(rounded)
}

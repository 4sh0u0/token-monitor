import Foundation
import TokenMonitorKit

// Localized names and formatted values for Kit models. Kept free of SwiftUI so
// the wording lives in one place for every screen. Numbers and costs go
// through `DisplayFormatter` (`model.formatter` / `@Environment(\.tmFormatter)`)
// so the user's units and currency apply.

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

extension PeriodSelection {
    /// The period's full name (hero title, the middle segment's menu):
    /// "This month", "This week", "Last 7 days" (`periodRange.*`).
    var title: String {
        switch self {
        case .today: return String(localized: "Today")
        case .month: return String(localized: "This month")
        case .week: return String(localized: "This week")
        case .last7: return String(localized: "Last 7 days")
        case .last30: return String(localized: "Last 30 days")
        case .allTime: return String(localized: "All time")
        }
    }

    /// The period picker's segment: "Today", "Month", "Week", "7D", "30D",
    /// "All time" (`edgeDock.periodShort.*` for the fixed ranges).
    var shortTitle: String {
        switch self {
        case .today: return String(localized: "Today")
        case .month: return String(localized: "Month")
        case .week: return String(localized: "Week")
        case .last7: return String(localized: "7D")
        case .last30: return String(localized: "30D")
        case .allTime: return String(localized: "All time")
        }
    }
}

extension AppTab {
    var title: String {
        switch self {
        case .overview: return String(localized: "Overview")
        case .limits: return String(localized: "Limits")
        case .devices: return String(localized: "Devices")
        case .status: return String(localized: "Status")
        case .settings: return String(localized: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "chart.bar.xaxis"
        case .limits: return "gauge.with.dots.needle.33percent"
        case .devices: return "laptopcomputer.and.iphone"
        case .status: return "waveform.path.ecg"
        case .settings: return "gearshape"
        }
    }
}

// MARK: Round-1 helpers kept for the views Phase 3b replaces

extension LimitProvider {
    @available(*, deprecated, message: "Round-1 wording; use LimitPresentation.statusChip(_:) and LimitStatusLabel.desktopKey")
    var statusTitle: String {
        switch status {
        case .ok: return String(localized: "Available")
        case .unauthorized: return String(localized: "Sign in again")
        case .rateLimited, .sourceRateLimited: return String(localized: "Rate limited")
        case .unavailable: return String(localized: "Unavailable")
        case .error: return String(localized: "Temporarily unavailable")
        case .disabled: return String(localized: "Disabled")
        case .notConfigured: return String(localized: "Not configured")
        }
    }
}

extension LimitWindow {
    /// The provider's own label, else a name for the window's kind.
    @available(*, deprecated, message: "Round-1 helper; use LimitWindowTitle / LimitPresentation.windowName")
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
    @available(*, deprecated, message: "Round-1 helper; use LimitPresentation.headline(window:provider:showUsed:)")
    var headline: String {
        if isUnlimited { return String(localized: "Unlimited") }
        if isSpend, let used = moneyAmount {
            let usedText = BalanceFormat.format(amount: used, currency: currency)
            if let limit, limit > 0 {
                let limitText = BalanceFormat.format(amount: limit, currency: currency)
                return String(localized: "\(usedText) of \(limitText) used")
            }
            return String(localized: "\(usedText) used")
        }
        if isCredits, let remaining = moneyAmount {
            let amount = BalanceFormat.format(amount: remaining, currency: currency)
            return String(localized: "\(amount) left")
        }
        if let remainingPercent {
            let percent = DisplayFormatter().percent(remainingPercent)
            return String(localized: "\(percent) left")
        }
        return "—"
    }

    /// "Resets in 2h 30m" / "Expires in 3d 4h" / "Changes in …", worded by
    /// `boundaryKind`; nil without a boundary.
    @available(*, deprecated, message: "Round-1 helper; use LimitPresentation.boundaryLine(window:now:)")
    func boundaryText(now: Date) -> String? {
        guard let resetsAt else { return nil }
        guard resetsAt > now else {
            switch boundaryKind {
            case .reset: return String(localized: "Resetting now")
            case .expiry: return String(localized: "Expired")
            case .mixed: return String(localized: "Changes now")
            }
        }
        let countdown = AppFormat.countdown(to: resetsAt, from: now)
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
    @available(*, deprecated, message: "Round-1 helper; use DevicePresentation.row(_:period:)")
    var todayTokens: Int { today.isExpired ? 0 : today.tokens }
    @available(*, deprecated, message: "Round-1 helper; use DevicePresentation.row(_:period:)")
    var todayCost: Double { today.isExpired ? 0 : today.costUsd }

    @available(*, deprecated, message: "Round-1 SF Symbol; use VendorMark(.operatingSystem(iconAssetName: DevicePresentation.osIconAssetName(platform:)))")
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
    @available(*, deprecated, message: "Round-1 helper; use AttributionRow.percent / AttributionRows.detailPercentLabel")
    static func share(_ fraction: Double) -> String {
        let percent = fraction * 100
        guard percent.isFinite else { return "—" }
        return JSCompat.toFixed(percent, percent > 0 && percent < 10 ? 1 : 0) + "%"
    }

    /// "5 min. ago", never "in …": a timestamp later than `now` (data newer
    /// than the last TimelineView tick, or a device clock running ahead)
    /// reads as just now, and so does anything under a minute, which the
    /// views only re-render every 30 s anyway.
    static func ago(_ date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return String(localized: "just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// The time left until `date` as `2h 30m` / `3d 4h` (two largest units,
    /// rounded up to whole minutes, at least one minute), localized by
    /// Foundation.
    static func countdown(to date: Date, from now: Date) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return Duration.seconds(minutes * 60).formatted(
            .units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2)
        )
    }

    /// "62 tok/s" (the unit is not translated, as on the desktop), in the
    /// user's compact units.
    static func outputSpeed(_ rate: Double, formatter: DisplayFormatter = DisplayFormatter()) -> String {
        let value = formatter.liveTokenRate(rate)
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

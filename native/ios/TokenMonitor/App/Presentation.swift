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

enum AppFormat {
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

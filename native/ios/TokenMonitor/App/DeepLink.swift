import Foundation
import TokenMonitorKit

/// The app's tabs, in tab-bar order. Status shows only when the
/// `showStatusTab` preference is on (hidden by default, as on the desktop).
enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case overview
    case limits
    case devices
    case status
    case settings

    var id: String { rawValue }

    /// The tabs the tab bar shows for these preferences.
    static func visible(showStatusTab: Bool) -> [AppTab] {
        allCases.filter { $0 != .status || showStatusTab }
    }
}

/// `tokenmonitor://` links opened by the widgets and complications:
/// - `dashboard?period=today|month|week|last7|last30|allTime` (also `overview`
///   or no route): the Overview tab, optionally on that period;
/// - `trends`: the Trends screen, pushed on the Overview tab;
/// - `limits`, `devices`, `settings`;
/// - `status`: the Status tab, or the service-status screen in Settings when
///   that tab is hidden.
enum DeepLink: Equatable {
    case dashboard(period: PeriodSelection?)
    case trends
    case limits
    case devices
    case status
    case settings

    static let scheme = "tokenmonitor"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        // `tokenmonitor://limits` carries the route as its host; also accept
        // the path form `tokenmonitor:///limits`.
        let host = components.host ?? ""
        let route = host.isEmpty
            ? (components.path.split(separator: "/").first.map(String.init) ?? "")
            : host
        switch route.lowercased() {
        case "", "dashboard", "overview":
            let rawPeriod = components.queryItems?.first(where: { $0.name == "period" })?.value
            self = .dashboard(period: rawPeriod.flatMap(Self.period(from:)))
        case "trends":
            self = .trends
        case "limits":
            self = .limits
        case "devices":
            self = .devices
        case "status":
            self = .status
        case "settings":
            self = .settings
        default:
            return nil
        }
    }

    /// A `period` value, case-insensitive (`allTime`, `alltime`, `last7`).
    static func period(from raw: String) -> PeriodSelection? {
        let folded = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return PeriodSelection.allCases.first { $0.rawValue.lowercased() == folded }
    }
}

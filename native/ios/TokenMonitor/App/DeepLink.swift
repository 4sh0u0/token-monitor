import Foundation
import TokenMonitorKit

enum AppTab: String, Hashable, CaseIterable {
    case overview
    case limits
    case devices
    case settings
}

/// `tokenmonitor://` links opened by the widgets and complications:
/// `dashboard?period=today|month|allTime`, `limits`, `devices`, `settings`.
enum DeepLink: Equatable {
    case dashboard(period: UsagePeriodKind?)
    case limits
    case devices
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
        case "limits":
            self = .limits
        case "devices":
            self = .devices
        case "settings":
            self = .settings
        default:
            return nil
        }
    }

    private static func period(from raw: String) -> UsagePeriodKind? {
        let folded = raw.lowercased()
        return UsagePeriodKind.allCases.first { $0.rawValue.lowercased() == folded }
    }
}

import SwiftUI
import TokenMonitorKit

/// A screen pushed onto a tab's navigation stack. Push one with
/// `NavigationLink(value: AppRoute.tools)` or `model.navigate(to:)`; every
/// tab's stack (built by `MainTabView`) resolves it through
/// `AppRouteDestination`.
enum AppRoute: Hashable {
    case tools
    case models
    case projects
    case sessions
    /// A session's detail, by `HubSession.id` (`client:sessionId`). The same
    /// session can have a today and a month entry with different totals;
    /// `period` is the one the opening screen showed (nil: month, else today).
    case sessionDetail(String, period: UsagePeriodKind? = nil)
    /// The collapsed background-review sessions of one period.
    case backgroundReviews(UsagePeriodKind)
    case trends
    /// One device, by `DeviceSummary.id`.
    case deviceDetail(String)
    case subscriptions
    case hubInfo
    case serviceStatus
    /// Settings › Status: the Status tab switch, the re-check interval and
    /// the services listed.
    case serviceStatusSettings
}

/// The view each route shows.
struct AppRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .tools:
            ToolsView()
        case .models:
            ModelsView()
        case .projects:
            ProjectsView()
        case .sessions:
            SessionsView()
        case let .sessionDetail(id, period):
            SessionDetailView(sessionID: id, initialPeriod: period)
        case .backgroundReviews(let period):
            BackgroundReviewsView(period: period)
        case .trends:
            TrendsView()
        case .deviceDetail(let id):
            DeviceDetailView(deviceID: id)
        case .subscriptions:
            SubscriptionsView()
        case .hubInfo:
            HubInfoView()
        case .serviceStatus:
            ServiceStatusView()
        case .serviceStatusSettings:
            ServiceStatusSettingsView()
        }
    }
}

extension View {
    /// Resolves `AppRoute` values pushed onto the enclosing stack.
    func appRouteDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            AppRouteDestination(route: route)
        }
    }
}

/// Each tab's navigation path, so a deep link can open a screen inside a tab
/// and a tab switch keeps the other tabs where they were.
struct AppNavigation: Equatable {
    var overview = NavigationPath()
    var limits = NavigationPath()
    var devices = NavigationPath()
    var status = NavigationPath()
    var settings = NavigationPath()

    subscript(tab: AppTab) -> NavigationPath {
        get {
            switch tab {
            case .overview: return overview
            case .limits: return limits
            case .devices: return devices
            case .status: return status
            case .settings: return settings
            }
        }
        set {
            switch tab {
            case .overview: overview = newValue
            case .limits: limits = newValue
            case .devices: devices = newValue
            case .status: status = newValue
            case .settings: settings = newValue
            }
        }
    }
}

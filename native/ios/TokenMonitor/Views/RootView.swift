import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Onboarding until a Hub is saved, then the tabs. Sets the presentation
/// context (units, currency, vendor colours, tool icons) for every screen.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.needsOnboarding {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .tmPresentation(model.context)
    }
}

/// Overview, Limits, Devices, Status (when `showStatusTab` is on) and
/// Settings. Each tab gets its own `NavigationStack`, bound to
/// `model.navigation`, that resolves `AppRoute` values; the tab's root view
/// must not add another stack.
struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            ForEach(model.visibleTabs) { tab in
                AppTabStack(tab: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
    }
}

/// One tab's navigation stack and root screen.
private struct AppTabStack: View {
    @Environment(AppModel.self) private var model
    let tab: AppTab

    var body: some View {
        NavigationStack(path: path) {
            root
                .appRouteDestinations()
        }
    }

    private var path: Binding<NavigationPath> {
        Binding(
            get: { model.navigation[tab] },
            set: { model.navigation[tab] = $0 }
        )
    }

    @ViewBuilder
    private var root: some View {
        switch tab {
        case .overview:
            OverviewView()
        case .limits:
            LimitsView()
        case .devices:
            DevicesView()
        case .status:
            ServiceStatusView()
        case .settings:
            SettingsView()
        }
    }
}

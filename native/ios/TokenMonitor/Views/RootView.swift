import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Onboarding until a Hub is saved, then the tabs.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.needsOnboarding {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.scenePhaseChanged(phase)
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            OverviewView()
                .tabItem { Label("Overview", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.overview)
            LimitsView()
                .tabItem { Label("Limits", systemImage: "gauge.with.dots.needle.33percent") }
                .tag(AppTab.limits)
            DevicesView()
                .tabItem { Label("Devices", systemImage: "laptopcomputer.and.iphone") }
                .tag(AppTab.devices)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}

import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Settings › Refresh intervals (§3.10): how often the app, the widgets, the
/// watch app and the complications read the Hub. The desktop has no such
/// setting; the wording follows its interval menus
/// (`settings.sync.uploadInterval.*`, `settings.collection.interval.*`).
struct RefreshSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker("App updates", selection: model.displayPreference(\.appRefreshSeconds)) {
                    ForEach(AppRefreshMode.allCases) { mode in
                        Text(mode.settingsTitle).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("App updates")
            } footer: {
                Text("Live keeps a connection to the Hub open while Token Monitor is on screen. The other choices check the Hub at that interval and hide the live token rate.")
            }
            .listRowBackground(TMTheme.card)

            Section {
                Picker("Widgets", selection: model.displayPreference(\.widgetRefreshMinutes)) {
                    ForEach(WidgetRefreshInterval.allCases) { interval in
                        Text(interval.settingsTitle).tag(interval)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Widgets")
            } footer: {
                Text("Widgets and complications refresh when iOS allows; the system may delay them.")
            }
            .listRowBackground(TMTheme.card)

            Section {
                Picker("Apple Watch", selection: model.displayPreference(\.watchRefreshSeconds)) {
                    ForEach(WatchRefreshInterval.allCases) { interval in
                        Text(interval.settingsTitle).tag(interval)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Apple Watch")
            } footer: {
                Text("How often the watch app checks the Hub while it is on screen.")
            }
            .listRowBackground(TMTheme.card)

            Section {
                Picker("Complications", selection: model.displayPreference(\.complicationRefreshMinutes)) {
                    ForEach(ComplicationRefreshInterval.allCases) { interval in
                        Text(interval.settingsTitle).tag(interval)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Complications")
            } footer: {
                Text("Widgets and complications refresh when iOS allows; the system may delay them.")
            }
            .listRowBackground(TMTheme.card)
        }
        .settingsListBackground()
        .navigationTitle("Refresh intervals")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Option names

extension AppRefreshMode {
    /// "Live" (`settings.sync.uploadInterval.live`) or "Every N minutes".
    var settingsTitle: String {
        switch self {
        case .live: return String(localized: "Live")
        case .oneMinute: return String(localized: "Every minute")
        case .twoMinutes: return String(localized: "Every 2 minutes")
        case .fiveMinutes: return String(localized: "Every 5 minutes")
        case .fifteenMinutes: return String(localized: "Every 15 minutes")
        case .thirtyMinutes: return String(localized: "Every 30 minutes")
        }
    }
}

extension WidgetRefreshInterval {
    var settingsTitle: String {
        switch self {
        case .fifteenMinutes: return String(localized: "Every 15 minutes")
        case .thirtyMinutes: return String(localized: "Every 30 minutes")
        case .oneHour: return String(localized: "Every hour")
        }
    }
}

extension WatchRefreshInterval {
    var settingsTitle: String {
        switch self {
        case .oneMinute: return String(localized: "Every minute")
        case .twoMinutes: return String(localized: "Every 2 minutes")
        case .fiveMinutes: return String(localized: "Every 5 minutes")
        case .fifteenMinutes: return String(localized: "Every 15 minutes")
        }
    }
}

extension ComplicationRefreshInterval {
    var settingsTitle: String {
        switch self {
        case .twentyMinutes: return String(localized: "Every 20 minutes")
        case .thirtyMinutes: return String(localized: "Every 30 minutes")
        case .oneHour: return String(localized: "Every hour")
        }
    }
}

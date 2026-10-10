import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The Settings tab: the Hub connection, then one row per settings page
/// (display, data, status), Hub setup help and About.
///
/// A tab root: `RootView` gives the tab its `NavigationStack`, so this view
/// adds none. Every preference write goes through
/// `AppModel.updatePreferences` (`displayPreference(_:)` builds the bindings).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsDisconnect = false

    var body: some View {
        Form {
            HubConnectionForm()
            if model.isConfigured {
                ConnectionStatusSection()
            }
            DisplaySettingsSection()
            DataSettingsSection()
            StatusSettingsSection()
            if model.isConfigured {
                Section {
                    Button(role: .destructive) {
                        confirmsDisconnect = true
                    } label: {
                        Label("Disconnect from Hub", systemImage: "xmark.circle")
                            .foregroundStyle(TMTheme.critical)
                    }
                }
                .listRowBackground(TMTheme.card)
            }
            HubSetupHelpSection()
            Section {
                LabeledContent("Version") {
                    Text(verbatim: AppFormat.appVersion)
                        .monospacedDigit()
                }
            } header: {
                Text("About")
            }
            .listRowBackground(TMTheme.card)
        }
        .settingsListBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Settings")
        .confirmationDialog("Disconnect from this Hub?", isPresented: $confirmsDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                model.disconnect()
            }
        } message: {
            Text("The Hub address and secret are removed from this iPhone, its widgets and your Apple Watch.")
        }
    }
}

// MARK: - Sections

/// The saved Hub: address, live-update state, last update, the current issue
/// and a link to the Hub's details.
private struct ConnectionStatusSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            if let connection = model.connection {
                LabeledContent("Hub") {
                    Text(verbatim: connection.displayHost)
                }
            }
            LabeledContent("Live updates") {
                LiveStatusIndicator()
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                LabeledContent("Last updated") {
                    if let updated = model.lastUpdated {
                        Text(verbatim: AppFormat.ago(updated, now: context.date))
                    } else {
                        Text("Never")
                    }
                }
            }
            if let issue = model.issue {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: issue.title)
                            .foregroundStyle(TMTheme.text)
                        Text(verbatim: issue.message)
                            .font(.caption)
                            .foregroundStyle(TMTheme.muted)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(TMTheme.warning)
                }
            }
            NavigationLink(value: AppRoute.hubInfo) {
                SettingsPageLabel("Hub info", systemImage: "server.rack")
            }
        } header: {
            Text("Connection")
        }
        .listRowBackground(TMTheme.card)
    }
}

/// How numbers, marks and the Overview look.
private struct DisplaySettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                SettingsPageLabel("Appearance", systemImage: "paintbrush")
            }
            NavigationLink {
                CurrencySettingsView()
            } label: {
                SettingsPageLabel("Currency", systemImage: "dollarsign.circle") {
                    Text(verbatim: model.preferences.currency.code)
                }
            }
            NavigationLink {
                ScopeAndPeriodSettingsView()
            } label: {
                SettingsPageLabel("Device scope and periods", systemImage: "square.stack.3d.up") {
                    Text(scopeSummary)
                        .lineLimit(1)
                }
            }
            NavigationLink {
                OverviewModulesSettingsView()
            } label: {
                SettingsPageLabel("Overview modules", systemImage: "square.grid.2x2")
            }
            NavigationLink {
                ToolListSettingsView()
            } label: {
                SettingsPageLabel("Tools", systemImage: "hammer")
            }
        } header: {
            Text("Display")
        }
        .listRowBackground(TMTheme.card)
    }

    /// "All devices", the scoped device's name, or "Device not found".
    private var scopeSummary: String {
        guard let id = model.preferences.deviceScope.deviceID else { return String(localized: "All devices") }
        if let device = model.scopedDevice { return device.displayName }
        if model.presented?.isScopeMissing == true { return String(localized: "Device not found") }
        return id
    }
}

/// Limits, sessions, subscriptions, refresh and export: the SETTINGS-B pages
/// and the refresh intervals.
private struct DataSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            NavigationLink {
                LimitsSettingsView()
            } label: {
                SettingsPageLabel("AI Tool Limits", systemImage: "gauge.with.dots.needle.33percent")
            }
            NavigationLink {
                SessionsSettingsView()
            } label: {
                SettingsPageLabel("Sessions", systemImage: "text.bubble")
            }
            // Routes resolve to `SubscriptionsView()` (and `HubInfoView()` /
            // `ServiceStatusView()` below), so deep links and
            // `navigate(to:)` land on the same screens.
            NavigationLink(value: AppRoute.subscriptions) {
                SettingsPageLabel("Subscriptions", systemImage: "creditcard")
            }
            NavigationLink {
                RefreshSettingsView()
            } label: {
                SettingsPageLabel("Refresh intervals", systemImage: "arrow.clockwise") {
                    Text(model.preferences.appRefreshSeconds.settingsTitle)
                        .lineLimit(1)
                }
            }
            NavigationLink {
                ExportView()
            } label: {
                SettingsPageLabel("Data export", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Data")
        }
        .listRowBackground(TMTheme.card)
    }
}

/// The Status tab switch, the status screen while the tab is hidden, and the
/// status options (re-check interval, services).
private struct StatusSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            Toggle(isOn: model.displayPreference(\.showStatusTab)) {
                Label("Show Status tab", systemImage: "waveform.path.ecg")
            }
            if !model.preferences.showStatusTab {
                NavigationLink(value: AppRoute.serviceStatus) {
                    SettingsPageLabel("Service status", systemImage: "checkmark.seal")
                }
            }
            NavigationLink {
                ServiceStatusSettingsView()
            } label: {
                SettingsPageLabel("Status options", systemImage: "slider.horizontal.3")
            }
        } header: {
            Text("Status")
        } footer: {
            Text("Status shows the public status pages of the AI services you use.")
        }
        .listRowBackground(TMTheme.card)
    }
}

// MARK: - Shared settings helpers

/// A settings row that opens a page: an icon, a title and an optional
/// current value on the trailing side (the `NavigationLink` adds the chevron).
struct SettingsPageLabel<Detail: View>: View {
    private let title: Text
    private let systemImage: String
    private let detail: Detail

    init(_ title: LocalizedStringKey, systemImage: String, @ViewBuilder detail: () -> Detail) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.detail = detail()
    }

    var body: some View {
        LabeledContent {
            detail
                .foregroundStyle(TMTheme.muted)
        } label: {
            Label {
                title
                    .foregroundStyle(TMTheme.text)
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }
}

extension SettingsPageLabel where Detail == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String) {
        self.init(title, systemImage: systemImage) { EmptyView() }
    }
}

extension AppModel {
    /// A binding to one display preference that writes through
    /// `updatePreferences`, so the snapshot, the widgets and the watch follow.
    func displayPreference<Value>(_ keyPath: WritableKeyPath<DisplayPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { self.preferences[keyPath: keyPath] },
            set: { value in
                self.updatePreferences { $0[keyPath: keyPath] = value }
            }
        )
    }
}

extension View {
    /// A settings page's list on Token Monitor's background.
    func settingsListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background {
                TMBackground().ignoresSafeArea()
            }
    }
}

import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Settings › Overview modules: which Overview modules show and in what
/// order (`homeModuleOrder`, `hiddenHomeModules`), the desktop's Home module
/// list (`renderHomeSettingsList`) plus the iOS-only token components card,
/// first by default. Hiding the last visible module shows them all again
/// (`HomeModuleLayout.toggleHidden`, as `normalizeHiddenHomeModules`).
struct OverviewModulesSettingsView: View {
    @Environment(AppModel.self) private var model

    private var order: [HomeModule] { HomeModuleLayout.ordered(model.preferences) }
    private var hidden: Set<HomeModule> {
        Set(HomeModuleLayout.normalizedHidden(model.preferences.hiddenHomeModules))
    }

    var body: some View {
        let order = order
        let hidden = hidden
        Form {
            Section {
                ForEach(order) { module in
                    ModuleRow(module: module, isHidden: hidden.contains(module)) {
                        toggle(module)
                    }
                    .accessibilityAction(named: Text("Move up")) { move(module, up: true) }
                    .accessibilityAction(named: Text("Move down")) { move(module, up: false) }
                }
                .onMove { source, destination in
                    var next = order
                    next.move(fromOffsets: source, toOffset: destination)
                    model.updatePreferences { $0.homeModuleOrder = next }
                }
            } header: {
                Text("Modules")
            } footer: {
                Text("Choose which modules appear on the Overview and their order. Hiding the last visible module shows every module again.")
            }
            .listRowBackground(TMTheme.card)

            Section {
                Button("Reset order") {
                    model.updatePreferences { $0.homeModuleOrder = HomeModule.defaultOrder }
                }
                .disabled(order == HomeModule.defaultOrder)
                Button("Show all") {
                    model.updatePreferences { $0.hiddenHomeModules = [] }
                }
                .disabled(hidden.isEmpty)
            }
            .listRowBackground(TMTheme.card)

            Section {
                NavigationLink {
                    LimitsSettingsView()
                } label: {
                    SettingsPageLabel("Limits", systemImage: "gauge.with.dots.needle.33percent")
                }
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    SettingsPageLabel("Activity", systemImage: "square.grid.3x3.fill")
                }
            } header: {
                Text("Module options")
            }
            .listRowBackground(TMTheme.card)
        }
        .settingsListBackground()
        .navigationTitle("Overview modules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
    }

    private func toggle(_ module: HomeModule) {
        model.updatePreferences {
            $0.hiddenHomeModules = HomeModuleLayout.toggleHidden($0.hiddenHomeModules, module: module)
        }
    }

    /// `moveHomeModuleOrder` (the desktop's Up/Down keys).
    private func move(_ module: HomeModule, up: Bool) {
        model.updatePreferences {
            $0.homeModuleOrder = HomeModuleLayout.move($0.homeModuleOrder, module: module, up: up)
        }
    }
}

/// One module: its name and a show/hide button; hidden rows are dimmed.
private struct ModuleRow: View {
    let module: HomeModule
    let isHidden: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: module.settingsSymbol)
                .frame(width: 22)
                .foregroundStyle(isHidden ? TMTheme.muted : TMTheme.accent)
                .accessibilityHidden(true)
            Text(module.settingsTitle)
                .foregroundStyle(isHidden ? TMTheme.muted : TMTheme.text)
            Spacer(minLength: 8)
            Button(action: toggle) {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .foregroundStyle(isHidden ? TMTheme.muted : TMTheme.text)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isHidden
                ? Text("Show \(module.settingsTitle) on the Overview")
                : Text("Hide \(module.settingsTitle) from the Overview"))
        }
    }
}

extension HomeModule {
    /// The module's name (`home.*`; "Token components" for the iOS card).
    var settingsTitle: String {
        switch self {
        case .components: return String(localized: "Token components")
        case .limits: return String(localized: "Limits")
        case .tool: return String(localized: "Tools")
        case .model: return String(localized: "Models")
        case .session: return String(localized: "Sessions")
        case .device: return String(localized: "Devices")
        case .trends: return String(localized: "Activity")
        }
    }

    var settingsSymbol: String {
        switch self {
        case .components: return "chart.pie"
        case .limits: return "gauge.with.dots.needle.33percent"
        case .tool: return "hammer"
        case .model: return "cpu"
        case .session: return "text.bubble"
        case .device: return "laptopcomputer.and.iphone"
        case .trends: return "square.grid.3x3.fill"
        }
    }
}

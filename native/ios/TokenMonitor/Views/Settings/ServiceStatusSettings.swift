import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Settings › Status options (`AppRoute.serviceStatusSettings`, also opened
/// from the Status screen; `renderServiceProviderList`), the one place for
/// every status preference: whether the Status tab shows (`showStatusTab`,
/// hidden by default like the desktop's view), how often an open Status
/// screen re-checks (`serviceStatusRefreshMs`: Manual, 1, 2, 5, 15 or 30
/// minutes), and which services it lists in which order
/// (`hiddenServiceProviders`, `serviceProviderDisplayOrder`).
/// `ServiceStatusStore` follows these on its own.
struct ServiceStatusSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let prefs = model.preferences
        let known = ServiceStatusProvider.all.map(\.id)
        let order = OrderedIDs.normalizeOrder(prefs.serviceProviderDisplayOrder, known: known)
        let hidden = Set(OrderedIDs.normalizeSelection(prefs.hiddenServiceProviders, known: known))
        List {
            Section {
                Toggle("Show Status tab", isOn: preference(\.showStatusTab))
                if !prefs.showStatusTab {
                    NavigationLink(value: AppRoute.serviceStatus) {
                        Label("Service status", systemImage: "waveform.path.ecg")
                    }
                }
            } footer: {
                Text("Shows Claude, OpenAI, Cursor and DeepSeek service status from their public status pages.")
            }
            .listRowBackground(TMTheme.card)

            Section {
                Picker("Re-check", selection: preference(\.serviceStatusRefreshMs)) {
                    ForEach(ServiceStatusRefresh.allCases) { option in
                        ServiceStatusSettingsText.refreshTitle(option)
                            .tag(option)
                    }
                }
            } footer: {
                Text("Only while the Status screen is open. Pull down on it to check now.")
            }
            .listRowBackground(TMTheme.card)

            Section {
                ForEach(order, id: \.self) { id in
                    if let provider = ServiceStatusProvider.provider(id: id) {
                        Toggle(isOn: shownBinding(id)) {
                            HStack(spacing: 10) {
                                VendorMark(.provider(provider.markID), size: 18, hidesWhenIconsOff: true)
                                Text(verbatim: provider.label)
                                    .foregroundStyle(hidden.contains(id) ? TMTheme.muted : TMTheme.text)
                            }
                        }
                    }
                }
                .onMove { source, destination in
                    var next = order
                    next.move(fromOffsets: source, toOffset: destination)
                    model.updatePreferences {
                        $0.serviceProviderDisplayOrder = next == known ? [] : next
                    }
                }
            } header: {
                Text("Services")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose which services appear on the Status view and their order.")
                    Text("Tap Edit, then drag a service to reorder the list.")
                }
            }
            .listRowBackground(TMTheme.card)

            Section {
                Button("Reset order") {
                    model.updatePreferences { $0.serviceProviderDisplayOrder = [] }
                }
                .disabled(!OrderedIDs.hasCustomOrder(prefs.serviceProviderDisplayOrder))
                Button("Show all") {
                    model.updatePreferences { $0.hiddenServiceProviders = [] }
                }
                .disabled(hidden.isEmpty)
            }
            .listRowBackground(TMTheme.card)
        }
        .scrollContentBackground(.hidden)
        .background {
            TMBackground().ignoresSafeArea()
        }
        .navigationTitle("Status options")
        .toolbar {
            // Reordering needs edit mode; a permanent one would disable the
            // Service status link above.
            EditButton()
        }
    }

    private func shownBinding(_ id: String) -> Binding<Bool> {
        let known = ServiceStatusProvider.all.map(\.id)
        return Binding(
            get: { !OrderedIDs.normalizeSelection(model.preferences.hiddenServiceProviders, known: known).contains(id) },
            set: { shown in
                model.updatePreferences { prefs in
                    var hidden = OrderedIDs.normalizeSelection(prefs.hiddenServiceProviders, known: known)
                    hidden.removeAll { $0 == id }
                    if !shown { hidden.append(id) }
                    prefs.hiddenServiceProviders = hidden
                }
            }
        )
    }

    private func preference<Value>(_ keyPath: WritableKeyPath<DisplayPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: { value in model.updatePreferences { $0[keyPath: keyPath] = value } }
        )
    }
}

/// The re-check picker's wording (`serviceStatus.refreshManual`,
/// `serviceStatus.refreshMinutes`).
enum ServiceStatusSettingsText {
    static func refreshTitle(_ option: ServiceStatusRefresh) -> Text {
        switch option {
        case .manual:
            return Text("Manual")
        default:
            let minutes = option.rawValue / 60_000
            return Text("\(minutes)m")
        }
    }
}

import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Settings › Sessions (`settings.session.*`): whether session titles show
/// (`sessionTitlesEnabled`) and which way the context gauge reads
/// (`sessionContextMetric`).
///
/// Titles reach the phone only when the Hub allows title sync and the
/// computer that ran the session shares them, so the page says what this
/// Hub allows (`GET /api/sync/content`, `HubInfoStore.syncContent`).
struct SessionsSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Toggle("Show session titles", isOn: preference(\.sessionTitlesEnabled))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hide session titles across all views.")
                    titleAvailability
                    Text("Titles are only shown on screen; they are never saved for widgets or Apple Watch.")
                }
            }
            .listRowBackground(TMTheme.card)

            Section {
                Picker("Context gauge shows", selection: preference(\.sessionContextMetric)) {
                    Text("Used").tag(ContextMetric.used)
                    Text("Remaining").tag(ContextMetric.remaining)
                }
            } footer: {
                Text("How much of the model's context window running sessions have used, or have left.")
            }
            .listRowBackground(TMTheme.card)
        }
        .scrollContentBackground(.hidden)
        .background {
            TMBackground().ignoresSafeArea()
        }
        .navigationTitle("Sessions")
        .task(id: model.connection?.snapshotKey) {
            await loadCapabilities()
        }
    }

    /// What the connected Hub allows, in the desktop's words where it has
    /// them (`settings.sync.content.*`).
    @ViewBuilder
    private var titleAvailability: some View {
        let info = model.hubInfo
        if model.connection != nil {
            switch info.syncContentStatus {
            case .available:
                if let content = info.syncContent, content.isSupported {
                    if content.sessionTitlesEnabled {
                        Text("Your Hub accepts session titles. Each computer still chooses whether to share them.")
                    } else {
                        Text("Title sync is not enabled on the server.")
                    }
                } else {
                    Text("Update the server to enable these options.")
                }
            case .unsupported:
                Text("Update the server to enable these options.")
            case .loading:
                Text("Checking sync options…")
            case .failed:
                Text("Could not check whether this Hub syncs session titles.")
            case .unknown:
                EmptyView()
            }
        }
    }

    /// Reads the capabilities once per Hub (and again after five minutes);
    /// `HubInfoStore.load` joins a read already running.
    private func loadCapabilities() async {
        guard let connection = model.connection else { return }
        let info = model.hubInfo
        if info.syncContent != nil, let loadedAt = info.loadedAt, Date().timeIntervalSince(loadedAt) < 300 { return }
        await info.load(connection: connection)
    }

    private func preference<Value>(_ keyPath: WritableKeyPath<DisplayPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: { value in model.updatePreferences { $0[keyPath: keyPath] = value } }
        )
    }
}

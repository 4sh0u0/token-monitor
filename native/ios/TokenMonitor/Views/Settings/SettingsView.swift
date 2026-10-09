import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsDisconnect = false

    var body: some View {
        NavigationStack {
            Form {
                HubConnectionForm()
                if model.isConfigured {
                    ConnectionStatusSection()
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
            .scrollContentBackground(.hidden)
            .background {
                TMBackground().ignoresSafeArea()
            }
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
}

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
        } header: {
            Text("Status")
        }
        .listRowBackground(TMTheme.card)
    }
}

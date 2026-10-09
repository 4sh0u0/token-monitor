import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Hub URL + secret, with "Test connection" and "Save". Used by onboarding
/// and the Settings tab; produces `Form` sections.
struct HubConnectionForm: View {
    @Environment(AppModel.self) private var model
    @State private var urlText = ""
    @State private var secret = ""
    @State private var revealsSecret = false
    @State private var test: TestState = .idle
    @State private var testTask: Task<Void, Never>? = nil
    @State private var saveError: String? = nil
    @State private var didSave = false
    @State private var didLoad = false
    @FocusState private var focus: Field?

    enum TestState: Equatable {
        case idle
        case running
        case succeeded(summary: String)
        case failed(HubIssue)
    }

    enum Field: Hashable {
        case url
        case secret
    }

    /// The connection the fields describe, nil while the URL is not usable.
    private var candidate: HubConnection? {
        try? HubConnection(userInput: urlText, secret: secret)
    }

    private var hasChanges: Bool {
        guard let candidate else { return false }
        return candidate != model.connection
    }

    var body: some View {
        Section {
            TextField("Hub URL", text: $urlText, prompt: Text(verbatim: "192.168.1.10:17321"))
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .url)
                .submitLabel(.next)
                .onSubmit { focus = .secret }
            secretField
            if let candidate, candidate.isInsecureRemote {
                InsecureHubWarning()
            } else if !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, candidate == nil {
                Label("Enter an http:// or https:// address.", systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(TMTheme.critical)
            }
        } header: {
            Text("Hub")
        } footer: {
            Text("Addresses on your local network or tailnet use http:// unless you type https://.")
        }
        .listRowBackground(TMTheme.card)
        .onAppear(perform: loadSavedValues)
        .onChange(of: urlText) { _, _ in resetFeedback() }
        .onChange(of: secret) { _, _ in resetFeedback() }

        Section {
            Button(action: runTest) {
                HStack {
                    Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    if test == .running {
                        ProgressView()
                    }
                }
            }
            .disabled(candidate == nil || test == .running)
            TestResultRow(state: test)
            Button(action: save) {
                // Text values, not a ternary of literals: that would pick
                // Label's unlocalized String initializer.
                if didSave && !hasChanges {
                    Label { Text("Saved") } icon: { Image(systemName: "checkmark") }
                } else {
                    Label { Text("Save") } icon: { Image(systemName: "square.and.arrow.down") }
                }
            }
            .disabled(!hasChanges)
        } footer: {
            if let saveError {
                Text(verbatim: saveError)
                    .foregroundStyle(TMTheme.critical)
            }
        }
        .listRowBackground(TMTheme.card)
        .onDisappear {
            testTask?.cancel()
        }
    }

    @ViewBuilder
    private var secretField: some View {
        HStack {
            Group {
                if revealsSecret {
                    TextField("Secret", text: $secret, prompt: Text("Optional"))
                } else {
                    SecureField("Secret", text: $secret, prompt: Text("Optional"))
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focus, equals: .secret)
            .submitLabel(.done)
            .onSubmit { focus = nil }
            Button {
                revealsSecret.toggle()
            } label: {
                Image(systemName: revealsSecret ? "eye.slash" : "eye")
                    .foregroundStyle(TMTheme.muted)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(revealsSecret ? Text("Hide secret") : Text("Show secret"))
        }
    }

    private func loadSavedValues() {
        guard !didLoad else { return }
        didLoad = true
        if let connection = model.connection {
            urlText = connection.baseURL.absoluteString
            secret = connection.secret
        } else if let url = model.savedBaseURL {
            urlText = url.absoluteString
        }
    }

    private func resetFeedback() {
        if test != .running { test = .idle }
        saveError = nil
    }

    private func runTest() {
        guard let candidate else { return }
        focus = nil
        testTask?.cancel()
        test = .running
        testTask = Task {
            do {
                let health = try await HubClient(connection: candidate).verify()
                guard !Task.isCancelled else { return }
                test = .succeeded(summary: Self.summary(of: health))
            } catch is CancellationError {
                test = .idle
            } catch {
                guard !Task.isCancelled else { return }
                test = .failed(HubIssue(error: error, connection: candidate))
            }
        }
    }

    private func save() {
        guard let candidate else { return }
        do {
            try model.save(candidate)
            // Show what was saved: the normalized URL, with the scheme it got.
            urlText = candidate.baseURL.absoluteString
            saveError = nil
            didSave = true
            focus = nil
        } catch {
            saveError = HubIssue(error: error, connection: candidate).message
        }
    }

    private static func summary(of health: HubHealth) -> String {
        let runtime = AppFormat.runtimeName(health.runtime)
        guard let devices = health.deviceCount else { return runtime }
        let count = String(devices)
        return String(localized: "\(runtime) · Devices: \(count)")
    }
}

private struct TestResultRow: View {
    let state: HubConnectionForm.TestState

    var body: some View {
        switch state {
        case .idle, .running:
            EmptyView()
        case .succeeded(let summary):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected")
                        .foregroundStyle(TMTheme.text)
                    Text(verbatim: summary)
                        .font(.caption)
                        .foregroundStyle(TMTheme.muted)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(TMTheme.success)
            }
            .accessibilityElement(children: .combine)
        case .failed(let issue):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: issue.title)
                        .foregroundStyle(TMTheme.text)
                    Text(verbatim: issue.message)
                        .font(.caption)
                        .foregroundStyle(TMTheme.muted)
                    if let detail = issue.detail, !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(.caption2)
                            .foregroundStyle(TMTheme.muted)
                    }
                }
            } icon: {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(TMTheme.critical)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Plain HTTP to a host off the local network: the secret and usage would
/// cross the internet unencrypted.
struct InsecureHubWarning: View {
    var body: some View {
        Label {
            Text("This address uses plain HTTP over the internet, so the secret and your usage travel unencrypted. Use https:// unless the Hub is on your own network.")
                .font(.footnote)
                .foregroundStyle(TMTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(TMTheme.warning)
        }
    }
}

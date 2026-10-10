import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Settings › Data export: the desktop's file set
/// (`token-monitor-export.json`, `token-monitor-snapshot.csv`, and the daily
/// and daily-models CSVs when the Hub has History), built from the Hub's raw
/// stats and History by `ExportService` and handed to the share sheet.
///
/// As on the desktop the export covers every device, model ids stay raw and
/// costs stay in USD whatever the display currency. The files are
/// temporary: the next export, or the next visit to this screen, removes
/// them. They are not removed when the screen goes away, because the share
/// sheet may still be reading them.
struct ExportView: View {
    @Environment(AppModel.self) private var model
    @State private var exportTask: Task<Void, Never>?

    var body: some View {
        let exporter = model.exporter
        Form {
            Section {
                Button {
                    startExport()
                } label: {
                    HStack(spacing: 10) {
                        if exporter.files.isEmpty {
                            Label("Create Export", systemImage: "doc.badge.arrow.up")
                        } else {
                            Label("Create Again", systemImage: "arrow.clockwise")
                        }
                        Spacer(minLength: 8)
                        if exporter.isExporting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(exporter.isExporting || model.connection == nil)
                if model.connection == nil {
                    Text("No Hub connected")
                        .foregroundStyle(TMTheme.muted)
                }
                if !exporter.files.isEmpty, !exporter.isExporting {
                    ShareLink(items: exporter.files) {
                        Label("Share Files", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Data export")
            } footer: {
                Text("Export to CSV / JSON — open in Excel, or feed Obsidian and scripts.")
            }
            .listRowBackground(TMTheme.card)

            if let failure = exporter.lastError, !exporter.isExporting {
                Section {
                    ExportFailureRow(failure: failure, connection: model.connection)
                }
                .listRowBackground(TMTheme.card)
            }

            if !exporter.files.isEmpty, !exporter.isExporting {
                Section {
                    ForEach(exporter.files, id: \.self) { url in
                        LabeledContent {
                            Text(verbatim: ExportFileInfo.size(of: url))
                                .monospacedDigit()
                                .foregroundStyle(TMTheme.muted)
                        } label: {
                            Label {
                                Text(verbatim: url.lastPathComponent)
                                    .font(.subheadline.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } icon: {
                                Image(systemName: url.pathExtension.lowercased() == "json" ? "curlybraces" : "tablecells")
                                    .foregroundStyle(TMTheme.muted)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Files")
                } footer: {
                    if let generatedAt = exporter.generatedAt {
                        Text("Created \(generatedAt.formatted(date: .omitted, time: .shortened)).")
                    }
                }
                .listRowBackground(TMTheme.card)
            }

            Section {
                Label {
                    Text("Costs are always in USD, as on the desktop, whatever currency the app shows. The export covers every device on the Hub.")
                        .font(.footnote)
                        .foregroundStyle(TMTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "dollarsign.circle")
                        .foregroundStyle(TMTheme.muted)
                }
            }
            .listRowBackground(TMTheme.card)
        }
        .scrollContentBackground(.hidden)
        .background {
            TMBackground().ignoresSafeArea()
        }
        .navigationTitle("Data export")
        .onAppear {
            // A visit starts from nothing rather than offering an old export.
            let exporter = model.exporter
            if !exporter.isExporting, !exporter.files.isEmpty || exporter.lastError != nil {
                exporter.clear()
            }
        }
        .onDisappear {
            exportTask?.cancel()
            exportTask = nil
        }
    }

    private func startExport() {
        guard !model.exporter.isExporting else { return }
        let connection = model.connection
        let exporter = model.exporter
        exportTask = Task {
            // Failures land in `exporter.lastError`.
            _ = try? await exporter.makeFiles(connection: connection)
            exportTask = nil
        }
    }
}

/// Why the export failed (`settings.export.manualFailed` plus the reason).
private struct ExportFailureRow: View {
    let failure: ExportService.Failure
    let connection: HubConnection?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Export failed")
                    .foregroundStyle(TMTheme.text)
                Text(verbatim: reason)
                    .font(.caption)
                    .foregroundStyle(TMTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(TMTheme.warning)
        }
        .accessibilityElement(children: .combine)
    }

    private var reason: String {
        switch failure {
        case .notConfigured:
            return String(localized: "No Hub connected")
        case .hub(let error):
            let issue = HubIssue(error: error, connection: connection)
            return "\(issue.title). \(issue.message)"
        case .invalidStats:
            return String(localized: "The Hub’s usage data could not be read.")
        case .invalidHistory:
            return String(localized: "The Hub’s history could not be read.")
        case .write(let detail):
            return String(localized: "The files could not be saved: \(detail)")
        }
    }
}

/// A written file's size for the list ("12 KB").
private enum ExportFileInfo {
    static func size(of url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

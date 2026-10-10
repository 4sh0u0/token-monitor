import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Settings › Hub: what the connected Hub is and what it shares, read-only.
/// - `GET /api/health`: the runtime, the device count and the `hubBuild`
///   core and runtime revisions, or "Legacy Hub" when the Hub predates them
///   (no comparison with the desktop's build registry).
/// - `GET /api/sync/content`: whether the Hub accepts session titles and
///   stores the shared settings groups.
/// - The model aliases the app applies (`AppModel.aliasDocument`): how many,
///   and the automatic grouping.
/// - `GET /api/sync/settings/customPricing`: the shared price overrides.
struct HubInfoView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            if let connection = model.connection {
                hubSection(connection)
                syncSection
                aliasSection
                pricingSection
            } else {
                Section {
                    Text("No Hub connected")
                        .foregroundStyle(TMTheme.muted)
                }
                .listRowBackground(TMTheme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background {
            TMBackground().ignoresSafeArea()
        }
        .navigationTitle("Hub")
        .refreshable {
            await model.hubInfo.load(connection: model.connection)
        }
        .task(id: model.connection?.snapshotKey) {
            await model.hubInfo.load(connection: model.connection)
        }
    }

    // MARK: Hub

    private func hubSection(_ connection: HubConnection) -> some View {
        let info = model.hubInfo
        let health = info.health
        return Section {
            LabeledContent("Hub URL") {
                Text(verbatim: connection.displayHost)
                    .textSelection(.enabled)
            }
            if let health {
                LabeledContent("Runtime") {
                    Text(HubInfoText.runtimeName(health.runtime))
                }
                LabeledContent("Devices") {
                    Text(verbatim: "\(health.deviceCount ?? model.stats?.devices.count ?? 0)")
                        .monospacedDigit()
                }
                if info.isLegacyHub {
                    LabeledContent("Hub build") {
                        Text("Legacy Hub")
                            .foregroundStyle(TMTheme.warning)
                    }
                } else {
                    if let core = health.coreRevision {
                        LabeledContent("Core revision") {
                            Text(verbatim: "\(core)")
                                .monospacedDigit()
                        }
                    }
                    if let runtime = health.runtimeRevision {
                        LabeledContent("Runtime revision") {
                            Text(verbatim: "\(runtime)")
                                .monospacedDigit()
                        }
                    }
                }
            } else {
                HubInfoStatusRow(status: info.healthStatus, connection: connection)
            }
        } header: {
            Text("Hub")
        } footer: {
            if let health, info.isLegacyHub {
                let target = HubInfoText.runtimeName(health.runtime)
                Text("\(target) update available — redeploy to get the latest Hub build")
            }
        }
        .listRowBackground(TMTheme.card)
    }

    // MARK: Sync capabilities

    private var syncSection: some View {
        let info = model.hubInfo
        return Section {
            if let content = info.syncContent, content.isSupported {
                LabeledContent("Session titles") {
                    HubInfoText.enabled(content.sessionTitlesEnabled)
                }
                LabeledContent("Model aliases and grouping") {
                    HubInfoText.enabled(content.sharedSettings)
                }
                LabeledContent("Custom pricing") {
                    HubInfoText.enabled(content.sharedSettings)
                }
            } else if info.syncContentStatus == .unsupported || info.syncContent != nil {
                Text("Update the server to enable these options.")
                    .foregroundStyle(TMTheme.muted)
            } else {
                HubInfoStatusRow(status: info.syncContentStatus, connection: model.connection)
            }
        } header: {
            Text("Additional sync")
        } footer: {
            if let content = info.syncContent, content.isSupported, !content.sessionTitlesEnabled {
                Text("Title sync is not enabled on the server.")
            } else {
                Text("Usage, cost, tool limits and subscriptions sync automatically.")
            }
        }
        .listRowBackground(TMTheme.card)
    }

    // MARK: Model aliases

    private var aliasSection: some View {
        let document = model.aliasDocument
        let count = document?.aliases.count ?? 0
        return Section {
            LabeledContent("Aliases") {
                if count > 0 {
                    Text("\(count) alias(es)")
                } else {
                    Text("None")
                }
            }
            LabeledContent("Automatic grouping") {
                Text(HubInfoText.groupingName(document?.grouping ?? .off))
            }
        } header: {
            Text("Model aliases")
        } footer: {
            Text("Use the same model names and groups on your devices.")
        }
        .listRowBackground(TMTheme.card)
    }

    // MARK: Custom pricing

    private var pricingSection: some View {
        let info = model.hubInfo
        let entries = info.customPricingEntries
        return Section {
            switch info.customPricingStatus {
            case .available:
                if entries.isEmpty {
                    Text("No overrides yet.")
                        .foregroundStyle(TMTheme.muted)
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: entry.modelId)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TMTheme.text)
                                .textSelection(.enabled)
                            let meta = HubInfoText.pricingMeta(entry)
                            if !meta.isEmpty {
                                Text(verbatim: meta)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(TMTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                }
            case .unsupported:
                Text("Update the server to enable these options.")
                    .foregroundStyle(TMTheme.muted)
            default:
                HubInfoStatusRow(status: info.customPricingStatus, connection: model.connection)
            }
        } header: {
            HStack {
                Text("Custom model pricing")
                Spacer()
                if info.customPricingStatus == .available {
                    if entries.isEmpty {
                        Text("None")
                    } else {
                        Text("\(entries.count) override(s)")
                    }
                }
            }
        } footer: {
            Text("Rates · USD / 1M tokens. Change them in Token Monitor on a computer.")
        }
        .listRowBackground(TMTheme.card)
    }
}

/// A read that has not produced a value: loading, failed (with the reason)
/// or not asked yet.
private struct HubInfoStatusRow: View {
    let status: HubInfoStore.Availability
    let connection: HubConnection?

    var body: some View {
        switch status {
        case .loading, .unknown:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading…")
                    .foregroundStyle(TMTheme.muted)
            }
        case .failed(let error):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    let issue = HubIssue(error: error, connection: connection)
                    Text(issue.title)
                        .foregroundStyle(TMTheme.text)
                    Text(issue.message)
                        .font(.caption)
                        .foregroundStyle(TMTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(TMTheme.warning)
            }
        case .unsupported:
            Text("Update the server to enable these options.")
                .foregroundStyle(TMTheme.muted)
        case .available:
            EmptyView()
        }
    }
}

/// The Hub screen's wording.
enum HubInfoText {
    /// `hubBuildPresentation.targetKey`: "Node Hub", "Cloudflare Worker" or
    /// "Hub".
    static func runtimeName(_ runtime: String?) -> String {
        switch runtime {
        case "node-hub": return String(localized: "Node Hub")
        case "cloudflare-worker": return String(localized: "Cloudflare Worker")
        default: return String(localized: "Hub")
        }
    }

    /// A capability's state.
    static func enabled(_ isEnabled: Bool) -> Text {
        isEnabled ? Text("Enabled") : Text("Disabled")
    }

    static func groupingName(_ grouping: ModelAliasGrouping) -> String {
        switch grouping {
        case .off: return String(localized: "Off")
        case .duplicates: return String(localized: "Merge duplicates")
        case .prefix: return String(localized: "Strip prefixes")
        }
    }

    /// `customPricingMeta`: the rates the override sets, in the desktop's
    /// order, `$` amounts per 1M tokens.
    static func pricingMeta(_ entry: CustomPricingEntry) -> String {
        let rates: [(String, Double?)] = [
            (String(localized: "Input (cache hit)"), entry.cacheReadPerM),
            (String(localized: "Input (cache miss)"), entry.inputPerM),
            (String(localized: "Output"), entry.outputPerM),
            (String(localized: "Cache write"), entry.cacheWritePerM),
            (String(localized: "Cache write (1 hour)"), entry.cacheWrite1hPerM)
        ]
        let parts = rates.compactMap { name, value in
            value.map { "\(name) $\(JSCompat.numberString($0))" }
        }
        return parts.isEmpty ? "" : "\(parts.joined(separator: " · ")) / 1M"
    }
}

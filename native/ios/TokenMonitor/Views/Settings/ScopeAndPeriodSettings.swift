import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Settings › Device scope and periods: the device scope (D-SCOPE), the
/// Overview's middle period (`periodMonthMode`) and the live token rate
/// (on/off, speed or burn, all devices or the selected device; D-LIVESCOPE).
struct ScopeAndPeriodSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            DeviceScopeSection()
            Section {
                Picker("Default usage range", selection: model.displayPreference(\.periodMonthMode)) {
                    ForEach(PeriodMonthMode.allCases) { mode in
                        Text(PeriodSelection.middle(for: mode).title)
                            .tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Default usage range")
            } footer: {
                Text("The middle choice of the Overview’s period picker. This week, Last 7 days and Last 30 days are built from the Hub’s history.")
            }
            .listRowBackground(TMTheme.card)
            LiveRateSection()
        }
        .settingsListBackground()
        .navigationTitle("Device scope and periods")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// All devices, or one device by Hub id. Lists every device the Hub knows
/// (online first), and keeps a scoped device the Hub no longer lists
/// selectable so the choice stays visible ("Device not found").
private struct DeviceScopeSection: View {
    @Environment(AppModel.self) private var model

    private var devices: [DeviceSummary] {
        let all = model.presented?.stats.devices ?? model.stats?.devices ?? []
        return all.sorted { lhs, rhs in
            if lhs.isStale != rhs.isStale { return !lhs.isStale }
            let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }

    /// The scoped device id when the Hub does not list it.
    private var missingDeviceID: String? {
        guard let id = model.preferences.deviceScope.deviceID,
              !devices.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    var body: some View {
        Section {
            Picker("Device scope", selection: scopeBinding) {
                Label {
                    Text("All devices")
                } icon: {
                    Image(systemName: "square.stack.3d.up")
                }
                .tag(DeviceScope.all)
                ForEach(devices) { device in
                    DeviceScopeOption(device: device)
                        .tag(DeviceScope.device(device.id))
                }
                if let missingDeviceID {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Device not found")
                            Text(verbatim: missingDeviceID)
                                .font(.caption)
                                .foregroundStyle(TMTheme.muted)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(TMTheme.warning)
                    }
                    .tag(DeviceScope.device(missingDeviceID))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Device scope")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Totals, tools, models, sessions, projects, activity and trends follow the scope, and so do the widgets and Apple Watch. Limits and the Devices tab always show every device.")
                if devices.isEmpty {
                    Text("Devices appear here once Token Monitor or the headless agent on a computer syncs with this Hub.")
                }
            }
        }
        .listRowBackground(TMTheme.card)
    }

    private var scopeBinding: Binding<DeviceScope> {
        Binding(
            get: { model.preferences.deviceScope },
            set: { model.setDeviceScope($0) }
        )
    }
}

/// A device in the scope picker: OS mark, name, "Offline" when stale.
private struct DeviceScopeOption: View {
    let device: DeviceSummary

    var body: some View {
        Label {
            HStack(spacing: 6) {
                Text(verbatim: device.displayName)
                    .lineLimit(1)
                if device.isStale {
                    Text("Offline")
                        .font(.caption)
                        .foregroundStyle(TMTheme.staleMuted)
                }
            }
        } icon: {
            VendorMark(
                .operatingSystem(iconAssetName: DevicePresentation.osIconAssetName(platform: device.platform)),
                size: 16,
                muted: device.isStale
            )
        }
    }
}

/// `showLiveTokenRate`, `tokenRateMode` and `liveTokenRateScope`. The scope
/// "Selected device" needs a device scope; without one it reads as all
/// devices and cannot be chosen.
private struct LiveRateSection: View {
    @Environment(AppModel.self) private var model

    private var hasDeviceScope: Bool { !model.preferences.deviceScope.isAll }

    var body: some View {
        Section {
            Toggle("Show live token rate", isOn: model.displayPreference(\.showLiveTokenRate))
            if model.preferences.showLiveTokenRate {
                Picker("Rate", selection: model.displayPreference(\.tokenRateMode)) {
                    Text("Generation speed (tok/s)").tag(TokenRateMode.speed)
                    Text("Token burn (TPM)").tag(TokenRateMode.burn)
                }
                Picker("Live rate scope", selection: scopeBinding) {
                    Text("All devices").tag(LiveRateScope.all)
                    Text("Selected device").tag(LiveRateScope.device)
                }
                .disabled(!hasDeviceScope)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Shows the latest generation speed on the Overview. Tap it there to switch between tok/s and TPM.")
                if model.preferences.showLiveTokenRate {
                    if model.preferences.appRefreshSeconds != .live {
                        Text("The live token rate appears only while App updates is set to Live.")
                    }
                    if !hasDeviceScope {
                        Text("Choose a device scope to use Selected device.")
                    }
                }
            }
        }
        .listRowBackground(TMTheme.card)
    }

    private var scopeBinding: Binding<LiveRateScope> {
        Binding(
            get: { hasDeviceScope ? model.preferences.liveTokenRateScope : .all },
            set: { scope in model.updatePreferences { $0.liveTokenRateScope = scope } }
        )
    }
}

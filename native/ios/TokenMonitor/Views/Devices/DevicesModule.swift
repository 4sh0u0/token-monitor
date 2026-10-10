import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The Overview's Devices module (`renderHomeDeviceModule`): the top four
/// devices of the Overview period by tokens, with their OS mark and compact
/// total; stale devices dimmed. A row opens the device; "Show all" opens the
/// Devices tab. Like the desktop module it lists every device, whatever the
/// device scope.
///
/// A self-contained card, like the other Overview modules. Draws nothing
/// before the first stats, and when no device used tokens in the period (the
/// desktop then says `home.noDevices`); a fixed range shows its loading /
/// unavailable note until every device's range is ready.
struct DevicesModule: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let presented = model.presented, !presented.stats.devices.isEmpty {
            let selection = model.selectedPeriod
            let content = DevicePeriods.homeRows(devices: presented.stats.devices, selection: selection, history: model.history)
            Group {
                if Self.draws(content) {
                    CardContainer {
                        VStack(alignment: .leading, spacing: 10) {
                            ModuleHeader(title: "Devices") {
                                Button {
                                    model.selectedTab = .devices
                                } label: {
                                    Text("Show all")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.borderless)
                                .tint(TMTheme.accent)
                            }
                            if let state = content.state {
                                PeriodUsageNote(state: state)
                            } else {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(content.rows) { row in
                                        NavigationLink(value: AppRoute.deviceDetail(row.id)) {
                                            DeviceModuleRowView(
                                                row: row,
                                                isScoped: row.id == model.preferences.deviceScope.deviceID
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .onAppear {
                DevicePeriods.requestRecordsIfNeeded(for: selection, history: model.history)
            }
            .onChange(of: model.selectedPeriod) { _, next in
                DevicePeriods.requestRecordsIfNeeded(for: next, history: model.history)
            }
        }
    }
}

extension DevicesModule {
    /// The module has something to show: its rows, or the note of a fixed
    /// range that is loading or unavailable.
    static func draws(_ content: DeviceHomeRows) -> Bool {
        content.state != nil || !content.rows.isEmpty
    }

    /// Whether the module draws anything for the current stats and period.
    @MainActor
    static func draws(_ model: AppModel) -> Bool {
        guard let devices = model.presented?.stats.devices, !devices.isEmpty else { return false }
        return draws(DevicePeriods.homeRows(devices: devices, selection: model.selectedPeriod, history: model.history))
    }
}

/// OS mark, name and compact tokens; a stale device is dimmed and says
/// "Offline" (the desktop's `home.staleDevice` tooltip; a phone has no hover).
private struct DeviceModuleRowView: View {
    @Environment(\.tmFormatter) private var formatter
    let row: DeviceHomeRow
    let isScoped: Bool

    var body: some View {
        HStack(spacing: 10) {
            DeviceOSMark(platform: row.platform, isStale: row.isStale, size: 16)
            Text(verbatim: row.name)
                .font(.subheadline)
                .foregroundStyle(row.isStale ? TMTheme.staleMuted : TMTheme.text)
                .lineLimit(1)
            if isScoped {
                DeviceScopeMark()
            }
            if row.isStale {
                Text("Offline")
                    .font(.caption2)
                    .foregroundStyle(TMTheme.staleMuted)
            }
            Spacer(minLength: 8)
            Text(verbatim: formatter.compactTokens(row.tokens))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(row.isStale ? TMTheme.staleMuted : TMTheme.number)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TMTheme.muted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

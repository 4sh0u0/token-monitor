import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// One device (`AppRoute.deviceDetail`): what it runs and when it last
/// synced, its tools and models for the app's period, each tool's status and
/// health, and the button that scopes the app to it.
///
/// Mirrors the desktop's device row detail (`deviceRowsForPeriod`,
/// `renderDeviceAccordion`) and its Settings › Tools health panel, which the
/// desktop only shows for itself.
struct DeviceDetailView: View {
    @Environment(AppModel.self) private var model
    let deviceID: String

    var body: some View {
        ScreenScrollView {
            if let presented = model.presented {
                if let device = presented.stats.device(id: deviceID) {
                    StatusBanner()
                    DeviceDetailContent(device: device)
                } else {
                    ContentUnavailableView {
                        Label("Device not found", systemImage: "laptopcomputer.slash")
                    } description: {
                        Text("This device is no longer on your Hub.")
                    }
                    .padding(.top, 48)
                }
            } else {
                DataPlaceholder()
            }
        }
        .navigationTitle(Text(verbatim: model.presented?.stats.device(id: deviceID)?.displayName ?? deviceID))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            DevicePeriods.requestRecordsIfNeeded(for: model.selectedPeriod, history: model.history)
        }
        .onChange(of: model.selectedPeriod) { _, selection in
            DevicePeriods.requestRecordsIfNeeded(for: selection, history: model.history)
        }
    }
}

private struct DeviceDetailContent: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let device: DeviceSummary

    var body: some View {
        DeviceHeaderCard(device: device)
        // Side by side on iPad, when the device reports any tool status.
        if sizeClass == .regular && !ClientHealthPresentation.toolStatuses(device: device).isEmpty {
            HStack(alignment: .top, spacing: 16) {
                DeviceUsageSection(device: device)
                    .frame(maxWidth: .infinity, alignment: .top)
                DeviceToolHealthSection(device: device)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        } else {
            DeviceUsageSection(device: device)
            DeviceToolHealthSection(device: device)
        }
    }
}

// MARK: - Header

/// Name, online state and scope; OS, runtime and version, upload interval,
/// "Synced …"; the scope button.
private struct DeviceHeaderCard: View {
    @Environment(AppModel.self) private var model
    let device: DeviceSummary

    var body: some View {
        let meta = DevicePresentation.meta(device)
        let isScoped = model.preferences.deviceScope.deviceID == device.id
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    DeviceOSMark(platform: device.platform, isStale: device.isStale, size: 32)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: device.displayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(device.isStale ? TMTheme.staleMuted : TMTheme.text)
                            .lineLimit(3)
                            .accessibilityAddTraits(.isHeader)
                        HStack(spacing: 6) {
                            OnlineTag(isStale: device.isStale)
                            if isScoped {
                                DeviceScopeMark()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 8) {
                        if let system = meta.operatingSystem {
                            MetaRow(title: "Operating system", value: system)
                        }
                        if let runtime = DeviceWording.runtime(meta) {
                            MetaRow(title: "Runtime", value: runtime)
                        }
                        if let interval = DeviceWording.uploadInterval(meta.uploadInterval) {
                            MetaRow(title: "Sync upload frequency", value: interval)
                        }
                        if let synced = DeviceWording.synced(meta, now: context.date) {
                            Text(verbatim: synced)
                                .font(.footnote)
                                .foregroundStyle(device.isStale ? TMTheme.warning : TMTheme.muted)
                        }
                    }
                }
                Divider().overlay(TMTheme.divider)
                ScopeControl(device: device, isScoped: isScoped)
            }
        }
    }
}

/// "Online" in mint, or "Offline" in the stale grey (`home.staleDevice`).
private struct OnlineTag: View {
    let isStale: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isStale ? TMTheme.staleMuted : TMTheme.success)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Group {
                if isStale {
                    Text("Offline")
                } else {
                    Text("Online")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(isStale ? TMTheme.staleMuted : TMTheme.success)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A label and its value on one line (stacked at accessibility sizes).
private struct MetaRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(TMTheme.muted)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            Text(verbatim: value)
                .font(.subheadline)
                .foregroundStyle(TMTheme.text)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Show only this device" scopes every usage surface to the device;
/// "Show all devices" undoes it (`setDeviceScope`).
private struct ScopeControl: View {
    @Environment(AppModel.self) private var model
    let device: DeviceSummary
    let isScoped: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                model.setDeviceScope(isScoped ? .all : .device(device.id))
            } label: {
                Label {
                    if isScoped {
                        Text("Show all devices")
                    } else {
                        Text("Show only this device")
                    }
                } icon: {
                    Image(systemName: isScoped ? "square.stack.3d.up" : "scope")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(TMTheme.accent)
            Text("The Overview, widgets and Apple Watch follow the device scope. Limits and the Devices tab always show every device.")
                .font(.caption)
                .foregroundStyle(TMTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Usage

/// The period switch, the device's total and cost, a tool bar, and each tool
/// with its share, tokens and (expandable) models.
private struct DeviceUsageSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmFormatter) private var formatter
    @Environment(\.tmPresentation) private var presentation
    let device: DeviceSummary

    var body: some View {
        let selection = model.selectedPeriod
        let figures = DevicePeriods.figures(device, selection: selection, history: model.history)
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                ModuleHeader(title: "Usage")
                DevicePeriodPicker()
                switch figures.availability {
                case .loading:
                    PeriodLoadingNote()
                case .unavailable(let reason):
                    PeriodUnavailableNote(reason: reason)
                case .ready:
                    total(figures, selection: selection)
                    breakdown(figures)
                }
            }
        }
    }

    private func total(_ figures: DevicePeriodFigures, selection: PeriodSelection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: selection.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(TMTheme.muted)
            Text(verbatim: formatter.fullTokens(figures.tokens))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(TMTheme.number)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            CostLabelText(usd: figures.costUsd, unpricedTokens: figures.unpricedTokens)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(TMTheme.muted)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func breakdown(_ figures: DevicePeriodFigures) -> some View {
        let breakdown = figures.breakdown
        if let empty = breakdown.emptyState {
            Text(DeviceWording.emptyBreakdown(empty))
                .font(.footnote)
                .foregroundStyle(TMTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            UsageBar(
                segments: breakdown.tools.map { tool in
                    UsageBar.Segment(
                        id: tool.id,
                        value: Double(tool.tokens),
                        color: VendorColor.color(for: tool.id, palette: presentation.palette)
                    )
                },
                total: Double(breakdown.totalTokens)
            )
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(breakdown.tools.enumerated()), id: \.element.id) { index, tool in
                    if index > 0 {
                        Divider().overlay(TMTheme.divider)
                    }
                    DeviceToolRowView(tool: tool)
                        .padding(.vertical, 8)
                }
            }
            // The device sent tokens per tool but no per-tool models (a fixed
            // range never has them, as on the desktop).
            if !breakdown.modelsAvailable && !figures.isDerived {
                Text(DeviceWording.emptyBreakdown(.detailsUnavailable))
                    .font(.caption)
                    .foregroundStyle(TMTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A tool of the device's period: mark, name, rounded share and full count;
/// expands to its models (compact counts) when the device sent them.
private struct DeviceToolRowView: View {
    @Environment(\.tmFormatter) private var formatter
    let tool: DeviceToolRow
    @State private var isExpanded = false

    var body: some View {
        if tool.models.isEmpty {
            label
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tool.models) { model in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: model.model)
                                .font(.footnote)
                                .foregroundStyle(TMTheme.text)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Text(verbatim: formatter.compactTokens(model.tokens))
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(TMTheme.muted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.leading, 26)
                .padding(.top, 6)
            } label: {
                label
            }
            .tint(TMTheme.muted)
        }
    }

    private var label: some View {
        HStack(alignment: .center, spacing: 8) {
            VendorMark(.client(tool.id), size: 16)
            Text(verbatim: DeviceWording.toolName(tool))
                .font(.subheadline)
                .foregroundStyle(TMTheme.text)
                .lineLimit(1)
            Text(verbatim: DeviceWording.percent(tool.percent))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(TMTheme.muted)
            Spacer(minLength: 8)
            Text(verbatim: formatter.fullTokens(tool.tokens))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(TMTheme.text)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

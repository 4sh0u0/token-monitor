import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The Devices tab: every device on the Hub, online first, for the app's
/// period (including WEEK / 7D / 30D from each device's History record).
/// Never follows the device scope; the scoped device carries a mark. A row
/// opens `DeviceDetailView`.
///
/// Tab root: `RootView` owns the navigation stack.
struct DevicesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScreenScrollView {
            if let presented = model.presented {
                StatusBanner()
                DeviceList(devices: presented.stats.devices)
            } else {
                DataPlaceholder()
            }
        }
        .navigationTitle("Devices")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LiveStatusIndicator()
            }
        }
        .onAppear {
            DevicePeriods.requestRecordsIfNeeded(for: model.selectedPeriod, history: model.history)
        }
        .onChange(of: model.selectedPeriod) { _, selection in
            DevicePeriods.requestRecordsIfNeeded(for: selection, history: model.history)
        }
    }
}

/// The period switch, the online count and the Online / Offline sections
/// (`DevicePresentation.ordered`: most recent upload first).
private struct DeviceList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let devices: [DeviceSummary]

    var body: some View {
        if devices.isEmpty {
            EmptyStateCard(
                title: "No devices yet",
                message: "Devices appear here once Token Monitor or the headless agent on a computer syncs with this Hub.",
                systemImage: "laptopcomputer.slash"
            )
        } else {
            let selection = model.selectedPeriod
            let ordered = DevicePresentation.ordered(devices)
            let figures = Dictionary(
                ordered.map { ($0.id, DevicePeriods.figures($0, selection: selection, history: model.history)) },
                uniquingKeysWith: { first, _ in first }
            )
            let counts = DevicePresentation.onlineCount(devices)
            let scopedID = model.preferences.deviceScope.deviceID
            VStack(alignment: .leading, spacing: 16) {
                DevicePeriodPicker()
                HStack(spacing: 8) {
                    Text("\(counts.online)/\(counts.total) online")
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(TMTheme.muted)
                    Spacer(minLength: 8)
                    Text(verbatim: selection.title)
                        .font(.footnote)
                        .foregroundStyle(TMTheme.muted)
                }
                if selection.isDerived, let state = DevicePeriods.listState(Array(figures.values)) {
                    PeriodUsageNote(state: state)
                }
                // One clock for every "Synced …" on the page.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let online = ordered.filter { !$0.isStale }
                    let offline = ordered.filter(\.isStale)
                    let sections = [
                        DeviceSection(id: "online", title: Text("Online"), devices: online),
                        DeviceSection(id: "offline", title: Text("Offline"), devices: offline),
                    ].filter { !$0.devices.isEmpty }
                    if sizeClass == .regular && sections.count > 1 {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(sections) { section in
                                sectionView(section, figures: figures, scopedID: scopedID, now: context.date)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(sections) { section in
                                sectionView(section, figures: figures, scopedID: scopedID, now: context.date)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionView(
        _ section: DeviceSection,
        figures: [String: DevicePeriodFigures],
        scopedID: String?,
        now: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                section.title
                Text(verbatim: String(section.devices.count))
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TMTheme.muted)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            CardContainer(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(section.devices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 {
                            Divider()
                                .overlay(TMTheme.divider)
                                .padding(.leading, 52)
                        }
                        NavigationLink(value: AppRoute.deviceDetail(device.id)) {
                            DeviceListRow(
                                device: device,
                                figures: figures[device.id] ?? .pending(.loading),
                                isScoped: device.id == scopedID,
                                now: now
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct DeviceSection: Identifiable {
    let id: String
    let title: Text
    let devices: [DeviceSummary]
}

/// One device: OS mark, name (with the scope mark), platform and "Synced …",
/// then its tokens and cost for the period. Stale devices are dimmed.
private struct DeviceListRow: View {
    @Environment(\.tmFormatter) private var formatter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let device: DeviceSummary
    let figures: DevicePeriodFigures
    let isScoped: Bool
    let now: Date

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        HStack(spacing: 10) {
            layout {
                HStack(alignment: .center, spacing: 12) {
                    DeviceOSMark(platform: device.platform, isStale: device.isStale, size: 24)
                        .frame(width: 28)
                    identity
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 4)
                }
                usage
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TMTheme.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var identity: some View {
        let meta = DevicePresentation.meta(device)
        let subtitle = [meta.operatingSystem, DeviceWording.synced(meta, now: now)]
            .compactMap { $0 }
            .joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(verbatim: device.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(device.isStale ? TMTheme.staleMuted : TMTheme.text)
                    .lineLimit(2)
                if isScoped {
                    DeviceScopeMark()
                }
            }
            if !subtitle.isEmpty {
                Text(verbatim: subtitle)
                    .font(.caption)
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var usage: some View {
        let alignment: HorizontalAlignment = dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
        VStack(alignment: alignment, spacing: 2) {
            if figures.isReady {
                Text(verbatim: formatter.compactTokens(figures.tokens))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(device.isStale ? TMTheme.staleMuted : TMTheme.number)
                CostLabelText(usd: figures.costUsd, unpricedTokens: figures.unpricedTokens, compact: true)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.muted)
            } else {
                Text(verbatim: "—")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TMTheme.muted)
            }
        }
        .lineLimit(1)
        .opacity(device.isStale ? 0.75 : 1)
    }
}

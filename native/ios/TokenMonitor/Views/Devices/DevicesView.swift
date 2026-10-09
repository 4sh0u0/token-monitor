import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

struct DevicesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScreenScrollView {
                if let stats = model.stats {
                    StatusBanner()
                    DeviceSections(devices: stats.devices)
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
        }
    }
}

private struct DeviceSections: View {
    let devices: [DeviceSummary]
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if devices.isEmpty {
            EmptyStateCard(
                title: "No devices yet",
                message: "Devices appear here once Token Monitor or the headless agent on a computer syncs with this Hub.",
                systemImage: "laptopcomputer.slash"
            )
        } else {
            let online = devices.filter(\.isOnline)
            let offline = devices.filter(\.isStale)
            // One clock for every "last seen" on the page.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 20) {
                    if !online.isEmpty {
                        section(title: Text("Online"), devices: online, now: context.date)
                    }
                    if !offline.isEmpty {
                        section(title: Text("Offline"), devices: offline, now: context.date)
                    }
                }
            }
        }
    }

    private func section(title: Text, devices: [DeviceSummary], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                title
                Text(verbatim: String(devices.count))
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TMTheme.muted)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if sizeClass == .regular {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(devices) { device in
                        DeviceCard(device: device, now: now)
                    }
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(devices) { device in
                        DeviceCard(device: device, now: now)
                    }
                }
            }
        }
    }
}

struct DeviceCard: View {
    let device: DeviceSummary
    let now: Date

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: device.platformSymbol)
                        .font(.title3)
                        .foregroundStyle(device.isOnline ? TMTheme.accent : TMTheme.muted)
                        .frame(minWidth: 28)
                        .accessibilityHidden(true)
                    DeviceIdentity(device: device, now: now)
                    Spacer(minLength: 8)
                    DeviceTodayUsage(device: device)
                }
                if !device.trackedClients.isEmpty {
                    TrackedTools(ids: device.trackedClients)
                }
            }
        }
        .opacity(device.isOnline ? 1 : 0.8)
    }
}

private struct DeviceIdentity: View {
    let device: DeviceSummary
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: device.displayName)
                .font(.headline)
                .foregroundStyle(TMTheme.text)
                .lineLimit(2)
            if let system = device.operatingSystemDescription {
                Text(verbatim: system)
                    .font(.caption)
                    .foregroundStyle(TMTheme.muted)
            }
            if let lastSeen = device.lastSeen {
                Text("Last seen \(AppFormat.ago(lastSeen, now: now))")
                    .font(.caption)
                    .foregroundStyle(device.isOnline ? TMTheme.muted : TMTheme.warning)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DeviceTodayUsage: View {
    let device: DeviceSummary

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Today")
                .font(.caption2.weight(.medium))
                .foregroundStyle(TMTheme.muted)
            Text(verbatim: TokenFormat.compactTokens(device.todayTokens))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(TMTheme.number)
            Text(verbatim: TokenFormat.usd(device.todayCost))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(TMTheme.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The AI tools a device tracks, as coloured chips.
private struct TrackedTools: View {
    let ids: [String]

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(ids, id: \.self) { id in
                HStack(spacing: 5) {
                    MarkDot(color: VendorColor.color(for: id))
                    Text(verbatim: VendorCatalog.clientLabel(id))
                        .font(.caption)
                        .foregroundStyle(TMTheme.text)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(TMTheme.track, in: Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Tracked tools"))
        .accessibilityValue(Text(verbatim: ids.map(VendorCatalog.clientLabel).joined(separator: ", ")))
    }
}

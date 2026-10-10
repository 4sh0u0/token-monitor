import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The toolbar's device-scope menu: All devices or one device (online
/// devices first, then offline ones). The scope applies to every usage
/// surface, widgets and the watch included, but never to Limits or the
/// Devices tab. Hidden while the Hub lists a single device and nothing is
/// scoped.
struct DeviceScopeMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let devices = DevicePresentation.ordered(model.stats?.devices ?? [])
        let scope = model.preferences.deviceScope
        if devices.count > 1 || !scope.isAll {
            Menu {
                Picker(selection: scopeBinding) {
                    Label {
                        Text("All devices")
                    } icon: {
                        Image(systemName: "square.stack.3d.up")
                    }
                    .tag(DeviceScope.all)
                    ForEach(devices, id: \.id) { device in
                        deviceLabel(device)
                            .tag(DeviceScope.device(device.id))
                    }
                } label: {
                    Text("Device scope")
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: symbol(scope))
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel(Text("Device scope"))
            .accessibilityValue(scopeValue)
        }
    }

    private var scopeBinding: Binding<DeviceScope> {
        Binding(
            get: { model.preferences.deviceScope },
            set: { model.setDeviceScope($0) }
        )
    }

    /// The filter symbol, filled while one device is scoped; a warning while
    /// the scoped device is missing from the Hub.
    private func symbol(_ scope: DeviceScope) -> String {
        if model.presented?.isScopeMissing == true { return "exclamationmark.triangle" }
        return scope.isAll ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
    }

    private var scopeValue: Text {
        if let device = model.scopedDevice { return Text(verbatim: device.displayName) }
        if model.presented?.isScopeMissing == true { return Text("Device not found") }
        return Text("All devices")
    }

    private func deviceLabel(_ device: DeviceSummary) -> some View {
        Label {
            Text(verbatim: device.displayName)
            if device.isStale {
                Text("Offline")
            }
        } icon: {
            if let asset = DevicePresentation.osIconAssetName(platform: device.platform) {
                Image(asset)
                    .renderingMode(.template)
            } else {
                Image(systemName: "desktopcomputer")
            }
        }
    }
}

/// Under the toolbar while one device is scoped: whose usage this is, its
/// offline state and last sync, and a way back to every device. When the
/// scoped device has left the Hub, every surface shows all devices and this
/// says so.
struct ScopeNotice: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let presented = model.presented {
            if let device = presented.device {
                notice {
                    VendorMark(
                        .operatingSystem(iconAssetName: DevicePresentation.osIconAssetName(platform: device.platform)),
                        size: 16,
                        muted: device.isStale
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Showing usage from \(device.displayName)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(TMTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if device.isStale {
                            staleLine(device)
                        }
                    }
                }
            } else if presented.isScopeMissing {
                notice {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(TMTheme.warning)
                        .accessibilityHidden(true)
                    Text("The selected device is no longer on this Hub. Showing all devices.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(TMTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// "Offline · Last seen 5 min. ago".
    private func staleLine(_ device: DeviceSummary) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Group {
                if let lastSeen = device.lastSeen {
                    Text("Offline") + Text(verbatim: " · ") + Text("Last seen \(AppFormat.ago(lastSeen, now: context.date))")
                } else {
                    Text("Offline")
                }
            }
            .font(.caption)
            .foregroundStyle(TMTheme.staleMuted)
        }
    }

    private func notice<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let reset = Button {
            model.setDeviceScope(.all)
        } label: {
            Text("Show all devices")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderless)

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        content()
                    }
                    reset
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    content()
                    Spacer(minLength: 8)
                    reset
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TMTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(TMTheme.cardStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

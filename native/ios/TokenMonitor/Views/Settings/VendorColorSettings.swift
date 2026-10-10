import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Settings › Appearance › Vendor Colors: a colour override per vendor mark
/// with a brand colour, plus "Other tools" (`default`), as the desktop's
/// vendor colour list (`renderVendorColorList`). Overrides repaint dots,
/// bars and charts on every surface, widgets and watch included.
struct VendorColorSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.self) private var environment
    /// Picked colours not saved yet: a colour well reports every step of a
    /// drag, and each save reloads the widgets and messages the watch.
    @State private var drafts: [String: String] = [:]
    @State private var commitTask: Task<Void, Never>? = nil

    /// The picker's ids: every mark with a brand colour in the desktop
    /// picker's order, then `default` (`orderedVendorIds`).
    private static let ids: [String] = VendorCatalog.marks
        .filter { $0.brandColorHex != nil }
        .map(\.id) + [VendorPalette.defaultKey]

    private var palette: VendorPalette { model.context.palette }

    private var hasOverrides: Bool {
        !drafts.isEmpty || Self.ids.contains { palette.overrideHex(for: $0) != nil }
    }

    var body: some View {
        Form {
            Section {
                ForEach(Self.ids, id: \.self) { id in
                    row(id)
                }
            } footer: {
                Text("Override the chart and list colour for each tool. Reset returns it to the brand colour.")
            }
            .listRowBackground(TMTheme.card)
        }
        .settingsListBackground()
        .navigationTitle("Vendor Colors")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Reset all", action: resetAll)
                    .disabled(!hasOverrides)
            }
        }
        .onDisappear(perform: commitNow)
    }

    private func row(_ id: String) -> some View {
        let isCustom = drafts[id] != nil || palette.overrideHex(for: id) != nil
        let name = Self.name(of: id)
        return HStack(spacing: 10) {
            VendorMark(.client(id), size: 16)
            Text(name)
                .foregroundStyle(TMTheme.text)
                .lineLimit(1)
            if isCustom {
                Text("Custom")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TMTheme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay {
                        Capsule().strokeBorder(TMTheme.cardStroke, lineWidth: 1)
                    }
            }
            Spacer(minLength: 8)
            if isCustom {
                Button {
                    reset(id)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundStyle(TMTheme.muted)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Reset to brand"))
            }
            ColorPicker(selection: colorBinding(id), supportsOpacity: false) {
                Text(name)
            }
            .labelsHidden()
        }
        .accessibilityElement(children: .contain)
    }

    private func colorBinding(_ id: String) -> Binding<Color> {
        Binding(
            get: { Color(hex: drafts[id] ?? palette.brandHex(for: id)) },
            set: { color in
                drafts[id] = Self.hex(color.resolve(in: environment))
                scheduleCommit()
            }
        )
    }

    // MARK: Saving

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            commitNow()
        }
    }

    /// `saveVendorColor` for every pending colour, in one preferences write.
    private func commitNow() {
        commitTask?.cancel()
        commitTask = nil
        let pending = drafts
        guard !pending.isEmpty else { return }
        model.updatePreferences { preferences in
            for (id, hex) in pending {
                preferences.vendorColors[id] = hex
            }
        }
        drafts = [:]
    }

    /// `resetVendorColor`: back to the brand colour.
    private func reset(_ id: String) {
        commitNow()
        model.updatePreferences { $0.vendorColors.removeValue(forKey: id) }
    }

    private func resetAll() {
        commitTask?.cancel()
        commitTask = nil
        drafts = [:]
        model.updatePreferences { $0.vendorColors = [:] }
    }

    // MARK: Helpers

    /// The row's name: "Other tools" for `default`, else the mark's label
    /// (the id capitalized when nothing names it, as `vendorLabel`).
    private static func name(of id: String) -> String {
        if id == VendorPalette.defaultKey { return String(localized: "Other tools") }
        let label = VendorCatalog.vendorLabel(id)
        guard label == id, let first = label.first else { return label }
        return first.uppercased() + label.dropFirst()
    }

    /// `#rrggbb` (lowercase) of a resolved colour, clamped to sRGB.
    private static func hex(_ color: Color.Resolved) -> String {
        func channel(_ value: Float) -> Int {
            Int((min(max(Double(value), 0), 1) * 255).rounded())
        }
        return String(format: "#%02x%02x%02x", channel(color.red), channel(color.green), channel(color.blue))
    }
}

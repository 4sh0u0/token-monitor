import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Settings › Appearance: tool icons, compact token units (only when the UI
/// language is Chinese, Japanese or Korean, as on the desktop), the compact
/// total, vendor colours and the Activity heatmap options.
struct AppearanceSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmFormatter) private var format

    /// A total big enough to compact in every unit system.
    private static let sampleTokens = 123_456_789

    var body: some View {
        Form {
            Section {
                Toggle("Tool Icons", isOn: model.displayPreference(\.showToolIcons))
            } footer: {
                Text("When off, a dot in the vendor colour replaces each tool’s icon. The Limits page always shows icons.")
            }
            .listRowBackground(TMTheme.card)

            Section {
                // `localized` only differs from `western` in these languages
                // (`supportsLocalizedCompactTokenUnits`), so elsewhere the row
                // is hidden, as on the desktop.
                if format.supportsLocalizedUnits {
                    Picker("Compact token units", selection: model.displayPreference(\.compactTokenUnits)) {
                        Text("International (K/M/B)").tag(CompactTokenUnits.western)
                        Text("East Asian (萬/億)").tag(CompactTokenUnits.localized)
                    }
                }
                Toggle("Show compact token total", isOn: model.displayPreference(\.showCompactTotalTokens))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if format.supportsLocalizedUnits {
                        Text(verbatim: "\(format.fullTokens(Self.sampleTokens)) → \(format.compactTokens(Self.sampleTokens))")
                            .monospacedDigit()
                    }
                    Text("Adds “\(compactSample)” under the full total on the Overview.")
                }
            }
            .listRowBackground(TMTheme.card)

            Section {
                NavigationLink {
                    VendorColorSettingsView()
                } label: {
                    SettingsPageLabel("Vendor Colors", systemImage: "paintpalette") {
                        if !model.preferences.vendorColors.isEmpty {
                            Text("Custom")
                        }
                    }
                }
            }
            .listRowBackground(TMTheme.card)

            Section {
                Picker("Heatmap color", selection: model.displayPreference(\.heatmapMetric)) {
                    Text("Tokens").tag(HeatmapMetric.tokens)
                    Text("Cost").tag(HeatmapMetric.cost)
                }
                Picker("Active days range", selection: model.displayPreference(\.homeActiveDaysWindow)) {
                    Text("All time").tag(ActiveDaysWindow.all)
                    Text("Last 12 months").tag(ActiveDaysWindow.year)
                }
            } header: {
                Text("Activity")
            }
            .listRowBackground(TMTheme.card)
        }
        .settingsListBackground()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// What the compact total line reads for the sample total ("≈ 123.5M").
    private var compactSample: String {
        format.compactApproximation(Self.sampleTokens) ?? format.compactTokens(Self.sampleTokens)
    }
}

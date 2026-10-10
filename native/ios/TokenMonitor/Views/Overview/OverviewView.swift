import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The Overview tab (the desktop's Home): the device scope, the period
/// picker, the period's headline, the Overview modules in the user's order
/// (`HomeModuleLayout.visible`), and links to the full views.
///
/// It is a tab root, so it adds no `NavigationStack`: `RootView` owns one per
/// tab and resolves the `AppRoute` links.
struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScreenScrollView {
            if model.presented != nil {
                OverviewContent()
            } else {
                DataPlaceholder()
            }
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                DeviceScopeMenu()
            }
            ToolbarItem(placement: .topBarTrailing) {
                LiveStatusIndicator()
            }
        }
        .task(id: model.selectedPeriod) {
            // WEEK / 7D / 30D are derived from History. (A new
            // `periodMonthMode` replaces a selected middle segment in
            // `AppModel`, as the desktop's Settings rule does.)
            if model.selectedPeriod.isDerived { model.history.ensureLoaded() }
        }
    }
}

/// Everything below the toolbar once stats have arrived.
private struct OverviewContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let selection = model.selectedPeriod
        StatusBanner()
        ScopeNotice()
        if let presented = model.presented, presented.device == nil, presented.isSourceStale {
            SourceStaleNotice()
        }
        OverviewPeriodPicker()
        HeroCard(selection: selection, state: model.usage(for: selection))
        modules
        OverviewViewsSection()
    }

    /// One column on iPhone. On a regular width, consecutive modules share a
    /// row, except the Activity mosaic, which keeps the full width; only the
    /// modules that draw something now are paired, so no card sits beside a
    /// blank half.
    @ViewBuilder
    private var modules: some View {
        let visible = HomeModuleLayout.visible(model.preferences)
        if sizeClass == .regular {
            ForEach(Self.rows(visible.filter(draws)), id: \.self) { row in
                if row.count == 2 {
                    HStack(alignment: .top, spacing: 16) {
                        OverviewModule(module: row[0])
                            .frame(maxWidth: .infinity, alignment: .top)
                        OverviewModule(module: row[1])
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                } else if let module = row.first {
                    OverviewModule(module: module)
                }
            }
        } else {
            ForEach(visible) { module in
                OverviewModule(module: module)
            }
        }
    }

    /// Whether `module` draws anything now (each module draws nothing while
    /// it has nothing to show; see `OverviewModule`).
    private func draws(_ module: HomeModule) -> Bool {
        switch module {
        case .components, .tool, .model:
            return model.selectedUsage.usage != nil
        case .limits:
            return !HomeLimitsModule.rows(model).isEmpty
        case .device:
            return DevicesModule.draws(model)
        case .session, .trends:
            return true
        }
    }

    /// Pairs consecutive modules into rows, keeping the user's order; the
    /// Activity mosaic always gets a row of its own.
    static func rows(_ modules: [HomeModule]) -> [[HomeModule]] {
        var rows: [[HomeModule]] = []
        var pending: HomeModule?
        for module in modules {
            if module == .trends {
                if let waiting = pending { rows.append([waiting]) }
                pending = nil
                rows.append([module])
            } else if let waiting = pending {
                rows.append([waiting, module])
                pending = nil
            } else {
                pending = module
            }
        }
        if let waiting = pending { rows.append([waiting]) }
        return rows
    }
}

/// One Overview module. Every module takes no parameters, reads the app
/// model and draws its own card; one with nothing to show draws nothing.
private struct OverviewModule: View {
    let module: HomeModule

    var body: some View {
        switch module {
        case .components:
            TokenComponentsCard()
        case .limits:
            HomeLimitsModule()
        case .tool:
            ToolsModule()
        case .model:
            ModelsModule()
        case .session:
            SessionsModule()
        case .device:
            DevicesModule()
        case .trends:
            ActivityModule()
        }
    }
}

/// Every device is offline, so the numbers are the last they reported.
private struct SourceStaleNotice: View {
    var body: some View {
        Label {
            Text("All devices are offline. These are the last numbers they reported.")
                .font(.footnote)
                .foregroundStyle(TMTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "moon.zzz")
                .foregroundStyle(TMTheme.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

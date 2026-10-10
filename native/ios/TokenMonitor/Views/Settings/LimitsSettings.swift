import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Settings › AI Tool Limits, the desktop's Limits settings group plus its
/// Home limits options (`settings.limits.*`, `settings.home.*`):
/// - what the Limits page draws: bars as Remaining or Used (`showLimitUsed`),
///   the reading's source (`showLimitSource`) and masked account emails
///   (`maskLimitAccountEmails`, app only: widgets and the watch stay masked);
/// - the provider order (`limitProviderOrder`) and each provider's visible
///   usage items (`limitProviderHiddenItems`, Codex's additional pools);
/// - the Overview limits module: accounts shown, text or bars, highlight
///   low, provider names (forced on while tool icons are off), and its own
///   provider order and hidden providers.
///
/// Providers are the ones the Hub reports (the phone configures none);
/// stored orders keep every other provider in place.
struct LimitsSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let prefs = model.preferences
        let limits = model.stats?.limits ?? []
        let reported = LimitsSettingsLogic.reportedIDs(limits)
        let listed = LimitsSettingsLogic.withHiddenItems(reported, prefs: prefs)
        let ordered = LimitsSettingsLogic.ordered(listed, stored: prefs.limitProviderOrder)
        Form {
            Section {
                Picker("Bars show", selection: preference(\.showLimitUsed)) {
                    Text("Remaining").tag(false)
                    Text("Used").tag(true)
                }
                Toggle("Show Source", isOn: preference(\.showLimitSource))
                Toggle("Mask account emails", isOn: preference(\.maskLimitAccountEmails))
            } header: {
                Text("Limits page")
            } footer: {
                Text("Rings and money balances always show what is left. Widgets and Apple Watch always mask account emails.")
            }
            .listRowBackground(TMTheme.card)

            Section {
                if ordered.isEmpty {
                    Text("No AI tool limits yet")
                        .foregroundStyle(TMTheme.muted)
                } else {
                    NavigationLink {
                        LimitsSettingsProviderOrderView()
                    } label: {
                        Label("Provider order", systemImage: "arrow.up.arrow.down")
                    }
                    ForEach(ordered, id: \.self) { id in
                        NavigationLink {
                            LimitsSettingsProviderOptionsView(providerID: id)
                        } label: {
                            LimitsSettingsProviderLabel(
                                providerID: id,
                                hiddenCount: LimitUsageItems.hiddenItems(prefs.limitProviderHiddenItems, provider: id).count
                            )
                        }
                    }
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("Choose which usage items each provider shows on the Limits page, the Overview, widgets and Apple Watch.")
            }
            .listRowBackground(TMTheme.card)

            Section {
                Stepper(value: preference(\.homeLimitAccountCount), in: DisplayPreferences.homeLimitAccountCountRange) {
                    LabeledContent("Accounts shown") {
                        Text(verbatim: "\(prefs.homeLimitAccountCount)")
                            .monospacedDigit()
                    }
                }
                Picker("Limit display", selection: preference(\.homeLimitDisplayMode)) {
                    Text("Text").tag(HomeLimitDisplayMode.text)
                    Text("Progress bars").tag(HomeLimitDisplayMode.bars)
                }
                Toggle("Highlight low limits", isOn: preference(\.showHomeLimitBars))
                Toggle("Show provider names for multiple accounts", isOn: providerNamesBinding)
                    .disabled(!prefs.showToolIcons)
                NavigationLink {
                    LimitsSettingsOverviewProvidersView()
                } label: {
                    LabeledContent("Overview limit providers") {
                        Text(verbatim: LimitsSettingsLogic.overviewSummary(reported: reported, prefs: prefs))
                    }
                }
            } header: {
                Text("Overview limits")
            } footer: {
                if !prefs.showToolIcons {
                    Text("Provider names stay visible when tool icons are hidden.")
                }
            }
            .listRowBackground(TMTheme.card)
        }
        .scrollContentBackground(.hidden)
        .background {
            TMBackground().ignoresSafeArea()
        }
        .navigationTitle("AI Tool Limits")
    }

    /// Provider names are forced on while tool icons are off (the desktop
    /// shows the checkbox ticked and disabled then).
    private var providerNamesBinding: Binding<Bool> {
        Binding(
            get: { !model.preferences.showToolIcons || model.preferences.showHomeLimitProviderNames },
            set: { value in model.updatePreferences { $0.showHomeLimitProviderNames = value } }
        )
    }

    private func preference<Value>(_ keyPath: WritableKeyPath<DisplayPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: { value in model.updatePreferences { $0[keyPath: keyPath] = value } }
        )
    }
}

// MARK: - One provider's options

/// `{provider} options`: the visible-usage-items checklist
/// (`limitProviderUsageItemRows`) and, for Codex, its additional pools. Rows
/// come from every account the Hub reports for the provider; an item that is
/// hidden but no longer reported stays listed, marked, so it can be shown
/// again.
struct LimitsSettingsProviderOptionsView: View {
    @Environment(AppModel.self) private var model
    let providerID: String

    var body: some View {
        let prefs = model.preferences
        let rows = LimitsSettingsLogic.checklist(providerID, limits: model.stats?.limits ?? [], prefs: prefs)
        let name = LimitsSettingsLogic.providerName(providerID)
        Form {
            if providerID == "codex" {
                Section {
                    Toggle("Show additional limits", isOn: codexAdditionalBinding)
                } footer: {
                    Text("Separately metered Codex pools. Each one can also be hidden below.")
                }
                .listRowBackground(TMTheme.card)
            }
            Section {
                if rows.isEmpty {
                    Text("This provider reports no usage items right now.")
                        .foregroundStyle(TMTheme.muted)
                } else {
                    ForEach(rows) { row in
                        Toggle(isOn: visibleBinding(row)) {
                            if row.available {
                                Text(verbatim: row.label)
                            } else {
                                Text("\(row.label) (not reported now)")
                                    .foregroundStyle(TMTheme.muted)
                            }
                        }
                    }
                }
            } header: {
                Text("Visible usage items")
            } footer: {
                Text("Hidden items stay hidden on every surface, including widgets and Apple Watch.")
            }
            .listRowBackground(TMTheme.card)
            if rows.contains(where: \.hidden) {
                Section {
                    Button("Restore defaults") {
                        model.updatePreferences {
                            $0.limitProviderHiddenItems = LimitUsageItems.restoreDefaults($0.limitProviderHiddenItems, provider: providerID)
                        }
                    }
                }
                .listRowBackground(TMTheme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background {
            TMBackground().ignoresSafeArea()
        }
        .navigationTitle(Text("\(name) options"))
    }

    private var codexAdditionalBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.showCodexAdditionalLimits },
            set: { value in model.updatePreferences { $0.showCodexAdditionalLimits = value } }
        )
    }

    private func visibleBinding(_ row: LimitsSettingsLogic.ChecklistRow) -> Binding<Bool> {
        let providerID = providerID
        return Binding(
            get: { !LimitUsageItems.hiddenSet(model.preferences.limitProviderHiddenItems, provider: providerID).contains(row.id) },
            set: { visible in
                model.updatePreferences {
                    $0.limitProviderHiddenItems = LimitUsageItems.setHidden(
                        $0.limitProviderHiddenItems,
                        provider: providerID,
                        itemID: row.id,
                        hidden: !visible
                    )
                }
            }
        )
    }
}

// MARK: - Limits page order

/// The Limits page's provider order (`limitProviderOrder`), dragged into
/// place (`reorderLimitProvider`). Only providers the Hub reports are listed;
/// the others keep their slots in the stored order.
struct LimitsSettingsProviderOrderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let prefs = model.preferences
        let reported = LimitsSettingsLogic.reportedIDs(model.stats?.limits ?? [])
        let ordered = LimitsSettingsLogic.ordered(reported, stored: prefs.limitProviderOrder)
        List {
            Section {
                if ordered.isEmpty {
                    Text("No AI tool limits yet")
                        .foregroundStyle(TMTheme.muted)
                }
                ForEach(ordered, id: \.self) { id in
                    LimitsSettingsProviderLabel(providerID: id, hiddenCount: 0)
                }
                .onMove { source, destination in
                    let next = LimitsSettingsLogic.moving(prefs.limitProviderOrder, reported: reported, from: source, to: destination)
                    model.updatePreferences {
                        $0.limitProviderOrder = LimitsSettingsLogic.isCatalogOrder(next, reported: reported) ? [] : next
                    }
                }
            } footer: {
                Text("Drag a provider to reorder the list.")
            }
            .listRowBackground(TMTheme.card)
            Section {
                Button("Reset order") {
                    model.updatePreferences { $0.limitProviderOrder = [] }
                }
                .disabled(!OrderedIDs.hasCustomOrder(prefs.limitProviderOrder))
            }
            .listRowBackground(TMTheme.card)
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background {
            TMBackground().ignoresSafeArea()
        }
        .navigationTitle("Provider order")
    }
}

// MARK: - Overview limit providers

/// The Overview limits module's providers (`renderHomeLimitProviderList`):
/// shown or hidden (`hiddenHomeLimitProviders`) and, once dragged, a custom
/// order (`homeLimitProviderOrder`; empty ranks by least remaining). The
/// list starts from the Limits page order, as the desktop's does.
struct LimitsSettingsOverviewProvidersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let prefs = model.preferences
        let reported = LimitsSettingsLogic.reportedIDs(model.stats?.limits ?? [])
        let base = LimitPresentation.homeProviderOrder(prefs)
        let ordered = LimitsSettingsLogic.ordered(reported, stored: base)
        let hidden = Set(prefs.hiddenHomeLimitProviders.map(OrderedIDs.normalizeID))
        List {
            Section {
                if ordered.isEmpty {
                    Text("No AI tool limits yet")
                        .foregroundStyle(TMTheme.muted)
                }
                ForEach(ordered, id: \.self) { id in
                    Toggle(isOn: shownBinding(id)) {
                        LimitsSettingsProviderLabel(providerID: id, hiddenCount: 0)
                    }
                }
                .onMove { source, destination in
                    let next = LimitsSettingsLogic.moving(base, reported: reported, from: source, to: destination)
                    model.updatePreferences {
                        $0.homeLimitProviderOrder = LimitPresentation.normalizedHomeProviderOrder(next)
                    }
                }
            } footer: {
                Text("Choose which limit providers appear on the Overview. Default is least remaining first; drag here to use a custom order.")
            }
            .listRowBackground(TMTheme.card)
            Section {
                Button("Reset order") {
                    model.updatePreferences { $0.homeLimitProviderOrder = [] }
                }
                .disabled(LimitPresentation.normalizedHomeProviderOrder(prefs.homeLimitProviderOrder).isEmpty)
                Button("Show all") {
                    model.updatePreferences { $0.hiddenHomeLimitProviders = [] }
                }
                .disabled(hidden.isEmpty)
            }
            .listRowBackground(TMTheme.card)
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background {
            TMBackground().ignoresSafeArea()
        }
        .navigationTitle("Overview limit providers")
    }

    private func shownBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !model.preferences.hiddenHomeLimitProviders.map(OrderedIDs.normalizeID).contains(id) },
            set: { shown in
                model.updatePreferences { prefs in
                    var hidden = prefs.hiddenHomeLimitProviders.map(OrderedIDs.normalizeID)
                    hidden.removeAll { $0 == id }
                    if !shown { hidden.append(id) }
                    prefs.hiddenHomeLimitProviders = hidden
                }
            }
        )
    }
}

// MARK: - Shared pieces

/// A provider row: its Limits-page mark (always an icon, as on the desktop's
/// Limits surfaces) and its settings name, with how many items are hidden.
private struct LimitsSettingsProviderLabel: View {
    let providerID: String
    let hiddenCount: Int

    var body: some View {
        HStack(spacing: 10) {
            VendorMark(.provider(providerID), size: 18, context: .limits)
            Text(verbatim: LimitsSettingsLogic.providerName(providerID))
                .foregroundStyle(TMTheme.text)
            Spacer(minLength: 8)
            if hiddenCount > 0 {
                Text("\(hiddenCount) hidden")
                    .font(.footnote)
                    .foregroundStyle(TMTheme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The settings pages' list logic: which providers the Hub reports, the
/// slot-keeping reorder of that subset, and the visible-items checklist.
enum LimitsSettingsLogic {
    struct ChecklistRow: Identifiable, Equatable {
        /// The stored item id.
        let id: String
        let label: String
        let hidden: Bool
        /// Some account draws the item now; false for a hidden item no
        /// record reports any more.
        let available: Bool
    }

    /// The provider ids the Hub reports, normalized, once each, in Hub order.
    static func reportedIDs(_ limits: [LimitProvider]) -> [String] {
        var seen = Set<String>()
        var ids: [String] = []
        for provider in limits {
            let id = OrderedIDs.normalizeID(provider.provider)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            ids.append(id)
        }
        return ids
    }

    /// `reported` plus the catalog providers that still have hidden items,
    /// so a provider that stopped reporting can have its items shown again.
    static func withHiddenItems(_ reported: [String], prefs: DisplayPreferences) -> [String] {
        let reportedSet = Set(reported)
        let catalog = Set(LimitPresentation.catalogProviderIDs)
        let extra = prefs.limitProviderHiddenItems.keys
            .map(OrderedIDs.normalizeID)
            .filter { catalog.contains($0) && !reportedSet.contains($0) }
            .filter { !LimitUsageItems.hiddenItems(prefs.limitProviderHiddenItems, provider: $0).isEmpty }
            .sorted()
        return reported + extra
    }

    /// The catalog's providers, then reported ones it does not know (a newer
    /// Hub), the `known` list for every order.
    static func known(_ reported: [String]) -> [String] {
        let catalog = LimitPresentation.catalogProviderIDs
        let catalogSet = Set(catalog)
        return catalog + reported.filter { !catalogSet.contains($0) }
    }

    /// `reported` in the order `stored` gives the full provider list.
    static func ordered(_ reported: [String], stored: [String]) -> [String] {
        let reportedSet = Set(reported)
        return OrderedIDs.normalizeOrder(stored, known: known(reported)).filter(reportedSet.contains)
    }

    /// The full order after moving rows of the reported subset: the subset is
    /// rearranged within the slots it already holds, so every provider the
    /// Hub does not report keeps its place.
    static func moving(_ stored: [String], reported: [String], from source: IndexSet, to destination: Int) -> [String] {
        var full = OrderedIDs.normalizeOrder(stored, known: known(reported))
        let reportedSet = Set(reported)
        let slots = full.indices.filter { reportedSet.contains(full[$0]) }
        var subset = slots.map { full[$0] }
        subset.move(fromOffsets: source, toOffset: destination)
        for (slot, id) in zip(slots, subset) {
            full[slot] = id
        }
        return full
    }

    /// The order equals the default (catalog) order, stored as `[]`.
    static func isCatalogOrder(_ order: [String], reported: [String]) -> Bool {
        order == OrderedIDs.normalizeOrder([], known: known(reported))
    }

    /// The desktop's settings name (`settingsLabel`, "Claude Code").
    static func providerName(_ id: String) -> String {
        VendorCatalog.limitProviders.first { $0.id == id }?.settingsLabel ?? VendorCatalog.limitProviderLabel(id)
    }

    /// "3 of 5 shown": the reported providers the Overview limits module
    /// shows.
    static func overviewSummary(reported: [String], prefs: DisplayPreferences) -> String {
        let hidden = Set(prefs.hiddenHomeLimitProviders.map(OrderedIDs.normalizeID))
        let shown = reported.filter { !hidden.contains($0) }.count
        return String(localized: "\(shown) of \(reported.count) shown")
    }

    /// `limitProviderUsageItemRows`: what the provider's accounts draw, in
    /// card order and first-seen across accounts, then hidden items nothing
    /// draws any more.
    static func checklist(_ providerID: String, limits: [LimitProvider], prefs: DisplayPreferences) -> [ChecklistRow] {
        let records = limits.filter { OrderedIDs.normalizeID($0.provider) == providerID }
        let hidden = LimitUsageItems.hiddenItems(prefs.limitProviderHiddenItems, provider: providerID)
        let hiddenSet = Set(hidden)
        var seen = Set<String>()
        var rows: [ChecklistRow] = []
        for record in records {
            for item in LimitPresentation.usageItems(for: record, showCodexAdditional: prefs.showCodexAdditionalLimits)
            where seen.insert(item.id).inserted {
                // A window row reads as on the Limits page; its desktop
                // checklist label spells some cadences ("3-hour") in English.
                let label = item.windowName.map(LimitText.windowName) ?? LimitText.usageItemLabel(item.label)
                rows.append(ChecklistRow(id: item.id, label: label, hidden: hiddenSet.contains(item.id), available: true))
            }
        }
        for id in hidden where !seen.contains(id) {
            let label = LimitUsageItems.fallbackLabel(provider: providerID, itemID: id).map(LimitText.usageItemLabel) ?? id
            rows.append(ChecklistRow(id: id, label: label, hidden: true, available: false))
        }
        return rows
    }
}

import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Settings › Tools: hide, pin and reorder the tracked tools
/// (`hiddenClients`, `pinnedClients`, `clientDisplayOrder`), as the desktop's
/// tool list (`renderToolPreferencesNow`, `clientPreferenceRowDrag`), plus the
/// model ranking metric. The choices apply to the Tools view, the Overview
/// tool module, the tools widget and the watch's Tools page.
struct ToolListSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    /// Every tracked client, in the desktop catalog's order (`KNOWN_CLIENTS`).
    private static let known: [String] = VendorCatalog.trackedClientIDs

    private var preferences: DisplayPreferences { model.preferences }

    /// `orderedClients`: the custom order, else the default order with the
    /// pinned tools first.
    private var orderedIDs: [String] {
        ClientDisplayOrder.orderedIDs(order: preferences.clientDisplayOrder, pinned: preferences.pinnedClients, known: Self.known)
    }

    private var hiddenIDs: [String] {
        ClientDisplayOrder.normalizeSelection(preferences.hiddenClients, known: Self.known)
    }

    private var pinnedIDs: [String] {
        ClientDisplayOrder.normalizeSelection(preferences.pinnedClients, known: Self.known)
    }

    private var isFiltering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let ordered = orderedIDs
        let hidden = Set(hiddenIDs)
        let pinned = Set(pinnedIDs)
        let visibleIDs = filtered(ordered)
        Form {
            Section {
                if visibleIDs.isEmpty {
                    Text("No matching entries")
                        .foregroundStyle(TMTheme.muted)
                }
                ForEach(visibleIDs, id: \.self) { id in
                    ToolPreferenceRow(
                        id: id,
                        isHidden: hidden.contains(id),
                        isPinned: pinned.contains(id),
                        togglePinned: { togglePinned(id) },
                        toggleHidden: { toggleHidden(id) }
                    )
                    .accessibilityActions {
                        if !isFiltering {
                            Button("Move up") { move(id, by: -1, in: ordered) }
                            Button("Move down") { move(id, by: 1, in: ordered) }
                        }
                    }
                }
                // Reordering a filtered list would move rows through
                // positions the filter hides (the desktop turns its drag off
                // while searching too).
                .onMove(perform: isFiltering ? nil : { source, destination in
                    reorder(ordered, from: source, to: destination)
                })
            } header: {
                Text("Tools")
            } footer: {
                Text("Hidden tools leave the Tools list, the Overview, the widgets and Apple Watch. Pinned tools stay on top until you drag the list into your own order.")
            }
            .listRowBackground(TMTheme.card)

            Section {
                Button("Reset order") {
                    model.updatePreferences {
                        $0.clientDisplayOrder = []
                        $0.pinnedClients = []
                    }
                }
                .disabled(!ClientDisplayOrder.hasCustomOrder(preferences.clientDisplayOrder) && pinned.isEmpty)
                Button("Show all") {
                    model.updatePreferences { $0.hiddenClients = [] }
                }
                .disabled(hidden.isEmpty)
            }
            .listRowBackground(TMTheme.card)

            Section {
                Picker("Model ranking", selection: model.displayPreference(\.modelRankingMetric)) {
                    Text("Tokens").tag(RankingMetric.tokens)
                    Text("Cost").tag(RankingMetric.cost)
                }
            } header: {
                Text("Models")
            }
            .listRowBackground(TMTheme.card)
        }
        .settingsListBackground()
        .searchable(text: $query, prompt: Text("Search tools"))
        .navigationTitle("Tools")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
                .disabled(isFiltering)
        }
    }

    /// `filterListItems` on `label id`, case-insensitively.
    private func filtered(_ ids: [String]) -> [String] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return ids }
        return ids.filter { id in
            "\(VendorCatalog.clientLabel(id)) \(id)".localizedCaseInsensitiveContains(needle)
        }
    }

    // MARK: Edits

    /// `onClientVisibilityToggle`.
    private func toggleHidden(_ id: String) {
        model.updatePreferences { preferences in
            var hidden = ClientDisplayOrder.normalizeSelection(preferences.hiddenClients, known: Self.known)
            if let index = hidden.firstIndex(of: id) {
                hidden.remove(at: index)
            } else {
                hidden.append(id)
            }
            preferences.hiddenClients = hidden
        }
    }

    /// `onClientPinnedToggle`: pinning returns the list to the pinned-first
    /// default order (the custom order is cleared, as on the desktop).
    private func togglePinned(_ id: String) {
        model.updatePreferences { preferences in
            preferences.pinnedClients = ClientDisplayOrder.togglePinned(preferences.pinnedClients, id: id, known: Self.known)
            preferences.clientDisplayOrder = []
        }
    }

    /// A drag: the list as dropped goes through `clientDisplayOrderCommit`,
    /// which keeps a reshuffle inside the pinned block a pin change and makes
    /// anything else an explicit order.
    private func reorder(_ ordered: [String], from source: IndexSet, to destination: Int) {
        guard let first = source.first, ordered.indices.contains(first) else { return }
        var dropped = ordered
        dropped.move(fromOffsets: source, toOffset: destination)
        commit(dropped: dropped, movedID: ordered[first])
    }

    /// The accessibility Move up / Move down actions: a one-row drag.
    private func move(_ id: String, by offset: Int, in ordered: [String]) {
        guard let from = ordered.firstIndex(of: id) else { return }
        let to = from + offset
        guard ordered.indices.contains(to) else { return }
        var dropped = ordered
        dropped.swapAt(from, to)
        commit(dropped: dropped, movedID: id)
    }

    private func commit(dropped: [String], movedID: String) {
        model.updatePreferences { preferences in
            let commit = ClientDisplayOrder.commit(
                dropped: dropped,
                movedID: movedID,
                order: preferences.clientDisplayOrder,
                pinned: preferences.pinnedClients,
                known: Self.known
            )
            commit.apply(to: &preferences)
        }
    }
}

/// One tool: mark, name, pin and show/hide buttons. Hidden tools are dimmed.
private struct ToolPreferenceRow: View {
    let id: String
    let isHidden: Bool
    let isPinned: Bool
    let togglePinned: () -> Void
    let toggleHidden: () -> Void

    private var name: String { VendorCatalog.clientLabel(id) }

    var body: some View {
        HStack(spacing: 10) {
            VendorMark(.client(id), size: 16, muted: isHidden)
            Text(verbatim: name)
                .foregroundStyle(isHidden ? TMTheme.muted : TMTheme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: togglePinned) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(isPinned ? TMTheme.accent : TMTheme.muted)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isPinned ? Text("Unpin \(name)") : Text("Pin \(name) to top"))
            Button(action: toggleHidden) {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .foregroundStyle(isHidden ? TMTheme.muted : TMTheme.text)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isHidden ? Text("Show \(name) in the Tools list") : Text("Hide \(name) from the Tools list"))
        }
    }
}

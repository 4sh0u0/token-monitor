import Foundation

/// The desktop's ordered-id preferences, ported function by function:
/// `limits/providerOrder.js`, `homeModulePreferences.js` and
/// `serviceStatusProviderPreferences.js` share these semantics.
///
/// A stored order or selection is a list of ids. Every function normalizes it
/// against `known` (the ids that exist right now, in their default order):
/// ids are trimmed and lowercased, unknown and repeated ids are dropped (the
/// first occurrence wins), and an order then gets every known id it does not
/// mention appended in `known` order. Stored lists keep unknown ids, so a
/// tool or provider that comes back later finds its place again.
public enum OrderedIDs {
    /// `String(value || '').trim().toLowerCase()`.
    public static func normalizeID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The known ids, normalized, blanks dropped (`providerIds`, `optionIds`).
    /// Repeats stay; the order functions skip them.
    static func knownIDs(_ known: [String]) -> [String] {
        known.map(normalizeID).filter { !$0.isEmpty }
    }

    /// `normalizeLimitProviderOrder` / `normalizeHomeModuleOrder` /
    /// `normalizeClientDisplayOrder`: the stored ids that are known, in stored
    /// order, then every other known id in `known` order.
    public static func normalizeOrder(_ stored: [String], known: [String]) -> [String] {
        let known = knownIDs(known)
        let knownSet = Set(known)
        var seen = Set<String>()
        var order: [String] = []
        for item in stored {
            let id = normalizeID(item)
            guard knownSet.contains(id), seen.insert(id).inserted else { continue }
            order.append(id)
        }
        for id in known where seen.insert(id).inserted {
            order.append(id)
        }
        return order
    }

    /// `normalizeLimitProviderSelection` / `normalizeSelectedClients`: the
    /// stored ids that are known, in stored order, each once.
    public static func normalizeSelection(_ stored: [String], known: [String]) -> [String] {
        let knownSet = Set(knownIDs(known))
        var seen = Set<String>()
        var selection: [String] = []
        for item in stored {
            let id = normalizeID(item)
            guard knownSet.contains(id), seen.insert(id).inserted else { continue }
            selection.append(id)
        }
        return selection
    }

    /// `moveLimitProvider`: the normalized order with `id` swapped with its
    /// neighbour above (`up`) or below; unchanged when `id` is unknown or
    /// already at that end. The result is the full order to store.
    public static func move(_ stored: [String], id: String, up: Bool, known: [String]) -> [String] {
        swapNeighbour(normalizeOrder(stored, known: known), id: id, up: up)
    }

    /// `reorderLimitProvider`: the normalized order with `id` moved to
    /// `index`, clamped to the list; unchanged when `id` is unknown.
    public static func reorder(_ stored: [String], id: String, to index: Int, known: [String]) -> [String] {
        moveItem(normalizeOrder(stored, known: known), id: id, to: index)
    }

    /// `hasCustomDisplayOrder`: whether the stored list names anything at all,
    /// known or not.
    public static func hasCustomOrder(_ stored: [String]) -> Bool {
        stored.contains { !normalizeID($0).isEmpty }
    }

    /// `orderedLimitProviders` / `orderedHomeModules`: `items` in the
    /// normalized order.
    ///
    /// `known` defaults to the items' own ids in item order. Items whose id is
    /// not in `known` are kept after the known ones, in item order, rather
    /// than dropped. Items sharing an id (several accounts of one provider)
    /// stay together in their original order, at their id's position.
    public static func ordered<Item>(
        _ items: [Item],
        id: (Item) -> String,
        order stored: [String],
        known: [String]? = nil
    ) -> [Item] {
        let ids = items.map { normalizeID(id($0)) }
        var effectiveKnown = knownIDs(known ?? [])
        var knownSet = Set(effectiveKnown)
        for itemID in ids where !itemID.isEmpty && knownSet.insert(itemID).inserted {
            effectiveKnown.append(itemID)
        }
        let rank = Dictionary(
            normalizeOrder(stored, known: effectiveKnown).enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return zip(items, ids).enumerated()
            .sorted { lhs, rhs in
                let left = rank[lhs.element.1] ?? Int.max
                let right = rank[rhs.element.1] ?? Int.max
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map { $0.element.0 }
    }

    // MARK: Shared list edits

    /// Swaps the normalized `id` with its neighbour; unchanged out of range.
    static func swapNeighbour(_ list: [String], id: String, up: Bool) -> [String] {
        guard let from = list.firstIndex(of: normalizeID(id)) else { return list }
        let to = from + (up ? -1 : 1)
        guard to >= 0, to < list.count else { return list }
        var next = list
        next.swapAt(from, to)
        return next
    }

    /// Removes the normalized `id` and inserts it at `index`, clamped to
    /// `0...count - 1` (`Math.max(0, Math.min(order.length - 1, …))`).
    static func moveItem(_ list: [String], id: String, to index: Int) -> [String] {
        guard let from = list.firstIndex(of: normalizeID(id)) else { return list }
        let to = max(0, min(list.count - 1, index))
        guard from != to else { return list }
        var next = list
        let item = next.remove(at: from)
        next.insert(item, at: to)
        return next
    }
}

/// `clientDisplayPreferences.js`: the tool list's custom order, hidden tools
/// and pinned tools (`clientDisplayOrder`, `hiddenClients`, `pinnedClients`).
///
/// `known` is the tracked-client list in its default order (the desktop's
/// `KNOWN_CLIENT_LIST`). Ids outside it can be neither hidden nor pinned nor
/// ordered: they keep their usage position (after the ordered ones once a
/// custom order exists).
public enum ClientDisplayOrder {
    /// `applyClientDisplayPreferences` (`clientDisplayPreferences.js:165-193`).
    ///
    /// `rows` arrive usage-sorted. Hidden known tools are removed. With a
    /// custom order (any non-blank stored id, known or not) the rest are
    /// sorted by that order, unknown ids last, and pins are ignored;
    /// otherwise pinned tools move to the top in pin order and everything
    /// else keeps its usage order.
    public static func apply<Row>(
        _ rows: [Row],
        id: (Row) -> String,
        order: [String],
        hidden: [String],
        pinned: [String],
        known: [String]
    ) -> [Row] {
        let hiddenSet = Set(OrderedIDs.normalizeSelection(hidden, known: known))
        let visible = rows.filter { !hiddenSet.contains(OrderedIDs.normalizeID(id($0))) }
        let rank: [String: Int]
        if OrderedIDs.hasCustomOrder(order) {
            rank = Dictionary(uniqueKeysWithValues: OrderedIDs.normalizeOrder(order, known: known).enumerated().map { ($1, $0) })
        } else {
            let pins = OrderedIDs.normalizeSelection(pinned, known: known)
            guard !pins.isEmpty else { return visible }
            rank = Dictionary(uniqueKeysWithValues: pins.enumerated().map { ($1, $0) })
        }
        // A stable sort, as `Array.prototype.sort` is: equal ranks keep their
        // usage order.
        return visible.enumerated()
            .sorted { lhs, rhs in
                let left = rank[OrderedIDs.normalizeID(id(lhs.element))] ?? Int.max
                let right = rank[OrderedIDs.normalizeID(id(rhs.element))] ?? Int.max
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// `apply` with the three lists read from `preferences`.
    public static func apply<Row>(
        _ rows: [Row],
        id: (Row) -> String,
        preferences: DisplayPreferences,
        known: [String]
    ) -> [Row] {
        apply(
            rows, id: id,
            order: preferences.clientDisplayOrder,
            hidden: preferences.hiddenClients,
            pinned: preferences.pinnedClients,
            known: known
        )
    }

    /// `hasCustomDisplayOrder`.
    public static func hasCustomOrder(_ order: [String]) -> Bool {
        OrderedIDs.hasCustomOrder(order)
    }

    /// `hasClientDisplayPreferences`: a stored order naming a known tool, or
    /// any known hidden or pinned tool (drives "Reset").
    public static func hasPreferences(order: [String], hidden: [String], pinned: [String], known: [String]) -> Bool {
        let knownSet = Set(OrderedIDs.knownIDs(known))
        return order.contains { knownSet.contains(OrderedIDs.normalizeID($0)) }
            || !OrderedIDs.normalizeSelection(hidden, known: known).isEmpty
            || !OrderedIDs.normalizeSelection(pinned, known: known).isEmpty
    }

    /// `orderedClients`: the known tools for the settings list — the custom
    /// order when one exists, else the default order with pinned tools first.
    public static func orderedIDs(order: [String], pinned: [String], known: [String]) -> [String] {
        let full = OrderedIDs.normalizeOrder(order, known: known)
        guard !OrderedIDs.hasCustomOrder(order) else { return full }
        let pins = OrderedIDs.normalizeSelection(pinned, known: known)
        guard !pins.isEmpty else { return full }
        let allowed = Set(full)
        let pinSet = Set(pins)
        return pins.filter { allowed.contains($0) } + full.filter { !pinSet.contains($0) }
    }

    /// `normalizeClientDisplayOrder`.
    public static func normalizeOrder(_ order: [String], known: [String]) -> [String] {
        OrderedIDs.normalizeOrder(order, known: known)
    }

    /// `normalizeHiddenClients` / `normalizePinnedClients`.
    public static func normalizeSelection(_ selection: [String], known: [String]) -> [String] {
        OrderedIDs.normalizeSelection(selection, known: known)
    }

    /// `moveClientDisplayOrder`: the full order to store.
    public static func move(order: [String], id: String, up: Bool, known: [String]) -> [String] {
        OrderedIDs.move(order, id: id, up: up, known: known)
    }

    /// `reorderClientDisplayOrder`: the full order to store.
    public static func reorder(order: [String], id: String, to index: Int, known: [String]) -> [String] {
        OrderedIDs.reorder(order, id: id, to: index, known: known)
    }

    /// `togglePinnedClient`: pins (appended) or unpins a known tool; an
    /// unknown id only normalizes the list.
    public static func togglePinned(_ pinned: [String], id: String, known: [String]) -> [String] {
        var pins = OrderedIDs.normalizeSelection(pinned, known: known)
        let target = OrderedIDs.normalizeID(id)
        guard Set(OrderedIDs.knownIDs(known)).contains(target) else { return pins }
        if let index = pins.firstIndex(of: target) {
            pins.remove(at: index)
        } else {
            pins.append(target)
        }
        return pins
    }

    /// `movePinnedClient`: swaps within the pinned block only.
    public static func movePinned(_ pinned: [String], id: String, up: Bool, known: [String]) -> [String] {
        OrderedIDs.swapNeighbour(OrderedIDs.normalizeSelection(pinned, known: known), id: id, up: up)
    }

    /// `reorderPinnedClient`: moves within the pinned block only.
    public static func reorderPinned(_ pinned: [String], id: String, to index: Int, known: [String]) -> [String] {
        OrderedIDs.moveItem(OrderedIDs.normalizeSelection(pinned, known: known), id: id, to: index)
    }

    /// What a whole-list drag commits (`clientDisplayOrderCommit`).
    public struct Commit: Sendable, Equatable {
        /// The new `clientDisplayOrder`; nil leaves the stored order alone.
        public var clientDisplayOrder: [String]?
        /// The new `pinnedClients` (empty once an explicit order takes over).
        public var pinnedClients: [String]

        public init(clientDisplayOrder: [String]?, pinnedClients: [String]) {
            self.clientDisplayOrder = clientDisplayOrder
            self.pinnedClients = pinnedClients
        }

        /// Writes the commit into `preferences`.
        public func apply(to preferences: inout DisplayPreferences) {
            if let clientDisplayOrder { preferences.clientDisplayOrder = clientDisplayOrder }
            preferences.pinnedClients = pinnedClients
        }
    }

    /// `clientDisplayOrderCommit`: a drop that only reshuffles the pinned
    /// block, while no explicit order exists, stays a pin change; any other
    /// drop becomes an explicit order and clears the pins.
    public static func commit(dropped: [String], movedID: String, order: [String], pinned: [String], known: [String]) -> Commit {
        let next = OrderedIDs.normalizeOrder(dropped, known: known)
        let pins = OrderedIDs.normalizeSelection(pinned, known: known)
        let pinSet = Set(pins)
        let head = Array(next.prefix(pins.count))
        let withinPinnedBlock = pinSet.contains(OrderedIDs.normalizeID(movedID))
            && head.count == pins.count
            && head.allSatisfy { pinSet.contains($0) }
        if !OrderedIDs.hasCustomOrder(order), withinPinnedBlock {
            return Commit(clientDisplayOrder: nil, pinnedClients: head)
        }
        return Commit(clientDisplayOrder: next, pinnedClients: [])
    }
}

/// `homeModulePreferences.js` over the iOS module list (`HomeModule.allCases`:
/// the desktop's Home modules with `components` first).
public enum HomeModuleLayout {
    private static var known: [String] { HomeModule.allCases.map(\.rawValue) }

    private static func modules(_ ids: [String]) -> [HomeModule] {
        ids.compactMap(HomeModule.init(rawValue:))
    }

    /// `normalizeHomeModuleOrder`: every module once, the stored ones first.
    public static func normalizedOrder(_ order: [HomeModule]) -> [HomeModule] {
        modules(OrderedIDs.normalizeOrder(order.map(\.rawValue), known: known))
    }

    /// `normalizeHiddenHomeModules`: each hidden module once, and nothing
    /// hidden when every module would be.
    public static func normalizedHidden(_ hidden: [HomeModule]) -> [HomeModule] {
        let selection = modules(OrderedIDs.normalizeSelection(hidden.map(\.rawValue), known: known))
        return selection.count >= HomeModule.allCases.count ? [] : selection
    }

    /// `orderedHomeModules`: every module in the stored order.
    public static func ordered(_ preferences: DisplayPreferences) -> [HomeModule] {
        normalizedOrder(preferences.homeModuleOrder)
    }

    /// The Overview's modules: `ordered` without the hidden ones
    /// (`homeModuleIds`, `app.js:5407-5413`).
    public static func visible(_ preferences: DisplayPreferences) -> [HomeModule] {
        let hidden = Set(normalizedHidden(preferences.hiddenHomeModules))
        return ordered(preferences).filter { !hidden.contains($0) }
    }

    /// `moveHomeModuleOrder`: the full order to store.
    public static func move(_ order: [HomeModule], module: HomeModule, up: Bool) -> [HomeModule] {
        modules(OrderedIDs.move(order.map(\.rawValue), id: module.rawValue, up: up, known: known))
    }

    /// `reorderHomeModuleOrder`: the full order to store.
    public static func reorder(_ order: [HomeModule], module: HomeModule, to index: Int) -> [HomeModule] {
        modules(OrderedIDs.reorder(order.map(\.rawValue), id: module.rawValue, to: index, known: known))
    }

    /// `onHomeModuleVisibilityToggle` then the save-time normalization:
    /// hiding the last visible module shows every module again.
    public static func toggleHidden(_ hidden: [HomeModule], module: HomeModule) -> [HomeModule] {
        var next = normalizedHidden(hidden)
        if let index = next.firstIndex(of: module) {
            next.remove(at: index)
        } else {
            next.append(module)
        }
        return normalizedHidden(next)
    }
}

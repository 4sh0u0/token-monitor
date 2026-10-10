import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

// Shared by the Devices tab, the device detail screen and the Overview's
// Devices module: one device's figures for a period selection, the period
// switch, the device mark, and the wording of the Kit's device enums
// (`DevicePresentation`, `ClientHealthPresentation`).
//
// The device screens never follow the device scope (desktop rule, plan F4):
// they read `presented.stats.devices`, which has the model aliases folded but
// lists every device.

// MARK: - Figures

/// One device's usage for a period selection: a Hub period read from the
/// device as is (`DevicePresentation.row`), or a fixed range (WEEK / 7D /
/// 30D) derived from its History record (`HistoryStore.deviceFixedRange`).
struct DevicePeriodFigures: Equatable {
    enum Availability: Equatable {
        case ready
        /// The device records (`GET /api/devices`) are still loading.
        case loading
        case unavailable(PeriodUnavailableReason)
    }

    var availability: Availability
    var tokens: Int
    var costUsd: Double
    var unpricedTokens: Int?
    /// Tools (with the Unclassified remainder) and their models.
    var breakdown: DeviceToolBreakdown
    /// The device's day or month ended before it uploaded again, so the Hub
    /// no longer counts it and it reads 0 (plan D-SCOPE).
    var isExpired: Bool
    /// A fixed range: its tools carry no per-model split, as on the desktop
    /// (`derivePeriod` sets `clientModels: false`).
    var isDerived: Bool

    var isReady: Bool { availability == .ready }

    static func pending(_ availability: Availability) -> DevicePeriodFigures {
        DevicePeriodFigures(
            availability: availability,
            tokens: 0,
            costUsd: 0,
            unpricedTokens: nil,
            breakdown: .empty,
            isExpired: false,
            isDerived: true
        )
    }
}

/// One row of the Overview Devices module.
struct DeviceHomeRow: Identifiable, Equatable {
    let id: String
    let name: String
    let tokens: Int
    let platform: String?
    let isStale: Bool
}

/// The Overview Devices module's rows, or the note to show instead while a
/// fixed range is loading or unavailable.
struct DeviceHomeRows: Equatable {
    var rows: [DeviceHomeRow]
    var state: PeriodUsageState?
}

@MainActor
enum DevicePeriods {
    /// `device`'s figures for `selection`.
    static func figures(
        _ device: DeviceSummary,
        selection: PeriodSelection,
        history: HistoryStore,
        now: Date = Date()
    ) -> DevicePeriodFigures {
        if let kind = selection.nativeKind {
            let row = DevicePresentation.row(device, period: kind)
            return DevicePeriodFigures(
                availability: .ready,
                tokens: row.tokens,
                costUsd: row.costUsd,
                unpricedTokens: row.unpricedTokens,
                breakdown: row.breakdown,
                isExpired: row.isExpired,
                isDerived: false
            )
        }
        let snapshot = history.deviceFixedRange(selection, deviceID: device.id, now: now)
        switch snapshot.status {
        case .ready:
            let period = snapshot.period ?? .empty
            let breakdown = DevicePresentation.toolBreakdown(period: period)
            return DevicePeriodFigures(
                availability: .ready,
                tokens: breakdown.totalTokens,
                costUsd: period.costUsd.isFinite ? max(0, period.costUsd) : 0,
                unpricedTokens: period.unpricedTokens,
                breakdown: breakdown,
                isExpired: false,
                isDerived: true
            )
        case .native:
            // A fixed range never reads a Hub period.
            return .pending(.unavailable(.historyUnavailable))
        case .unavailable(let reason):
            return .pending(recordsPending(history) ? .loading : .unavailable(PeriodUnavailableReason(reason)))
        }
    }

    /// The device records are on their way: not loaded, and the Hub neither
    /// lacks `/api/devices` nor failed the last load.
    static func recordsPending(_ history: HistoryStore) -> Bool {
        !history.deviceRecordsLoaded && !history.deviceRecordsUnavailable
    }

    /// What a list of devices says above its rows for a fixed range: loading
    /// while any record is, else why some range is missing; nil when every
    /// device is ready.
    static func listState(_ figures: [DevicePeriodFigures]) -> PeriodUsageState? {
        if figures.contains(where: { $0.availability == .loading }) { return .loading }
        for item in figures {
            if case .unavailable(let reason) = item.availability { return .unavailable(reason) }
        }
        return nil
    }

    /// The Overview Devices module's rows (`homeDeviceRows(..., limit: 4)`).
    /// Hub periods: `DevicePresentation.homeDevices`. Fixed ranges: each
    /// device's derived total, ranked by the same rule (tokens descending,
    /// online before stale, then Hub order; devices without tokens dropped),
    /// once every device's range is ready; until then the note to show.
    static func homeRows(
        devices: [DeviceSummary],
        selection: PeriodSelection,
        history: HistoryStore,
        limit: Int = 4,
        now: Date = Date()
    ) -> DeviceHomeRows {
        if let kind = selection.nativeKind {
            let rows = DevicePresentation.homeDevices(devices: devices, period: kind, limit: limit).map { row in
                DeviceHomeRow(id: row.id, name: row.name, tokens: row.tokens, platform: row.platform, isStale: row.isStale)
            }
            return DeviceHomeRows(rows: rows, state: nil)
        }
        let ranges = devices.map { Self.figures($0, selection: selection, history: history, now: now) }
        if let state = listState(ranges) {
            return DeviceHomeRows(rows: [], state: state)
        }
        let ranked = zip(devices, ranges).enumerated()
            .filter { $0.element.1.tokens > 0 }
            .sorted { left, right in
                let leftTokens = left.element.1.tokens
                let rightTokens = right.element.1.tokens
                if leftTokens != rightTokens { return leftTokens > rightTokens }
                if left.element.0.isStale != right.element.0.isStale { return !left.element.0.isStale }
                return left.offset < right.offset
            }
            .prefix(max(0, limit))
            .map { entry in
                DeviceHomeRow(
                    id: entry.element.0.id,
                    name: entry.element.0.displayName,
                    tokens: entry.element.1.tokens,
                    platform: entry.element.0.platform,
                    isStale: entry.element.0.isStale
                )
            }
        return DeviceHomeRows(rows: Array(ranked), state: nil)
    }

    /// Asks for the device History records when a fixed range needs them
    /// (`GET /api/devices` is heavy; Hub periods never read it).
    static func requestRecordsIfNeeded(for selection: PeriodSelection, history: HistoryStore) {
        if selection.isDerived { history.ensureDeviceRecordsLoaded() }
    }
}

// MARK: - Period switch

/// The device screens' period switch: Today, the middle segment and All time,
/// as on the Overview, plus a menu that picks the middle segment (month, week,
/// 7D, 30D). It shows and sets the app's one period (`selectPeriod`), as the
/// desktop's Devices view follows its single period.
struct DevicePeriodPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Picker("Period", selection: selection) {
                ForEach(model.periodChoices) { choice in
                    Text(verbatim: choice.shortTitle).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            Menu {
                Picker("Range", selection: middle) {
                    ForEach(PeriodSelection.middleChoices) { choice in
                        Text(verbatim: choice.title).tag(choice)
                    }
                }
            } label: {
                Image(systemName: "calendar")
                    .font(.body.weight(.medium))
                    .foregroundStyle(TMTheme.muted)
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Range"))
            .accessibilityValue(Text(verbatim: model.middleSelection.title))
        }
    }

    private var selection: Binding<PeriodSelection> {
        Binding(
            get: { model.selectedPeriod },
            set: { model.selectPeriod($0) }
        )
    }

    private var middle: Binding<PeriodSelection> {
        Binding(
            get: { model.middleSelection },
            set: { model.selectPeriod($0) }
        )
    }
}

// MARK: - Marks

/// A device's OS mark (Apple, Windows or Linux; a dot otherwise), dimmed for
/// a stale device. Follows `showToolIcons` like every other mark.
struct DeviceOSMark: View {
    let platform: String?
    var isStale: Bool = false
    var size: CGFloat = 16

    var body: some View {
        VendorMark(
            .operatingSystem(iconAssetName: DevicePresentation.osIconAssetName(platform: platform)),
            size: size,
            muted: isStale
        )
    }
}

/// Marks the device the app is scoped to (`deviceScope`): the Overview,
/// widgets and Apple Watch show only its usage.
struct DeviceScopeMark: View {
    var body: some View {
        Image(systemName: "scope")
            .font(.caption.weight(.semibold))
            .foregroundStyle(TMTheme.accent)
            .accessibilityLabel(Text("Selected device"))
    }
}

// MARK: - Tool status tags

/// A tool's tag in a device's tool list, as the desktop's Settings › Tools
/// row draws it: a tracked tool whose health is `attention` reads "Needs
/// attention"; otherwise its `clientStatus` tag, "Waiting for data" when the
/// device sent none yet. Untracked tools get no tag.
enum ClientToolTagKind: Hashable {
    case attention
    case status(ClientStatusTag)

    init?(_ tool: ClientToolStatus) {
        guard tool.isTracked else { return nil }
        if tool.health?.overall == .attention {
            self = .attention
        } else if let tag = tool.tag ?? ClientStatusTag.tag(client: tool.clientID, status: "waiting") {
            self = .status(tag)
        } else {
            return nil
        }
    }

    var tone: ClientHealthTone {
        switch self {
        case .attention: return .warn
        case .status(let tag): return tag.tone
        }
    }

    /// `settings.tools.status.*`.
    var title: String {
        switch self {
        case .attention: return String(localized: "Needs attention")
        case .status(.active): return String(localized: "Tracked")
        case .status(.waiting): return String(localized: "Waiting for data")
        case .status(.missing): return String(localized: "Not installed")
        case .status(.signIn): return String(localized: "Sign in needed")
        case .status(.openApp): return String(localized: "Open the app")
        }
    }
}

/// A tool status tag (`.tool-status-tag-*`).
struct ClientToolTagView: View {
    let kind: ClientToolTagKind

    var body: some View {
        Text(verbatim: kind.title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(kind.tone.tagColor)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(kind.tone.tagBorder, lineWidth: 1)
            }
            .opacity(kind.tone == .muted ? 0.72 : 1)
    }
}

extension ClientHealthTone {
    /// A tool tag's text colour (`styles.css` `.tool-status-tag-*`).
    var tagColor: Color {
        switch self {
        case .ok: return TMTheme.success
        case .warn, .setup: return TMTheme.caution
        case .neutral, .muted: return TMTheme.muted
        }
    }

    /// A tool tag's border colour.
    var tagBorder: Color {
        switch self {
        case .ok: return TMTheme.success.opacity(0.28)
        case .warn: return TMTheme.caution.opacity(0.42)
        case .setup: return TMTheme.caution.opacity(0.32)
        case .neutral: return Color.white.opacity(0.2)
        case .muted: return Color.white.opacity(0.13)
        }
    }

    /// A health note's colour (`.tool-health-note-line.tone-*`).
    var noteColor: Color {
        switch self {
        case .ok: return TMTheme.success
        case .warn, .setup: return TMTheme.caution
        case .neutral: return TMTheme.text.opacity(0.86)
        case .muted: return TMTheme.muted
        }
    }
}

// MARK: - Wording

/// Localized words for the Kit's device and client-health enums.
enum DeviceWording {
    /// `settings.age.*` (the desktop's `relativeAgeLabel`).
    static func age(_ age: DeviceSyncedAge) -> String {
        switch age {
        case .justNow: return String(localized: "just now")
        case .minutes(let minutes): return String(localized: "\(minutes)m ago")
        case .hours(let hours): return String(localized: "\(hours)h ago")
        case .days(let days): return String(localized: "\(days)d ago")
        }
    }

    /// `devices.synced`: "Synced 5m ago"; nil without a timestamp.
    static func synced(_ meta: DeviceMeta, now: Date) -> String? {
        guard let bucket = meta.syncedAge(now: now) else { return nil }
        let ago = age(bucket)
        return String(localized: "Synced \(ago)")
    }

    /// `devices.runtime.*`; any other runtime as the device sent it.
    static func runtimeName(_ runtime: DeviceRuntime) -> String {
        switch runtime {
        case .widget: return String(localized: "Widget")
        case .agent: return String(localized: "Agent")
        case .other(let raw): return raw
        }
    }

    /// The desktop's runtime part of the meta line: "Widget v0.70.0",
    /// "v0.70.0" or "Agent"; nil when the device says neither.
    static func runtime(_ meta: DeviceMeta) -> String? {
        let name = meta.runtime.map(runtimeName)
        guard let version = meta.agentVersion else { return name }
        return [name, "v" + version].compactMap { $0 }.joined(separator: " ")
    }

    /// `settings.sync.uploadInterval.*`: "Live", "Every 20 minutes"; nil when
    /// the device does not say.
    static func uploadInterval(_ interval: DeviceUploadInterval) -> String? {
        switch interval {
        case .live: return String(localized: "Live")
        case .minutes(let minutes): return String(localized: "Every \(minutes) minutes")
        case .unknown: return nil
        }
    }

    /// The tool row's name: the catalog label, or "Unclassified" for the
    /// remainder no tool accounts for (`dashboard.tooltip.unclassified`).
    static func toolName(_ row: DeviceToolRow) -> String {
        row.isUnattributed ? String(localized: "Unclassified") : VendorCatalog.clientLabel(row.id)
    }

    /// The desktop's `Math.round(percent)%`.
    static func percent(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return "\(Int(JSCompat.round(max(0, value))))%"
    }

    /// `home.noTools` / `devices.detailsUnavailable`.
    static func emptyBreakdown(_ state: DeviceBreakdownEmptyState) -> String {
        switch state {
        case .noTools: return String(localized: "No tool usage in this period")
        case .detailsUnavailable: return String(localized: "Tool details are unavailable from this device.")
        }
    }
}

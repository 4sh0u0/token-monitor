import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// A tab's scrolling page: the Token Monitor background, a readable width on
/// iPad and pull to refresh.
struct ScreenScrollView<Content: View>: View {
    @Environment(AppModel.self) private var model
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .background {
            TMBackground().ignoresSafeArea()
        }
        .refreshable {
            await model.refresh()
        }
    }
}

/// The card surface every section sits on (the desktop widget's glass card).
struct CardContainer<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TMTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(TMTheme.cardStroke, lineWidth: 1)
            }
    }
}

/// A card's section title.
struct CardTitle: View {
    private let title: Text

    init(_ titleKey: LocalizedStringKey) {
        title = Text(titleKey)
    }

    init(verbatim title: String) {
        self.title = Text(verbatim: title)
    }

    var body: some View {
        title
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TMTheme.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A plain colour dot (token components, chart legends). Vendor, tool,
/// model, provider and device marks use `VendorMark` instead, so the
/// `showToolIcons` and vendor-colour preferences apply.
struct MarkDot: View {
    let color: Color
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A small titled figure (cost, speed) under a headline number.
struct MetricTile: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(TMTheme.muted)
            Text(verbatim: value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(TMTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A small capsule label (plan names, status).
struct Chip: View {
    let text: String
    var color: Color = TMTheme.muted

    var body: some View {
        Text(verbatim: text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// The mint call-to-action button with dark text (white on mint is unreadable).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(TMTheme.background)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                TMTheme.accent.opacity(configuration.isPressed ? 0.75 : 1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

/// Lays chips out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            // A chip wider than the line is clipped to it rather than overflowing.
            if size.width > maxWidth { size.width = maxWidth }
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty, needed > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append(Item(index: index, size: size))
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: Round-2 shared components

/// A cost in the display currency that may leave out unpriced tokens, as the
/// desktop labels it (`usageCostLabel` / `compactUsageCostLabel`):
/// - full: `$1.23`, `$1.23 + 1,234 unpriced tokens`, `— (1,234 unpriced tokens)`;
/// - compact: `$1.23`, `$1.23 + ?`, `—`.
///
/// Style it like `Text` (`.font`, `.foregroundStyle`). Formats with the
/// environment's `tmFormatter`.
struct CostLabelText: View {
    @Environment(\.tmFormatter) private var formatter
    let usd: Double
    let unpricedTokens: Int?
    let compact: Bool
    /// Formats the amount itself compactly (`$1.2K`).
    let compactAmount: Bool

    init(usd: Double, unpricedTokens: Int?, compact: Bool = false, compactAmount: Bool = false) {
        self.usd = usd
        self.unpricedTokens = unpricedTokens
        self.compact = compact
        self.compactAmount = compactAmount
    }

    var body: some View {
        Text(verbatim: Self.string(usd: usd, unpricedTokens: unpricedTokens, compact: compact, compactAmount: compactAmount, formatter: formatter))
    }

    /// The label as a string (accessibility values, joined lines).
    static func string(
        usd: Double,
        unpricedTokens: Int?,
        compact: Bool = false,
        compactAmount: Bool = false,
        formatter: DisplayFormatter
    ) -> String {
        string(formatter.costLabel(usd, unpricedTokens: unpricedTokens, compact: compact, compactAmount: compactAmount))
    }

    /// Words a Kit `CostLabel`.
    static func string(_ label: CostLabel) -> String {
        switch label {
        case .plain(let cost):
            return cost
        case .partial(let cost, let unpriced):
            return "\(cost) + \(unpriced) \(unpricedTokensLabel)"
        case .unknown(let unpriced):
            return "— (\(unpriced) \(unpricedTokensLabel))"
        case .compactPartial(let cost):
            return "\(cost) + ?"
        case .compactUnknown:
            return "—"
        }
    }

    /// `usage.unpricedTokens`.
    static var unpricedTokensLabel: String { String(localized: "unpriced tokens") }
}

/// The device scope in a screen's header: the scoped device's OS mark and
/// name (dimmed with "Offline" when stale), or "Device not found" when the
/// scoped device left the Hub (the numbers are then every device's). Shows
/// nothing for all devices unless `showsAllDevices`.
struct ScopeBadge: View {
    @Environment(AppModel.self) private var model
    var showsAllDevices: Bool = false

    var body: some View {
        if let presented = model.presented {
            if let device = presented.device {
                badge {
                    VendorMark(.operatingSystem(iconAssetName: DevicePresentation.osIconAssetName(platform: device.platform)), size: 11, muted: device.isStale)
                    Text(verbatim: device.displayName)
                        .lineLimit(1)
                    if device.isStale {
                        Text("Offline")
                            .foregroundStyle(TMTheme.staleMuted)
                    }
                }
            } else if presented.isScopeMissing {
                badge {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(TMTheme.warning)
                        .accessibilityHidden(true)
                    Text("Device not found")
                }
            } else if showsAllDevices {
                badge {
                    Image(systemName: "square.stack.3d.up")
                        .accessibilityHidden(true)
                    Text("All devices")
                }
            }
        }
    }

    private func badge<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 5) {
            content()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(TMTheme.muted)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(TMTheme.card, in: Capsule())
        .overlay {
            Capsule().strokeBorder(TMTheme.cardStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

extension PeriodUnavailableReason {
    /// The desktop's `periodRange.*` sentence.
    var message: String {
        switch self {
        case .historyDisabled: return String(localized: "Enable History to use WEEK, 7D and 30D.")
        case .historyUnavailable: return String(localized: "History is temporarily unavailable.")
        case .sessions: return String(localized: "Session details are not available for this range.")
        case .projects: return String(localized: "Project details are not available for this range.")
        }
    }
}

/// Why a period or a breakdown cannot be shown, in the desktop's words.
struct PeriodUnavailableNote: View {
    let reason: PeriodUnavailableReason

    var body: some View {
        NoteLabel(systemImage: "calendar.badge.exclamationmark", text: reason.message)
    }
}

/// History is still loading for a fixed range (`periodRange.loading`).
struct PeriodLoadingNote: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading history…")
                .font(.footnote)
                .foregroundStyle(TMTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The state of a period that is not ready: loading, or the reason it is
/// unavailable. Draws nothing for `.ready`.
struct PeriodUsageNote: View {
    let state: PeriodUsageState

    var body: some View {
        switch state {
        case .ready:
            EmptyView()
        case .loading:
            PeriodLoadingNote()
        case .unavailable(let reason):
            PeriodUnavailableNote(reason: reason)
        }
    }
}

/// The Hub left details out (`sessions.incomplete`, `projects.incomplete`):
/// a muted line with an info mark.
struct IncompleteNotice: View {
    private let text: Text

    init(text: LocalizedStringKey) {
        self.text = Text(text)
    }

    init(verbatim text: String) {
        self.text = Text(verbatim: text)
    }

    var body: some View {
        NoteLabel(systemImage: "info.circle", text: text)
    }
}

/// A module's or section's title, optionally linking to its full screen
/// (title plus chevron, pushed on the current tab), with an optional
/// trailing accessory (a toggle, a count).
struct ModuleHeader<Accessory: View>: View {
    private let title: Text
    private let route: AppRoute?
    private let accessory: Accessory

    init(title: LocalizedStringKey, route: AppRoute? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = Text(title)
        self.route = route
        self.accessory = accessory()
    }

    init(verbatim title: String, route: AppRoute? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = Text(verbatim: title)
        self.route = route
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 8) {
            if let route {
                NavigationLink(value: route) {
                    HStack(spacing: 4) {
                        styledTitle
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TMTheme.muted)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                styledTitle
            }
            Spacer(minLength: 8)
            accessory
        }
    }

    private var styledTitle: some View {
        title
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TMTheme.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

extension ModuleHeader where Accessory == EmptyView {
    init(title: LocalizedStringKey, route: AppRoute? = nil) {
        self.init(title: title, route: route) { EmptyView() }
    }

    init(verbatim title: String, route: AppRoute? = nil) {
        self.init(verbatim: title, route: route) { EmptyView() }
    }
}

/// A muted footnote line with a leading symbol.
private struct NoteLabel: View {
    let systemImage: String
    let text: Text

    init(systemImage: String, text: Text) {
        self.systemImage = systemImage
        self.text = text
    }

    init(systemImage: String, text: String) {
        self.init(systemImage: systemImage, text: Text(verbatim: text))
    }

    var body: some View {
        Label {
            text
                .font(.footnote)
                .foregroundStyle(TMTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .font(.footnote)
                .foregroundStyle(TMTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

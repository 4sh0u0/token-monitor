import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// One provider's accounts on the Limits page, in Hub order (the desktop
/// draws several accounts of a provider as one card: a header, then a row
/// per account).
struct LimitAccountGroup: Identifiable, Equatable {
    /// The provider id, trimmed and lowercased.
    let providerID: String
    let accounts: [LimitProvider]

    var id: String { providerID }

    /// `providers` (already in page order) grouped by provider, each group at
    /// its first account's place.
    static func groups(_ providers: [LimitProvider]) -> [LimitAccountGroup] {
        var order: [String] = []
        var accounts: [String: [LimitProvider]] = [:]
        for provider in providers {
            let id = OrderedIDs.normalizeID(provider.provider)
            if accounts[id] == nil { order.append(id) }
            accounts[id, default: []].append(provider)
        }
        return order.map { LimitAccountGroup(providerID: $0, accounts: accounts[$0] ?? []) }
    }
}

/// A provider's card: its single account, or a header ("Codex", "3
/// accounts") over one row per account.
struct LimitProviderCard: View {
    let group: LimitAccountGroup
    /// The Hub's devices, for "From {device}".
    let devices: [DeviceSummary]
    let now: Date

    @ScaledMetric(relativeTo: .headline) private var markSize: CGFloat = 16

    var body: some View {
        CardContainer {
            if group.accounts.count == 1, let account = group.accounts.first {
                LimitAccountRow(
                    provider: account,
                    peers: group.accounts,
                    index: 0,
                    grouped: false,
                    showsMark: true,
                    devices: devices,
                    now: now
                )
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    ForEach(Array(group.accounts.enumerated()), id: \.element.id) { index, account in
                        Divider()
                            .overlay(TMTheme.divider)
                        LimitAccountRow(
                            provider: account,
                            peers: group.accounts,
                            index: index,
                            grouped: true,
                            showsMark: rowsShowMarks,
                            devices: devices,
                            now: now
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The group header: the provider's mark and name, and how many accounts
    /// (MiMo's two products of one account are not counted as two).
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VendorMark(
                .provider(groupMarkID),
                size: markSize,
                context: .limits,
                muted: group.accounts.allSatisfy(\.isStale)
            )
            Text(verbatim: group.accounts.first?.displayName ?? group.providerID)
                .font(.headline)
                .foregroundStyle(TMTheme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            if group.providerID != "mimo" {
                Text(verbatim: LimitText.groupCount(providerID: group.providerID, count: group.accounts.count))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TMTheme.muted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Relay accounts of one adapter share its mark on the header; mixed
    /// adapters keep the generic mark there and their own on each row
    /// (`thirdPartySharedAdapterFamily`).
    private var adapterMarks: Set<String> {
        Set(group.accounts.map(LimitPresentation.iconID))
    }

    private var groupMarkID: String {
        if group.providerID == "thirdparty" {
            return adapterMarks.count == 1 ? (adapterMarks.first ?? "thirdparty") : "thirdparty"
        }
        return group.accounts.first.map(LimitPresentation.iconID) ?? group.providerID
    }

    /// Inside a group the header already wears the mark: the desktop's row
    /// policies drop it for these providers, and relays keep theirs only when
    /// the adapters differ.
    private var rowsShowMarks: Bool {
        if group.providerID == "thirdparty" { return adapterMarks.count > 1 }
        return !Self.groupedRowsWithoutMark.contains(group.providerID)
    }

    private static let groupedRowsWithoutMark: Set<String> = [
        "codex", "claude", "mimo", "cursor", "opencode", "volcengine", "openrouter", "antigravity"
    ]
}

/// One account: who it is, its status, freshness and plan, then its quota
/// windows, balance details and reset credits. A transient failure keeps its
/// last windows under the new status; a row with nothing to draw shows only
/// its header.
private struct LimitAccountRow: View {
    let provider: LimitProvider
    /// Every row of this provider, in Hub order (titles tell them apart).
    let peers: [LimitProvider]
    let index: Int
    let grouped: Bool
    let showsMark: Bool
    let devices: [DeviceSummary]
    let now: Date

    @Environment(\.tmPresentation) private var presentation
    @ScaledMetric(relativeTo: .headline) private var markSize: CGFloat = 16

    var body: some View {
        let prefs = presentation.preferences
        let windows = LimitPresentation.visibleWindows(provider, prefs: prefs)
        VStack(alignment: .leading, spacing: 14) {
            header
            if LimitPresentation.antigravityNeedsVerification(provider) {
                Label {
                    Text(verbatim: LimitText.antigravityVerificationDetail)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "person.badge.key")
                }
                .font(.caption)
                .foregroundStyle(TMTheme.muted)
            }
            if !windows.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(windows) { window in
                        LimitWindowRow(window: window, provider: provider, tint: tint, now: now)
                    }
                }
            }
            LimitDetailsSection(provider: provider, now: now)
        }
    }

    // MARK: Header

    private var header: some View {
        let prefs = presentation.preferences
        let chip = LimitPresentation.statusChip(provider)
        let meta = LimitPresentation.metaLine(provider, now: now, showSource: prefs.showLimitSource, devices: devices)
        let cell = LimitPresentation.planCell(provider, grouped: grouped)
        // A stale row says so in its meta line ("Stale · 2h ago"); a healthy
        // fresh one wears only the mint dot.
        let showsChip = !chip.showsLiveDot && chip.label != .stale
        // The plan cell of a row that is not healthy repeats the chip.
        let plan: String? = {
            if case .status(let label) = cell, showsChip, label == chip.label { return nil }
            return LimitText.plan(cell)
        }()
        let identity = accountLine.flatMap { $0 == plan ? nil : $0 }
        return HStack(alignment: .top, spacing: 10) {
            if showsMark {
                VendorMark(.provider(LimitPresentation.iconID(provider)), size: markSize, context: .limits, muted: provider.isStale)
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: title)
                        .font(grouped ? .subheadline.weight(.semibold) : .headline)
                        .foregroundStyle(provider.isStale ? TMTheme.muted : TMTheme.text)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if chip.showsLiveDot {
                        StatusTag(text: LimitText.statusLabel(chip.label), tone: chip.tone, showsOKDot: true)
                    }
                }
                if let identity {
                    Text(verbatim: identity)
                        .font(.caption)
                        .foregroundStyle(TMTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let meta {
                    Text(verbatim: LimitText.metaLine(meta))
                        .font(.caption)
                        .foregroundStyle(meta.freshness.tone == .stale ? TMTheme.tagColor(.stale) : TMTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if showsChip || plan != nil {
                VStack(alignment: .trailing, spacing: 4) {
                    if showsChip {
                        StatusTag(text: LimitText.statusLabel(chip.label), tone: chip.tone, font: .caption)
                    }
                    if let plan {
                        Text(verbatim: plan)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(TMTheme.muted)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }
                }
                .layoutPriority(-1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A lone account is titled by its provider (with MiMo's product); in a
    /// group, by the account (`accountTitle`, the address masked when
    /// `maskLimitAccountEmails` is on).
    private var title: String {
        if grouped {
            return LimitText.accountTitle(LimitPresentation.accountTitle(
                provider,
                peers: peers,
                index: index,
                mask: presentation.preferences.maskLimitAccountEmails
            ))
        }
        if let product = LimitPresentation.mimoProduct(provider) {
            return provider.displayName + " · " + product
        }
        return provider.displayName
    }

    /// A lone account's identity under the provider's name, when anything
    /// names it (never the "Account 1" fallback, nor MiMo's product again).
    private var accountLine: String? {
        guard !grouped else { return nil }
        var title = LimitPresentation.accountTitle(provider, peers: [provider], index: 0, mask: presentation.preferences.maskLimitAccountEmails)
        guard !title.isFallback else { return nil }
        if let product = LimitPresentation.mimoProduct(provider), title.parts.last == .text(product) {
            title.parts.removeLast()
        }
        let text = LimitText.accountTitle(title)
        return text.isEmpty ? nil : text
    }

    /// The provider's colour, the user's override included.
    private var tint: Color {
        VendorColor.color(for: provider.provider, palette: presentation.palette)
    }
}

/// One quota window: name, value, meter (in the user's used/remaining mode;
/// none for a note row) and the boundary countdown with the window's second
/// figure.
private struct LimitWindowRow: View {
    let window: LimitWindow
    let provider: LimitProvider
    let tint: Color
    let now: Date

    @Environment(\.tmPresentation) private var presentation
    @Environment(\.tmFormatter) private var format

    var body: some View {
        let showUsed = presentation.preferences.showLimitUsed
        let name = LimitText.windowName(LimitPresentation.windowName(window, provider: provider))
        let fill = LimitPresentation.meterFill(window: window, provider: provider, showUsed: showUsed)
        let value = LimitText.headline(LimitPresentation.headline(window: window, provider: provider, showUsed: showUsed), format: format)
        let boundary = LimitPresentation.boundaryLine(window: window, now: now).map(LimitText.boundary)
        let detail = LimitPresentation.windowDetail(window: window, provider: provider, showUsed: showUsed, now: now)
            .map { LimitText.windowDetail($0, format: format) }
            .flatMap { $0.isEmpty ? nil : $0 }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TMTheme.text)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(verbatim: value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(provider.isStale ? TMTheme.muted : TMTheme.number)
                    .multilineTextAlignment(.trailing)
            }
            LimitMeter(fill: fill, color: tint)
            if boundary != nil || detail != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let boundary {
                        Text(verbatim: boundary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    if let detail {
                        Text(verbatim: detail)
                            .monospacedDigit()
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .font(.caption)
                .foregroundStyle(TMTheme.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: [value, boundary, detail].compactMap { $0 }.joined(separator: ", ")))
    }
}

/// The meter-less lines under the windows: balance, gift and cash, prepaid
/// grants, spend by period, tracking since, relay details, the usage summary
/// and reset credits (each hidden with its item in the visible-items list).
private struct LimitDetailsSection: View {
    let provider: LimitProvider
    let now: Date

    @Environment(\.tmPresentation) private var presentation
    @Environment(\.tmFormatter) private var format

    var body: some View {
        let hidden = presentation.preferences.limitProviderHiddenItems
        let lines = detailLines(hiddenItems: hidden)
        let resets = LimitPresentation.resetCredits(provider, now: now, hiddenItems: hidden)
        if !lines.isEmpty || resets != nil {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(lines) { line in
                    LimitDetailLine(label: line.label, value: line.value, note: line.note)
                }
                if let resets {
                    LimitResetCreditsView(line: resets)
                }
            }
        }
    }

    private struct Line: Identifiable {
        let id: String
        let label: String
        let value: String
        var note: String? = nil
    }

    /// `balanceRows` with the spend figures folded into one "Spend" line
    /// (Today, Week, Month, All time), then `usageSummaryRows`.
    private func detailLines(hiddenItems: [String: [String]]) -> [Line] {
        var lines: [Line] = []
        var spend: [String] = []
        var spendIndex: Int?
        for (offset, row) in LimitPresentation.balanceRows(provider, hiddenItems: hiddenItems).enumerated() {
            let id = "balance-\(offset)"
            switch row {
            case let .balance(amount, currency):
                lines.append(Line(id: id, label: LimitText.fixedItem(.credits), value: format.balance(amount, currency: currency)))
            case let .gift(amount, currency):
                lines.append(Line(id: id, label: String(localized: "Gift"), value: format.balance(amount, currency: currency)))
            case let .cash(amount, currency):
                lines.append(Line(id: id, label: String(localized: "Cash"), value: format.balance(amount, currency: currency)))
            case let .tranche(amount, currency, expiresAt):
                lines.append(Line(id: id, label: format.balance(amount, currency: currency), value: LimitText.trancheExpiry(expiresAt, now: now)))
            case let .spend(period, amount, currency):
                if spendIndex == nil {
                    spendIndex = lines.count
                    lines.append(Line(id: "spend", label: LimitText.fixedItem(.spend), value: ""))
                }
                spend.append(LimitText.spendPeriod(period) + " " + format.balance(amount, currency: currency))
            case let .trackingSince(date, partialMonth):
                lines.append(Line(
                    id: id,
                    label: String(localized: "Tracking since"),
                    value: LimitText.day(date),
                    note: partialMonth ? String(localized: "This month’s spend counts from that day.") : nil
                ))
            case .requests(let count):
                lines.append(Line(id: id, label: String(localized: "Requests"), value: format.fullTokens(count)))
            case .quotaGroup(let group):
                lines.append(Line(id: id, label: String(localized: "Group"), value: group))
            case .expires(let date):
                lines.append(Line(id: id, label: String(localized: "Expires"), value: LimitText.day(date)))
            }
        }
        if let spendIndex {
            lines[spendIndex] = Line(id: "spend", label: LimitText.fixedItem(.spend), value: spend.joined(separator: " · "))
        }
        let period = provider.usageSummary?.period
        for (offset, row) in LimitPresentation.usageSummaryRows(provider, hiddenItems: hiddenItems).enumerated() {
            lines.append(Line(
                id: "usage-\(offset)",
                label: LimitText.usageSummaryLabel(row, period: period),
                value: LimitText.usageSummaryValue(row, format: format)
            ))
        }
        return lines
    }
}

/// A label on the left, its figure on the right, an optional note below.
private struct LimitDetailLine: View {
    let label: String
    let value: String
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: label)
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(verbatim: value)
                    .foregroundStyle(TMTheme.text)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
            .font(.subheadline)
            if let note {
                Text(verbatim: note)
                    .font(.caption)
                    .foregroundStyle(TMTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "3 resets", when they expire ("2d 4h · 5d 1h · +1") and, for Claude, each
/// grant: its caption, how many resets it has left, when it expires, what it
/// clears and when it can be spent.
private struct LimitResetCreditsView: View {
    let line: LimitPresentation.ResetCreditsLine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LimitDetailLine(label: LimitText.resetCount(line.count), value: LimitText.resetTimeline(line) ?? "")
            ForEach(Array(line.grants.enumerated()), id: \.offset) { _, grant in
                grantView(grant)
            }
        }
    }

    private func grantView(_ grant: LimitPresentation.ResetGrantRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let caption = [grant.label, grant.resetsLeft.map { String(localized: "\($0) left") }]
                .compactMap { $0 }
                .joined(separator: " · ")
            if !caption.isEmpty {
                Text(verbatim: caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TMTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                LimitDetailLine(label: String(localized: "Expires"), value: LimitText.grantExpiry(grant))
                if !grant.clears.isEmpty {
                    LimitDetailLine(label: String(localized: "Clears"), value: grant.clears.map(LimitText.resetClear).joined(separator: " · "))
                }
                if let usability = grant.usability {
                    LimitDetailLine(label: String(localized: "Usable"), value: LimitText.usability(usability))
                }
            }
            .font(.caption)
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(TMTheme.divider)
                .frame(width: 2)
        }
    }
}

#Preview("Limits cards") {
    let now = Date()
    let claude = LimitProvider(
        id: "claude-3f9a2c11",
        provider: "claude",
        accountEmail: "dev@example.com",
        planLabel: "max",
        status: .ok,
        source: "oauth",
        updatedAt: now.addingTimeInterval(-300),
        windows: [
            LimitWindow(kind: .session, usedPercent: 42, remainingPercent: 58, resetsAt: now.addingTimeInterval(9_000)),
            LimitWindow(kind: .weekly, usedPercent: 81, remainingPercent: 19, resetsAt: now.addingTimeInterval(300_000))
        ],
        resetCredits: LimitResetCredits(availableCount: 2, expirations: [now.addingTimeInterval(86_400 * 3)])
    )
    let codexA = LimitProvider(
        id: "codex-aa11bb22",
        provider: "codex",
        accountEmail: "me@example.com",
        planLabel: "plus",
        status: .rateLimited,
        updatedAt: now.addingTimeInterval(-1_200),
        windows: [LimitWindow(kind: .session, usedPercent: 90, remainingPercent: 10, resetsAt: now.addingTimeInterval(40))]
    )
    let codexB = LimitProvider(
        id: "codex-cc33dd44",
        provider: "codex",
        accountEmail: "team@example.com",
        status: .ok,
        updatedAt: now.addingTimeInterval(-7_200),
        isStale: true,
        windows: [LimitWindow(kind: .weekly, usedPercent: 30, remainingPercent: 70, resetsAt: now.addingTimeInterval(500_000))]
    )
    let deepseek = LimitProvider(
        id: "deepseek-ee55ff66",
        provider: "deepseek",
        status: .ok,
        updatedAt: now,
        windows: [LimitWindow(kind: .billing, metric: .credits, remaining: 12.5, currency: "USD")],
        balance: LimitBalance(amount: 12.5, currency: "USD", todaySpend: 0.42, monthSpend: 7.9)
    )
    let antigravity = LimitProvider(id: "antigravity-0011aa22", provider: "antigravity", status: .unauthorized, actionRequired: "accountVerification")
    ScrollView {
        VStack(spacing: 16) {
            ForEach(LimitAccountGroup.groups([claude, codexA, codexB, deepseek, antigravity])) { group in
                LimitProviderCard(group: group, devices: [], now: now)
            }
        }
        .padding()
    }
    .background(TMBackground())
}

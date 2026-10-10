import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Everything the Hub knows about one session: client, models and their
/// shares, providers, project, times, the token split, cost, speed, cache
/// hits, the live context window and prompt-cache estimate, turn state and
/// usage-source notes.
///
/// The desktop's drill-down reads the session's transcript from local files
/// (`shared/sessionDetail.js`); a Hub never has it, so this screen shows the
/// synced record and says where the transcript stays.
///
/// The same session can have a today and a month entry with different
/// totals; a picker switches between them. It opens on the period the
/// screen that pushed it was showing (`initialPeriod`), else month.
struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    let sessionID: String
    /// The period the opening screen showed (`AppRoute.sessionDetail`).
    var initialPeriod: UsagePeriodKind? = nil
    @State private var chosenPeriod: UsagePeriodKind?

    var body: some View {
        let entries = Self.entries(for: sessionID, in: model.presented?.stats)
        let period = resolvedPeriod(entries)
        let entry = entries.first { $0.period == period }
        ScreenScrollView {
            if model.presented == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if let entry {
                TimelineView(SessionLiveSchedule(sessions: [entry.session])) { context in
                    SessionDetailContent(
                        session: entry.session,
                        period: entry.period,
                        periods: entries.map(\.period),
                        selection: $chosenPeriod,
                        now: SessionLiveSchedule.now(context)
                    )
                }
            } else {
                notFound
            }
        }
        .navigationTitle(Text(verbatim: entry.map { title(of: $0.session) } ?? ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var notFound: some View {
        CardContainer {
            Label {
                Text("This session is no longer in today’s or this month’s usage.")
                    .font(.subheadline)
                    .foregroundStyle(TMTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "clock.badge.questionmark")
                    .foregroundStyle(TMTheme.muted)
            }
        }
    }

    /// The title when titles are on and the Hub sent one, else
    /// "Client · model" (the desktop's detail heading uses the title only).
    private func title(of session: HubSession) -> String {
        let row = SessionRows.row(for: session, titlesEnabled: model.preferences.sessionTitlesEnabled)
        return SessionText.name(row.name)
    }

    private func resolvedPeriod(_ entries: [Entry]) -> UsagePeriodKind? {
        let available = Set(entries.map(\.period))
        for candidate in [chosenPeriod, initialPeriod, .month, .today] {
            if let candidate, available.contains(candidate) { return candidate }
        }
        return nil
    }

    struct Entry {
        let period: UsagePeriodKind
        let session: HubSession
    }

    /// The session's today and month entries (a Hub has no all-time list).
    static func entries(for id: String, in stats: HubStats?) -> [Entry] {
        guard let stats else { return [] }
        return [UsagePeriodKind.today, .month].compactMap { kind in
            stats[kind].sessions.first { $0.id == id }.map { Entry(period: kind, session: $0) }
        }
    }
}

private struct SessionDetailContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmFormatter) private var formatter
    @Environment(\.tmPresentation) private var presentation
    @ScaledMetric(relativeTo: .headline) private var markSize: CGFloat = 26

    let session: HubSession
    let period: UsagePeriodKind
    let periods: [UsagePeriodKind]
    @Binding var selection: UsagePeriodKind?
    let now: Date

    private var metric: ContextMetric { model.preferences.sessionContextMetric }

    var body: some View {
        let row = SessionRows.row(for: session, titlesEnabled: model.preferences.sessionTitlesEnabled, now: now)
        VStack(alignment: .leading, spacing: 16) {
            if periods.count > 1 {
                Picker("Period", selection: periodBinding) {
                    ForEach(periods) { kind in
                        Text(verbatim: kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }
            header(row)
            if let id = row.idLabel {
                SessionIDCard(id: id)
            }
            tokensCard
            detailsCard(row)
            if row.context != nil || row.promptCache != nil {
                liveCard(row)
            }
            modelsCard
            providersCard
            notes
        }
    }

    private var periodBinding: Binding<UsagePeriodKind> {
        Binding(get: { period }, set: { selection = $0 })
    }

    // MARK: Header

    private func header(_ row: SessionRow) -> some View {
        let color = SessionColor.color(client: row.client, model: row.modelLabel, key: session.id, palette: presentation.palette)
        return CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    SessionMark(client: row.client, color: color, isRunning: row.isRunning, size: markSize)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: SessionText.name(row.name))
                            .font(.headline)
                            .foregroundStyle(TMTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if case .title = row.name, let subtitle = row.subtitle {
                            Text(verbatim: SessionText.subtitle(subtitle, formatter: formatter))
                                .font(.subheadline)
                                .foregroundStyle(TMTheme.muted)
                        }
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            SessionStateBadge(state: row.state)
                            Chip(text: period.title)
                            if row.isArchived {
                                Chip(text: SessionText.archived, color: TMTheme.warning)
                            }
                            if row.isBackgroundReview {
                                Chip(text: SessionText.backgroundReviews, color: TMTheme.chartBlue)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    MetricTile(title: "Total tokens", value: formatter.fullTokens(session.totalTokens))
                    MetricTile(
                        title: "Cost",
                        value: CostLabelText.string(usd: session.costUsd, unpricedTokens: session.unpricedTokens, compact: true, formatter: formatter)
                    )
                }
                if let unpriced = session.unpricedTokens, unpriced > 0 {
                    Text("Cost excludes \(formatter.fullTokens(unpriced)) tokens without a known price.")
                        .font(.caption)
                        .foregroundStyle(TMTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Tokens

    private var tokensCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("Tokens")
                SessionField("Input (cache miss)", verbatim: formatter.fullTokens(session.inputTokens))
                SessionField("Input (cache hit)", verbatim: formatter.fullTokens(session.cacheReadTokens))
                SessionField("Cache write", verbatim: formatter.fullTokens(session.cacheWriteTokens))
                SessionField("Output", verbatim: formatter.fullTokens(session.outputTokens))
                if session.reasoningTokens > 0 {
                    SessionField("Reasoning", verbatim: formatter.fullTokens(session.reasoningTokens))
                }
            }
        }
    }

    // MARK: Details

    private func detailsCard(_ row: SessionRow) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("Details")
                SessionField("Tool") {
                    HStack(spacing: 6) {
                        VendorMark(.client(row.client), size: 14)
                        Text(verbatim: row.clientLabel ?? "—")
                            .foregroundStyle(TMTheme.text)
                    }
                }
                if let project = trimmed(session.projectLabel) {
                    SessionField("Project", verbatim: project)
                }
                SessionField("Status") {
                    HStack(spacing: 6) {
                        SessionStateGlyph(state: row.state, size: 12)
                        Text(verbatim: SessionText.state(row.state))
                            .foregroundStyle(TMTheme.text)
                    }
                }
                SessionField("Turn", verbatim: SessionText.turn(session.turnEnded))
                if let started = session.startedAt {
                    SessionField("Started", verbatim: started.formatted(date: .abbreviated, time: .shortened))
                }
                if let lastUsed = session.lastUsedAt {
                    SessionField("Last used", verbatim: lastUsedText(lastUsed))
                }
                SessionField("Messages", verbatim: formatter.fullTokens(session.messageCount))
                if let rate = SessionRows.roundedTokenRate(session) {
                    SessionField("Output speed", verbatim: SessionText.tokensPerSecond(rate))
                }
                if let hit = SessionRows.cacheHitLabel(session) {
                    SessionField("Cache hit rate", verbatim: hit)
                }
            }
        }
    }

    private func lastUsedText(_ date: Date) -> String {
        let absolute = date.formatted(date: .abbreviated, time: .shortened)
        guard let age = SessionRows.age(of: date, now: now) else { return absolute }
        return absolute + SessionText.separator + SessionText.age(age)
    }

    // MARK: Context window and prompt cache

    private func liveCard(_ row: SessionRow) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                if let context = row.context {
                    VStack(alignment: .leading, spacing: 8) {
                        CardTitle("Context window")
                        ContextWindowBar(gauge: context, metric: metric)
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: SessionText.contextPercent(context, metric: metric, formatter: formatter))
                                .foregroundStyle(TMTheme.contextColor(context.tone))
                            Spacer(minLength: 8)
                            Text(verbatim: SessionText.contextWindow(context, formatter: formatter))
                                .monospacedDigit()
                                .foregroundStyle(TMTheme.muted)
                        }
                        .font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let cache = row.promptCache {
                    VStack(alignment: .leading, spacing: 4) {
                        CardTitle("Prompt cache")
                        Text(verbatim: SessionText.cacheLeft(cache))
                            .font(.subheadline)
                            .foregroundStyle(TMTheme.text)
                        Text(verbatim: SessionText.cacheTier(cache))
                            .font(.caption)
                            .foregroundStyle(TMTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Models and providers

    @ViewBuilder
    private var modelsCard: some View {
        let shares = Self.modelShares(session)
        if !shares.isEmpty {
            CardContainer {
                VStack(alignment: .leading, spacing: 10) {
                    CardTitle("Models")
                    ForEach(shares) { share in
                        ShareRow(
                            mark: share.model.map { VendorMarkSubject.model($0) },
                            name: share.model ?? String(localized: "Unclassified"),
                            tokens: share.tokens,
                            percent: share.percent,
                            cost: share.model.flatMap { session.modelCosts[$0] }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var providersCard: some View {
        let providers = Self.providerShares(session)
        if !providers.isEmpty {
            CardContainer {
                VStack(alignment: .leading, spacing: 10) {
                    CardTitle("Providers")
                    ForEach(providers, id: \.id) { provider in
                        ShareRow(
                            mark: .provider(provider.id),
                            name: VendorCatalog.vendorLabel(provider.id),
                            tokens: provider.tokens,
                            percent: provider.percent,
                            cost: nil
                        )
                    }
                }
            }
        }
    }

    // MARK: Notes

    private var notes: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let note = SessionText.usageSourceNote(session) {
                IncompleteNotice(verbatim: note)
            }
            Label {
                Text("Transcripts stay on the computer that recorded this session. The Hub syncs only its usage.")
                    .font(.footnote)
                    .foregroundStyle(TMTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.laptopcomputer")
                    .font(.footnote)
                    .foregroundStyle(TMTheme.muted)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Values

    /// The model table: `SessionRows.modelShares` for two or more models;
    /// a single model gets the same shape (its share, then whatever no model
    /// claimed), which the desktop has no tooltip for.
    static func modelShares(_ session: HubSession) -> [SessionModelShare] {
        let shares = SessionRows.modelShares(session)
        if !shares.isEmpty { return shares }
        let models = session.models.filter { $0.value > 0 }
        guard models.count == 1, let only = models.first else { return [] }
        let model = only.key
        let tokens = only.value
        let total = max(session.totalTokens, tokens)
        let denominator = Double(total)
        guard !model.isEmpty else {
            return [SessionModelShare(model: nil, tokens: total, percent: 100)]
        }
        var rows = [SessionModelShare(model: model, tokens: tokens, percent: Double(tokens) / denominator * 100)]
        if total > tokens {
            rows.append(SessionModelShare(model: nil, tokens: total - tokens, percent: Double(total - tokens) / denominator * 100))
        }
        return rows
    }

    struct ProviderShare {
        let id: String
        let tokens: Int
        let percent: Double
    }

    /// The `providers` split, heaviest first, as a share of the session.
    static func providerShares(_ session: HubSession) -> [ProviderShare] {
        let entries = session.providers.filter { $0.value > 0 && !$0.key.isEmpty }
        let attributed = entries.values.reduce(0, +)
        let denominator = Double(max(session.totalTokens, attributed))
        guard denominator > 0 else { return [] }
        return entries
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { ProviderShare(id: $0.key, tokens: $0.value, percent: Double($0.value) / denominator * 100) }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

/// The session's state as a small badge: spinner, check or idle dot, and
/// the word (`session.running` / `finished` / `idle`).
private struct SessionStateBadge: View {
    let state: SessionActivityState

    var body: some View {
        let color = state == .running ? TMTheme.success : TMTheme.muted
        HStack(spacing: 4) {
            SessionStateGlyph(state: state, size: 10)
            Text(verbatim: SessionText.state(state))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// The session id with a copy button (`session.copyId`).
private struct SessionIDCard: View {
    let id: String
    @State private var copied = false

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle("Session ID")
                HStack(alignment: .top, spacing: 10) {
                    Text(verbatim: id)
                        .font(.footnote.monospaced())
                        .foregroundStyle(TMTheme.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button {
                        SessionClipboard.copy(id)
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .frame(minWidth: 20, minHeight: 20)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(Text("Copy session ID"))
                }
                if copied {
                    Text("Copied")
                        .font(.caption)
                        .foregroundStyle(TMTheme.success)
                        .transition(.opacity)
                }
            }
        }
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { copied = false }
        }
    }
}

/// The context window as a full-width bar, filled by the reading the user
/// chose (used by default) and tinted once headroom runs low.
private struct ContextWindowBar: View {
    let gauge: SessionContextGauge
    let metric: ContextMetric

    var body: some View {
        let fraction = min(1, max(0, Double(gauge.percent(for: metric)) / 100))
        Capsule()
            .fill(TMTheme.track)
            .frame(height: 8)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(gauge.tone == .neutral ? Color.white.opacity(0.55) : TMTheme.contextColor(gauge.tone))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A model or provider line: mark, name, full tokens, share and cost.
private struct ShareRow: View {
    @Environment(\.tmFormatter) private var formatter
    @ScaledMetric(relativeTo: .subheadline) private var markSize: CGFloat = 14

    let mark: VendorMarkSubject?
    let name: String
    let tokens: Int
    let percent: Double
    let cost: Double?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                if let mark {
                    VendorMark(mark, size: markSize)
                } else {
                    MarkDot(color: TMTheme.muted)
                }
            }
            .frame(width: markSize, height: markSize)
            Text(verbatim: name)
                .font(.subheadline)
                .foregroundStyle(TMTheme.text)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: formatter.fullTokens(tokens))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.number)
                Text(verbatim: detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [AttributionRows.detailPercentLabel(percent)]
        if let cost, cost > 0 { parts.append(formatter.cost(cost)) }
        return parts.joined(separator: SessionText.separator)
    }
}

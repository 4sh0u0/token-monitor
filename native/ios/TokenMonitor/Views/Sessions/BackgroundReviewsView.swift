import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The Codex Auto Review runs the Sessions list collapses into one row
/// (desktop `renderBackgroundReviewDetail`): their count and totals, then
/// each run newest first, titled "model · time", with its id, tokens, cost
/// and a share bar. A run opens its detail.
struct BackgroundReviewsView: View {
    @Environment(AppModel.self) private var model
    let period: UsagePeriodKind

    var body: some View {
        ScreenScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScopeBadge()
                if let presented = model.presented {
                    let usage = presented.stats[period]
                    TimelineView(SessionLiveSchedule(sessions: usage.sessions.filter(\.isBackgroundReview))) { context in
                        let now = SessionLiveSchedule.now(context)
                        let runs = Self.runs(in: usage, titlesEnabled: model.preferences.sessionTitlesEnabled, now: now)
                        content(runs, now: now)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
        }
        .navigationTitle(Text(verbatim: SessionText.backgroundReviews))
    }

    /// The background-review runs of `usage`, newest first, as the group
    /// row holds them.
    static func runs(in usage: UsagePeriod, titlesEnabled: Bool, now: Date) -> [SessionRow] {
        SessionRows.rows(period: usage, titlesEnabled: titlesEnabled, now: now)
            .first(where: \.isReviewGroup)?
            .reviewRows ?? []
    }

    @ViewBuilder
    private func content(_ runs: [SessionRow], now: Date) -> some View {
        if runs.isEmpty {
            CardContainer {
                Text("No activity in this period.")
                    .font(.subheadline)
                    .foregroundStyle(TMTheme.muted)
            }
        } else {
            let tokens = runs.reduce(0) { $0 + $1.tokens }
            let cost = runs.reduce(0.0) { $0 + $1.costUsd }
            let maximum = runs.map(\.tokens).max() ?? 0
            VStack(alignment: .leading, spacing: 12) {
                CardContainer {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: SessionText.backgroundRuns(runs.count))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TMTheme.text)
                        Text(verbatim: summary(tokens: tokens, cost: cost))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(TMTheme.muted)
                        Text(verbatim: period.title)
                            .font(.caption)
                            .foregroundStyle(TMTheme.muted)
                    }
                    .accessibilityElement(children: .combine)
                }
                CardContainer(padding: 0) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                            if index > 0 {
                                SessionRowDivider(leading: 14)
                            }
                            Button {
                                if let session = run.session {
                                    SessionDetailOrigin.open(session.id, period: period, model: model)
                                }
                            } label: {
                                BackgroundReviewRunRow(run: run, maximum: maximum, now: now)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if let id = run.idLabel {
                                    SessionCopyIDButton(id: id)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    /// "{tokens} · {cost}" (the desktop's `.background-review-totals`).
    @MainActor
    private func summary(tokens: Int, cost: Double) -> String {
        model.formatter.fullTokens(tokens) + SessionText.separator + model.formatter.cost(cost)
    }
}

/// One run: "model · time", its id, full tokens, cost and a share bar.
private struct BackgroundReviewRunRow: View {
    @Environment(\.tmFormatter) private var formatter
    @Environment(\.tmPresentation) private var presentation
    @ScaledMetric(relativeTo: .subheadline) private var markSize: CGFloat = 16

    let run: SessionRow
    let maximum: Int
    let now: Date

    var body: some View {
        let color = SessionColor.color(client: run.client, model: run.modelLabel, key: run.session?.id ?? run.id, palette: presentation.palette)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                SessionMark(client: run.client, color: color, isRunning: run.isRunning, size: markSize)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(TMTheme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let id = run.idLabel {
                        Text(verbatim: id)
                            .font(.caption2)
                            .foregroundStyle(TMTheme.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(verbatim: formatter.fullTokens(run.tokens))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(TMTheme.number)
                    CostLabelText(usd: run.costUsd, unpricedTokens: run.unpricedTokens)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(TMTheme.muted)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TMTheme.muted.opacity(0.6))
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
            SessionShareBar(value: run.tokens, maximum: maximum, color: color)
                .padding(.leading, markSize + 10)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// `[modelLabel, time].join(' · ') || 'Codex Auto Review'`.
    private var title: String {
        let parts = [SessionText.modelLabel(run.modelLabel), run.timeLabel].compactMap { $0 }
        return parts.isEmpty ? SessionText.backgroundReviews : parts.joined(separator: SessionText.separator)
    }
}

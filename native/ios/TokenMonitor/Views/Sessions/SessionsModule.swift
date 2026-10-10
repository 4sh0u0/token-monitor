import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The Overview's Sessions module (desktop `renderHomeSessionModule`): the
/// five most recent sessions of this month and today, plus every session
/// still running beyond them, with "{n} running" in the header. Each row
/// shows its state glyph, client mark, name (title, project or the start of
/// its id), compact tokens, its models and age, and the context gauge or
/// prompt-cache countdown. The header opens the Sessions list; a row opens
/// its detail.
///
/// A self-contained card, like the other Overview modules; follows the
/// device scope, not the selected period (the desktop module always reads
/// month and today).
struct SessionsModule: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        CardContainer {
            if let stats = model.presented?.stats {
                TimelineView(SessionLiveSchedule(sessions: stats.month.sessions + stats.today.sessions)) { context in
                    let now = SessionLiveSchedule.now(context)
                    let recent = SessionRows.recent(
                        month: stats.month,
                        today: stats.today,
                        titlesEnabled: model.preferences.sessionTitlesEnabled,
                        now: now
                    )
                    content(recent, stats: stats, now: now)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ModuleHeader(title: "Sessions", route: .sessions)
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ recent: RecentSessions, stats: HubStats, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader(title: "Sessions", route: .sessions) {
                if recent.runningCount > 0 {
                    Text(verbatim: SessionText.running(recent.runningCount))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TMTheme.success)
                }
            }
            if recent.rows.isEmpty {
                Text("No sessions in this period")
                    .font(.subheadline)
                    .foregroundStyle(TMTheme.muted)
            } else {
                VStack(spacing: 10) {
                    ForEach(recent.rows) { row in
                        Button {
                            let period: UsagePeriodKind = stats.month.sessions.contains { $0.id == row.id } ? .month : .today
                            SessionDetailOrigin.open(row.id, period: period, model: model)
                        } label: {
                            RecentSessionRow(row: row, now: now, metric: model.preferences.sessionContextMetric)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// One row of the Sessions module.
private struct RecentSessionRow: View {
    @Environment(\.tmFormatter) private var formatter
    @Environment(\.tmPresentation) private var presentation
    @ScaledMetric(relativeTo: .subheadline) private var markSize: CGFloat = 15
    @ScaledMetric(relativeTo: .subheadline) private var glyphSize: CGFloat = 12

    let row: RecentSession
    let now: Date
    let metric: ContextMetric

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VendorMark(
                .client(row.client),
                size: markSize,
                dotColor: SessionColor.color(client: row.client, model: row.modelLabel, key: row.id, palette: presentation.palette)
            )
            .padding(.top, 1)
            SessionStateGlyph(state: row.state, size: glyphSize)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: SessionText.recentName(row.name))
                        .font(.subheadline)
                        .foregroundStyle(TMTheme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(verbatim: formatter.compactTokens(row.tokens))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(TMTheme.number)
                        .lineLimit(1)
                }
                HStack(alignment: .center, spacing: 8) {
                    if !meta.isEmpty {
                        Text(verbatim: meta)
                            .font(.caption)
                            .foregroundStyle(TMTheme.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    SessionGaugeSlot(
                        context: row.context,
                        promptCache: row.showsPromptCache ? row.promptCache : nil,
                        metric: metric
                    )
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .accessibilityValue(Text(verbatim: accessibilityValue))
    }

    /// Models and age: "claude-sonnet-4-5 · 4m ago", "3 models · 2h ago".
    private var meta: String {
        let age = SessionRows.age(of: row.activityTime, now: now).map(SessionText.age)
        return [SessionText.modelLabel(row.modelLabel), age]
            .compactMap { $0 }
            .joined(separator: SessionText.separator)
    }

    private var accessibilityLabel: String {
        [SessionText.recentName(row.name), SessionText.state(row.state), meta]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var accessibilityValue: String {
        var parts = [formatter.compactTokens(row.tokens) + " " + String(localized: "tokens")]
        if let context = row.context {
            parts.append(SessionText.contextPercent(context, metric: metric, formatter: formatter))
        } else if row.showsPromptCache, let cache = row.promptCache {
            parts.append(SessionText.cacheLeft(cache))
        }
        return parts.joined(separator: ", ")
    }
}

import SwiftUI
import TokenMonitorKit
import TokenMonitorUI
#if canImport(UIKit)
import UIKit
#endif

/// The Sessions list (desktop Sessions view, `sessionRowsForPeriod`): every
/// session of the selected period with tokens, newest first, 100 per page,
/// the background-review runs collapsed into one "Codex Auto Review" row at
/// the end. Follows the global period and device scope.
///
/// The Hub has session details for today and this month only: all time
/// (kept on each computer) and the fixed ranges (derived from History) show
/// why instead, with a way back to a period that has them.
struct SessionsView: View {
    @Environment(AppModel.self) private var model
    @State private var pageIndex = 0

    private static let topID = "sessions-top"

    var body: some View {
        ScreenScrollView {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 16) {
                    header
                        .id(Self.topID)
                    content(scrollToTop: {
                        withAnimation(.snappy) { proxy.scrollTo(Self.topID, anchor: .top) }
                    })
                }
            }
        }
        .navigationTitle(Text("Sessions"))
        .onChange(of: model.selectedPeriod) {
            pageIndex = 0
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScopeBadge()
            Picker("Period", selection: periodBinding) {
                ForEach(model.periodChoices) { choice in
                    Text(verbatim: choice.shortTitle).tag(choice)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var periodBinding: Binding<PeriodSelection> {
        Binding(
            get: { model.selectedPeriod },
            set: { model.selectPeriod($0) }
        )
    }

    @ViewBuilder
    private func content(scrollToTop: @escaping () -> Void) -> some View {
        if let presented = model.presented {
            if let kind = model.selectedPeriod.nativeKind, kind != .allTime {
                SessionsList(
                    usage: presented.stats[kind],
                    kind: kind,
                    isIncomplete: Self.isIncomplete(presented, kind: kind),
                    pageIndex: $pageIndex,
                    scrollToTop: scrollToTop
                )
            } else {
                unavailable
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
    }

    /// All time and the fixed ranges carry no sessions on a Hub.
    private var unavailable: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                if model.selectedPeriod == .allTime {
                    Label {
                        Text("The Hub keeps session details for today and this month only.")
                            .font(.footnote)
                            .foregroundStyle(TMTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(TMTheme.muted)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    PeriodUnavailableNote(reason: .sessions)
                }
                HStack(spacing: 10) {
                    Button(UsagePeriodKind.today.title) {
                        model.selectPeriod(.today)
                    }
                    Button(UsagePeriodKind.month.title) {
                        model.selectPeriod(.month)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    /// `sessions.incomplete`: the scoped device's own omission count, else
    /// the aggregate's.
    static func isIncomplete(_ presented: ScopedStats, kind: UsagePeriodKind) -> Bool {
        if let device = presented.device {
            return SessionRows.isIncomplete(device: device, period: kind)
        }
        return SessionRows.isIncomplete(stats: presented.stats, period: kind)
    }
}

/// One period's rows, re-evaluated whenever a session's live state changes
/// (and at least each minute).
private struct SessionsList: View {
    @Environment(AppModel.self) private var model
    let usage: UsagePeriod
    let kind: UsagePeriodKind
    let isIncomplete: Bool
    @Binding var pageIndex: Int
    let scrollToTop: () -> Void

    var body: some View {
        TimelineView(SessionLiveSchedule(sessions: usage.sessions)) { context in
            let now = SessionLiveSchedule.now(context)
            let rows = SessionRows.rows(
                period: usage,
                titlesEnabled: model.preferences.sessionTitlesEnabled,
                now: now
            )
            let page = SessionRows.page(rows, index: pageIndex)
            VStack(alignment: .leading, spacing: 12) {
                if isIncomplete {
                    IncompleteNotice(text: "Some session details were omitted to keep synchronized data within the upload limit. Period totals remain complete.")
                }
                if rows.isEmpty {
                    CardContainer {
                        Text("No sessions in this period")
                            .font(.subheadline)
                            .foregroundStyle(TMTheme.muted)
                    }
                } else {
                    rowsCard(page, maximum: rows.map(\.tokens).max() ?? 0)
                    if page.isPaginated {
                        pager(page)
                    }
                }
            }
        }
    }

    private func rowsCard(_ page: SessionPage, maximum: Int) -> some View {
        CardContainer(padding: 0) {
            LazyVStack(spacing: 0) {
                ForEach(Array(page.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        SessionRowDivider(leading: 14)
                    }
                    rowButton(row, maximum: maximum)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func rowButton(_ row: SessionRow, maximum: Int) -> some View {
        Button {
            if row.isReviewGroup {
                model.navigate(to: .backgroundReviews(kind))
            } else if let session = row.session {
                SessionDetailOrigin.open(session.id, period: kind, model: model)
            }
        } label: {
            SessionListRow(row: row, maximum: maximum, metric: model.preferences.sessionContextMetric)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let id = row.idLabel {
                SessionCopyIDButton(id: id)
            }
        }
    }

    private func pager(_ page: SessionPage) -> some View {
        HStack(spacing: 12) {
            Button {
                pageIndex = max(0, page.index - 1)
                scrollToTop()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 28, minHeight: 28)
            }
            .disabled(page.index == 0)
            .accessibilityLabel(Text("Previous page"))
            Spacer(minLength: 8)
            Text(verbatim: SessionText.pageRange(page))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(TMTheme.muted)
            Spacer(minLength: 8)
            Button {
                pageIndex = min(page.pageCount - 1, page.index + 1)
                scrollToTop()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 28, minHeight: 28)
            }
            .disabled(page.index >= page.pageCount - 1)
            .accessibilityLabel(Text("Next page"))
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Session pages"))
    }
}

/// "Copy session ID" for a row's context menu.
struct SessionCopyIDButton: View {
    let id: String

    var body: some View {
        Button {
            SessionClipboard.copy(id)
        } label: {
            Label("Copy session ID", systemImage: "doc.on.doc")
        }
    }
}

enum SessionClipboard {
    @MainActor
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}

import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The toolbar's live-update state: a coloured dot and a word ("Live", or
/// "Every 5 min" in an interval refresh mode).
struct LiveStatusIndicator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            title
                .font(.caption.weight(.medium))
                .foregroundStyle(TMTheme.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: Text {
        if model.issue != nil, model.liveState != .streaming { return Text("Offline") }
        switch model.liveState {
        case .streaming: return Text("Live")
        case .polling: return Text("Polling")
        case .periodic:
            let minutes = Int(((model.pollInterval ?? 60) / 60).rounded())
            return Text("Every \(minutes) min")
        case .connecting: return Text("Connecting")
        case .idle: return Text("Paused")
        }
    }

    private var color: Color {
        if model.issue != nil, model.liveState != .streaming { return TMTheme.critical }
        switch model.liveState {
        case .streaming, .periodic: return TMTheme.success
        case .polling: return TMTheme.warning
        case .connecting, .idle: return TMTheme.muted
        }
    }
}

/// Shown above the content when the last refresh failed but earlier numbers
/// are still on screen: what went wrong and how old the numbers are.
struct StatusBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let issue = model.issue, model.stats != nil {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(TMTheme.warning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TMTheme.text)
                        if let updated = model.lastUpdated {
                            Text("Updated \(AppFormat.ago(updated, now: context.date))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(TMTheme.warning)
                        }
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(TMTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if issue.suggestsSettings {
                            Button("Open Settings") {
                                model.selectedTab = .settings
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TMTheme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(TMTheme.warning.opacity(0.3), lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// What a tab shows before any stats arrived: progress, or the error with a
/// way to fix it.
struct DataPlaceholder: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let issue = model.issue {
                ContentUnavailableView {
                    Label(issue.title, systemImage: issue.kind == .unreachable ? "wifi.exclamationmark" : "exclamationmark.triangle")
                } description: {
                    VStack(spacing: 6) {
                        Text(issue.message)
                        if let detail = issue.detail, !detail.isEmpty {
                            Text(verbatim: detail)
                                .font(.footnote)
                                .foregroundStyle(TMTheme.muted)
                        }
                    }
                } actions: {
                    Button("Try Again") {
                        Task { await model.refresh() }
                    }
                    .buttonStyle(.bordered)
                    Button("Open Settings") {
                        model.selectedTab = .settings
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Connecting to your Hub…")
                        .font(.subheadline)
                        .foregroundStyle(TMTheme.muted)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}

/// An empty section: nothing to show yet, and why.
struct EmptyStateCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String

    var body: some View {
        CardContainer(padding: 20) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(TMTheme.muted)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TMTheme.text)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(TMTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }
}

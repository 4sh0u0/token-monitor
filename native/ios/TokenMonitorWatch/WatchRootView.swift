import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

struct WatchRootView: View {
    let store: WatchStore

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("watchPeriod") private var period: UsagePeriodKind = .today

    var body: some View {
        NavigationStack {
            content
        }
        .task(id: scenePhase) {
            // Polls only while the app is on screen; the task is cancelled
            // when the wrist drops.
            guard scenePhase == .active else { return }
            await store.runWhileActive()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                store.didLeaveForeground()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !store.isConfigured {
            WatchNotConfiguredView()
        } else if let snapshot = store.snapshot {
            TabView {
                WatchUsagePage(store: store, snapshot: snapshot, period: $period)
                WatchToolsPage(snapshot: snapshot, period: period)
                WatchLimitsPage(snapshot: snapshot)
                WatchStatusPage(store: store, snapshot: snapshot)
            }
            .tabViewStyle(.verticalPage)
        } else if let error = store.lastError {
            WatchErrorView(error: error) {
                Task { await store.refresh(force: true) }
            }
        } else {
            WatchLoadingView()
        }
    }
}

struct WatchNotConfiguredView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "iphone")
                    .font(.title2)
                    .foregroundStyle(TMTheme.accent)
                    .accessibilityHidden(true)
                Text("Open Token Monitor on your iPhone to connect a Hub")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(TMTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") {
                    WatchSessionBridge.shared.requestSync(force: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .containerBackground(for: .navigation) { TMBackground() }
    }
}

struct WatchErrorView: View {
    let error: HubClientError
    let retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(TMTheme.warning)
                    .accessibilityHidden(true)
                Text(WatchText.errorMessage(error))
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(TMTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again", action: retry)
            }
            .frame(maxWidth: .infinity)
        }
        .containerBackground(for: .navigation) { TMBackground() }
    }
}

struct WatchLoadingView: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Waiting for data")
                .font(.footnote)
                .foregroundStyle(TMTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .navigation) { TMBackground() }
    }
}

/// When the numbers were fetched, and whether to trust them: a failed
/// refresh or old data is called out above the time.
struct WatchFreshnessLine: View {
    let store: WatchStore
    let snapshot: TokenSnapshot

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                if store.lastError != nil {
                    Label("Refresh failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(TMTheme.warning)
                } else if store.isStale(at: context.date) {
                    Label("Data may be stale", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(TMTheme.caution)
                }
                Text("Updated \(snapshot.fetchedAt, format: .relative(presentation: .named))")
                    .foregroundStyle(TMTheme.muted)
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}

extension UsagePeriodKind {
    /// The period the toolbar button switches to.
    var next: UsagePeriodKind {
        switch self {
        case .today: return .month
        case .month: return .allTime
        case .allTime: return .today
        }
    }
}

#Preview("Not configured") {
    NavigationStack {
        WatchNotConfiguredView()
    }
}

#Preview("Error") {
    NavigationStack {
        WatchErrorView(error: .transport("offline")) {}
    }
}

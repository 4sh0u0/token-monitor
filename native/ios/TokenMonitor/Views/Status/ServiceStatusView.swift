import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The Status tab (and Settings › Service status while the tab is hidden):
/// the vendors' public Statuspage summaries for Claude, OpenAI, Cursor and
/// DeepSeek, read straight from each vendor (never through the Hub), in the
/// user's order without the hidden ones (`ServiceStatusStore`).
///
/// Like the desktop's view, the re-check timer runs only while the screen
/// is visible (`start()` / `stop()`), the first visit checks at once, a row
/// opens the vendor's status page, and the "checked … ago" ages tick every
/// second. Pull to refresh and the toolbar button skip the 60 s cache.
///
/// A tab root: it adds no `NavigationStack` (RootView owns one per tab).
struct ServiceStatusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        let store = model.serviceStatus
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store.allHidden {
                    EmptyStateCard(
                        title: "All services hidden",
                        message: "Choose the services to show in Status settings.",
                        systemImage: "eye.slash"
                    )
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(spacing: 12) {
                            ForEach(store.providers) { provider in
                                ServiceStatusRow(
                                    provider: provider,
                                    summary: store.summary(for: provider.id),
                                    isChecking: store.isLoading,
                                    now: context.date
                                )
                            }
                        }
                    }
                }
                Label {
                    Text("Checked directly on each service’s public status page. Nothing from your Hub is sent.")
                        .font(.footnote)
                        .foregroundStyle(TMTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(TMTheme.muted)
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)
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
            await store.refresh(force: true)
        }
        .navigationTitle("Status")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await store.refresh(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isLoading || store.allHidden)
                NavigationLink(value: AppRoute.serviceStatusSettings) {
                    Label("Status settings", systemImage: "slider.horizontal.3")
                }
            }
        }
        .onAppear {
            isVisible = true
            store.start()
        }
        .onDisappear {
            isVisible = false
            store.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            // A tab kept alive behind another one must not start checking.
            guard isVisible else { return }
            switch phase {
            case .active: store.start()
            case .background: store.stop()
            default: break
            }
        }
    }
}

/// One service: its mark (omitted while tool icons are off, as on the
/// desktop), name and status pill; the active incident or the vendor's own
/// description; then the affected components, the counts and how long ago it
/// was checked. Tapping opens the vendor's status page.
private struct ServiceStatusRow: View {
    @Environment(\.openURL) private var openURL
    let provider: ServiceStatusProvider
    let summary: ServiceStatusSummary?
    let isChecking: Bool
    let now: Date

    var body: some View {
        let tone = summary?.tone ?? .unknown
        Button {
            openURL(summary?.pageURL ?? provider.pageURL)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    VendorMark(.provider(provider.markID), size: 18, hidesWhenIconsOff: true)
                    Text(verbatim: provider.label)
                        .font(.headline)
                        .foregroundStyle(TMTheme.text)
                    Spacer(minLength: 8)
                    ServiceStatusPill(tone: tone)
                }
                headline
                    .font(.subheadline)
                    .foregroundStyle(TMTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if let summary {
                    let names = summary.affectedNames()
                    if !names.visible.isEmpty {
                        Text(verbatim: ServiceStatusText.affectedList(names))
                            .font(.caption)
                            .foregroundStyle(TMTheme.muted)
                            .lineLimit(2)
                    }
                    Text(verbatim: ServiceStatusText.meta(summary, now: now))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(TMTheme.muted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TMTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(ServiceStatusPill.border(tone), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Open \(provider.label) status page"))
    }

    @ViewBuilder
    private var headline: some View {
        if let summary {
            if summary.isCheckFailure {
                Text("Status check failed")
            } else {
                let text = summary.headline
                if text.isEmpty || (summary.incidentTitle == nil && text == "Unknown") {
                    Text("Unknown")
                } else {
                    Text(verbatim: text)
                }
            }
        } else if isChecking {
            Text("Checking status...")
                .foregroundStyle(TMTheme.muted)
        } else {
            Text("Not checked")
                .foregroundStyle(TMTheme.muted)
        }
    }
}

/// `.service-status-pill`: the overall state in the tone's colour.
private struct ServiceStatusPill: View {
    let tone: ServiceStatusTone

    var body: some View {
        title
            .font(.caption.weight(.semibold))
            .foregroundStyle(Self.color(tone))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Self.color(tone).opacity(0.14), in: Capsule())
    }

    private var title: Text {
        switch tone {
        case .ok: return Text("Operational")
        case .degraded: return Text("Degraded")
        case .outage: return Text("Outage")
        case .unknown: return Text("Unknown")
        }
    }

    /// Degraded and outage cards carry a faint border of their tone.
    static func border(_ tone: ServiceStatusTone) -> Color {
        switch tone {
        case .degraded, .outage: return color(tone).opacity(0.35)
        case .ok, .unknown: return TMTheme.cardStroke
        }
    }

    static func color(_ tone: ServiceStatusTone) -> Color {
        switch tone {
        case .ok: return TMTheme.success
        case .degraded: return TMTheme.warning
        case .outage: return TMTheme.critical
        case .unknown: return TMTheme.muted
        }
    }
}

/// The rows' second and third lines (`serviceStatusMeta`, `formatAgo`).
enum ServiceStatusText {
    /// "Affected: 3 · Incidents: 1 · 12s ago", "No active issues · 2m ago".
    static func meta(_ summary: ServiceStatusSummary, now: Date) -> String {
        let meta = ServiceStatusPresentation.meta(summary)
        var parts: [String] = []
        if meta.affectedCount > 0 { parts.append(String(localized: "Affected: \(meta.affectedCount)")) }
        if meta.incidentCount > 0 { parts.append(String(localized: "Incidents: \(meta.incidentCount)")) }
        if meta.maintenanceCount > 0 { parts.append(String(localized: "Maintenance: \(meta.maintenanceCount)")) }
        if !meta.hasCounts, meta.showsNoIssues { parts.append(String(localized: "No active issues")) }
        parts.append(ago(ServiceStatusPresentation.agoBucket(since: summary.checkedAt, now: now)))
        return parts.joined(separator: " · ")
    }

    static func ago(_ bucket: ServiceStatusPresentation.AgoBucket) -> String {
        switch bucket.unit {
        case .seconds: return String(localized: "\(bucket.value)s ago")
        case .minutes: return String(localized: "\(bucket.value)m ago")
        case .hours: return String(localized: "\(bucket.value)h ago")
        }
    }

    /// The affected components' names, the first two and "+N" more (the
    /// desktop keeps them in the row's tooltip).
    static func affectedList(_ names: ServiceStatusPresentation.AffectedNames) -> String {
        let list = names.visible.formatted(.list(type: .and, width: .narrow))
        return names.overflow > 0 ? "\(list) +\(names.overflow)" : list
    }
}

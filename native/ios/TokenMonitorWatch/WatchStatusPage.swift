import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Page 4: devices reporting to the Hub, the Hub itself, and a manual refresh.
struct WatchStatusPage: View {
    let store: WatchStore
    let snapshot: TokenSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(verbatim: "\(snapshot.devices.online)")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(TMTheme.number)
                    Text(verbatim: "/\(snapshot.devices.total)")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(TMTheme.muted)
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(snapshot.devices.online)/\(snapshot.devices.total) online"))
                Text("Online")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(snapshot.devices.online > 0 ? TMTheme.success : TMTheme.muted)
                    .accessibilityHidden(true)
                if let lastActivity = snapshot.sourceUpdatedAt {
                    TimelineView(.everyMinute) { _ in
                        Text("Last activity \(lastActivity, format: .relative(presentation: .named))")
                            .font(.caption2)
                            .foregroundStyle(TMTheme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Divider()
                    .padding(.vertical, 2)
                if let host = store.hubHost {
                    Label(host, systemImage: "server.rack")
                        .font(.caption2)
                        .foregroundStyle(TMTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                WatchFreshnessLine(store: store, snapshot: snapshot)
                Button {
                    Task { await store.refresh(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Devices")
        .containerBackground(for: .tabView) { TMBackground() }
    }
}

#Preview {
    NavigationStack {
        WatchStatusPage(store: WatchStore(), snapshot: .watchSample)
    }
}

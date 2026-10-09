import SwiftUI
import TokenMonitorKit

@main
struct TokenMonitorWatchApp: App {
    @State private var store = WatchStore()

    init() {
        // Activated here, not in a view, so a background launch for a
        // WatchConnectivity delivery has a delegate before content arrives.
        WatchSessionBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(store: store)
        }
        .backgroundTask(.watchConnectivity) {
            await WatchSessionBridge.shared.finishPendingDeliveries()
        }
    }
}

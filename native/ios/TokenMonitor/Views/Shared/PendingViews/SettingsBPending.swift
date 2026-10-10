import SwiftUI
import TokenMonitorKit

// TEMPORARY (Phase 3a): placeholders so `AppRouteDestination` and the
// Overview modules compile before Phase 3b lands the real views.
// SETTINGS-B deletes THIS FILE in the change that adds the real
// SubscriptionsView, HubInfoView, ServiceStatusView.
// The real views keep these names and initializers.

struct SubscriptionsView: View {
    var body: some View {
        PendingScreen(name: "SubscriptionsView")
    }
}

struct HubInfoView: View {
    var body: some View {
        PendingScreen(name: "HubInfoView")
    }
}

struct ServiceStatusView: View {
    var body: some View {
        PendingScreen(name: "ServiceStatusView")
    }
}

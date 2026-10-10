import SwiftUI
import TokenMonitorKit

// TEMPORARY (Phase 3a): placeholders so `AppRouteDestination` and the
// Overview modules compile before Phase 3b lands the real views.
// DEVICES deletes THIS FILE in the change that adds the real
// DeviceDetailView, DevicesModule.
// The real views keep these names and initializers.

struct DeviceDetailView: View {
    let deviceID: String

    var body: some View {
        PendingScreen(name: "DeviceDetailView")
    }
}

/// Overview module placeholder; the real one takes no parameters and reads
/// `@Environment(AppModel.self)`.
struct DevicesModule: View {
    var body: some View {
        EmptyView()
    }
}

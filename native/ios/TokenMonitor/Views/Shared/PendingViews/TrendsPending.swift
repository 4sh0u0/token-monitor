import SwiftUI
import TokenMonitorKit

// TEMPORARY (Phase 3a): placeholders so `AppRouteDestination` and the
// Overview modules compile before Phase 3b lands the real views.
// TRENDS deletes THIS FILE in the change that adds the real
// TrendsView, ActivityModule.
// The real views keep these names and initializers.

struct TrendsView: View {
    var body: some View {
        PendingScreen(name: "TrendsView")
    }
}

/// Overview module placeholder; the real one takes no parameters and reads
/// `@Environment(AppModel.self)`.
struct ActivityModule: View {
    var body: some View {
        EmptyView()
    }
}

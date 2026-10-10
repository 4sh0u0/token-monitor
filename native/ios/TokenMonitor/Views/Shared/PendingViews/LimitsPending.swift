import SwiftUI
import TokenMonitorKit

// TEMPORARY (Phase 3a): placeholders so `AppRouteDestination` and the
// Overview modules compile before Phase 3b lands the real views.
// LIMITS deletes THIS FILE in the change that adds the real
// HomeLimitsModule.
// The real views keep these names and initializers.

/// Overview module placeholder; the real one takes no parameters and reads
/// `@Environment(AppModel.self)`.
struct HomeLimitsModule: View {
    var body: some View {
        EmptyView()
    }
}

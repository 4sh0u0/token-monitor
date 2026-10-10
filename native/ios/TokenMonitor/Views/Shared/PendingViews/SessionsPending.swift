import SwiftUI
import TokenMonitorKit

// TEMPORARY (Phase 3a): placeholders so `AppRouteDestination` and the
// Overview modules compile before Phase 3b lands the real views.
// SESSIONS deletes THIS FILE in the change that adds the real
// SessionsView, SessionDetailView, BackgroundReviewsView, SessionsModule.
// The real views keep these names and initializers.

struct SessionsView: View {
    var body: some View {
        PendingScreen(name: "SessionsView")
    }
}

struct SessionDetailView: View {
    let sessionID: String

    var body: some View {
        PendingScreen(name: "SessionDetailView")
    }
}

struct BackgroundReviewsView: View {
    let period: UsagePeriodKind

    var body: some View {
        PendingScreen(name: "BackgroundReviewsView")
    }
}

/// Overview module placeholder; the real one takes no parameters and reads
/// `@Environment(AppModel.self)`.
struct SessionsModule: View {
    var body: some View {
        EmptyView()
    }
}

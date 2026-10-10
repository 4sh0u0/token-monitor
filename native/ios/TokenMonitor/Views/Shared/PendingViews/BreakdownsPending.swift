import SwiftUI
import TokenMonitorKit

// TEMPORARY (Phase 3a): placeholders so `AppRouteDestination` and the
// Overview modules compile before Phase 3b lands the real views.
// BREAKDOWNS deletes THIS FILE in the change that adds the real
// ToolsView, ModelsView, ProjectsView.
// The real views keep these names and initializers.

struct ToolsView: View {
    var body: some View {
        PendingScreen(name: "ToolsView")
    }
}

struct ModelsView: View {
    var body: some View {
        PendingScreen(name: "ModelsView")
    }
}

struct ProjectsView: View {
    var body: some View {
        PendingScreen(name: "ProjectsView")
    }
}

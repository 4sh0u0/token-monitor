import SwiftUI
import TokenMonitorUI

// TEMPORARY (Phase 3a): the body of the placeholder screens in this folder.
// Deleted with the last placeholder file once Phase 3b has landed every
// real view (the orchestrator removes the whole `PendingViews` folder).

/// A screen that is not built yet. Not localized on purpose: it never ships.
struct PendingScreen: View {
    let name: String

    var body: some View {
        Text(verbatim: name)
            .font(.footnote.monospaced())
            .foregroundStyle(TMTheme.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                TMBackground().ignoresSafeArea()
            }
    }
}

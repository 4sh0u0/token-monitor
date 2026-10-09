import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

@main
struct TokenMonitorApp: App {
    @State private var model: AppModel
    /// Read here, in the `App`, it is the aggregate of every window (iPad
    /// multitasking): active while any is, background only when all are. A
    /// per-window phase would let one window going to the background stop
    /// live updates for one still on screen.
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Before the model exists, so the bridge is activated before the first push.
        PhoneSessionBridge.shared.activate()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // TMTheme is dark-first (its surfaces are white-on-dark), so the
                // app keeps the desktop widget's dark look in light mode too.
                .preferredColorScheme(.dark)
                .tint(TMTheme.accent)
                .onOpenURL { url in
                    model.open(url)
                }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.scenePhaseChanged(phase)
        }
    }
}

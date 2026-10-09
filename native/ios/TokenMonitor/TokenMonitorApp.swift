import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

@main
struct TokenMonitorApp: App {
    @State private var model: AppModel

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
    }
}

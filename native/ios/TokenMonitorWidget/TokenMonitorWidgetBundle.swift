import SwiftUI
import WidgetKit

@main
struct TokenMonitorWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
        LimitsWidget()
        ActivityWidget()
    }
}

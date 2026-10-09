import SwiftUI
import WidgetKit

@main
struct TokenMonitorWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageComplication()
        QuotaComplication()
    }
}

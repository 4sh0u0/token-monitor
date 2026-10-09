import Foundation
import SwiftUI
import TokenMonitorKit
import TokenMonitorUI
import WidgetKit

/// Widget kinds. The app reloads every timeline at once
/// (`WidgetCenter.reloadAllTimelines()`), so nothing outside this target needs
/// them; they must never change, or placed widgets lose their configuration.
enum WidgetKind {
    static let usage = "TokenMonitorUsageWidget"
    static let limits = "TokenMonitorLimitsWidget"
}

/// `tokenmonitor://` links into the app (parsed by `DeepLink` in the app target).
enum WidgetLink {
    static let settings = url("tokenmonitor://settings")
    static let limits = url("tokenmonitor://limits")

    static func dashboard(_ period: UsagePeriodKind) -> URL {
        url("tokenmonitor://dashboard?period=\(period.rawValue)")
    }

    private static func url(_ string: String) -> URL {
        // The literals above are valid; the fallback only keeps this total.
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }
}

enum WidgetTiming {
    /// A cached snapshot younger than this is shown as is; an older one makes
    /// the timeline provider ask the Hub first.
    static let refreshAfter: TimeInterval = 10 * 60
    /// The reload WidgetKit is asked for. Only a request: the daily budget
    /// decides when it actually happens.
    static let reloadInterval: TimeInterval = 15 * 60
    /// Data older than this is marked stale. Deliberately well past
    /// `reloadInterval`, because budget-limited reloads routinely run late and
    /// a widget that is working as designed should not look broken.
    static let staleAfter: TimeInterval = 30 * 60
    /// Reset/expiry boundaries within this horizon get their own timeline
    /// entry, so a live countdown is hidden once its moment has passed instead
    /// of counting up ("Reset in 3 min" turning into time since the reset).
    static let boundaryHorizon: TimeInterval = 12 * 60 * 60
    static let maxBoundaryEntries = 4
}

extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            return false
        }
    }
}

/// The frame every widget view is drawn in: the deep link, and the dark
/// Token Monitor background on the Home Screen. Lock Screen (accessory)
/// families get no background of their own — the system draws them.
struct WidgetChrome<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    private let url: URL
    private let content: Content

    init(url: URL, @ViewBuilder content: () -> Content) {
        self.url = url
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: fill, maxHeight: fill, alignment: .topLeading)
            // The Home Screen surfaces are designed dark-first (like the macOS
            // widget), so hierarchical styles must resolve against a dark
            // scheme even when the phone is in light mode.
            .environment(\.colorScheme, family.isAccessory ? colorScheme : .dark)
            // Widget sizes are fixed; past this size rows would be clipped
            // rather than grow.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .widgetURL(url)
            .containerBackground(for: .widget) {
                if family.isAccessory {
                    Color.clear
                } else {
                    TMBackground()
                }
            }
    }

    /// Home Screen content fills the widget; accessory content keeps its own size.
    private var fill: CGFloat? {
        family.isAccessory ? nil : CGFloat.infinity
    }
}

#if canImport(SwiftUI)
import SwiftUI
import TokenMonitorKit

// The user's display choices (units, currency, vendor colours, tool icons, …)
// travel down the view tree as one environment value, so shared views such as
// `VendorMark` read them without every caller threading them through. Each
// surface sets it once near its root:
//
//     ContentView().tmPresentation(model.context)

private struct TMPresentationKey: EnvironmentKey {
    static let defaultValue = PresentationContext.standard
}

private struct TMFormatterKey: EnvironmentKey {
    static let defaultValue = TMFormatterKey.formatter(for: .standard)

    static func formatter(for context: PresentationContext) -> DisplayFormatter {
        DisplayFormatter(preferences: context.preferences, rates: context.rates, languageIdentifier: context.languageIdentifier)
    }
}

extension EnvironmentValues {
    /// Preferences, exchange rates and UI language for this subtree;
    /// `PresentationContext.standard` when no surface set one.
    public var tmPresentation: PresentationContext {
        get { self[TMPresentationKey.self] }
        set {
            self[TMPresentationKey.self] = newValue
            // Built once per change rather than on every read.
            self[TMFormatterKey.self] = TMFormatterKey.formatter(for: newValue)
        }
    }

    /// The number and money formatter for `tmPresentation`, kept in step with
    /// it: `@Environment(\.tmFormatter) private var format`.
    public var tmFormatter: DisplayFormatter {
        self[TMFormatterKey.self]
    }
}

extension View {
    /// Sets the presentation context (and its formatter) for this subtree.
    public func tmPresentation(_ context: PresentationContext) -> some View {
        environment(\.tmPresentation, context)
    }
}
#endif

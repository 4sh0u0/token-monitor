import Foundation

/// Namespace for how Limits rows are presented on every surface (status
/// chip, freshness, meters, Home rows); presentation types that need no other
/// name live inside it.
public enum LimitPresentation {}

/// A limits provider's status chip: the desktop Settings-tag vocabulary
/// (`providerPresentation.js` `limitProviderStatusLabel`). Each case maps to
/// one desktop i18n key (`settings.limits.status.<case>`, with the two
/// exceptions `verifyInAntigravity` and `encryptedByApp`); targets localize it.
public enum LimitStatusLabel: String, Sendable, Codable, CaseIterable {
    case stale
    case verifyInAntigravity
    case encryptedByApp
    case live
    case linked
    case disabled
    case noSyncedData
    case updateCredential
    case updateApiKey
    case openCline
    case signInAgain
    case relogin
    case limited
    case usageApiLimited
    case unavailable
    case addCredential
    case notSetUp
    case signIn
    case addApiKey
    case runGrokLogin
    case runKiroLogin
    case error
}

/// The status chip's colour family (`styles.css` tag tones).
public enum LimitStatusTone: String, Sendable, Codable, CaseIterable {
    case ok
    case setup
    case warn
    case stale
    case sync
    case muted
}

/// Whether a meter reads what is left or what is used.
public enum MeterMode: String, Sendable, Codable, CaseIterable {
    case remaining
    case used
}

/// How to draw one quota meter.
public struct MeterFill: Sendable, Hashable {
    /// Bar fill 0–1; nil when the window has no meter.
    public var fraction: Double?
    /// The percentage the text shows (in `mode`), nil when unknown.
    public var percent: Double?
    /// What `fraction` and `percent` measure.
    public var mode: MeterMode
    /// Opacity of the provider colour for the fill, by tone.
    public var toneOpacity: Double

    public init(fraction: Double?, percent: Double?, mode: MeterMode, toneOpacity: Double) {
        self.fraction = fraction
        self.percent = percent
        self.mode = mode
        self.toneOpacity = toneOpacity
    }
}

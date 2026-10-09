import Foundation

/// The App Group shared by the iOS app, its widget extension, the watch app
/// and the watch widget extension.
///
/// The identifier is read from the running bundle's `TMAppGroup` Info.plist
/// key (set to `$(TM_APP_GROUP)` from `Config/Base.xcconfig`), so personal
/// identifiers live in the gitignored `Local.xcconfig`, never in code. The same
/// identifier is the Keychain access group for the Hub secret.
public enum AppGroup {
    public static let infoPlistKey = "TMAppGroup"

    /// Nil when the key is missing or still an unexpanded build setting.
    public static var identifier: String? {
        identifier(in: .main)
    }

    public static func identifier(in bundle: Bundle) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    /// The shared container, nil without the App Group entitlement (or off
    /// Apple platforms).
    public static var containerURL: URL? {
        #if canImport(Darwin)
        guard let identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        #else
        return nil
        #endif
    }

    /// The shared defaults suite, falling back to `.standard` when the group
    /// is unavailable (the app still works; widgets just cannot see it).
    public static var defaults: UserDefaults {
        identifier.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}

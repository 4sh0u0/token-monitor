import Foundation

/// The display preferences in the App Group's `UserDefaults`, as the JSON of
/// `DisplayPreferences` under `displayPreferences.v1`. The app writes them;
/// its widgets read them; on the watch the watch app writes the copy the
/// iPhone sends (`PreferencesPayload`) and its complications read it.
public struct PreferencesStore: @unchecked Sendable {
    // @unchecked: UserDefaults and NotificationCenter are thread-safe but not
    // annotated Sendable on every SDK this builds against.

    public static let key = "displayPreferences.v1"

    /// Posted (object: nil, on the saving thread) by `save(_:)` and `clear()`
    /// when the stored preferences changed. Same-process only: widgets are
    /// reloaded through WidgetCenter instead.
    public static let didChangeNotification = Notification.Name("TokenMonitorDisplayPreferencesDidChange")

    public let defaults: UserDefaults
    public let notificationCenter: NotificationCenter

    public init(defaults: UserDefaults, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    /// The App Group defaults (`.standard` in a build without the group).
    public static var shared: PreferencesStore {
        PreferencesStore(defaults: AppGroup.defaults)
    }

    /// The stored preferences, normalized; the defaults when nothing is
    /// stored or the stored value is not a JSON object.
    public func load() -> DisplayPreferences {
        guard let data = storedData(), let preferences = try? DisplayPreferences(jsonData: data) else {
            return .defaults
        }
        return preferences
    }

    /// Stores `preferences` normalized. Returns whether the stored value
    /// changed; only then is `didChangeNotification` posted.
    @discardableResult
    public func save(_ preferences: DisplayPreferences) -> Bool {
        guard let data = try? preferences.normalized().jsonData() else { return false }
        if storedData() == data { return false }
        defaults.set(data, forKey: Self.key)
        notificationCenter.post(name: Self.didChangeNotification, object: nil)
        return true
    }

    /// Applies `mutate` to the stored preferences and saves the result.
    /// Returns the preferences now stored.
    @discardableResult
    public func update(_ mutate: (inout DisplayPreferences) -> Void) -> DisplayPreferences {
        var preferences = load()
        mutate(&preferences)
        save(preferences)
        return preferences.normalized()
    }

    /// Back to the defaults (removes the stored value).
    public func clear() {
        guard defaults.object(forKey: Self.key) != nil else { return }
        defaults.removeObject(forKey: Self.key)
        notificationCenter.post(name: Self.didChangeNotification, object: nil)
    }

    private func storedData() -> Data? {
        if let data = defaults.data(forKey: Self.key) { return data }
        return defaults.string(forKey: Self.key).map { Data($0.utf8) }
    }
}

/// The preferences the iPhone sends the watch over WatchConnectivity, under
/// the context key `prefs` (`contextKey`), as `{v, preferences,
/// rateCacheData}` JSON in a `Data` value. It travels in the application
/// context and the sync reply, never in the complication user-info.
///
/// An old watch ignores the key; a new watch paired with an old phone never
/// receives it and keeps the defaults.
public struct PreferencesPayload: Codable, Equatable, Sendable {
    /// `v`. A payload with another version is not decoded.
    public static let version = 1
    /// The WatchConnectivity context and reply key.
    public static let contextKey = "prefs"
    /// The encoded payload's budget (round-2 plan §3.4).
    public static let defaultMaxBytes = 8192

    public var preferences: DisplayPreferences
    /// The phone's exchange-rate cache, as stored (an encoded
    /// `ExchangeRateCache`), so the watch converts costs with the same rates
    /// without fetching them itself. Nil when the phone has none.
    public var rateCacheData: Data?

    public init(preferences: DisplayPreferences, rateCacheData: Data? = nil) {
        self.preferences = preferences
        self.rateCacheData = rateCacheData
    }

    /// `encoded()` could not fit the budget even after dropping
    /// `vendorColors` and `limitProviderHiddenItems`.
    public struct TooLargeError: Error, Equatable, Sendable {
        public var byteCount: Int
        public var maxBytes: Int
    }

    private enum CodingKeys: String, CodingKey {
        case v, preferences, rateCacheData
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .v)
        guard version == Self.version else {
            throw DecodingError.dataCorruptedError(forKey: .v, in: container, debugDescription: "unsupported preferences payload version \(version)")
        }
        preferences = try container.decode(DisplayPreferences.self, forKey: .preferences)
        rateCacheData = (try? container.decodeIfPresent(Data.self, forKey: .rateCacheData)) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .v)
        try container.encode(preferences, forKey: .preferences)
        try container.encodeIfPresent(rateCacheData, forKey: .rateCacheData)
    }

    /// The payload's JSON (sorted keys, preferences normalized), at most
    /// `maxBytes`. Over budget, `vendorColors` is dropped first, then
    /// `limitProviderHiddenItems` (the watch then shows their defaults);
    /// still over, it throws `TooLargeError`.
    public func encoded(maxBytes: Int = PreferencesPayload.defaultMaxBytes) throws -> Data {
        var payload = self
        payload.preferences = preferences.normalized()
        var data = try Self.encode(payload)
        if data.count > maxBytes, !payload.preferences.vendorColors.isEmpty {
            payload.preferences.vendorColors = [:]
            data = try Self.encode(payload)
        }
        if data.count > maxBytes, !payload.preferences.limitProviderHiddenItems.isEmpty {
            payload.preferences.limitProviderHiddenItems = [:]
            data = try Self.encode(payload)
        }
        guard data.count <= maxBytes else {
            throw TooLargeError(byteCount: data.count, maxBytes: maxBytes)
        }
        return data
    }

    /// Nil for anything but a version-1 payload whose `preferences` is a JSON
    /// object; the preferences themselves decode leniently.
    public static func decode(_ data: Data) -> PreferencesPayload? {
        try? JSONDecoder().decode(PreferencesPayload.self, from: data)
    }

    private static func encode(_ payload: PreferencesPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }
}

import Foundation
#if canImport(Security)
import Security
#endif

/// Where the Hub secret is kept. The Keychain on Apple platforms; tests and
/// Linux use `InMemorySecretStorage`.
public protocol SecretStorage: Sendable {
    /// The stored secret, nil when none is stored.
    func readSecret() throws -> String?
    func writeSecret(_ secret: String) throws
    func deleteSecret() throws
}

public enum SecretStorageError: Error, Equatable, Sendable {
    /// The Keychain returned an `OSStatus` other than success / not found
    /// (e.g. `errSecInteractionNotAllowed` before first unlock).
    case keychain(status: Int32)
    case malformedItem
}

/// A process-local secret store for tests and previews.
public final class InMemorySecretStorage: SecretStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var secret: String?

    public init(secret: String? = nil) {
        self.secret = secret
    }

    public func readSecret() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return secret
    }

    public func writeSecret(_ secret: String) throws {
        lock.lock()
        defer { lock.unlock() }
        self.secret = secret
    }

    public func deleteSecret() throws {
        lock.lock()
        defer { lock.unlock() }
        secret = nil
    }
}

#if canImport(Security)
/// The Hub secret as a generic-password Keychain item.
///
/// `accessGroup` is the App Group identifier, so the app and its widget
/// extension (and, on the watch, the watch app and its widgets) read the same
/// item; App Group identifiers are valid Keychain access groups on iOS and
/// watchOS without a keychain-access-groups entitlement.
/// `kSecAttrAccessibleAfterFirstUnlock` lets widgets refresh while the device
/// is locked; the item is never synchronized through iCloud Keychain.
public struct KeychainSecretStorage: SecretStorage {
    public static let defaultService = "TokenMonitor.Hub"
    public static let defaultAccount = "hub-secret"

    public let service: String
    public let account: String
    public let accessGroup: String?

    public init(service: String = defaultService, account: String = defaultAccount, accessGroup: String? = AppGroup.identifier) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    public func readSecret() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
                throw SecretStorageError.malformedItem
            }
            return secret
        case errSecItemNotFound:
            return nil
        default:
            throw SecretStorageError.keychain(status: status)
        }
    }

    public func writeSecret(_ secret: String) throws {
        let data = Data(secret.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw SecretStorageError.keychain(status: updateStatus) }
        var item = baseQuery
        for (key, value) in attributes { item[key] = value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw SecretStorageError.keychain(status: addStatus) }
    }

    public func deleteSecret() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStorageError.keychain(status: status)
        }
    }
}
#endif

/// Persists the Hub connection: the URL in the App Group's `UserDefaults`, the
/// secret in the Keychain. Both are readable by the widget extensions.
public struct HubConnectionStore: @unchecked Sendable {
    // @unchecked: UserDefaults is thread-safe but not annotated Sendable on
    // every SDK this builds against.

    public static let baseURLKey = "hubBaseURL"

    public let defaults: UserDefaults
    public let secrets: SecretStorage

    public init(defaults: UserDefaults, secrets: SecretStorage) {
        self.defaults = defaults
        self.secrets = secrets
    }

    #if canImport(Security)
    /// App Group defaults + the App Group Keychain item.
    public static var shared: HubConnectionStore {
        HubConnectionStore(defaults: AppGroup.defaults, secrets: KeychainSecretStorage())
    }
    #endif

    /// The saved Hub URL, without touching the Keychain.
    public var baseURL: URL? {
        defaults.string(forKey: Self.baseURLKey).flatMap { HubConnection.normalizedBaseURL(from: $0) }
    }

    public var isConfigured: Bool { baseURL != nil }

    /// The saved connection; nil when no URL is saved.
    /// - Throws: `SecretStorageError` when the Keychain cannot be read (for
    ///   example before the first unlock after a reboot). Callers that must not
    ///   fail — widgets — should fall back to the cached snapshot instead of
    ///   calling the Hub without the secret.
    public func loadConnection() throws -> HubConnection? {
        guard let url = baseURL else { return nil }
        let secret = try secrets.readSecret() ?? ""
        return HubConnection(baseURL: url, secret: secret)
    }

    /// `loadConnection()`, with an unreadable Keychain reported as nil.
    public func load() -> HubConnection? {
        (try? loadConnection()) ?? nil
    }

    /// Saves both halves; an empty secret deletes the Keychain item.
    public func save(_ connection: HubConnection) throws {
        if connection.secret.isEmpty {
            try secrets.deleteSecret()
        } else {
            try secrets.writeSecret(connection.secret)
        }
        defaults.set(connection.baseURL.absoluteString, forKey: Self.baseURLKey)
    }

    public func clear() throws {
        defaults.removeObject(forKey: Self.baseURLKey)
        try secrets.deleteSecret()
    }
}

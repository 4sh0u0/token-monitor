import Foundation
import TokenMonitorKit

/// A failure explained to the user: a localized title, an actionable message
/// and, where the system supplied one, its own (already localized) detail.
struct HubIssue: Equatable {
    enum Kind: Equatable {
        case notConfigured
        case invalidURL
        case unauthorized
        /// 503: a Cloudflare Worker refuses every request until
        /// TOKEN_MONITOR_SECRET is set.
        case hubSecretMissing
        case httpStatus(Int)
        case unreachable
        case unexpectedResponse
        /// The Keychain is not readable yet (before the first unlock).
        case secretLocked
        case keychain(Int32)
        case other
    }

    // errSecInteractionNotAllowed, spelled out so this file needs no Security import.
    private static let keychainInteractionNotAllowed: Int32 = -25308

    var kind: Kind
    var detail: String?
    /// The Hub's host is on the local network or a tailnet, so iOS's Local
    /// Network permission and the Wi-Fi the phone is on matter.
    var isLocalHub: Bool

    init(kind: Kind, detail: String? = nil, isLocalHub: Bool = false) {
        self.kind = kind
        self.detail = detail
        self.isLocalHub = isLocalHub
    }

    init(error: Error, connection: HubConnection?) {
        let isLocal = connection.map(Self.isLocal) ?? false
        if let error = error as? HubClientError {
            switch error {
            case .notConfigured:
                self.init(kind: .notConfigured)
            case .invalidURL:
                self.init(kind: .invalidURL)
            case .unauthorized:
                self.init(kind: .unauthorized)
            case .http(let status):
                self.init(kind: status == 503 ? .hubSecretMissing : .httpStatus(status))
            case .transport(let detail):
                self.init(kind: .unreachable, detail: detail, isLocalHub: isLocal)
            case .decoding:
                // The raw DecodingError is noise to a user; the message says what to do.
                self.init(kind: .unexpectedResponse)
            }
        } else if let error = error as? SecretStorageError {
            switch error {
            case .keychain(let status) where status == Self.keychainInteractionNotAllowed:
                self.init(kind: .secretLocked)
            case .keychain(let status):
                self.init(kind: .keychain(status))
            case .malformedItem:
                self.init(kind: .keychain(0))
            }
        } else {
            self.init(kind: .other, detail: error.localizedDescription)
        }
    }

    static func isLocal(_ connection: HubConnection) -> Bool {
        let host = URLComponents(url: connection.baseURL, resolvingAgainstBaseURL: false)?.host ?? connection.baseURL.host ?? ""
        return HubConnection.isLocalHost(host)
    }

    var title: String {
        switch kind {
        case .notConfigured:
            return String(localized: "No Hub connected")
        case .invalidURL:
            return String(localized: "Invalid Hub address")
        case .unauthorized:
            return String(localized: "Wrong or missing secret")
        case .hubSecretMissing:
            return String(localized: "The Hub has no secret configured")
        case .httpStatus(let status):
            let code = String(status)
            return String(localized: "Hub error (HTTP \(code))")
        case .unreachable:
            return String(localized: "Can’t reach the Hub")
        case .unexpectedResponse:
            return String(localized: "Unexpected response from the Hub")
        case .secretLocked:
            return String(localized: "Secret not available yet")
        case .keychain:
            return String(localized: "Keychain error")
        case .other:
            return String(localized: "Something went wrong")
        }
    }

    var message: String {
        switch kind {
        case .notConfigured:
            return String(localized: "Add your Hub’s address and secret in Settings.")
        case .invalidURL:
            return String(localized: "Enter an address such as 192.168.1.10:17321 or https://token-monitor.example.workers.dev.")
        case .unauthorized:
            return String(localized: "The Hub rejected the secret. Enter the Hub’s TOKEN_MONITOR_SECRET, or the secret shown by the desktop widget that hosts the Hub.")
        case .hubSecretMissing:
            return String(localized: "This Hub refuses all requests until a secret is set. For a Cloudflare Worker, run “npx wrangler secret put TOKEN_MONITOR_SECRET”, then enter the same secret here.")
        case .httpStatus:
            return String(localized: "Check that the address points to a Token Monitor Hub.")
        case .unreachable:
            if isLocalHub {
                return String(localized: "Check that the Hub is running and that this iPhone is on the same network or tailnet. If you declined Local Network access, turn it on in Settings › Privacy & Security › Local Network.")
            }
            return String(localized: "Check that the Hub is running, the address is right, and this iPhone is online.")
        case .unexpectedResponse:
            return String(localized: "The address answered, but not with data this app understands. Make sure it is a Token Monitor Hub (not a sign-in page), and update Token Monitor on the Hub.")
        case .secretLocked:
            return String(localized: "Unlock your iPhone so Token Monitor can read the Hub secret from the Keychain.")
        case .keychain(let status):
            let code = String(status)
            return String(localized: "The Hub secret couldn’t be read (error \(code)). Enter it again in Settings.")
        case .other:
            return String(localized: "Pull down to try again.")
        }
    }

    /// Changing the Hub settings is what fixes it (as opposed to waiting).
    var suggestsSettings: Bool {
        switch kind {
        case .notConfigured, .invalidURL, .unauthorized, .hubSecretMissing, .keychain:
            return true
        case .httpStatus, .unreachable, .unexpectedResponse, .secretLocked, .other:
            return false
        }
    }

    /// Retrying without new settings cannot succeed, so live updates stop
    /// until the user changes something or pulls to refresh.
    var stopsLiveUpdates: Bool {
        switch kind {
        case .notConfigured, .invalidURL, .unauthorized:
            return true
        default:
            return false
        }
    }
}

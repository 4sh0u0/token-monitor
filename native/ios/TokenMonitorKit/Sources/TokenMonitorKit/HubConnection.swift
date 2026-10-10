import Foundation

/// Where the Hub is and how to authenticate to it.
///
/// `Codable` includes the secret so the iPhone can hand the connection to the
/// watch over WatchConnectivity; never write the encoded form anywhere but the
/// Keychain or that transfer (`HubConnectionStore` keeps only the URL in
/// `UserDefaults`).
public struct HubConnection: Sendable, Hashable, Codable {
    /// Normalized base URL: scheme + host (+ port, + a reverse-proxy path
    /// prefix), no trailing `/`, no `/api/...`.
    public var baseURL: URL
    /// Shared Hub secret, sent as `Authorization: Bearer`. May be empty for a
    /// loopback Node hub run without one.
    public var secret: String

    public init(baseURL: URL, secret: String) {
        self.baseURL = Self.normalizedBaseURL(from: baseURL.absoluteString) ?? baseURL
        self.secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds a connection from what the user typed or pasted.
    ///
    /// Input without a `scheme://` gets `http://` when its host is on the
    /// local network or a tailnet (`192.168.1.10:17321`, `mac.local:17321`):
    /// the Node hub and the widget's Host hub serve plain HTTP there, so an
    /// `https://` guess would only fail the TLS handshake. Every other host
    /// (the Worker, a reverse proxy) gets `https://`. An explicit scheme is
    /// always kept.
    /// - Throws: `HubClientError.invalidURL` when `input` is not an HTTP(S) URL.
    public init(userInput: String, secret: String) throws {
        guard let url = Self.normalizedBaseURL(from: userInput, defaultScheme: Self.defaultScheme(forUserInput: userInput)) else {
            throw HubClientError.invalidURL
        }
        self.baseURL = url
        self.secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The scheme `init(userInput:secret:)` assumes when the input has none.
    static func defaultScheme(forUserInput input: String) -> String {
        guard let probe = normalizedBaseURL(from: input, defaultScheme: "https"),
              let host = URLComponents(url: probe, resolvingAgainstBaseURL: false)?.host ?? probe.host,
              isLocalHost(host) else { return "https" }
        return "http"
    }

    public var hasSecret: Bool { !secret.isEmpty }

    /// Which Hub a `TokenSnapshot` came from (`TokenSnapshot.hubKey`): a
    /// stable hash of the normalized base URL. Never derived from the secret,
    /// so it carries nothing of it, and a rotated secret keeps the cache.
    public var snapshotKey: String { Self.snapshotKey(for: baseURL) }

    /// `snapshotKey` of the Hub at `baseURL`, for callers that have only the
    /// saved URL (widgets before the Keychain is readable).
    public static func snapshotKey(for baseURL: URL) -> String {
        // Normalized again: a decoded connection (`Codable`) keeps its URL as sent.
        let normalized = normalizedBaseURL(from: baseURL.absoluteString)?.absoluteString ?? baseURL.absoluteString
        return StableHash.hex(normalized, length: 16)
    }

    /// Plain HTTP to a host that is not on the local network or a tailnet:
    /// the secret and usage would cross the internet unencrypted, so the UI
    /// should warn.
    public var isInsecureRemote: Bool { Self.isInsecureRemote(baseURL) }

    /// `host[:port]` only — what a settings summary may show (never the
    /// secret, URL credentials or path).
    public var displayHost: String {
        guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty else { return baseURL.absoluteString }
        let bareHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let shownHost = bareHost.contains(":") ? "[\(bareHost)]" : bareHost
        return components.port.map { "\(shownHost):\($0)" } ?? shownHost
    }

    /// The URL of a Hub endpoint, keeping any reverse-proxy path prefix.
    public func url(for endpoint: HubEndpoint) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL.appendingPathComponent(endpoint.rawValue)
        }
        let prefix = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = "\(prefix)/\(endpoint.rawValue)"
        return components.url ?? baseURL.appendingPathComponent(endpoint.rawValue)
    }

    /// Normalizes user input into a Hub base URL, or nil when it is not one.
    ///
    /// Trims whitespace; adds `defaultScheme` when no `scheme://` is present;
    /// accepts only http/https with a host; lowercases scheme and host; drops
    /// URL credentials, query and fragment; drops a pasted `/api/...` path
    /// (keeping a reverse-proxy prefix before it) and trailing slashes.
    public static func normalizedBaseURL(from input: String, defaultScheme: String = "https") -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let hasScheme = trimmed.range(of: "://") != nil
        // `mailto:x@y` or `javascript:…` is a scheme, not `host:port`.
        if !hasScheme, trimmed.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:(?![0-9])"#, options: .regularExpression) != nil {
            return nil
        }
        let withScheme = hasScheme ? trimmed : "\(defaultScheme)://\(trimmed)"
        guard var components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }
        components.scheme = scheme
        // IPv6 literals are left alone: Foundation versions disagree on whether
        // `host` carries the brackets, and writing it back can drop them.
        if !host.contains(":"), host != host.lowercased() { components.host = host.lowercased() }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        var segments = components.path.split(separator: "/").map(String.init)
        if let apiIndex = segments.firstIndex(where: { $0.lowercased() == "api" }) {
            segments = Array(segments[..<apiIndex])
        }
        components.path = segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
        return components.url
    }

    public static func isInsecureRemote(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http" else { return false }
        let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host ?? url.host ?? ""
        return !isLocalHost(host)
    }

    /// Hosts whose plain-HTTP traffic stays off the public internet: loopback,
    /// mDNS `.local`, `.home.arpa`, unqualified LAN names, RFC 1918 private,
    /// CGNAT 100.64/10 (Tailscale), link-local, IPv6 ULA, and Tailscale
    /// MagicDNS `.ts.net` names (tailnet traffic is WireGuard-encrypted, and a
    /// public Funnel is HTTPS-only, so `http://*.ts.net` is tailnet traffic).
    public static func isLocalHost(_ rawHost: String) -> Bool {
        var host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        if let octets = ipv4Octets(host) { return isPrivateIPv4(octets) }
        if host.contains(":") { return isPrivateIPv6(host) }
        if !host.contains(".") { return true }
        return [".local", ".home.arpa", ".ts.net"].contains { host.hasSuffix($0) }
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isASCII), let value = Int(part), value <= 255 else { return nil }
            return value
        }
        return octets.count == 4 ? octets : nil
    }

    private static func isPrivateIPv4(_ octets: [Int]) -> Bool {
        switch (octets[0], octets[1]) {
        case (127, _), (10, _), (0, _): return true
        case (172, 16...31): return true
        case (192, 168): return true
        case (169, 254): return true
        case (100, 64...127): return true
        default: return false
        }
    }

    private static func isPrivateIPv6(_ host: String) -> Bool {
        if host == "::1" || host == "::" { return true }
        if host.hasPrefix("::ffff:"), let octets = ipv4Octets(String(host.dropFirst("::ffff:".count))) {
            return isPrivateIPv4(octets)
        }
        let firstGroup = host.split(separator: ":", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard let value = UInt16(firstGroup, radix: 16), !firstGroup.isEmpty else { return false }
        // fe80::/10 link-local, fc00::/7 unique local.
        return (value & 0xffc0) == 0xfe80 || (value & 0xfe00) == 0xfc00
    }
}

/// Hub endpoints the companion apps read. Nothing is ever POSTed.
public enum HubEndpoint: String, Sendable {
    case health = "api/health"
    case stats = "api/stats"
    case statsStream = "api/stats/stream"
    /// `{daily[], monthly[], summary}`; an older Hub answers 404.
    case history = "api/history"
    /// Per-device records, including each device's history.
    case devices = "api/devices"
    case subscriptions = "api/subscriptions"
    case syncContent = "api/sync/content"
    case syncSettingsModelAliases = "api/sync/settings/modelAliases"
    case syncSettingsCustomPricing = "api/sync/settings/customPricing"
}

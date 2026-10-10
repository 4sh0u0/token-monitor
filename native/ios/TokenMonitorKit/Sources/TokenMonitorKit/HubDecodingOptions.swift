import Foundation

/// What a `GET /api/stats` decode builds beyond the totals every surface
/// needs.
///
/// The stats body carries every session of today and this month, a project
/// rollup per period and a full copy of each period for every device. The
/// app shows all of that; a widget or complication shows a handful of
/// numbers and runs under a tight memory limit. The options travel through
/// `JSONDecoder.userInfo[.hubDecodingOptions]`, so every nested decoder sees
/// the same choice. A decoder without them decodes as `.compact`, the
/// round-1 behaviour.
public struct HubDecodingOptions: Sendable, Equatable {
    /// Which devices get their full periods in `DeviceSummary.details` (and
    /// their limits rows in `DeviceSummary.limits`).
    public enum DeviceDetail: Sendable, Equatable {
        case none
        case all
        /// One device, by its Hub id (`DeviceSummary.id`).
        case only(String)

        public func includes(_ deviceID: String) -> Bool {
            switch self {
            case .none: return false
            case .all: return true
            case .only(let id): return id == deviceID
            }
        }
    }

    /// Decode `periods.*.sessions` into `UsagePeriod.sessions` (aggregate and
    /// detailed devices). `sessionCount` is filled either way.
    public var includeSessions: Bool
    /// Decode `periods.*.projects` into `UsagePeriod.projects`.
    public var includeProjects: Bool
    public var deviceDetail: DeviceDetail

    public init(includeSessions: Bool = false, includeProjects: Bool = false, deviceDetail: DeviceDetail = .none) {
        self.includeSessions = includeSessions
        self.includeProjects = includeProjects
        self.deviceDetail = deviceDetail
    }

    /// Widgets, the watch and complications: totals, tool/model rows and
    /// breakdown maps, device totals; no sessions, projects or device detail.
    public static let compact = HubDecodingOptions()

    /// The iPhone app: sessions, projects and every device's detail.
    public static let app = HubDecodingOptions(includeSessions: true, includeProjects: true, deviceDetail: .all)

    /// `.compact` plus the detail of the scoped device, so a device-scoped
    /// widget can show that device's periods. `.all` is plain `.compact`.
    public static func compact(scopedTo scope: DeviceScope) -> HubDecodingOptions {
        guard let id = scope.deviceID else { return .compact }
        return HubDecodingOptions(deviceDetail: .only(id))
    }

    /// A `JSONDecoder` that carries these options.
    public func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.userInfo[.hubDecodingOptions] = self
        return decoder
    }
}

extension CodingUserInfoKey {
    /// The `HubDecodingOptions` a stats decode uses; absent means `.compact`.
    public static let hubDecodingOptions = CodingUserInfoKey(rawValue: "TokenMonitorKit.hubDecodingOptions")!
}

extension Decoder {
    var hubDecodingOptions: HubDecodingOptions {
        userInfo[.hubDecodingOptions] as? HubDecodingOptions ?? .compact
    }
}

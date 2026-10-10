import Foundation
import TokenMonitorKit

/// What a period selection shows right now (`AppModel.usage(for:)`).
enum PeriodUsageState: Equatable {
    /// The usage to show. For a Hub period (today, month, all time) the
    /// snapshot is nil; for a fixed range (WEEK / 7D / 30D) it carries the
    /// range, its daily rows and its summary.
    case ready(UsagePeriod, FixedRangeSnapshot?)
    /// No stats yet, or History is still loading for a fixed range.
    case loading
    case unavailable(PeriodUnavailableReason)

    var usage: UsagePeriod? {
        if case .ready(let usage, _) = self { return usage }
        return nil
    }

    var fixedRange: FixedRangeSnapshot? {
        if case .ready(_, let snapshot) = self { return snapshot }
        return nil
    }
}

/// Why a period, or a breakdown of it, cannot be shown. Each reason has the
/// desktop's `periodRange.*` wording (`PeriodUnavailableNote`).
enum PeriodUnavailableReason: Hashable, Sendable {
    /// `periodRange.historyDisabled`.
    case historyDisabled
    /// `periodRange.historyUnavailable`: the Hub or device does not share
    /// History, it failed to load, or the device's day cannot be placed.
    case historyUnavailable
    /// `periodRange.sessionUnavailable`: fixed ranges have no sessions.
    case sessions
    /// `periodRange.projectUnavailable`: fixed ranges have no projects.
    case projects

    init(_ reason: FixedRangeUnavailableReason) {
        switch reason {
        case .historyDisabled: self = .historyDisabled
        case .historyUnavailable: self = .historyUnavailable
        }
    }

    /// Sessions and projects exist only for the Hub's own periods: the
    /// reason a breakdown is missing for `selection`, nil when it is
    /// available.
    static func breakdown(_ breakdown: FixedRangeBreakdown, for selection: PeriodSelection) -> PeriodUnavailableReason? {
        guard !FixedRanges.supports(breakdown, selection: selection) else { return nil }
        switch breakdown {
        case .session: return .sessions
        case .project: return .projects
        case .tool, .model, .device: return .historyUnavailable
        }
    }
}

extension PeriodSelection {
    /// The middle segment's selections, in the `periodMonthMode` menu order.
    static let middleChoices: [PeriodSelection] = PeriodMonthMode.allCases.map(PeriodSelection.middle(for:))

    /// The `periodMonthMode` that puts this selection in the middle segment;
    /// nil for today and all time.
    var monthMode: PeriodMonthMode? {
        switch self {
        case .month: return .month
        case .week: return .week
        case .last7: return .last7
        case .last30: return .last30
        case .today, .allTime: return nil
        }
    }
}

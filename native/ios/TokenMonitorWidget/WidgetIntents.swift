import AppIntents
import Foundation
import TokenMonitorKit
import WidgetKit

/// The Usage widget's period. A local enum rather than a conformance on the
/// Kit's `UsagePeriodKind`: App Intents metadata is extracted from this
/// target's sources, so the enum and its literal representations live here.
enum UsagePeriodOption: String, AppEnum, CaseIterable {
    case today
    case month
    case allTime

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Period")
    static let caseDisplayRepresentations: [UsagePeriodOption: DisplayRepresentation] = [
        .today: DisplayRepresentation(title: "Today"),
        .month: DisplayRepresentation(title: "This Month"),
        .allTime: DisplayRepresentation(title: "All Time")
    ]

    var kind: UsagePeriodKind {
        switch self {
        case .today: return .today
        case .month: return .month
        case .allTime: return .allTime
        }
    }
}

/// Which breakdown the medium and large Usage widgets list.
enum BreakdownOption: String, AppEnum, CaseIterable {
    case tools
    case models

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Breakdown")
    static let caseDisplayRepresentations: [BreakdownOption: DisplayRepresentation] = [
        .tools: DisplayRepresentation(title: "Tools"),
        .models: DisplayRepresentation(title: "Models")
    ]
}

struct UsageWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Usage"
    static let description = IntentDescription("Choose the period and breakdown shown by this widget.")

    @Parameter(title: "Period", default: .today)
    var period: UsagePeriodOption

    @Parameter(title: "Breakdown", default: .tools)
    var breakdown: BreakdownOption
}

/// What the Activity widget's colours measure. A local enum (App Intents
/// metadata is extracted from this target's sources); "App Setting" follows
/// the app's Activity heatmap colour (`heatmapMetric`).
enum ActivityMetricOption: String, AppEnum, CaseIterable {
    case automatic
    case tokens
    case cost

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")
    static let caseDisplayRepresentations: [ActivityMetricOption: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(title: "App Setting"),
        .tokens: DisplayRepresentation(title: "Tokens"),
        .cost: DisplayRepresentation(title: "Cost")
    ]

    func metric(_ preferences: DisplayPreferences) -> HeatmapMetric {
        switch self {
        case .automatic: return preferences.heatmapMetric
        case .tokens: return .tokens
        case .cost: return .cost
        }
    }
}

struct ActivityWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Activity"
    static let description = IntentDescription("Choose what the heatmap’s colors measure.")

    @Parameter(title: "Metric", default: .automatic)
    var metric: ActivityMetricOption
}

struct LimitsWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "AI Tool Limits"
    static let description = IntentDescription("Pin one provider, or leave empty to show the most constrained limits first.")

    /// Nil means automatic: the Home limits order (most constrained first
    /// unless the user set a Home provider order).
    @Parameter(title: "Provider")
    var provider: LimitProviderEntity?
}

/// One AI Tool Limits row of the cached snapshot, offered in the Limits
/// widget's configuration.
///
/// The id is `LimitProvider.id` (a hash of the account key), which stays the
/// same across refreshes. When a pinned account disappears from the snapshot
/// the widget falls back to automatic rather than showing nothing.
struct LimitProviderEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")
    static let defaultQuery = LimitProviderQuery()

    let id: String
    let name: String
    let detail: String?

    var displayRepresentation: DisplayRepresentation {
        if let detail {
            return DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
        }
        return DisplayRepresentation(title: "\(name)")
    }

    /// The providers of the cached snapshot, in the snapshot's display order.
    /// Reads only the small App Group file — never the network.
    static func available() -> [LimitProviderEntity] {
        guard let snapshot = SnapshotLoader.cachedSnapshot() else { return [] }
        var countByProvider: [String: Int] = [:]
        for provider in snapshot.limits {
            countByProvider[provider.provider, default: 0] += 1
        }
        return snapshot.limits.map { provider in
            // The account only tells rows apart when one provider has several;
            // otherwise the plan is enough (and keeps the email off screen).
            let isShared = (countByProvider[provider.provider] ?? 0) > 1
            let parts: [String] = [provider.planLabel, isShared ? provider.maskedAccountDisplayName : nil]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            return LimitProviderEntity(
                id: provider.id,
                name: provider.displayName,
                detail: parts.isEmpty ? nil : parts.joined(separator: " · ")
            )
        }
    }
}

struct LimitProviderQuery: EntityQuery {
    func entities(for identifiers: [LimitProviderEntity.ID]) async throws -> [LimitProviderEntity] {
        let wanted = Set(identifiers)
        return LimitProviderEntity.available().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [LimitProviderEntity] {
        LimitProviderEntity.available()
    }
}

/// The refresh button on medium and large widgets: fetches the Hub now,
/// ignoring the cache's freshness window. WidgetKit reloads the tapped
/// widget's timeline after `perform()` returns; every other widget is
/// reloaded too so they all show the same fetch.
struct RefreshUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Widget"
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
        _ = await SnapshotLoader.load(forceRefresh: true, context: PresentationContext.load())
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

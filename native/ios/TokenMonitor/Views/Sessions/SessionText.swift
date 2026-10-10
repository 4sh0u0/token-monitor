import Foundation
import TokenMonitorKit

/// The words around the Kit's session values (`SessionRows`, `SessionLive`).
///
/// As on the desktop, "N call(s)", "N tok/s" and "N models" stay untranslated
/// literals (`sessionRows.js:101-109, 205-238`): they are billing units,
/// printed with en-US grouping in every language, so screens show them with
/// `Text(verbatim:)`. So does the English "Session" the
/// desktop names a session without a client by (`sessionTitleParts`).
/// Everything else is localized here.
enum SessionText {
    /// Joins the parts of a session line (`sessionRows.js` `' · '`).
    static let separator = " · "

    /// en-US grouping for the untranslated literals (`toLocaleString('en-US')`).
    private static let grouping = DisplayFormatter()

    // MARK: Names

    /// A Sessions row's title line.
    static func name(_ name: SessionRowName) -> String {
        switch name {
        case .title(let title):
            return title
        case .tool(let clientLabel, let model):
            return tool(clientLabel: clientLabel, model: model)
        case .backgroundReviews:
            return backgroundReviews
        }
    }

    /// "Claude Code · claude-sonnet-4-5", "OpenCode · 3 models".
    static func tool(clientLabel: String?, model: SessionModelLabel) -> String {
        [clientLabel ?? "Session", modelLabel(model)]
            .compactMap { $0 }
            .joined(separator: separator)
    }

    /// The model id, "N models" (untranslated), or nil without a model.
    static func modelLabel(_ label: SessionModelLabel) -> String? {
        switch label {
        case .none: return nil
        case .single(let model): return model
        case .count(let count): return "\(count) models"
        }
    }

    /// The Overview module's name for a session: title, project, the start
    /// of its id, or "—".
    static func recentName(_ name: RecentSessionName) -> String {
        switch name {
        case .title(let text), .project(let text), .sessionID(let text):
            return text
        case .none:
            return "—"
        }
    }

    /// `sessions.backgroundReviews`.
    static var backgroundReviews: String { String(localized: "Codex Auto Review") }

    /// `sessions.backgroundReviewCount`.
    static func backgroundRuns(_ count: Int) -> String {
        String(localized: "\(count) background runs")
    }

    // MARK: Lines

    /// The line under a row's title.
    static func subtitle(_ subtitle: SessionRowSubtitle, formatter: DisplayFormatter) -> String {
        switch subtitle {
        case .tool(let clientLabel, let model):
            return tool(clientLabel: clientLabel, model: model)
        case .activity(let parts):
            return activity(parts)
        case .reviewSummary(let latestTime, let latestTokens):
            var parts: [String] = []
            if let latestTime {
                parts.append(String(localized: "Latest \(latestTime)"))
            }
            if latestTokens > 0 {
                parts.append(formatter.compactTokens(latestTokens))
            }
            return parts.joined(separator: separator)
        }
    }

    /// Archived · time · calls · cache hit · tok/s.
    static func activity(_ parts: [SessionActivityPart]) -> String {
        parts.map(activityPart).joined(separator: separator)
    }

    static func activityPart(_ part: SessionActivityPart) -> String {
        switch part {
        case .archived: return archived
        case .time(let time): return time
        case .calls(let count): return calls(count)
        case .cacheHit(let label): return label
        case .tokensPerSecond(let rate): return tokensPerSecond(rate)
        }
    }

    /// "1 call", "1,234 calls" (untranslated, `messageLabel`).
    static func calls(_ count: Int) -> String {
        "\(grouping.fullTokens(count)) \(count == 1 ? "call" : "calls")"
    }

    /// "1,234 tok/s" (untranslated, `tokenRateLabel`).
    static func tokensPerSecond(_ rate: Int) -> String {
        "\(grouping.fullTokens(rate)) tok/s"
    }

    // MARK: State

    /// `session.archived`.
    static var archived: String { String(localized: "Archived") }

    /// `session.running` / `session.finished` / `session.idle`.
    static func state(_ state: SessionActivityState) -> String {
        switch state {
        case .running: return String(localized: "Running")
        case .ended: return String(localized: "Finished")
        case .idle: return String(localized: "Idle")
        }
    }

    /// The client's own turn boundary, kept three-state: finished, under
    /// way, or not reported at all.
    static func turn(_ turnEnded: Bool?) -> String {
        switch turnEnded {
        case true?: return String(localized: "Finished")
        case false?: return String(localized: "In progress")
        case nil: return String(localized: "Not reported")
        }
    }

    /// `homeSessionAgo`, worded with `edgeDock.ago*`.
    static func age(_ age: SessionAge) -> String {
        switch age {
        case .justNow: return String(localized: "just now")
        case .minutes(let minutes): return String(localized: "\(minutes)m ago")
        case .hours(let hours): return String(localized: "\(hours)h ago")
        case .days(let days): return String(localized: "\(days)d ago")
        }
    }

    /// `home.runningSessions`.
    static func running(_ count: Int) -> String {
        String(localized: "\(count) running")
    }

    // MARK: Context and cache

    /// The gauge's reading as a sentence (`session.contextUsed` /
    /// `session.contextLeft`), for VoiceOver and the detail screen.
    static func contextPercent(_ gauge: SessionContextGauge, metric: ContextMetric, formatter: DisplayFormatter) -> String {
        let percent = formatter.percent(Double(gauge.percent(for: metric)))
        switch metric {
        case .used: return String(localized: "\(percent) of context used")
        case .remaining: return String(localized: "\(percent) context left")
        }
    }

    /// "190.9K / 950K" (the desktop's gauge tooltip), in the user's units.
    static func contextWindow(_ gauge: SessionContextGauge, formatter: DisplayFormatter) -> String {
        "\(formatter.compactTokens(gauge.contextTokens)) / \(formatter.compactTokens(gauge.contextWindow))"
    }

    /// The countdown in the gauge slot: "Cache 4m" (`session.cacheEstimate`).
    static func cacheBadge(_ cache: PromptCacheCountdown) -> String {
        String(localized: "Cache \(cache.minutes)m")
    }

    /// The countdown in full: "Cache ~4m left" (`session.cacheEstimateTooltip`).
    static func cacheLeft(_ cache: PromptCacheCountdown) -> String {
        String(localized: "Cache ~\(cache.minutes)m left")
    }

    /// The TTL tier the transcript implies; the wire value is an estimate,
    /// not the provider's own expiry.
    static func cacheTier(_ cache: PromptCacheCountdown) -> String {
        let minutes = cache.ttlSeconds / 60
        return String(localized: "\(minutes)-minute cache, estimated from the transcript")
    }

    // MARK: Pages

    /// `sessions.pageRange`.
    static func pageRange(_ page: SessionPage) -> String {
        String(localized: "\(page.start)–\(page.end) of \(page.total)")
    }

    // MARK: Usage source

    /// What the session's `usageSource` / `usageCoverage` say about its
    /// numbers; nil for ordinary sessions.
    static func usageSourceNote(_ session: HubSession) -> String? {
        var sentences: [String] = []
        if let source = trimmed(session.usageSource) {
            if source == "codex-dots-local" {
                sentences.append(String(localized: "Dots usage, recorded from local tasks only while connected."))
            } else {
                sentences.append(String(localized: "Usage source: \(source)"))
            }
        }
        if let coverage = trimmed(session.usageCoverage) {
            if coverage == "observed-only" {
                sentences.append(String(localized: "Coverage may be incomplete."))
            } else {
                sentences.append(String(localized: "Coverage: \(coverage)"))
            }
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

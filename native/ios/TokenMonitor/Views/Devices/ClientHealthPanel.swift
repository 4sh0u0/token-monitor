import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

// A device's per-tool status and health, ported from the desktop's
// Settings › Tools rows (`clientStatusTag`, `clientHealthPanel`,
// `clientHealthGroup`). The desktop shows them for its own device only; a
// phone shows them for any device (`devices[].clientHealth` /
// `clientStatus`). Local-only actions (re-scan, reveal, custom sources,
// the Codex dots toggles) have no place here.

/// The "Tool health" card of a device: the healthy / review / not-installed
/// counts and one row per tool the device reports on, each expandable to its
/// health panel. Draws nothing when the device reports no tools.
struct DeviceToolHealthSection: View {
    let device: DeviceSummary

    var body: some View {
        let tools = ClientHealthPresentation.toolStatuses(device: device)
        if !tools.isEmpty {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                CardContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        ModuleHeader(title: "Tool health")
                        if let counts = ClientHealthPresentation.counts(device: device) {
                            Text("Healthy \(counts.healthy) · Review \(counts.review) · Not installed \(counts.unavailable)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(TMTheme.muted)
                        }
                        let todayKey = Self.todayKey(device, now: context.date)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                                if index > 0 {
                                    Divider().overlay(TMTheme.divider)
                                }
                                ClientToolHealthRow(tool: tool, todayKey: todayKey, now: context.date)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The device's own day (its period window, rolled to its time zone once
    /// it ended), else the phone's: "Last output" counts days from it.
    static func todayKey(_ device: DeviceSummary, now: Date) -> String {
        FixedRanges.deviceDayState(device: device, now: now)?.currentKey
            ?? DayKey.string(from: now, calendar: .current)
    }
}

/// One tool of a device: mark, name and status tag; expands to the health
/// panel when the device sent a health entry for it.
struct ClientToolHealthRow: View {
    let tool: ClientToolStatus
    let todayKey: String
    let now: Date
    @State private var isExpanded = false

    var body: some View {
        if let health = tool.health {
            DisclosureGroup(isExpanded: $isExpanded) {
                ClientHealthPanel(detail: health, todayKey: todayKey, now: now)
                    .padding(.top, 8)
            } label: {
                label
            }
            .tint(TMTheme.muted)
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            VendorMark(.client(tool.clientID), size: 16)
            Text(verbatim: VendorCatalog.clientLabel(tool.clientID))
                .font(.subheadline)
                .foregroundStyle(tool.isTracked ? TMTheme.text : TMTheme.muted)
                .lineLimit(1)
            if let tag = ClientToolTagKind(tool) {
                ClientToolTagView(kind: tag)
            }
            Spacer(minLength: 0)
            if let health = tool.health {
                OverallHealthDot(overall: health.overall)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The tool's overall health (`OVERALL_TONES`) as a small dot, named for
/// VoiceOver.
private struct OverallHealthDot: View {
    let overall: ClientHealthOverall

    var body: some View {
        Circle()
            .fill(overall.tone.tagColor)
            .frame(width: 7, height: 7)
            .opacity(overall.tone == .muted ? 0.6 : 1)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: Self.title(overall)))
    }

    /// The overall in the words of the desktop's summary and status tags.
    static func title(_ overall: ClientHealthOverall) -> String {
        switch overall {
        case .healthy: return String(localized: "Healthy")
        case .waiting: return String(localized: "Waiting for data")
        case .attention: return String(localized: "Needs attention")
        case .unavailable: return String(localized: "Not installed")
        case .unknown: return String(localized: "Unknown")
        }
    }
}

/// A tool's health panel (`clientHealthPanel`): Source, Collection and Usage,
/// each with the diagnostic notes that belong to it.
struct ClientHealthPanel: View {
    let detail: ClientHealthDetail
    /// The device's day, for "Last output Today / Yesterday / N days ago".
    let todayKey: String
    let now: Date

    @Environment(\.tmFormatter) private var formatter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var titleWidth: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(detail.groups.enumerated()), id: \.element) { index, group in
                if index > 0 {
                    Divider().overlay(TMTheme.divider)
                }
                groupRow(group)
                    .padding(.vertical, 7)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Layout

    private func groupRow(_ group: ClientHealthGroupID) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text(title(group))
                .font(.caption.weight(.medium))
                .foregroundStyle(TMTheme.muted)
                .frame(width: stacked ? nil : titleWidth, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 4) {
                groupBody(group)
                ForEach(Array(detail.notes(in: group).enumerated()), id: \.offset) { _, note in
                    Text(Self.message(note.code))
                        .font(.caption)
                        .foregroundStyle(note.tone.noteColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func groupBody(_ group: ClientHealthGroupID) -> some View {
        switch group {
        case .source:
            sourceBody(detail.source)
        case .collection:
            collectionBody(detail.collection)
        case .data:
            dataBody(detail.data)
        }
    }

    // MARK: Source

    @ViewBuilder
    private func sourceBody(_ source: ClientHealthSourceGroup) -> some View {
        Text(Self.sourceSummary(source))
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(TMTheme.text)
        if !source.checks.isEmpty {
            FlowLayout(spacing: 4, lineSpacing: 4) {
                ForEach(source.checks, id: \.id) { check in
                    SourceCheckChip(check: check)
                }
            }
        }
    }

    // MARK: Collection

    @ViewBuilder
    private func collectionBody(_ collection: ClientHealthCollectionGroup) -> some View {
        Text(Self.collectionSummary(collection.state))
            .font(.caption)
            .foregroundStyle(TMTheme.text)
        if let attempt = collection.lastAttemptAt {
            let ago = Self.ago(since: attempt, now: now)
            meta(String(localized: "Last tried \(ago)"))
        }
        if let success = collection.lastSuccessAt {
            let ago = Self.ago(since: success, now: now)
            meta(String(localized: "Last succeeded \(ago)"))
        }
        if let failure = Self.failureDetails(collection) {
            Text(verbatim: failure)
                .font(.caption2.monospaced())
                .foregroundStyle(TMTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Usage

    @ViewBuilder
    private func dataBody(_ data: ClientHealthDataGroup) -> some View {
        if let periods = data.periods {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(periods.enumerated()), id: \.element.id) { index, cell in
                    VStack(alignment: index == 0 ? .leading : .trailing, spacing: 1) {
                        Text(verbatim: cell.period.title)
                            .font(.caption2)
                            .foregroundStyle(TMTheme.muted)
                        Text(verbatim: formatter.compactTokens(cell.tokens))
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(TMTheme.text)
                        if cell.costUsd > 0 {
                            Text(verbatim: formatter.cost(cell.costUsd))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(TMTheme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : .trailing)
                }
            }
        } else {
            let tokens = formatter.compactTokens(data.liveTokens)
            Text("\(tokens) tokens counted")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(TMTheme.text)
        }
        if let day = data.lastActivityDay {
            let relative = Self.relativeDay(ClientHealthPresentation.relativeDay(day, todayKey: todayKey))
            meta(String(localized: "Last output \(relative) · \(day)"))
        }
    }

    private func meta(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(TMTheme.muted)
    }

    // MARK: Wording

    private func title(_ group: ClientHealthGroupID) -> String {
        switch group {
        case .source: return String(localized: "Source")
        case .collection: return String(localized: "Collection")
        case .data: return String(localized: "Usage")
        }
    }

    /// `settings.tools.health.source.*`.
    static func sourceSummary(_ source: ClientHealthSourceGroup) -> String {
        switch source.state {
        case .detected: return String(localized: "Detected \(source.detectedCount) of \(source.checkedCount)")
        case .missing: return String(localized: "Not detected")
        case .unknown: return String(localized: "Unknown")
        }
    }

    /// `settings.tools.health.sync.*`.
    static func collectionSummary(_ state: ClientHealthCollectionState) -> String {
        switch state {
        case .direct: return String(localized: "Read directly from local data")
        case .idle: return String(localized: "Not synced yet")
        case .pending: return String(localized: "Sync pending")
        case .ok: return String(localized: "Last sync succeeded")
        case .failed: return String(localized: "Last sync failed")
        case .unknown: return String(localized: "Unknown")
        case .notTracked: return String(localized: "Not tracked")
        case .waiting: return String(localized: "Waiting for data")
        }
    }

    /// `settings.tools.health.code.*`: what the diagnostic means.
    static func message(_ code: ClientHealthDiagnostic) -> String {
        switch code {
        case .sourceMissing:
            return String(localized: "No data directory found for this tool.")
        case .noUsageObserved:
            return String(localized: "Its data directory is there, but nothing has been counted yet.")
        case .wslDetectedNoData:
            return String(localized: "Found in WSL, but the scan returned no usage.")
        case .syncFailed:
            return String(localized: "The last auto-sync failed, so these numbers may be stale.")
        case .syncTimeout:
            return String(localized: "The last auto-sync timed out, so these numbers may be stale.")
        case .syncSpawnFailed:
            return String(localized: "The auto-sync could not start. Check that tokscale is installed.")
        case .syncExitError:
            return String(localized: "The auto-sync exited with an error, so these numbers may be stale.")
        case .syncLockPresent:
            return String(localized: "An Antigravity sync lock is blocking updates. Confirm no sync is running, then repair it in Token Monitor on that computer.")
        }
    }

    /// `settings.tools.health.day.*`, or the plain date.
    static func relativeDay(_ day: ClientHealthRelativeDay) -> String {
        switch day {
        case .today: return String(localized: "Today")
        case .yesterday: return String(localized: "Yesterday")
        case .daysAgo(let days): return String(localized: "\(days) days ago")
        case .date(let date): return date
        }
    }

    /// The desktop's `formatAgo` (`serviceStatus.ago*`): whole seconds,
    /// minutes or hours.
    static func ago(since date: Date, now: Date) -> String {
        let bucket = ServiceStatusPresentation.agoBucket(since: date, now: now)
        switch bucket.unit {
        case .seconds: return String(localized: "\(bucket.value)s ago")
        case .minutes: return String(localized: "\(bucket.value)m ago")
        case .hours: return String(localized: "\(bucket.value)h ago")
        }
    }

    /// The raw failure details the desktop keeps for diagnostics (stage,
    /// detail code, exit code): wire codes, shown as they are.
    static func failureDetails(_ collection: ClientHealthCollectionGroup) -> String? {
        var parts = [collection.failureStage, collection.detailCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let exitCode = collection.exitCode {
            parts.append(String(localized: "Exit code \(exitCode)"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One logical data root the device checked for a tool (`checks[].id`, never
/// a path): mint when it exists.
private struct SourceCheckChip: View {
    let check: ClientHealthCheck

    var body: some View {
        Text(verbatim: check.id)
            .font(.caption2.monospaced())
            .foregroundStyle(check.exists ? TMTheme.success : TMTheme.muted)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(check.exists ? TMTheme.success.opacity(0.28) : Color.white.opacity(0.14), lineWidth: 1)
            }
            .opacity(check.exists ? 1 : 0.72)
    }
}

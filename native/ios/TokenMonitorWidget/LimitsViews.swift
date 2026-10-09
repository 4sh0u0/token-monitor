import SwiftUI
import TokenMonitorKit
import TokenMonitorUI
import WidgetKit

/// Which limits a widget shows.
enum LimitSelection {
    /// Automatic order: healthy, fresh readings first; among them the least
    /// left first (by each provider's headline window); then the snapshot's
    /// own display order, so equal rows never swap between refreshes.
    static func ordered(_ providers: [LimitProvider]) -> [LimitProvider] {
        providers.enumerated().sorted { left, right in
            let leftReady = left.element.isReady ? 0 : 1
            let rightReady = right.element.isReady ? 0 : 1
            if leftReady != rightReady { return leftReady < rightReady }
            let leftRemaining = remaining(left.element)
            let rightRemaining = remaining(right.element)
            if leftRemaining != rightRemaining { return leftRemaining < rightRemaining }
            return left.offset < right.offset
        }.map { $0.element }
    }

    /// What is left of the headline window, 0...1; windows without a meter
    /// sort after every measured one.
    static func remaining(_ provider: LimitProvider) -> Double {
        guard let window = provider.headlineWindow,
              let fraction = provider.meterFraction(for: window) else { return 2 }
        return fraction
    }

    static func pinned(_ id: String?, in snapshot: TokenSnapshot) -> LimitProvider? {
        guard let id else { return nil }
        return snapshot.limits.first { $0.id == id }
    }

    /// The pinned provider first while it is still in the snapshot, then the
    /// automatic order.
    static func providers(in snapshot: TokenSnapshot, pinnedID: String?, limit: Int) -> [LimitProvider] {
        let automatic = Self.ordered(snapshot.limits)
        guard let pinned = Self.pinned(pinnedID, in: snapshot) else {
            return Array(automatic.prefix(limit))
        }
        return Array(([pinned] + automatic.filter { $0.id != pinned.id }).prefix(limit))
    }

    /// Medium widget cells: a pinned provider's windows, else one cell per
    /// provider showing its headline window.
    static func cells(in snapshot: TokenSnapshot, pinnedID: String?, limit: Int) -> [LimitCell] {
        if let pinned = Self.pinned(pinnedID, in: snapshot) {
            let windows = Array(pinned.primaryWindows.prefix(limit))
            if windows.isEmpty {
                return [LimitCell(id: pinned.id, title: pinned.displayName, provider: pinned, window: nil)]
            }
            return windows.map { window in
                LimitCell(id: "\(pinned.id)|\(window.id)", title: WidgetText.windowTitle(window), provider: pinned, window: window)
            }
        }
        return Self.providers(in: snapshot, pinnedID: nil, limit: limit).map { provider in
            LimitCell(id: provider.id, title: provider.displayName, provider: provider, window: provider.headlineWindow)
        }
    }
}

struct LimitCell: Identifiable {
    let id: String
    let title: String
    let provider: LimitProvider
    let window: LimitWindow?
}

private extension LimitProvider {
    func fraction(of window: LimitWindow?) -> Double? {
        window.flatMap { meterFraction(for: $0) }
    }

    /// Mint while there is room, amber/red when running low; muted when the
    /// reading is not healthy and fresh.
    func tint(for window: LimitWindow?) -> Color {
        isReady ? TMTheme.quotaColor(remainingFraction: fraction(of: window)) : TMTheme.muted
    }
}

/// A capacity ring for one window: fills by what is left, the headline in the
/// middle. `showMeter == false` draws the bare track with the value.
struct LimitRing: View {
    let provider: LimitProvider
    let window: LimitWindow?
    let lineWidth: CGFloat
    let valueSize: CGFloat
    var caption: String? = nil

    var body: some View {
        QuotaRing(fraction: provider.fraction(of: window), color: provider.tint(for: window), lineWidth: lineWidth) {
            VStack(spacing: 0) {
                Text(value)
                    .font(.system(size: valueSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(provider.isReady ? TMTheme.number : TMTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                if let caption {
                    Text(caption)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(TMTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, lineWidth + 3)
        }
        .aspectRatio(1, contentMode: .fit)
        .widgetAccentable()
    }

    private var value: String {
        guard let window else { return "—" }
        return WidgetText.windowValue(window, in: provider, compact: true, withLeft: false)
    }
}

/// The line under a meter: the live reset/expiry countdown, else what the
/// user can act on (the status), else the plan.
struct LimitDetailText: View {
    let provider: LimitProvider
    let window: LimitWindow?
    let now: Date

    var body: some View {
        if let window, let boundary = WidgetText.boundary(window, now: now) {
            boundary
        } else {
            Text(fallback)
        }
    }

    private var fallback: String {
        if provider.status != .ok { return WidgetText.status(provider) }
        // A space keeps the line's height so rows stay aligned.
        return provider.planLabel ?? " "
    }
}

/// A full-width limits row: name, window and value, then the meter and the
/// countdown. Used by the large Usage dashboard.
struct LimitMeterRow: View {
    let provider: LimitProvider
    let now: Date

    var body: some View {
        let window = provider.headlineWindow
        let fraction = provider.fraction(of: window)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                VendorDot(color: provider.color)
                Text(provider.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(provider.isReady ? TMTheme.text : TMTheme.muted)
                    .lineLimit(1)
                if let window {
                    Text(WidgetText.windowTitle(window))
                        .font(.caption2)
                        .foregroundStyle(TMTheme.muted)
                        .lineLimit(1)
                }
                if provider.isStale { StaleBadge() }
                Spacer(minLength: 4)
                Text(valueText(window))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(provider.isReady ? TMTheme.number : TMTheme.muted)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                if let fraction {
                    QuotaBar(fraction: fraction, color: provider.tint(for: window), height: 3)
                        .widgetAccentable()
                } else {
                    Spacer(minLength: 0)
                }
                LimitDetailText(provider: provider, window: window, now: now)
                    .font(.system(size: 10))
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func valueText(_ window: LimitWindow?) -> String {
        guard let window else { return WidgetText.status(provider) }
        return WidgetText.windowValue(window, in: provider, compact: false, withLeft: true)
    }
}

// MARK: - Families

/// systemSmall: the most constrained (or pinned) provider as one ring.
struct LimitsSmallView: View {
    let entry: TokenEntry
    let provider: LimitProvider

    var body: some View {
        let window = provider.headlineWindow
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                VendorDot(color: provider.color)
                Text(provider.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TMTheme.text)
                    .lineLimit(1)
                if entry.isStale || provider.isStale { StaleBadge() }
                Spacer(minLength: 0)
            }
            LimitRing(
                provider: provider,
                window: window,
                lineWidth: 7,
                valueSize: 22,
                caption: window.map { WidgetText.windowTitle($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            LimitDetailText(provider: provider, window: window, now: entry.date)
                .font(.caption2)
                .foregroundStyle(TMTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// systemMedium: up to four rings — one per provider, or a pinned
/// provider's windows.
struct LimitsMediumView: View {
    let entry: TokenEntry
    let snapshot: TokenSnapshot

    var body: some View {
        let pinned = LimitSelection.pinned(entry.pinnedLimitID, in: snapshot)
        let cells = LimitSelection.cells(in: snapshot, pinnedID: entry.pinnedLimitID, limit: 4)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                if let pinned {
                    VendorDot(color: pinned.color)
                    Text(pinned.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TMTheme.text)
                        .lineLimit(1)
                } else {
                    SectionLabel(text: WidgetText.limits)
                }
                if entry.isStale || pinned?.isStale == true { StaleBadge() }
                Spacer(minLength: 4)
                UpdatedFootnote(snapshot: snapshot, now: entry.date, isStale: entry.isStale)
                RefreshButton()
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(cells) { cell in
                    LimitRingCell(cell: cell, now: entry.date, showsVendorDot: pinned == nil)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct LimitRingCell: View {
    let cell: LimitCell
    let now: Date
    let showsVendorDot: Bool

    var body: some View {
        VStack(spacing: 4) {
            LimitRing(provider: cell.provider, window: cell.window, lineWidth: 5, valueSize: 13)
                .frame(maxWidth: 56, maxHeight: 56)
            HStack(spacing: 3) {
                if showsVendorDot { VendorDot(color: cell.provider.color, size: 6) }
                Text(cell.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(cell.provider.isReady ? TMTheme.text : TMTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            LimitDetailText(provider: cell.provider, window: cell.window, now: now)
                .font(.system(size: 9.5))
                .foregroundStyle(TMTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// accessoryCircular: the headline window as a capacity gauge.
struct LimitsCircularView: View {
    let provider: LimitProvider

    var body: some View {
        let window = provider.headlineWindow
        AccessoryQuotaGauge(
            fraction: provider.fraction(of: window),
            valueText: window.map { WidgetText.windowValue($0, in: provider, compact: true, withLeft: false) } ?? "—",
            label: provider.displayName,
            tint: provider.tint(for: window)
        )
    }
}

/// accessoryRectangular: provider and window, the value, the meter and the
/// live countdown — `AccessorySummaryView` takes only static text, and the
/// countdown has to stay live without timeline churn.
struct LimitsRectangularView: View {
    let provider: LimitProvider
    let now: Date

    var body: some View {
        let window = provider.headlineWindow
        let fraction = provider.fraction(of: window)
        VStack(alignment: .leading, spacing: 1) {
            Text(title(window))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value(window))
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            if let fraction {
                Gauge(value: fraction) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
            }
            LimitDetailText(provider: provider, window: window, now: now)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func title(_ window: LimitWindow?) -> String {
        guard let window else { return provider.displayName }
        return "\(provider.displayName) · \(WidgetText.windowTitle(window))"
    }

    private func value(_ window: LimitWindow?) -> String {
        guard let window else { return WidgetText.status(provider) }
        return WidgetText.windowValue(window, in: provider, compact: false, withLeft: true)
    }
}

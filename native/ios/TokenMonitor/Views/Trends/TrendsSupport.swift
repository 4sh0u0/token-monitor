import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

// Shared by the Activity module and the Trends screen: what the History store
// can show right now, and how day keys, values and durations are printed.

/// What the History-based views can show for the current device scope.
enum TrendsLoadState: Equatable {
    /// Nothing is held yet and a load is in flight (or about to start).
    case loading
    /// The load failed and nothing (not even the stats preview) is held.
    case failed
    /// History is loaded but has no days (desktop `home.noHistory`).
    case empty
    /// The scoped device does not share its History with the Hub.
    case deviceUnshared
    /// `daily` has days to draw (possibly the 30-day preview).
    case ready
}

extension HistoryStore {
    /// The state the Activity module and the Trends screen draw. Like the
    /// desktop (`renderHomeTrendsModule`), only stored History rows count as
    /// "has history"; the live-today row alone does not.
    var trendsLoadState: TrendsLoadState {
        if let history, !history.daily.isEmpty { return .ready }
        switch phase {
        case .idle, .loading:
            return .loading
        case .failed:
            return .failed
        case .ready:
            if scope.deviceID != nil, !isHistoryAvailable { return .deviceUnshared }
            return .empty
        }
    }

    /// Why the screen shows the stats' 30-day preview instead of
    /// `/api/history`, nil when it does not.
    var trendsPreviewReason: TrendsPreviewReason? {
        guard isPreviewFallback else { return nil }
        return phase == .failed ? .loadFailed : .unsupported
    }
}

/// Why History is the stats' 30-day preview.
enum TrendsPreviewReason: Equatable {
    /// The Hub has no `/api/history` (404/405).
    case unsupported
    /// The first load failed; the preview stands in while it is retried.
    case loadFailed
}

/// Day keys, values and durations as the Trends views print them. Dates are
/// formatted in the user's locale (the desktop prints `M/D` and `Mon D` in
/// English for every language); day keys are calendar days, so they are laid
/// out in UTC and never shift with the phone's time zone.
enum TrendsFormat {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private static var style: Date.FormatStyle {
        Date.FormatStyle(locale: .autoupdatingCurrent, calendar: utc, timeZone: utc.timeZone)
    }

    /// A `yyyy-MM-dd` key at UTC midnight.
    static func date(_ key: String) -> Date? {
        DayKey.date(from: String(key.prefix(10)), calendar: utc)
    }

    /// `yyyy-MM` → the localized short month ("Jun", "6月"), the desktop
    /// Home's `compactMonthLabel`.
    static func monthLabel(_ key: String) -> String {
        guard let date = date(key + "-01") else { return key }
        return date.formatted(style.month(.abbreviated))
    }

    /// A day in full: "Mon, Nov 3, 2025".
    static func longDate(_ key: String) -> String {
        guard let date = date(key) else { return key }
        return date.formatted(style.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    /// A day without the year: "Nov 3" (the dashboard's `longDate`).
    static func shortDate(_ key: String) -> String {
        guard let date = date(key) else { return key }
        return date.formatted(style.month(.abbreviated).day())
    }

    /// An axis label: "11/3" (the desktop's `M/D` `shortDate`).
    static func axisDate(_ key: String) -> String {
        guard let date = date(key) else { return key }
        return date.formatted(style.month(.defaultDigits).day())
    }

    /// A chart value in its metric: compact tokens or a compact cost.
    static func value(_ value: Double, metric: TrendMetricKind, formatter: DisplayFormatter) -> String {
        switch metric {
        case .tokens: return formatter.compactTokens(value)
        case .cost: return formatter.compactCost(value)
        }
    }

    /// `formatDurationCompact` (whole minutes, rounded), localized: "2h 5m",
    /// "5m", "0m" in English.
    static func duration(milliseconds: Double) -> String {
        let parts = StatCards.durationParts(milliseconds: milliseconds)
        let total = Duration.seconds(parts.hours * 3600 + parts.minutes * 60)
        return total.formatted(.units(allowed: [.hours, .minutes], width: .narrow, zeroValueUnits: .hide))
    }

    /// The Home active-days chip (`home.activeDays` / `home.activeDaysYear`).
    static func activeDays(_ count: Int, window: ActiveDaysWindow) -> String {
        switch window {
        case .all: return String(localized: "\(count) active days")
        case .year: return String(localized: "\(count) active days in the last 12 months")
        }
    }

    /// `usage.excludedFromCost`, with a full en-US count.
    static func excludedFromCost(_ tokens: Int, formatter: DisplayFormatter) -> String {
        let fullCount = formatter.fullTokens(tokens)
        return String(localized: "\(fullCount) tokens excluded from the cost estimate")
    }

    /// A Trends range in words: "Last 30 days", "All time".
    static func rangeTitle(_ range: TrendRange) -> String {
        guard let days = range.dayCount else { return String(localized: "All time") }
        return lastDays(days)
    }

    /// `home.trendRange`: "Last 45 days".
    static func lastDays(_ count: Int) -> String {
        String(localized: "Last \(count) days")
    }
}

/// A muted footnote with a leading symbol and an optional action, for the
/// History notes (preview, failures) on the Trends screens.
struct TrendsNote: View {
    let systemImage: String
    let text: String
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.footnote)
                .foregroundStyle(TMTheme.muted)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.footnote)
                .foregroundStyle(TMTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                    .tint(TMTheme.accent)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The History states that have nothing to draw: loading, failed, empty, or a
/// device that shares no History. `compact` is the Overview module's inline
/// form; otherwise a centred block for the Trends screen.
struct TrendsStateView: View {
    @Environment(AppModel.self) private var model
    let state: TrendsLoadState
    var compact: Bool = false

    var body: some View {
        switch state {
        case .ready:
            EmptyView()
        case .loading:
            block {
                ProgressView()
                    .controlSize(compact ? .small : .regular)
                Text("Scanning usage history…")
                    .font(compact ? .footnote : .subheadline)
                    .foregroundStyle(TMTheme.muted)
            }
        case .empty:
            block {
                symbol("chart.bar.xaxis")
                Text("No usage history yet")
                    .font(compact ? .footnote : .headline)
                    .foregroundStyle(compact ? TMTheme.muted : TMTheme.text)
            }
        case .deviceUnshared:
            block {
                symbol("clock.badge.xmark")
                Text("This device doesn’t share its usage history with the Hub.")
                    .font(compact ? .footnote : .subheadline)
                    .foregroundStyle(TMTheme.muted)
                    .multilineTextAlignment(compact ? .leading : .center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .failed:
            failed
        }
    }

    private var failed: some View {
        let issue = model.history.lastError.map { HubIssue(error: $0, connection: model.connection) }
        return block {
            symbol("exclamationmark.triangle")
            Text("Couldn’t load usage history")
                .font(compact ? .footnote.weight(.semibold) : .headline)
                .foregroundStyle(TMTheme.text)
            if let issue, !compact {
                Text(verbatim: issue.message)
                    .font(.subheadline)
                    .foregroundStyle(TMTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Try Again") {
                model.history.refresh()
            }
            .font(compact ? .footnote.weight(.semibold) : .body)
            .buttonStyle(.bordered)
            .tint(TMTheme.accent)
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(compact ? .footnote : .title2)
            .foregroundStyle(TMTheme.muted)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func block<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if compact {
            HStack(spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .accessibilityElement(children: .combine)
        }
    }
}

extension View {
    /// Keeps `width` equal to this view's width (iOS 17-safe measuring).
    func trendsMeasuringWidth(_ width: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width.wrappedValue = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        width.wrappedValue = newWidth
                    }
            }
        }
    }
}

/// The smooth area line of the Home "Trend" (`areaLineChart(curve: true)`),
/// drawn from the Kit's geometry so the curve is the desktop's Catmull-Rom
/// with 1/6 tension: a fading fill under a 2 pt chart-blue stroke.
struct TrendsAreaLinePlot: View {
    let points: [TrendLinePoint]
    var insets: TrendPlotInsets = .homeTrend
    var color: Color = TMTheme.chartBlue

    var body: some View {
        GeometryReader { proxy in
            let geometry = TrendSeriesBuilder.areaLine(
                points: points,
                width: Double(proxy.size.width),
                height: Double(proxy.size.height),
                insets: insets,
                curve: true
            )
            ZStack {
                Path(trendElements: geometry.area)
                    .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path(trendElements: geometry.line)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

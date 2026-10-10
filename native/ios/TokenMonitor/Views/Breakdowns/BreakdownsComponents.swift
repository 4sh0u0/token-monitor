import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

// The parts the Tools, Models and Projects screens share: the screen frame
// (period picker, scope, totals and the period's state), the expandable row
// and its detail lines. The rows follow the desktop's breakdown list
// (`app.js` `updateRow`): full token count, compact cost label (full label in
// the detail), and a bar scaled to the largest row with a 2 % floor
// (`breakdownRenderPolicy.js` `rowWidth`).

/// A breakdown screen pushed from the Overview: it follows the Overview's
/// period (`model.selectedPeriod`, changed through `selectPeriod`) and the
/// device scope (`model.presented`), and shows the content only when the
/// period has usage to break down.
struct BreakdownsScreen<Content: View>: View {
    @Environment(AppModel.self) private var model
    private let title: LocalizedStringKey
    private let breakdown: FixedRangeBreakdown
    private let content: (UsagePeriod) -> Content

    /// - Parameters:
    ///   - breakdown: what the screen lists; fixed ranges (WEEK / 7D / 30D)
    ///     have tools and models but no projects (`FixedRanges.supports`).
    ///   - content: the list for the ready period.
    init(_ title: LocalizedStringKey, breakdown: FixedRangeBreakdown, @ViewBuilder content: @escaping (UsagePeriod) -> Content) {
        self.title = title
        self.breakdown = breakdown
        self.content = content
    }

    var body: some View {
        ScreenScrollView {
            if model.presented == nil {
                DataPlaceholder()
            } else {
                StatusBanner()
                BreakdownsPeriodPicker()
                periodContent
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.selectedPeriod, initial: true) { _, selection in
            // A fixed range derives from History, which loads lazily.
            if selection.isDerived, FixedRanges.supports(breakdown, selection: selection) {
                model.history.ensureLoaded()
            }
        }
    }

    @ViewBuilder
    private var periodContent: some View {
        let selection = model.selectedPeriod
        if let reason = PeriodUnavailableReason.breakdown(breakdown, for: selection) {
            // `periodRange.projectUnavailable` (the desktop hides the list).
            PeriodUnavailableNote(reason: reason)
        } else {
            switch model.usage(for: selection) {
            case .ready(let usage, _):
                BreakdownsTotalsCard(selection: selection, usage: usage)
                content(usage)
            case .loading:
                PeriodLoadingNote()
            case .unavailable(let reason):
                PeriodUnavailableNote(reason: reason)
            }
        }
    }
}

/// The screen's period: Today / the middle segment / All time, bound through
/// `selectPeriod`, plus a menu that switches the middle segment
/// (`periodMonthMode`: month, week, 7D, 30D) as the Overview's picker does.
struct BreakdownsPeriodPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selection = Binding(get: { model.selectedPeriod }, set: { model.selectPeriod($0) })
        let middle = Binding(get: { model.middleSelection }, set: { model.selectPeriod($0) })
        HStack(spacing: 8) {
            Picker("Period", selection: selection) {
                ForEach(choices) { choice in
                    Text(verbatim: choice.shortTitle).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            Menu {
                Picker("Period", selection: middle) {
                    ForEach(PeriodSelection.middleChoices) { choice in
                        Text(verbatim: choice.title).tag(choice)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "calendar")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TMTheme.accent)
                    .frame(minWidth: 36, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Period"))
        }
    }

    /// Today, middle, all time. A selection that is not one of them (the
    /// middle mode changed in Settings meanwhile) takes the middle place, so
    /// the control always shows what the list shows.
    private var choices: [PeriodSelection] {
        var choices = model.periodChoices
        if !choices.contains(model.selectedPeriod), choices.count == 3 {
            choices[1] = model.selectedPeriod
        }
        return choices
    }
}

/// The period's total above a breakdown: full token count (plus the
/// "≈ compact" line when enabled), the full cost label and the scope.
struct BreakdownsTotalsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmFormatter) private var formatter
    let selection: PeriodSelection
    let usage: UsagePeriod

    var body: some View {
        CardContainer(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text(verbatim: selection.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TMTheme.muted)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    ScopeBadge()
                }
                Text(verbatim: formatter.fullTokens(usage.totalTokens))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.number)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel(Text("Total tokens"))
                    .accessibilityValue(Text(verbatim: formatter.fullTokens(usage.totalTokens)))
                if model.preferences.showCompactTotalTokens, let approximation = formatter.compactApproximation(usage.totalTokens) {
                    Text(verbatim: approximation)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(TMTheme.muted)
                        .accessibilityHidden(true)
                }
                CostLabelText(usd: usage.costUsd, unpricedTokens: usage.unpricedTokens)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text("Total cost"))
                    .accessibilityValue(Text(verbatim: CostLabelText.string(usd: usage.costUsd, unpricedTokens: usage.unpricedTokens, formatter: formatter)))
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One expandable row of a breakdown: mark, name, full token count, a share
/// bar, the share and the compact cost label (`$1.23 + ?`, `—`). Tapping it
/// shows `detail` underneath.
struct BreakdownsRow<Mark: View, Detail: View>: View {
    @Environment(\.tmFormatter) private var formatter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let name: String
    private let tokens: Int
    private let costUsd: Double
    private let unpricedTokens: Int?
    private let barFraction: Double
    private let barFill: AnyShapeStyle
    private let share: String?
    private let isPinned: Bool
    private let isExpanded: Bool
    private let onToggle: (() -> Void)?
    private let mark: Mark
    private let detail: Detail

    /// - Parameters:
    ///   - barFraction: the bar's width, 0…1 (`BreakdownsBar.fraction`).
    ///   - share: the row's share of the period ("12%"), nil to omit.
    ///   - onToggle: expands or collapses the row; nil for a row without
    ///     details (no tokens).
    init(
        name: String,
        tokens: Int,
        costUsd: Double,
        unpricedTokens: Int?,
        barFraction: Double,
        barFill: AnyShapeStyle,
        share: String? = nil,
        isPinned: Bool = false,
        isExpanded: Bool,
        onToggle: (() -> Void)?,
        @ViewBuilder mark: () -> Mark,
        @ViewBuilder detail: () -> Detail
    ) {
        self.name = name
        self.tokens = tokens
        self.costUsd = costUsd
        self.unpricedTokens = unpricedTokens
        self.barFraction = barFraction
        self.barFill = barFill
        self.share = share
        self.isPinned = isPinned
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.mark = mark()
        self.detail = detail()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onToggle {
                Button {
                    withAnimation(.snappy) {
                        onToggle()
                    }
                } label: {
                    head
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: name))
                .accessibilityValue(accessibilityValue)
            } else {
                // Nothing to expand (no tokens): a plain element, not a
                // disabled ("dimmed") button.
                head
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: name))
                    .accessibilityValue(accessibilityValue)
            }
            if isExpanded, onToggle != nil {
                Rectangle()
                    .fill(TMTheme.divider)
                    .frame(height: 1)
                    .padding(.vertical, 10)
                    .accessibilityHidden(true)
                detail
                    .transition(.opacity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TMTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(TMTheme.cardStroke, lineWidth: 1)
        }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 8) {
            let titleLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
            titleLayout {
                HStack(alignment: .center, spacing: 10) {
                    mark
                    Text(verbatim: name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(TMTheme.text)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.leading)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(TMTheme.muted)
                            .accessibilityHidden(true)
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }
                Text(verbatim: formatter.fullTokens(tokens))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.number)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
            }
            let metaLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
            metaLayout {
                BreakdownsBar(fraction: barFraction, fill: barFill)
                    .frame(minWidth: 40)
                HStack(spacing: 8) {
                    if let share {
                        Text(verbatim: share)
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(TMTheme.muted)
                    }
                    CostLabelText(usd: costUsd, unpricedTokens: unpricedTokens, compact: true)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(TMTheme.muted)
                        .lineLimit(1)
                    if onToggle != nil {
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(TMTheme.muted)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .fixedSize()
            }
        }
    }

    /// "Total tokens: 1,234, Total cost: $1.23 + 12 unpriced tokens, 12%"
    /// (the desktop's row `aria-label` wording).
    private var accessibilityValue: Text {
        let cost = CostLabelText.string(usd: costUsd, unpricedTokens: unpricedTokens, formatter: formatter)
        var text = Text("Total tokens") + Text(verbatim: ": \(formatter.fullTokens(tokens)), ")
            + Text("Total cost") + Text(verbatim: ": \(cost)")
        if let share {
            text = text + Text(verbatim: ", \(share)")
        }
        if isPinned {
            text = text + Text(verbatim: ", ") + Text("Pinned")
        }
        return text
    }
}

/// A row's bar: a track and a fill (a vendor colour, or a project's
/// per-tool gradient).
struct BreakdownsBar: View {
    let fraction: Double
    let fill: AnyShapeStyle
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(TMTheme.track)
                Capsule()
                    .fill(fill)
                    .frame(width: proxy.size.width * CGFloat(fraction.isFinite ? min(1, max(0, fraction)) : 0))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// `rowWidth`: the share of the largest row, at least 2 % when the row
    /// has any value, 0 when nothing measurable is listed.
    static func fraction(_ value: Double, max maximum: Double) -> Double {
        guard value.isFinite, maximum.isFinite, value > 0, maximum > 0 else { return 0 }
        return max(0.02, min(1, value / maximum))
    }
}

/// `value` as a percentage of `total` in the desktop's detail wording
/// ("<1%", "12%"); nil when there is no total.
func breakdownsShareLabel(_ value: Double, of total: Double) -> String? {
    guard total.isFinite, total > 0, value.isFinite else { return nil }
    return AttributionRows.detailPercentLabel(value / total * 100)
}

/// One line of an expanded row (`appendAccordionMetricRow`): a label, an
/// optional share and a value, with an optional leading mark.
struct BreakdownsDetailRow<Leading: View>: View {
    private let title: Text
    private let percent: String?
    private let value: String
    private let leading: Leading

    init(title: Text, percent: String? = nil, value: String, @ViewBuilder leading: () -> Leading) {
        self.title = title
        self.percent = percent
        self.value = value
        self.leading = leading()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            leading
            title
                .font(.footnote)
                .foregroundStyle(TMTheme.text.opacity(0.9))
                .lineLimit(2)
                .truncationMode(.middle)
            if let percent {
                Text(verbatim: percent)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.muted)
            }
            Spacer(minLength: 8)
            Text(verbatim: value)
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(TMTheme.number)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

extension BreakdownsDetailRow where Leading == EmptyView {
    init(title: Text, percent: String? = nil, value: String) {
        self.init(title: title, percent: percent, value: value) { EmptyView() }
    }
}

/// A row's token components (`tokenComponentBreakdown`): cache hit and
/// miss with their share of input, output, and unclassified tokens when
/// there are any — never folded into cache miss.
struct BreakdownsComponentRows: View {
    @Environment(\.tmFormatter) private var formatter
    let components: TokenComponents

    var body: some View {
        let input = AttributionRows.inputPercentages(components)
        VStack(alignment: .leading, spacing: 8) {
            UsageBar(
                segments: [
                    UsageBar.Segment(id: "cacheRead", value: Double(components.cacheRead), color: TMTheme.chartBlue),
                    UsageBar.Segment(id: "cacheMiss", value: Double(components.cacheMiss), color: TMTheme.purple),
                    UsageBar.Segment(id: "output", value: Double(components.output), color: TMTheme.accent),
                    UsageBar.Segment(id: "unclassified", value: Double(components.unclassified), color: TMTheme.muted)
                ],
                height: 4
            )
            BreakdownsDetailRow(
                title: Text("Input (cache hit)"),
                percent: AttributionRows.detailPercentLabel(input.hit),
                value: formatter.fullTokens(components.cacheRead)
            ) {
                MarkDot(color: TMTheme.chartBlue)
            }
            BreakdownsDetailRow(
                title: Text("Input (cache miss)"),
                percent: AttributionRows.detailPercentLabel(input.miss),
                value: formatter.fullTokens(components.cacheMiss)
            ) {
                MarkDot(color: TMTheme.purple)
            }
            BreakdownsDetailRow(title: Text("Output"), value: formatter.fullTokens(components.output)) {
                MarkDot(color: TMTheme.accent)
            }
            if components.unclassified > 0 {
                BreakdownsDetailRow(title: Text("Unclassified"), value: formatter.fullTokens(components.unclassified)) {
                    MarkDot(color: TMTheme.muted)
                }
            }
        }
    }
}

/// The full cost label of an expanded row ("$1.23 + 1,234 unpriced tokens").
struct BreakdownsCostRow: View {
    @Environment(\.tmFormatter) private var formatter
    let costUsd: Double
    let unpricedTokens: Int?

    var body: some View {
        BreakdownsDetailRow(
            title: Text("Cost"),
            value: CostLabelText.string(usd: costUsd, unpricedTokens: unpricedTokens, formatter: formatter)
        )
    }
}

/// A breakdown with nothing to list for the period.
struct BreakdownsEmptyNote: View {
    let text: LocalizedStringKey

    var body: some View {
        CardContainer {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(TMTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Today / the middle segment / All time, as the desktop's DAY / MONTH /
/// TOTAL tabs. The middle segment shows `periodMonthMode` (This month, WEEK,
/// 7D or 30D) and carries the range menu: tapping it while it is not
/// selected shows its range, tapping it again (or touching and holding it)
/// opens the menu. Every change goes through `model.selectPeriod`, which also
/// stores the chosen range as `periodMonthMode`.
struct OverviewPeriodPicker: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selectionSpace

    var body: some View {
        HStack(spacing: 2) {
            segment(.today)
            middleSegment
            segment(.allTime)
        }
        .padding(3)
        .background(TMTheme.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(TMTheme.cardStroke, lineWidth: 1)
        }
        .animation(.snappy(duration: 0.25), value: model.selectedPeriod)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Period"))
    }

    private func segment(_ selection: PeriodSelection) -> some View {
        let isSelected = model.selectedPeriod == selection
        return Button {
            model.selectPeriod(selection)
        } label: {
            segmentLabel(Text(verbatim: selection.shortTitle), isSelected: isSelected, showsChevron: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: selection.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var middleSegment: some View {
        let middle = model.middleSelection
        let isSelected = model.selectedPeriod == middle
        let label = segmentLabel(Text(verbatim: middle.shortTitle), isSelected: isSelected, showsChevron: true)
        Group {
            if isSelected {
                // Already showing it: a tap opens the range menu.
                Menu {
                    rangeChoices
                } label: {
                    label
                }
            } else {
                // A tap shows the remembered range; touch and hold for the menu.
                Menu {
                    rangeChoices
                } label: {
                    label
                } primaryAction: {
                    model.selectPeriod(middle)
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: middle.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// This month, This week, Last 7 days, Last 30 days, with a check on
    /// the current `periodMonthMode`.
    private var rangeChoices: some View {
        Picker(selection: rangeBinding) {
            ForEach(PeriodSelection.middleChoices) { choice in
                Text(verbatim: choice.title).tag(choice)
            }
        } label: {
            Text("Period")
        }
        .pickerStyle(.inline)
    }

    private var rangeBinding: Binding<PeriodSelection> {
        Binding(
            get: { model.middleSelection },
            set: { model.selectPeriod($0) }
        )
    }

    private func segmentLabel(_ title: Text, isSelected: Bool, showsChevron: Bool) -> some View {
        HStack(spacing: 4) {
            title
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
        }
        .font(.subheadline.weight(isSelected ? .semibold : .medium))
        .foregroundStyle(isSelected ? TMTheme.text : TMTheme.muted)
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .matchedGeometryEffect(id: "selection", in: selectionSpace)
            }
        }
        .contentShape(Rectangle())
    }
}

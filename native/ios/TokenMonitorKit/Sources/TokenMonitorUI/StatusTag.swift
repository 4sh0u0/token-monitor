#if canImport(SwiftUI)
import SwiftUI
import TokenMonitorKit

/// A limits provider's status chip (desktop `.limit-provider-tag-*`): the
/// tone's colour on a faint border of it. `text` is the localized
/// `LimitStatusLabel`.
///
/// With `showsOKDot`, an `ok` status draws only the small mint dot the
/// desktop's Settings list shows for a detected provider, with `text` as its
/// accessibility label.
public struct StatusTag: View {
    private let text: String
    private let tone: LimitStatusTone
    private let showsOKDot: Bool
    private let font: Font

    public init(text: String, tone: LimitStatusTone, showsOKDot: Bool = false, font: Font = .caption2) {
        self.text = text
        self.tone = tone
        self.showsOKDot = showsOKDot
        self.font = font
    }

    public var body: some View {
        if showsOKDot && tone == .ok {
            Circle()
                .fill(TMTheme.success)
                .frame(width: 6, height: 6)
                .background(
                    Circle()
                        .fill(TMTheme.success.opacity(0.1))
                        .frame(width: 8, height: 8)
                )
                .accessibilityElement()
                .accessibilityLabel(text)
        } else {
            Text(verbatim: text)
                .font(font.weight(.medium))
                .foregroundStyle(TMTheme.tagColor(tone))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(TMTheme.tagBorder(tone), lineWidth: 1)
                )
        }
    }
}
#endif

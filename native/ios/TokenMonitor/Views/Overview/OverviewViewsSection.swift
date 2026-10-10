import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The end of the Overview: links to the full views (the desktop's view
/// switcher), pushed on the Overview tab's stack.
struct OverviewViewsSection: View {
    private static let routes: [AppRoute] = [.tools, .models, .projects, .sessions, .trends]

    var body: some View {
        CardContainer(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                CardTitle("Views")
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                ForEach(Array(Self.routes.enumerated()), id: \.offset) { index, route in
                    if index > 0 {
                        Divider()
                            .overlay(TMTheme.divider)
                            .padding(.leading, 52)
                    }
                    NavigationLink(value: route) {
                        ViewLinkRow(route: route)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)
        }
    }
}

private struct ViewLinkRow: View {
    let route: AppRoute
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(TMTheme.accent)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            title
                .font(.body)
                .foregroundStyle(TMTheme.text)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TMTheme.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var title: Text {
        switch route {
        case .tools: return Text("Tools")
        case .models: return Text("Models")
        case .projects: return Text("Projects")
        case .sessions: return Text("Sessions")
        case .trends: return Text("Trends")
        default: return Text(verbatim: "")
        }
    }

    private var symbol: String {
        switch route {
        case .tools: return "hammer"
        case .models: return "cpu"
        case .projects: return "folder"
        case .sessions: return "text.bubble"
        case .trends: return "chart.line.uptrend.xyaxis"
        default: return "circle"
        }
    }
}

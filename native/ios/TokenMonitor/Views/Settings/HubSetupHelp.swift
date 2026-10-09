import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The three ways to run a Hub (README, "Multi-device sync"), as a `Form` section.
struct HubSetupHelpSection: View {
    private static let guideURL = URL(string: "https://github.com/Javis603/token-monitor#multi-device-sync")

    var body: some View {
        Section {
            HelpItem(
                title: "Desktop widget",
                systemImage: "macwindow",
                message: "In Token Monitor on an always-on computer, open Settings › Multi-device Sync and choose “Host hub on this device”. Enter one of the addresses and the secret it shows. This iPhone must be on the same network or tailnet."
            )
            HelpItem(
                title: "Node hub",
                systemImage: "server.rack",
                message: "On an always-on machine, set TOKEN_MONITOR_SECRET in .env and run “npm run hub”. It listens on port 17321."
            )
            HelpItem(
                title: "Cloudflare Worker",
                systemImage: "cloud",
                message: "Deploy the repository’s worker folder to Cloudflare with a TOKEN_MONITOR_SECRET, then enter its https:// address. It works from anywhere, including mobile data."
            )
            if let guideURL = Self.guideURL {
                Link(destination: guideURL) {
                    Label("Multi-device sync guide", systemImage: "book")
                }
            }
        } header: {
            Text("Set up a Hub")
        } footer: {
            Text("This app only reads from your Hub. It never uploads anything.")
        }
        .listRowBackground(TMTheme.card)
    }
}

private struct HelpItem: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey

    var body: some View {
        DisclosureGroup {
            Text(message)
                .font(.footnote)
                .foregroundStyle(TMTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(TMTheme.text)
        }
    }
}

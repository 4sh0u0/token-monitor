import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// First launch: what the app does and what it needs, leading into the Hub form.
struct OnboardingView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(.largeTitle, weight: .semibold))
                            .foregroundStyle(TMTheme.accent)
                            .padding(16)
                            .background(TMTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .accessibilityHidden(true)
                        Text(verbatim: "Token Monitor")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(TMTheme.text)
                        Text("Your AI token usage, costs and tool limits from every computer, synced through your Token Monitor Hub.")
                            .font(.body)
                            .foregroundStyle(TMTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        FeatureRow(
                            systemImage: "chart.bar.fill",
                            title: "Usage and cost",
                            message: "Today, this month and all time, by tool and by model."
                        )
                        FeatureRow(
                            systemImage: "gauge.with.dots.needle.33percent",
                            title: "Tool limits",
                            message: "Quota windows, balances and when they reset."
                        )
                        FeatureRow(
                            systemImage: "applewatch",
                            title: "Widgets and Apple Watch",
                            message: "Glance at today’s numbers without opening the app."
                        )
                    }
                    VStack(spacing: 12) {
                        NavigationLink {
                            HubSetupScreen()
                        } label: {
                            Text("Connect to Your Hub")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Text("You need a running Hub: the desktop widget’s “Host hub on this device”, a Node hub, or a Cloudflare Worker.")
                            .font(.footnote)
                            .foregroundStyle(TMTheme.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background {
                TMBackground().ignoresSafeArea()
            }
        }
    }
}

private struct FeatureRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(TMTheme.chartBlue)
                .frame(minWidth: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TMTheme.text)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(TMTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The Hub form on its own screen, reached from onboarding. Saving makes the
/// root view switch to the tabs.
struct HubSetupScreen: View {
    var body: some View {
        Form {
            HubConnectionForm()
            HubSetupHelpSection()
        }
        .scrollContentBackground(.hidden)
        .background {
            TMBackground().ignoresSafeArea()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Connect to Hub")
        .navigationBarTitleDisplayMode(.inline)
    }
}

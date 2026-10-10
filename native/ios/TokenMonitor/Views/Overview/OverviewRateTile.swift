import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The hero's rate, in `tokenRateMode` (output tok/s or TPM); tapping it
/// switches the mode, as clicking the desktop's reading does.
///
/// - Live mode with `showLiveTokenRate`: the live reading
///   (`model.liveRate`, all devices or the scoped one per
///   `liveTokenRateScope`), `— tok/s` before the first sample, dimmed once
///   idle, and a per-model popover grouped by device
///   (`LiveTokenRate.tooltipEntries`).
/// - Otherwise: the period's average (`≈ 62 tok/s` / `≈ 1.2K tok/min`),
///   hidden when it rounds to 0, as the desktop's title reading is.
struct OverviewRateTile: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmFormatter) private var formatter
    let usage: UsagePeriod
    @State private var showsModels = false

    private var mode: TokenRateMode { model.preferences.tokenRateMode }

    var body: some View {
        Group {
            if model.showsLiveRate {
                liveTile
            } else if let average = averageText {
                tile(title: mode == .burn ? Text("Token burn") : Text("Output speed"), value: average, dimmed: false)
                    .accessibilityHint(Text("Switches between tok/s and TPM."))
            }
        }
        .onChange(of: model.showsLiveRate) { _, shows in
            // A popover closed by its tile going away must not reopen with it.
            if !shows { showsModels = false }
        }
    }

    // MARK: Live

    private var liveTile: some View {
        let sample = model.liveRate
        let idle = sample?.idle ?? true
        let entries = LiveTokenRate.tooltipEntries(sample: sample, mode: mode)
        return HStack(alignment: .top, spacing: 6) {
            tile(title: mode == .burn ? Text("Live token burn") : Text("Live generation speed"), value: liveText(sample?.value(mode)), dimmed: idle)
                .animation(.snappy, value: sample?.revision)
                .accessibilityLabel(liveAccessibilityLabel(sample: sample))
                .accessibilityHint(Text("Switches between tok/s and TPM."))
            // Kept in place while there is nothing to list (hidden and
            // disabled), so the tile does not shift and the popover does not
            // come back by itself when per-model rates return.
            Button {
                showsModels = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(TMTheme.muted)
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(entries.isEmpty ? 0 : 1)
            .disabled(entries.isEmpty)
            .accessibilityHidden(entries.isEmpty)
            .accessibilityLabel(Text("Rates by model"))
            .popover(isPresented: $showsModels) {
                LiveRateModelList(mode: mode)
                    .tmPresentation(model.context)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `62 tok/s`, `1.2K TPM`, or `— tok/s` without a sample. The units are
    /// not translated, as on the desktop.
    private func liveText(_ rate: Double?) -> String {
        let value = rate.map(formatter.liveTokenRate) ?? "—"
        return "\(value) \(Self.unit(mode))"
    }

    static func unit(_ mode: TokenRateMode) -> String {
        mode == .burn ? "TPM" : "tok/s"
    }

    /// `home.liveTokenRate.*Title` without the desktop's "Click to …"
    /// sentence (the hint says what a tap does).
    private func liveAccessibilityLabel(sample: LiveTokenRateSample?) -> Text {
        let value = liveText(sample?.value(mode))
        let scope = scopeName
        let idle = sample?.idle == true
        switch (mode, idle) {
        case (.speed, false): return Text("Live generation speed (\(scope)): \(value)")
        case (.burn, false): return Text("Live token burn (\(scope)): \(value)")
        case (.speed, true): return Text("Last observed generation speed (\(scope)): \(value)")
        case (.burn, true): return Text("Last observed token burn (\(scope)): \(value)")
        }
    }

    /// All devices, or the scoped device the rate follows.
    private var scopeName: String {
        let scope = LiveTokenRate.effectiveScope(rateScope: model.preferences.liveTokenRateScope, deviceScope: model.preferences.deviceScope)
        guard scope == .device else { return String(localized: "All devices") }
        return model.scopedDevice?.displayName ?? String(localized: "Device not found")
    }

    // MARK: Average

    /// `home.tokenRate` / `home.tokenRateBurn` over the period's timed
    /// counters; nil when the rate rounds to 0.
    private var averageText: String? {
        let rate = mode == .burn
            ? LiveTokenRate.burnPerMinute(usage.throughput)
            : LiveTokenRate.tokensPerSecond(usage.throughput)
        guard JSCompat.round(rate) > 0 else { return nil }
        let value = formatter.compactTokens(rate)
        return mode == .burn
            ? String(localized: "≈ \(value) tok/min")
            : String(localized: "≈ \(value) tok/s")
    }

    // MARK: Tile

    private func tile(title: Text, value: String, dimmed: Bool) -> some View {
        Button {
            toggleMode()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(verbatim: value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .opacity(dimmed ? 0.55 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleMode() {
        let next: TokenRateMode = mode == .burn ? .speed : .burn
        withAnimation(.snappy) {
            model.updatePreferences { $0.tokenRateMode = next }
        }
    }
}

/// The live rate's per-model breakdown: each live device's models by rate,
/// under a device heading when several devices are live.
private struct LiveRateModelList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmFormatter) private var formatter
    let mode: TokenRateMode

    var body: some View {
        let entries = LiveTokenRate.tooltipEntries(sample: model.liveRate, mode: mode)
        VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                Text(verbatim: "—")
                    .font(.subheadline)
                    .foregroundStyle(TMTheme.muted)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                switch entry {
                case .device(let name, let separated):
                    if separated {
                        Divider()
                            .overlay(TMTheme.divider)
                            .padding(.vertical, 2)
                    }
                    Text(verbatim: name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TMTheme.muted)
                        .accessibilityAddTraits(.isHeader)
                case .model(let name, let rate):
                    HStack(spacing: 8) {
                        VendorMark(.model(name), size: 14)
                        Text(verbatim: name)
                            .font(.subheadline)
                            .foregroundStyle(TMTheme.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 12)
                        Text(verbatim: "\(formatter.liveTokenRate(rate)) \(OverviewRateTile.unit(mode))")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(TMTheme.number)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 260, idealWidth: 300, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(TMTheme.background)
        .presentationBackground(TMTheme.background)
    }
}

import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// Settings › Currency: the display currency, and for TWD/HKD/CNY the
/// exchange rate, automatic (the daily rate, else the built-in floor) or
/// manual (`currencyRates` override), as the desktop's currency row
/// (`app.js` `syncCurrencyRateControls` and the rate-mode listeners).
struct CurrencySettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmFormatter) private var format
    @State private var manualText = ""
    @FocusState private var editsManualRate: Bool

    private enum RateMode: Hashable {
        case auto
        case manual
    }

    private var currency: DisplayCurrency { model.preferences.currency }

    /// `currencyRateMode`: manual while a valid override is stored.
    private var rateMode: RateMode {
        CurrencyRates.isValidRate(model.preferences.currencyRates[currency.code]) ? .manual : .auto
    }

    /// The rate in effect for the selected currency (override included).
    private var effectiveRate: Double {
        model.context.rates.multiplier(for: currency)
    }

    var body: some View {
        Form {
            Section {
                Picker("Currency", selection: model.displayPreference(\.currency)) {
                    ForEach(DisplayCurrency.allCases) { option in
                        Text(option.settingsTitle)
                            .tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Currency")
            } footer: {
                Text("The Hub reports costs in US dollars; they are converted for display, in the widgets and on Apple Watch too.")
            }
            .listRowBackground(TMTheme.card)

            if currency != .usd {
                rateSection
            }
        }
        .settingsListBackground()
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: syncManualText)
        .onChange(of: currency) { _, _ in syncManualText() }
        .onChange(of: rateMode) { _, _ in syncManualText() }
        .onChange(of: editsManualRate) { _, editing in
            if !editing { commitManualRate() }
        }
        .onDisappear {
            if editsManualRate { commitManualRate() }
        }
    }

    private var rateSection: some View {
        Section {
            Picker("Exchange rate", selection: rateModeBinding) {
                Text("Auto").tag(RateMode.auto)
                Text("Manual").tag(RateMode.manual)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch rateMode {
            case .auto:
                Text(autoStatus)
                    .font(.subheadline)
                    .foregroundStyle(TMTheme.muted)
                    .monospacedDigit()
            case .manual:
                HStack(spacing: 8) {
                    Text(verbatim: "1 USD =")
                        .foregroundStyle(TMTheme.muted)
                    TextField(
                        "Exchange rate",
                        text: $manualText,
                        prompt: Text(verbatim: format.rate(effectiveRate))
                    )
                    .keyboardType(.decimalPad)
                    .focused($editsManualRate)
                    .monospacedDigit()
                    .submitLabel(.done)
                    .onSubmit(commitManualRate)
                    Text(verbatim: currency.code)
                        .foregroundStyle(TMTheme.muted)
                }
            }
        } header: {
            Text("Exchange rate")
        } footer: {
            Text("Auto uses the day’s exchange rate. Manual keeps the rate you enter; clear it to go back to Auto.")
        }
        .listRowBackground(TMTheme.card)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    editsManualRate = false
                }
            }
        }
    }

    /// `settings.currency.rateLive` with the fetched rates' day (`MM-DD`, as
    /// the desktop's `date.slice(5)`), else `rateDefault` (built-in floor).
    private var autoStatus: String {
        let rates = model.context.rates
        let rate = format.rate(effectiveRate)
        if rates.origin(for: currency) == .fetched, let date = rates.fetchedDate, !date.isEmpty {
            let day = date.count > 5 ? String(date.dropFirst(5)) : date
            return String(localized: "1 USD = \(rate) · updated \(day)")
        }
        return String(localized: "1 USD = \(rate)")
    }

    private var rateModeBinding: Binding<RateMode> {
        Binding(
            get: { rateMode },
            set: { mode in
                let code = currency.code
                guard currency != .usd, mode != rateMode else { return }
                switch mode {
                case .auto:
                    // Auto is the absence of an override.
                    model.updatePreferences { $0.currencyRates.removeValue(forKey: code) }
                case .manual:
                    // Seeded with the rate shown, so switching changes nothing
                    // until the user edits it (`Number(formatRate(current)) || 1`).
                    let shown = Double(format.rate(effectiveRate)) ?? 0
                    let seed = CurrencyRates.isValidRate(shown) ? shown : 1
                    model.updatePreferences { $0.currencyRates[code] = seed }
                    manualText = format.rate(seed)
                    // The field appears with this change; focus it once it exists.
                    Task { @MainActor in
                        editsManualRate = true
                    }
                }
            }
        )
    }

    /// The field shows the rate in effect unless the user is typing in it.
    private func syncManualText() {
        guard !editsManualRate else { return }
        manualText = rateMode == .manual ? format.rate(effectiveRate) : ""
    }

    /// A valid number becomes the override; an empty or invalid one removes
    /// it, back to Auto (the desktop's override-input listener).
    private func commitManualRate() {
        guard currency != .usd, rateMode == .manual else { return }
        let code = currency.code
        let text = manualText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let value = Double(text)
        model.updatePreferences { preferences in
            if let value, CurrencyRates.isValidRate(value) {
                preferences.currencyRates[code] = value
            } else {
                preferences.currencyRates.removeValue(forKey: code)
            }
        }
        syncManualText()
    }
}

extension DisplayCurrency {
    /// The desktop's currency menu entry (`settings.currency.*`).
    var settingsTitle: String {
        switch self {
        case .usd: return String(localized: "USD - US Dollar")
        case .twd: return String(localized: "TWD - New Taiwan Dollar")
        case .hkd: return String(localized: "HKD - Hong Kong Dollar")
        case .cny: return String(localized: "CNY - Chinese Yuan")
        }
    }
}

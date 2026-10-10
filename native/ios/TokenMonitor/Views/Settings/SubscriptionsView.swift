import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The Hub's shared subscription list (`GET /api/subscriptions`), read-only:
/// the monthly total in the display currency (lapsed plans and other months'
/// top-ups left out), and per record what the desktop's plan tooltip says
/// (`subscriptionTooltipRows`): price and cadence, next charge or valid
/// until with the days left, months subscribed and paid to date; for a
/// top-up ledger the last top-up, this month's and the total, and — when
/// the record matches a provider account with a balance (by email, profile
/// name or the sole account; D-TOPUP) — the balance, burn rate and when it
/// runs out. Records are edited on a computer; there is no binding UI.
struct SubscriptionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tmFormatter) private var formatter

    var body: some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                TMBackground().ignoresSafeArea()
            }
            .navigationTitle("Subscriptions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        attachStore()
                        Task { await model.subscriptions.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.connection == nil || model.subscriptions.isLoading)
                }
            }
            .refreshable {
                attachStore()
                await model.subscriptions.refresh()
            }
            .task(id: TaskKey(hub: model.connection?.snapshotKey, hasStats: model.stats != nil)) {
                attachStore()
                model.subscriptions.ensureLoaded()
            }
    }

    private struct TaskKey: Equatable {
        var hub: String?
        var hasStats: Bool
    }

    /// The store learns the connection from AppModel's store sync, which runs
    /// after the alias sync and History; hand it over now so a screen opened
    /// right after launch (or on an older Hub that announces no version) can
    /// load at once. `update` only fetches when the version moved.
    private func attachStore() {
        guard let connection = model.connection else { return }
        model.subscriptions.update(stats: model.stats, connection: connection)
    }

    @ViewBuilder
    private var content: some View {
        let store = model.subscriptions
        if model.connection == nil {
            ScrollView {
                ContentUnavailableView {
                    Label("No Hub connected", systemImage: "network.slash")
                } description: {
                    Text("Add your Hub’s address and secret in Settings.")
                }
                .padding(.top, 48)
            }
        } else if let document = store.document {
            list(document.subscriptions, store: store)
        } else {
            switch store.phase {
            case .unsupported:
                ScrollView {
                    ContentUnavailableView {
                        Label("Subscriptions unavailable", systemImage: "creditcard")
                    } description: {
                        Text("This Hub does not share subscriptions. Update the Hub to see them here.")
                    }
                    .padding(.top, 48)
                }
            case .failed:
                ScrollView {
                    failure(store.lastError)
                        .padding(.top, 48)
                }
            case .idle, .loading, .ready:
                ScrollView {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading subscriptions…")
                            .font(.subheadline)
                            .foregroundStyle(TMTheme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func list(_ subscriptions: [HubSubscription], store: SubscriptionStore) -> some View {
        let today = SubscriptionMath.todayString()
        let rates = formatter.rates.effectiveMultipliers
        let limits = model.stats?.limits ?? []
        let mask = model.preferences.maskLimitAccountEmails
        let total = SubscriptionMath.monthlyTotalUsd(subscriptions, rates: rates, today: today)
        let lapsedCount = subscriptions.count - SubscriptionMath.activeSubscriptions(subscriptions, today: today).count
        return Form {
            if subscriptions.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No subscriptions yet")
                            .font(.headline)
                            .foregroundStyle(TMTheme.text)
                        Text("Add what you pay for each AI account in Token Monitor on your computer. The list is kept on your Hub and shared by every device.")
                            .font(.subheadline)
                            .foregroundStyle(TMTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(TMTheme.card)
            } else {
                Section {
                    let totalText = formatter.cost(total)
                    Text("Total \(totalText) / month")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(TMTheme.text)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if lapsedCount > 0 {
                            Text("Plans that have ended are left out of the total; top-ups count for this month only.")
                        }
                        Text("The list is kept on your Hub and shared by every device. Edit it in Token Monitor on your computer.")
                    }
                }
                .listRowBackground(TMTheme.card)

                ForEach(subscriptions) { subscription in
                    SubscriptionCard(
                        subscription: subscription,
                        account: SubscriptionMath.matchBalanceAccount(subscription, providers: limits),
                        today: today,
                        rates: rates,
                        maskEmails: mask
                    )
                }
            }
            if let error = store.lastError {
                Section {
                    Label {
                        Text(HubIssue(error: error, connection: model.connection).title)
                            .font(.footnote)
                            .foregroundStyle(TMTheme.muted)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(TMTheme.warning)
                    }
                } footer: {
                    if let loadedAt = store.loadedAt {
                        Text("Showing the list from \(loadedAt.formatted(date: .abbreviated, time: .shortened)).")
                    }
                }
                .listRowBackground(TMTheme.card)
            }
        }
    }

    private func failure(_ error: HubClientError?) -> some View {
        let issue = error.map { HubIssue(error: $0, connection: model.connection) }
        return ContentUnavailableView {
            Label {
                Text(issue?.title ?? String(localized: "Something went wrong"))
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        } description: {
            if let issue {
                Text(issue.message)
            }
        } actions: {
            Button("Try Again") {
                attachStore()
                Task { await model.subscriptions.refresh() }
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - One record

/// One subscription or top-up ledger: the provider's mark (omitted while
/// tool icons are off, as on the desktop), the account it is for, then its
/// detail rows.
private struct SubscriptionCard: View {
    @Environment(\.tmFormatter) private var formatter
    let subscription: HubSubscription
    /// The provider account the record matches (email, profile name or the
    /// sole account), for the title and a ledger's balance.
    let account: LimitProvider?
    let today: String
    let rates: [String: Double]
    let maskEmails: Bool

    var body: some View {
        let lapsed = SubscriptionDetail.isLapsed(subscription, today: today)
        Section {
            header(lapsed: lapsed)
            if subscription.isTopUp {
                topUpRows
            } else {
                planRows
            }
        }
        .listRowBackground(TMTheme.card)
    }

    private func header(lapsed: Bool) -> some View {
        let accountLabel = SubscriptionDetail.accountLabel(subscription, account: account, mask: maskEmails)
        let providerName = SubscriptionDetail.providerName(subscription.provider)
        let title = [providerName, accountLabel ?? subscription.planName].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .center, spacing: 10) {
            if LimitPresentation.catalogProviderIDs.contains(SubscriptionDetail.normalizedProvider(subscription.provider)) {
                VendorMark(
                    .provider(SubscriptionDetail.normalizedProvider(subscription.provider)),
                    size: 20,
                    muted: lapsed,
                    hidesWhenIconsOff: true
                )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.headline)
                    .foregroundStyle(lapsed ? TMTheme.muted : TMTheme.text)
                    .lineLimit(2)
                if accountLabel != nil, !subscription.planName.isEmpty {
                    Text(verbatim: subscription.planName)
                        .font(.subheadline)
                        .foregroundStyle(TMTheme.muted)
                }
            }
            Spacer(minLength: 8)
            if subscription.isTopUp {
                Chip(text: String(localized: "Top-ups"), color: TMTheme.chartBlue)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: Plan

    @ViewBuilder
    private var planRows: some View {
        detailRow("Price", SubscriptionDetail.priceText(subscription))
        let endDate = SubscriptionMath.coverageEndDate(subscription, today: today)
        let daysLeft = SubscriptionMath.daysUntilRenewal(subscription, today: today)
        if let endDate {
            let value = [SubscriptionDetail.longDate(endDate), daysLeft.map(SubscriptionDetail.daysText)]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            if subscription.autoRenew {
                detailRow("Next charge", value, warn: (daysLeft ?? 0) < 0)
            } else {
                detailRow("Valid until", value, warn: (daysLeft ?? 0) < 0)
            }
        }
        if !subscription.autoRenew {
            detailRow("Auto-renew", String(localized: "Off"))
        }
        detailRow("Subscribed", SubscriptionDetail.elapsedText(subscription, today: today))
    }

    // MARK: Top-up ledger

    @ViewBuilder
    private var topUpRows: some View {
        if let last = SubscriptionMath.lastTopUp(subscription) {
            let amount = SubscriptionMath.moneyText(minor: last.amountMinor, currency: subscription.currency)
            detailRow("Last top-up", "\(SubscriptionDetail.longDate(last.date)) · \(amount)")
        }
        let monthMinor = SubscriptionMath.topUpMonthMinor(subscription, today: today)
        if monthMinor > 0 {
            detailRow("Added this month", SubscriptionMath.moneyText(minor: monthMinor, currency: subscription.currency))
        }
        let entries = SubscriptionMath.topUpEntries(subscription)
        if entries.count > 1 {
            let total = SubscriptionMath.moneyText(minor: SubscriptionMath.topUpTotalMinor(subscription), currency: subscription.currency)
            detailRow("Total in", "\(total) · \(String(localized: "\(entries.count) top-ups"))")
        }
        if entries.isEmpty {
            Text("No top-ups recorded yet.")
                .font(.subheadline)
                .foregroundStyle(TMTheme.muted)
        }
        if let account, let balance = SubscriptionMath.topUpBalance(of: account, for: subscription) {
            detailRow("Balance", formatter.balance(balance.amount, currency: balance.currency))
            if let projection = SubscriptionMath.topUpProjection(
                subscription,
                balance: balance.amount,
                balanceCurrency: balance.currency,
                today: today,
                rates: rates
            ), projection.dailyBurn > 0 {
                let perDay = formatter.balance(projection.dailyBurn, currency: balance.currency)
                detailRow("Burn rate", String(localized: "\(perDay)/day"))
                if let exhaust = projection.exhaustDate {
                    let value = [SubscriptionDetail.longDate(exhaust), projection.daysRemaining.map(SubscriptionDetail.daysText)]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    detailRow("Runs out", value)
                }
            }
        }
    }

    private func detailRow(_ title: LocalizedStringKey, _ value: String, warn: Bool = false) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .monospacedDigit()
                .foregroundStyle(warn ? TMTheme.warning : TMTheme.text)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(title)
                .foregroundStyle(TMTheme.muted)
        }
        .font(.subheadline)
    }
}

// MARK: - Wording

/// `subscriptionText.js` with the app's localization.
enum SubscriptionDetail {
    static func normalizedProvider(_ id: String) -> String {
        OrderedIDs.normalizeID(id)
    }

    /// `providerLabel`: the provider's settings name ("Claude Code").
    static func providerName(_ id: String) -> String {
        let normalized = normalizedProvider(id)
        if let entry = VendorCatalog.limitProviders.first(where: { $0.id == normalized }) {
            return entry.settingsLabel
        }
        return id
    }

    /// `subscriptionRowAccountLabel`: the matched account's title (masked
    /// when asked), else the record's stored binding; nil when nothing names
    /// the account.
    static func accountLabel(_ subscription: HubSubscription, account: LimitProvider?, mask: Bool) -> String? {
        if let account {
            let title = LimitPresentation.accountTitle(account, peers: [account], index: 0, mask: mask)
            if !title.isFallback {
                let text = accountTitleText(title)
                if !text.isEmpty { return text }
            }
        }
        let email = (subscription.bindingEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty { return mask ? LimitPresentation.maskedEmail(email) : email }
        let name = (subscription.bindingProfileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// A Kit account title with its fixed words localized.
    static func accountTitleText(_ title: LimitAccountTitle) -> String {
        title.parts.map { part -> String in
            switch part {
            case .text(let text): return text
            case .personalWorkspace: return String(localized: "Personal")
            case .environment: return String(localized: "Environment")
            case .accountNumber(let number): return String(localized: "Account \(number)")
            case .disambiguator(let value): return "#\(value)"
            }
        }
        .joined(separator: " · ")
    }

    /// Coverage stopped on or before today: left out of the total.
    static func isLapsed(_ subscription: HubSubscription, today: String) -> Bool {
        SubscriptionMath.activeSubscriptions([subscription], today: today).isEmpty
    }

    /// `priceText`: "$20.00 / mo", "HK$399.00 / 3 mo", "$200.00 / yr".
    static func priceText(_ subscription: HubSubscription) -> String {
        let amount = SubscriptionMath.amountText(subscription)
        let count = max(1, min(24, subscription.intervalCount))
        switch (subscription.interval, count) {
        case (.year, 1): return String(localized: "\(amount) / yr")
        case (.year, _): return String(localized: "\(amount) / \(count) yr")
        case (.month, 1): return String(localized: "\(amount) / mo")
        case (.month, _): return String(localized: "\(amount) / \(count) mo")
        }
    }

    /// `daysText`: "today" on the day itself, "ended" once lapsed, else
    /// "12d left".
    static func daysText(_ days: Int) -> String {
        if days < 0 { return String(localized: "ended") }
        if days == 0 { return String(localized: "today") }
        return String(localized: "\(days)d left")
    }

    /// `elapsedText`: "7 mo · $140.00 total", "12d · $20.00 total", or
    /// "Starts later".
    static func elapsedText(_ subscription: HubSubscription, today: String) -> String {
        let elapsed: String
        switch SubscriptionMath.elapsed(subscription, today: today) {
        case .notStarted:
            return String(localized: "Starts later")
        case .months(let months):
            elapsed = String(localized: "\(months) mo")
        case .days(let days):
            elapsed = String(localized: "\(days)d")
        }
        let paid = SubscriptionMath.moneyText(minor: SubscriptionMath.paidToDateMinor(subscription, today: today), currency: subscription.currency)
        return "\(elapsed) · \(String(localized: "\(paid) total"))"
    }

    /// `dateText`: "Mar 4, 2026" in the app's language.
    static func longDate(_ value: String?) -> String {
        guard let date = SubscriptionMath.localDate(value) else { return "" }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }
}

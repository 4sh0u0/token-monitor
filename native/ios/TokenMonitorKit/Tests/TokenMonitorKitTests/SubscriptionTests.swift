import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TokenMonitorKit

/// `Fixtures/v2/subscriptions.json` (captured from a real Node hub) and the
/// golden rendered by running `src/shared/subscriptionDisplay.js` over it at
/// four "today" dates (`Fixtures/v2/golden/subscriptions.json`). The inline
/// vectors below were computed with `node` from the desktop modules
/// (`subscriptionDisplay.js`, `subscriptionText.js`, `currency.js`).
final class SubscriptionTests: XCTestCase {
    // MARK: Decoding

    func testDocumentDecodesTheHubFixture() throws {
        let document = try SubscriptionDocument.decode(from: SubscriptionFixtures.data("subscriptions.json"))
        XCTAssertEqual(document.version, 1)
        XCTAssertEqual(document.updatedAt, "2026-10-10T16:29:45.000Z")
        XCTAssertEqual(document.subscriptions.map(\.id), [
            "sub-claude-max", "sub-codex-yearly", "sub-cursor-ending", "sub-zai-quarterly",
            "sub-kimi-lapsed", "topup-openrouter-hkd", "topup-deepseek-cny"
        ])

        let claude = document.subscriptions[0]
        XCTAssertEqual(claude.provider, "claude")
        XCTAssertEqual(claude.kind, .subscription)
        XCTAssertEqual(claude.bindingEmail, "dev@example.com")
        XCTAssertNil(claude.bindingProfileName)
        XCTAssertEqual(claude.planName, "Max 5x")
        XCTAssertEqual(claude.amountMinor, 10_000)
        XCTAssertEqual(claude.currency, "USD")
        XCTAssertEqual(claude.interval, .month)
        XCTAssertEqual(claude.intervalCount, 1)
        XCTAssertEqual(claude.startDate, "2026-01-31")
        XCTAssertTrue(claude.autoRenew)
        XCTAssertNil(claude.nextRenewalOverride)
        XCTAssertNil(claude.endDate)
        XCTAssertEqual(claude.note, "Jan-31 anchor")
        XCTAssertEqual(claude.updatedAt, "2026-02-01T08:00:00.000Z")

        let zai = document.subscriptions[3]
        XCTAssertEqual(zai.currency, "TWD")
        XCTAssertEqual(zai.displayCurrency, .twd)
        XCTAssertEqual(zai.intervalCount, 3)

        let openrouter = document.subscriptions[5]
        XCTAssertTrue(openrouter.isTopUp)
        XCTAssertNil(openrouter.startDate)
        XCTAssertEqual(openrouter.topUps.map(\.id), ["top-or-2", "top-or-3", "top-or-1"])
        XCTAssertEqual(openrouter.topUps.map(\.date), ["2026-10-03", "2026-09-20", "2026-08-12"])
    }

    func testNormalizationMatchesTheDesktop() throws {
        // `normalizeSubscriptions(messy, {currencyApi: currency.js})`.
        let document = try SubscriptionDocument.decode(from: Data(SubscriptionFixtures.messyDocument.utf8))
        // The version token is kept verbatim (`String(doc.updatedAt || '')`).
        XCTAssertEqual(document.updatedAt, " 2026-10-10T16:29:45.000Z ")
        XCTAssertEqual(document.subscriptions.map(\.id), [
            "messy-1", "messy-2", "messy-6", "messy-7", "messy-8", "messy-9", "messy-10"
        ])
        let records = Dictionary(uniqueKeysWithValues: document.subscriptions.map { ($0.id, $0) })

        XCTAssertEqual(records["messy-1"], HubSubscription(
            id: "messy-1", provider: "claude", kind: .subscription,
            bindingEmail: "dev@example.com", bindingProfileName: "Work",
            planName: "Max", amountMinor: 2000, currency: "HKD", interval: .year, intervalCount: 24,
            startDate: "2026-01-31", topUps: [], autoRenew: true,
            nextRenewalOverride: nil, endDate: nil, note: "7", updatedAt: "2026-01-31T00:00:00.000Z"
        ))
        XCTAssertEqual(records["messy-2"], HubSubscription(
            id: "messy-2", provider: "deepseek", kind: .topup,
            amountMinor: 0, currency: "USD", interval: .month, intervalCount: 1, startDate: nil,
            topUps: [
                .init(id: "c", date: "2026-09-01", amountMinor: 250),
                .init(id: "e", date: "2026-09-01", amountMinor: 1),
                .init(id: "a", date: "2026-08-01", amountMinor: 100),
                // The desktop generates a random id; the Kit uses the entry's index.
                .init(id: "top_3", date: "2026-08-01", amountMinor: 7)
            ],
            autoRenew: false
        ))
        XCTAssertEqual(records["messy-6"], HubSubscription(
            id: "messy-6", provider: "kimi", amountMinor: 12, currency: "CNY", interval: .month, intervalCount: 1,
            startDate: "2026-03-15", autoRenew: true
        ))
        XCTAssertEqual(records["messy-7"], HubSubscription(
            id: "messy-7", provider: "zai", amountMinor: 31, currency: "TWD", intervalCount: 10,
            startDate: "2026-02-28", nextRenewalOverride: "2026-03-31"
        ))
        XCTAssertEqual(records["messy-8"], HubSubscription(
            id: "messy-8", provider: "zai", amountMinor: 1, currency: "USD", intervalCount: 3, startDate: "2026-02-28"
        ))
        XCTAssertEqual(records["messy-9"], HubSubscription(
            id: "messy-9", provider: "zai", amountMinor: 125, currency: "USD", intervalCount: 1, startDate: "2026-02-28"
        ))
        XCTAssertEqual(records["messy-10"], HubSubscription(
            id: "messy-10", provider: "zai", amountMinor: 0, currency: "CNY", intervalCount: 1, startDate: "2026-02-28"
        ))
    }

    func testRecordsWithoutAnIDGetTheirIndex() throws {
        let body = #"{"updatedAt":"x","subscriptions":[{"provider":"claude","startDate":"2026-01-01"},{"provider":"codex","startDate":"2026-01-01"}]}"#
        let document = try SubscriptionDocument.decode(from: Data(body.utf8))
        XCTAssertEqual(document.subscriptions.map(\.id), ["sub_0", "sub_1"])

        // A record decoded on its own inside an array takes the same index.
        let list = try JSONDecoder().decode([HubSubscription].self, from: Data(#"[{"provider":"claude","startDate":"2026-01-01"}]"#.utf8))
        XCTAssertEqual(list.map(\.id), ["sub_0"])
    }

    func testMalformedBodies() throws {
        XCTAssertThrowsError(try SubscriptionDocument.decode(from: Data("<html>portal</html>".utf8))) { error in
            guard case HubClientError.decoding = error else { return XCTFail("unexpected \(error)") }
        }
        XCTAssertThrowsError(try SubscriptionDocument.decode(from: Data("[]".utf8)))
        let bare = try SubscriptionDocument.decode(from: Data(#"{"ok":true}"#.utf8))
        XCTAssertEqual(bare, .empty)
        let odd = try SubscriptionDocument.decode(from: Data(#"{"updatedAt":null,"subscriptions":{"a":1}}"#.utf8))
        XCTAssertEqual(odd.updatedAt, "")
        XCTAssertEqual(odd.subscriptions, [])
    }

    func testEncodingRoundTripsWithoutTheAccountKey() throws {
        let document = try SubscriptionDocument.decode(from: SubscriptionFixtures.data("subscriptions.json"))
        let encoded = try JSONEncoder().encode(document)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("accountKey"))
        XCTAssertEqual(try SubscriptionDocument.decode(from: encoded), document)
        let record = try XCTUnwrap(document.subscriptions.first)
        XCTAssertEqual(try JSONDecoder().decode(HubSubscription.self, from: JSONEncoder().encode(record)), record)
    }

    func testHubClientFetchesTheList() async throws {
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = HubClient(connection: try HubConnection(userInput: "http://hub.test:17321", secret: "s3cret"), session: session)

        StubURLProtocol.stub(path: "/api/subscriptions", status: 200, body: try SubscriptionFixtures.data("subscriptions.json"))
        let document = try await client.subscriptions()
        XCTAssertEqual(document.subscriptions.count, 7)
        let request = try XCTUnwrap(StubURLProtocol.recordedRequests.last)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/subscriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret")

        StubURLProtocol.stub(path: "/api/subscriptions", status: 404, body: Data(#"{"error":"not_found"}"#.utf8))
        do {
            _ = try await client.subscriptions()
            XCTFail("expected a 404")
        } catch {
            XCTAssertEqual(error as? HubClientError, .http(status: 404))
        }
        StubURLProtocol.reset()
    }

    // MARK: Golden parity

    func testGoldenPerRecordAtEveryDate() throws {
        let golden = try SubscriptionFixtures.golden()
        let document = try SubscriptionDocument.decode(from: SubscriptionFixtures.data("subscriptions.json"))
        let stats = try HubStats.decode(from: SubscriptionFixtures.data("stats.json"))
        let rates = golden.rates
        XCTAssertEqual(golden.updatedAt, document.updatedAt)
        XCTAssertEqual(golden.subscriptions.map(\.id), document.subscriptions.map(\.id))

        for (expected, record) in zip(golden.subscriptions, document.subscriptions) {
            let label = expected.id
            XCTAssertEqual(record.provider, expected.provider, label)
            XCTAssertEqual(record.kind.rawValue, expected.kind, label)
            XCTAssertEqual(record.isTopUp, expected.isTopUp, label)
            XCTAssertEqual(SubscriptionMath.intervalMonths(record), expected.intervalMonths, label)
            XCTAssertEqual(SubscriptionMath.amountUnits(record), expected.amountUnits, label)
            XCTAssertEqual(SubscriptionMath.amountUsd(record, rates: rates), expected.amountUsd, label)
            for (code, minor) in expected.convertMinor {
                XCTAssertEqual(SubscriptionMath.convertMinor(record.amountMinor, from: record.currency, to: code, rates: rates), minor, "\(label) → \(code)")
            }
            XCTAssertEqual(SubscriptionMath.coverageStopDate(record), expected.coverageStopDate.nilIfEmpty, label)
            XCTAssertEqual(SubscriptionMath.topUpEntries(record), expected.topUpEntries.map(\.topUp), label)
            XCTAssertEqual(SubscriptionMath.lastTopUp(record), expected.lastTopUp?.topUp, label)
            XCTAssertEqual(SubscriptionMath.firstTopUpDate(record), expected.firstTopUpDate.nilIfEmpty, label)
            XCTAssertEqual(SubscriptionMath.topUpTotalMinor(record), expected.topUpTotalMinor, label)

            // The golden matched with the full desktop ladder; every binding in
            // the fixture leaves `accountKey` empty, so the Kit's ladder agrees.
            let account = SubscriptionMath.matchBalanceAccount(record, providers: stats.limits)
            if let expectedAccount = expected.matchedAccount {
                let match = try XCTUnwrap(account, label)
                XCTAssertEqual(match.id, try SubscriptionFixtures.limitProviderID(accountKey: expectedAccount.accountKey), label)
                XCTAssertEqual(match.provider, expectedAccount.provider, label)
                XCTAssertEqual(match.accountEmail ?? "", expectedAccount.accountEmail ?? "", label)
                XCTAssertEqual(match.accountName ?? "", expectedAccount.accountName ?? "", label)
            } else {
                XCTAssertNil(account, label)
            }
            let balance = account.flatMap { SubscriptionMath.topUpBalance(of: $0, for: record) }
            XCTAssertEqual(balance?.amount, expected.balance?.amount, label)
            XCTAssertEqual(balance?.currency, expected.balance?.currency, label)

            for today in golden.todays {
                let day = try XCTUnwrap(expected.byDay[today])
                let where_ = "\(label) @ \(today)"
                XCTAssertEqual(SubscriptionMath.scheduledRenewalDate(record, today: today), day.scheduledRenewalDate.nilIfEmpty, where_)
                XCTAssertEqual(SubscriptionMath.nextRenewalDate(record, today: today), day.nextRenewalDate.nilIfEmpty, where_)
                XCTAssertEqual(SubscriptionMath.coverageEndDate(record, today: today), day.coverageEndDate.nilIfEmpty, where_)
                XCTAssertEqual(SubscriptionMath.daysUntilRenewal(record, today: today), day.daysUntilRenewal, where_)
                XCTAssertEqual(SubscriptionMath.elapsedPeriods(record, today: today), day.elapsedPeriods, where_)
                XCTAssertEqual(SubscriptionMath.paidToDateMinor(record, today: today), day.paidToDateMinor, where_)
                XCTAssertEqual(SubscriptionMath.subscribedMonths(record, today: today), day.subscribedMonths, where_)
                XCTAssertEqual(SubscriptionMath.monthlyAmountUsd(record, rates: rates, today: today), day.monthlyAmountUsd, where_)
                XCTAssertEqual(SubscriptionMath.topUpMonthMinor(record, today: today), day.topUpMonthMinor, where_)

                let projection = record.isTopUp
                    ? SubscriptionMath.topUpProjection(record, providers: stats.limits, today: today, rates: rates)
                    : nil
                XCTAssertEqual(projection, day.topUpProjection?.projection, where_)
                if let balance, record.isTopUp {
                    XCTAssertEqual(
                        SubscriptionMath.topUpProjection(record, balance: balance.amount, balanceCurrency: balance.currency, today: today, rates: rates),
                        projection,
                        where_
                    )
                }
            }
        }
    }

    func testGoldenTotalsAtEveryDate() throws {
        let golden = try SubscriptionFixtures.golden()
        let subscriptions = try SubscriptionDocument.decode(from: SubscriptionFixtures.data("subscriptions.json")).subscriptions
        for today in golden.todays {
            let expected = try XCTUnwrap(golden.totals[today])
            XCTAssertEqual(SubscriptionMath.activeSubscriptions(subscriptions, today: today).map(\.id), expected.activeSubscriptionIds, today)
            XCTAssertEqual(SubscriptionMath.monthlyTotalUsd(subscriptions, rates: golden.rates, today: today), expected.monthlyTotalUsd, today)
            for (provider, rollup) in expected.providerRollup {
                let actual = SubscriptionMath.providerRollup(subscriptions, provider: provider, rates: golden.rates, today: today)
                XCTAssertEqual(actual, SubscriptionMath.ProviderRollup(count: rollup.count, monthlyUsd: rollup.monthlyUsd), "\(provider) @ \(today)")
            }
        }
    }

    func testGoldenAnchoredMonthsAndDayCounts() throws {
        let golden = try SubscriptionFixtures.golden()
        let anchor = SubscriptionMath.Day(year: 2026, month: 1, day: 31)
        let anchored = (0...13).map { SubscriptionMath.formatDate(SubscriptionMath.addMonthsAnchored(anchor, $0)) }
        XCTAssertEqual(anchored, golden.addMonthsAnchoredJan31)
        for vector in golden.daysBetween {
            XCTAssertEqual(SubscriptionMath.daysBetween(vector.from, vector.to), vector.days, "\(vector.from) → \(vector.to)")
        }
    }

    // MARK: Renewal schedule

    func testJanuary31AnchorKeepsItsDay() {
        let plan = HubSubscription(id: "jan31", provider: "claude", amountMinor: 10_000, startDate: "2026-01-31")
        let renewals = ["2026-01-31": "2026-01-31", "2026-02-01": "2026-02-28", "2026-02-28": "2026-02-28",
                        "2026-03-01": "2026-03-31", "2026-04-01": "2026-04-30", "2026-05-01": "2026-05-31",
                        "2027-02-01": "2027-02-28", "2028-02-01": "2028-02-29", "2025-12-01": "2026-01-31"]
        for (today, expected) in renewals {
            XCTAssertEqual(SubscriptionMath.scheduledRenewalDate(plan, today: today), expected, today)
        }
        // Charged on 1/31, 2/28 and 3/31 by April 1st; nothing before the start.
        XCTAssertEqual(SubscriptionMath.elapsedPeriods(plan, today: "2026-04-01"), 3)
        XCTAssertEqual(SubscriptionMath.paidToDateMinor(plan, today: "2026-04-01"), 30_000)
        XCTAssertEqual(SubscriptionMath.elapsedPeriods(plan, today: "2026-01-30"), 0)
        XCTAssertEqual(SubscriptionMath.subscribedMonths(plan, today: "2026-02-28"), 0)
        XCTAssertEqual(SubscriptionMath.subscribedMonths(plan, today: "2026-03-31"), 2)
    }

    func testOverridesAndCoverageBoundaries() {
        var plan = HubSubscription(id: "o", provider: "codex", amountMinor: 2000, startDate: "2026-01-15", nextRenewalOverride: "2026-02-20")
        XCTAssertEqual(SubscriptionMath.scheduledRenewalDate(plan, today: "2026-02-01"), "2026-02-20")
        // A past override is ignored rather than rolled forward.
        XCTAssertEqual(SubscriptionMath.scheduledRenewalDate(plan, today: "2026-02-21"), "2026-03-15")

        plan.autoRenew = false
        XCTAssertNil(SubscriptionMath.nextRenewalDate(plan, today: "2026-02-01"))
        XCTAssertEqual(SubscriptionMath.coverageStopDate(plan), "2026-02-15")
        XCTAssertEqual(SubscriptionMath.coverageEndDate(plan, today: "2026-06-01"), "2026-02-15")
        XCTAssertEqual(SubscriptionMath.daysUntilRenewal(plan, today: "2026-02-20"), -5)
        XCTAssertEqual(SubscriptionMath.elapsedPeriods(plan, today: "2026-06-01"), 1)

        plan.endDate = "2026-04-15"
        XCTAssertEqual(SubscriptionMath.coverageStopDate(plan), "2026-04-15")
        // The renewal falling on the stop date is the one that was cancelled.
        XCTAssertEqual(SubscriptionMath.elapsedPeriods(plan, today: "2026-12-01"), 3)

        let ledger = HubSubscription(id: "l", provider: "openrouter", kind: .topup, startDate: "2026-01-01",
                                     topUps: [.init(id: "t", date: "2026-02-01", amountMinor: 500)])
        XCTAssertNil(SubscriptionMath.scheduledRenewalDate(ledger, today: "2026-03-01"))
        XCTAssertNil(SubscriptionMath.coverageEndDate(ledger, today: "2026-03-01"))
        XCTAssertNil(SubscriptionMath.daysUntilRenewal(ledger, today: "2026-03-01"))
        XCTAssertEqual(SubscriptionMath.elapsedPeriods(ledger, today: "2026-03-01"), 0)
    }

    // MARK: Totals

    func testLapsedPlansAreExcludedFromTheMonthlyTotal() throws {
        let golden = try SubscriptionFixtures.golden()
        let subscriptions = try SubscriptionDocument.decode(from: SubscriptionFixtures.data("subscriptions.json")).subscriptions
        let rates = golden.rates
        let byID = Dictionary(uniqueKeysWithValues: subscriptions.map { ($0.id, $0) })
        let kimi = try XCTUnwrap(byID["sub-kimi-lapsed"])
        let cursor = try XCTUnwrap(byID["sub-cursor-ending"])

        // Kimi stopped renewing after one month: lapsed on 2026-06-01.
        XCTAssertEqual(SubscriptionMath.coverageStopDate(kimi), "2026-06-01")
        let active = SubscriptionMath.activeSubscriptions(subscriptions, today: "2026-10-10")
        XCTAssertFalse(active.contains { $0.id == kimi.id })
        XCTAssertTrue(active.contains { $0.id == cursor.id })
        // Cursor stops on 2026-11-05, so that day it no longer counts.
        XCTAssertFalse(SubscriptionMath.activeSubscriptions(subscriptions, today: "2026-11-05").contains { $0.id == cursor.id })

        let total = SubscriptionMath.monthlyTotalUsd(subscriptions, rates: rates, today: "2026-10-10")
        let withoutKimi = subscriptions.filter { $0.id != kimi.id }
        XCTAssertEqual(total, SubscriptionMath.monthlyTotalUsd(withoutKimi, rates: rates, today: "2026-10-10"))
        XCTAssertGreaterThan(SubscriptionMath.monthlyAmountUsd(kimi, rates: rates, today: "2026-10-10"), 0)

        // A yearly plan counts a twelfth; a quarterly one a third.
        let codex = try XCTUnwrap(byID["sub-codex-yearly"])
        XCTAssertEqual(SubscriptionMath.monthlyAmountUsd(codex, rates: rates, today: "2026-10-10"), 200.0 / 12)
        let zai = try XCTUnwrap(byID["sub-zai-quarterly"])
        XCTAssertEqual(SubscriptionMath.monthlyAmountUsd(zai, rates: rates, today: "2026-10-10"), SubscriptionMath.amountUsd(zai, rates: rates) / 3)
        // A ledger counts only this month's top-ups.
        let openrouter = try XCTUnwrap(byID["topup-openrouter-hkd"])
        XCTAssertEqual(SubscriptionMath.topUpMonthMinor(openrouter, today: "2026-10-10"), 3900)
        XCTAssertEqual(SubscriptionMath.topUpMonthMinor(openrouter, today: "2026-09-30"), 3900)
        XCTAssertEqual(SubscriptionMath.topUpMonthMinor(openrouter, today: "2026-08-01"), 7800)
    }

    func testMissingRatesFallBackToTheFloors() {
        let plan = HubSubscription(id: "t", provider: "zai", amountMinor: 31_500, currency: "TWD", startDate: "2026-01-01")
        XCTAssertEqual(SubscriptionMath.amountUsd(plan, rates: [:]), 10)
        XCTAssertEqual(SubscriptionMath.amountUsd(plan, rates: ["TWD": 0]), 10)
        XCTAssertEqual(SubscriptionMath.amountUsd(plan, rates: ["TWD": .nan]), 10)
        XCTAssertEqual(SubscriptionMath.convertMinor(1000, from: "USD", to: "CNY", rates: [:]), 6800)
        XCTAssertEqual(SubscriptionMath.convertMinor(1000, from: "EUR", to: "hkd", rates: [:]), 7800)
    }

    // MARK: Top-up projection

    func testTopUpProjectionVectors() {
        // `topUpProjection(ledger, balance, today, {currencyApi, balanceCurrency})`
        // after `configureRates({USD: 1, TWD: 30.4821, HKD: 7.8, CNY: 7.1234})`.
        let rates = ["USD": 1, "TWD": 30.4821, "HKD": 7.8, "CNY": 7.1234]
        let ledger = HubSubscription(id: "l", provider: "openrouter", kind: .topup, currency: "HKD", topUps: [
            .init(id: "x", date: "2026-10-01", amountMinor: 7800),
            .init(id: "y", date: "2026-09-01", amountMinor: 7800)
        ])
        func projection(_ record: HubSubscription, _ balance: Double, _ today: String, _ currency: String?) -> TopUpProjection? {
            SubscriptionMath.topUpProjection(record, balance: balance, balanceCurrency: currency, today: today, rates: rates)
        }
        XCTAssertEqual(projection(ledger, 25, "2026-10-10", "USD"), TopUpProjection(dailyBurn: 0, exhaustDate: nil, daysRemaining: nil))
        XCTAssertNil(projection(ledger, 5, "2026-09-01", "USD"))
        XCTAssertNil(projection(ledger, 5, "2026-08-01", "USD"))
        XCTAssertEqual(projection(ledger, -2, "2026-10-10", "USD"), TopUpProjection(dailyBurn: 0.5641025641025641, exhaustDate: "2026-10-06", daysRemaining: -4))
        XCTAssertEqual(projection(ledger, 50, "2026-10-10", "HKD"), TopUpProjection(dailyBurn: 2.717948717948718, exhaustDate: "2026-10-28", daysRemaining: 18))
        XCTAssertEqual(projection(ledger, 50, "2026-10-10", "CNY"), TopUpProjection(dailyBurn: 2.371025641025641, exhaustDate: "2026-10-31", daysRemaining: 21))
        XCTAssertEqual(projection(ledger, 100, "2026-10-10", nil), TopUpProjection(dailyBurn: 1.435897435897436, exhaustDate: "2026-12-18", daysRemaining: 69))
        XCTAssertEqual(projection(ledger, 100, "2026-10-10", ""), projection(ledger, 100, "2026-10-10", nil))

        var empty = ledger
        empty.topUps = []
        XCTAssertNil(projection(empty, 5, "2026-10-10", "USD"))
        var zero = ledger
        zero.topUps = [.init(id: "z", date: "2026-01-01", amountMinor: 0)]
        XCTAssertNil(projection(zero, 5, "2026-10-10", "USD"))
        var tiny = ledger
        tiny.currency = "USD"
        tiny.topUps = [.init(id: "z", date: "2026-01-01", amountMinor: 100_000)]
        XCTAssertEqual(projection(tiny, 999.99, "2026-10-10", "USD"),
                       TopUpProjection(dailyBurn: 0.00003546099290776917, exhaustDate: "79234-12-24", daysRemaining: 28_199_718))
        XCTAssertNil(projection(ledger, 5, "soon", "USD"))
        XCTAssertNil(projection(ledger, .nan, "2026-10-10", "USD"))

        // Beyond `Date.UTC`'s range the desktop shows no date; so does the Kit.
        tiny.topUps = [.init(id: "z", date: "2026-01-01", amountMinor: 1_000_000_000)]
        let far = projection(tiny, 9_999_999.99, "2026-10-10", "USD")
        XCTAssertNotNil(far?.daysRemaining)
        XCTAssertNil(far?.exhaustDate)
    }

    // MARK: Accounts

    func testMatchBalanceAccountLadder() {
        func account(_ id: String, _ provider: String = "openrouter", email: String? = nil, name: String? = nil) -> LimitProvider {
            LimitProvider(id: id, provider: provider, accountEmail: email, accountName: name)
        }
        var record = HubSubscription(id: "r", provider: " OpenRouter ", kind: .topup,
                                     topUps: [.init(id: "t", date: "2026-01-01", amountMinor: 100)])
        let other = account("other", "claude", email: "dev@example.com")

        XCTAssertNil(SubscriptionMath.matchBalanceAccount(record, providers: []))
        XCTAssertNil(SubscriptionMath.matchBalanceAccount(record, providers: [other]))
        // The sole account of the provider, whatever the binding says.
        XCTAssertEqual(SubscriptionMath.matchBalanceAccount(record, providers: [other, account("solo")])?.id, "solo")
        record.bindingEmail = "nobody@example.com"
        XCTAssertEqual(SubscriptionMath.matchBalanceAccount(record, providers: [account("solo")])?.id, "solo")

        let work = account("work", email: "Work@Example.com ", name: "team")
        let home = account("home", email: "home@example.com", name: "team")
        let personal = account("personal", name: "me")
        // Several accounts and nothing matching: ambiguous.
        XCTAssertNil(SubscriptionMath.matchBalanceAccount(record, providers: [work, home, personal]))
        // The email wins, case- and whitespace-insensitively.
        record.bindingEmail = "work@example.com"
        XCTAssertEqual(SubscriptionMath.matchBalanceAccount(record, providers: [home, work, personal])?.id, "work")
        // A profile name only when it names exactly one account.
        record.bindingEmail = nil
        record.bindingProfileName = "me"
        XCTAssertEqual(SubscriptionMath.matchBalanceAccount(record, providers: [work, home, personal])?.id, "personal")
        record.bindingProfileName = "team"
        XCTAssertNil(SubscriptionMath.matchBalanceAccount(record, providers: [work, home, personal]))
    }

    func testTopUpBalanceAndBalanceOnlyAccounts() {
        let record = HubSubscription(id: "r", provider: "deepseek", kind: .topup, currency: "HKD",
                                     topUps: [.init(id: "t", date: "2026-01-01", amountMinor: 100)])
        let credits = LimitWindow(id: "c", kind: .billing, metric: .credits, remaining: 12.5, currency: "CNY")
        let spend = LimitWindow(id: "s", kind: .billing, metric: .spend, used: 3, currency: "USD")
        let session = LimitWindow(id: "p", kind: .session, usedPercent: 40)

        let windowed = LimitProvider(id: "a", provider: "deepseek", windows: [spend, credits], balance: LimitBalance(amount: 99, currency: "USD"))
        XCTAssertEqual(SubscriptionMath.topUpBalance(of: windowed, for: record), .init(amount: 12.5, currency: "CNY"))
        let balanceOnly = LimitProvider(id: "b", provider: "deepseek", balance: LimitBalance(amount: 7, currency: nil))
        XCTAssertEqual(SubscriptionMath.topUpBalance(of: balanceOnly, for: record), .init(amount: 7, currency: "HKD"))
        XCTAssertNil(SubscriptionMath.topUpBalance(of: LimitProvider(id: "c", provider: "deepseek", windows: [session]), for: record))

        XCTAssertTrue(SubscriptionMath.isBalanceOnlyAccount(LimitProvider(id: "d", provider: "deepseek", windows: [credits, spend])))
        XCTAssertFalse(SubscriptionMath.isBalanceOnlyAccount(LimitProvider(id: "e", provider: "claude", windows: [session, credits])))
        XCTAssertFalse(SubscriptionMath.isBalanceOnlyAccount(LimitProvider(id: "f", provider: "claude", windows: [spend])))
    }

    // MARK: Text helpers

    func testElapsedAndMoneyMatchSubscriptionText() {
        // `subscriptionText.elapsedText()` / `amountText()` / `topUpMinorText()`.
        func plan(_ start: String, _ minor: Int, _ currency: String, _ interval: HubSubscription.Interval = .month,
                  count: Int = 1, autoRenew: Bool = true, end: String? = nil) -> HubSubscription {
            HubSubscription(id: start, provider: "x", amountMinor: minor, currency: currency, interval: interval,
                            intervalCount: count, startDate: start, autoRenew: autoRenew, endDate: end)
        }
        let cases: [(HubSubscription, String, [SubscriptionMath.Elapsed], [Int])] = [
            (plan("2026-01-31", 10_000, "USD"), "$100.00", [.months(8), .months(9), .months(12)], [90_000, 100_000, 140_000]),
            (plan("2026-09-25", 2000, "HKD"), "HK$20.00", [.days(15), .months(1), .months(5)], [2000, 4000, 12_000]),
            (plan("2026-11-01", 2000, "TWD"), "NT$20.00", [.notStarted, .days(4), .months(3)], [0, 2000, 8000]),
            (plan("2026-05-01", 9900, "CNY", autoRenew: false), "¥99.00", [.months(1), .months(1), .months(1)], [9900, 9900, 9900]),
            (plan("2026-09-20", 9900, "CNY", autoRenew: false, end: "2026-10-01"), "¥99.00", [.days(11), .days(11), .days(11)], [9900, 9900, 9900]),
            (plan("2026-10-10", 1, "USD", .year, count: 2), "$0.01", [.days(0), .days(26), .months(4)], [1, 1, 1])
        ]
        for (record, amount, elapsed, paid) in cases {
            XCTAssertEqual(SubscriptionMath.amountText(record), amount)
            for (index, today) in ["2026-10-10", "2026-11-05", "2027-02-28"].enumerated() {
                XCTAssertEqual(SubscriptionMath.elapsed(record, today: today), elapsed[index], "\(record.id) @ \(today)")
                XCTAssertEqual(SubscriptionMath.paidToDateMinor(record, today: today), paid[index], "\(record.id) @ \(today)")
            }
        }
        let money: [(Int, String, String)] = [
            (0, "USD", "$0.00"), (3900, "HKD", "HK$39.00"), (12_345, "TWD", "NT$123.45"), (5, "CNY", "¥0.05"),
            (-250, "USD", "$-2.50"), (100, "EUR", "$1.00"), (1999, " hkd ", "HK$19.99")
        ]
        for (minor, currency, text) in money {
            XCTAssertEqual(SubscriptionMath.moneyText(minor: minor, currency: currency), text)
        }
    }

    // MARK: Calendar days

    func testCalendarDayHelpers() throws {
        let instant = try XCTUnwrap(ISODate.parse("2026-10-10T23:30:00Z"))
        XCTAssertEqual(SubscriptionMath.todayString(now: instant, timeZone: TimeZone(identifier: "UTC")!), "2026-10-10")
        XCTAssertEqual(SubscriptionMath.todayString(now: instant, timeZone: TimeZone(identifier: "Asia/Tokyo")!), "2026-10-11")
        XCTAssertEqual(SubscriptionMath.todayString(now: instant, timeZone: TimeZone(identifier: "America/Los_Angeles")!), "2026-10-10")

        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let midnight = try XCTUnwrap(SubscriptionMath.localDate("2026-02-28", timeZone: tokyo))
        XCTAssertEqual(SubscriptionMath.todayString(now: midnight, timeZone: tokyo), "2026-02-28")
        XCTAssertEqual(SubscriptionMath.todayString(now: midnight.addingTimeInterval(-1), timeZone: tokyo), "2026-02-27")
        XCTAssertNil(SubscriptionMath.localDate("2026-02-29"))

        XCTAssertTrue(SubscriptionMath.isDateString(" 2026-13-45 "))
        XCTAssertFalse(SubscriptionMath.isDateString("2026-1-05"))
        XCTAssertFalse(SubscriptionMath.isDateString("２０２６-01-05"))
        XCTAssertNil(SubscriptionMath.normalizedDate("2026-13-45"))
        XCTAssertEqual(SubscriptionMath.normalizedDate("\u{FEFF}2028-02-29\n"), "2028-02-29")
        XCTAssertNil(SubscriptionMath.normalizedDate("2027-02-29"))
        // `Date.UTC` reads years 0–99 as 1900–1999, so 0000 is not a leap year.
        XCTAssertNil(SubscriptionMath.normalizedDate("0000-02-29"))
        XCTAssertEqual(SubscriptionMath.normalizedDate("0400-02-29"), "0400-02-29")
    }
}

// MARK: - Fixtures

private enum SubscriptionFixtures {
    static func data(_ name: String, subdirectory: String = "Fixtures/v2") throws -> Data {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let url = Bundle.module.url(forResource: parts[0], withExtension: parts.count > 1 ? parts[1] : nil, subdirectory: subdirectory) else {
            throw NSError(domain: "SubscriptionFixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing fixture \(subdirectory)/\(name)"])
        }
        return try Data(contentsOf: url)
    }

    static func golden() throws -> SubscriptionsGolden {
        try JSONDecoder().decode(SubscriptionsGolden.self, from: data("subscriptions.json", subdirectory: "Fixtures/v2/golden"))
    }

    /// The id the Kit derives for the stats row carrying `accountKey`.
    static func limitProviderID(accountKey: String?) throws -> String {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data("stats.json")) as? [String: Any])
        let limits = try XCTUnwrap(root["limits"] as? [String: Any])
        let rows = try XCTUnwrap(limits["providers"] as? [[String: Any]])
        let row = try XCTUnwrap(rows.first { ($0["accountKey"] as? String) == accountKey })
        return try JSONDecoder().decode(LimitProvider.self, from: JSONSerialization.data(withJSONObject: row)).id
    }

    /// Exercises every coercion `normalizeSubscription()` applies.
    static let messyDocument = #"""
    {"ok":true,"version":1,"updatedAt":" 2026-10-10T16:29:45.000Z ","subscriptions":[{"id":" messy-1 ","provider":" Claude ","kind":"SUBSCRIPTION","binding":{"profileName":" Work ","accountKey":"k","accountEmail":" Dev@Example.COM "},"planName":" Max ","amountMinor":"1999.5","currency":" hkd ","interval":"YEAR","intervalCount":"30","startDate":" 2026-01-31 ","topUps":"nope","autoRenew":0,"nextRenewalOverride":"2026-02-30","endDate":20261231,"note":7,"updatedAt":"2026-01-31T00:00:00.000Z"},{"id":"messy-2","provider":"deepseek","kind":"TopUp","binding":"x","amountMinor":-5,"currency":"jpy","interval":"week","intervalCount":0,"startDate":null,"topUps":[{"id":"a","date":"2026-08-01","amountMinor":100},{"id":"b","date":"bad","amountMinor":5},{"id":" c ","date":"2026-09-01","amountMinor":250.4},{"date":"2026-08-01","amountMinor":"7"},"junk",{"id":"e","date":"2026-09-01","amountMinor":true}],"autoRenew":false},{"id":"messy-3","provider":"","startDate":"2026-01-01"},{"id":"messy-4","provider":"codex","kind":"subscription","startDate":"2026-13-01"},{"id":"messy-5","provider":"codex","kind":"topup","topUps":[]},{"id":"messy-1","provider":"cursor","startDate":"2026-01-01"},["array"],null,{"id":"messy-6","provider":["Kimi"],"startDate":["2026-03-15"],"amountMinor":[" 12 "],"intervalCount":"  ","currency":["cny"],"interval":null,"autoRenew":"false"},{"id":"messy-7","provider":"zai","startDate":"2026-02-28","amountMinor":"0x1F","intervalCount":"1e1","currency":"TWD","autoRenew":null,"nextRenewalOverride":" 2026-03-31 ","endDate":""},{"id":"messy-8","provider":"zai","startDate":"2026-02-28","amountMinor":"1.","intervalCount":2.5,"currency":"usd"},{"id":"messy-9","provider":"zai","startDate":"2026-02-28","amountMinor":"+12.5e1","intervalCount":-3,"currency":null},{"id":"messy-10","provider":"zai","startDate":" 2026-02-28﻿","amountMinor":"Infinity","intervalCount":"abc","currency":"CNY"}]}
    """#
}

/// The shape of `Fixtures/v2/golden/subscriptions.json`.
private struct SubscriptionsGolden: Decodable {
    struct Entry: Decodable {
        let id: String
        let date: String
        let amountMinor: Int
        var topUp: HubSubscription.TopUp { .init(id: id, date: date, amountMinor: amountMinor) }
    }

    struct Account: Decodable {
        let provider: String
        let accountKey: String?
        let accountEmail: String?
        let accountName: String?
    }

    struct Balance: Decodable {
        let amount: Double
        let currency: String
    }

    struct Projection: Decodable {
        let dailyBurn: Double
        let exhaustDate: String
        let daysRemaining: Int?
        var projection: TopUpProjection {
            TopUpProjection(dailyBurn: dailyBurn, exhaustDate: exhaustDate.nilIfEmpty, daysRemaining: daysRemaining)
        }
    }

    struct Day: Decodable {
        let scheduledRenewalDate: String
        let nextRenewalDate: String
        let coverageEndDate: String
        let daysUntilRenewal: Int?
        let elapsedPeriods: Int
        let paidToDateMinor: Int
        let subscribedMonths: Int
        let monthlyAmountUsd: Double
        let topUpMonthMinor: Int
        let topUpProjection: Projection?
    }

    struct Record: Decodable {
        let id: String
        let provider: String
        let kind: String
        let isTopUp: Bool
        let intervalMonths: Int
        let amountUnits: Double
        let amountUsd: Double
        let convertMinor: [String: Int]
        let coverageStopDate: String
        let topUpEntries: [Entry]
        let lastTopUp: Entry?
        let firstTopUpDate: String
        let topUpTotalMinor: Int
        let matchedAccount: Account?
        let balance: Balance?
        let byDay: [String: Day]
    }

    struct Rollup: Decodable {
        let count: Int
        let monthlyUsd: Double
    }

    struct Totals: Decodable {
        let activeSubscriptionIds: [String]
        let monthlyTotalUsd: Double
        let providerRollup: [String: Rollup]
    }

    struct DayCount: Decodable {
        let from: String
        let to: String
        let days: Int?
    }

    let rates: [String: Double]
    let todays: [String]
    let updatedAt: String
    let subscriptions: [Record]
    let totals: [String: Totals]
    let addMonthsAnchoredJan31: [String]
    let daysBetween: [DayCount]
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

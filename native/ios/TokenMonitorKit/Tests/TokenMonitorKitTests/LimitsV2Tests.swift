import Foundation
import XCTest
@testable import TokenMonitorKit

/// The round-2 limits extras (`limits/core.js` normalization) and the
/// `usageItems.js` port, against the v2 Hub capture and its desktop goldens.
final class LimitsV2Tests: XCTestCase {
    // MARK: Fixtures

    private static func v2Data(_ name: String, golden: Bool = false) throws -> Data {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let url = Bundle.module.url(
            forResource: parts[0],
            withExtension: parts.count > 1 ? parts[1] : nil,
            subdirectory: golden ? "Fixtures/v2/golden" : "Fixtures/v2"
        ) else {
            throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing v2 fixture \(name)"])
        }
        return try Data(contentsOf: url)
    }

    private static func golden() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: v2Data("usage-items.json", golden: true)) as? [String: Any])
    }

    private func limits() throws -> [LimitProvider] {
        try HubStats.decode(from: Self.v2Data("stats.json")).limits
    }

    private func provider(_ id: String, in providers: [LimitProvider]? = nil) throws -> LimitProvider {
        let rows = try providers ?? limits()
        return try XCTUnwrap(rows.first { $0.provider == id }, "no \(id) row")
    }

    /// The id the Kit derives from a wire `accountKey`.
    private func providerID(_ provider: String, accountKey: String) -> String {
        "\(provider)-\(StableHash.hex("\(provider)|key:\(accountKey)"))"
    }

    private static func hiddenValue(_ object: Any?) -> [String: [String]] {
        guard let object = object as? [String: Any] else { return [:] }
        // A non-array selection (`"kimi": "credits"`) reads as empty, as in
        // `hiddenItemList`.
        return object.mapValues { ($0 as? [Any])?.compactMap { $0 as? String } ?? [] }
    }

    private static func date(_ iso: String) -> Date { ISODate.parse(iso)! }

    // MARK: Extras decode

    func testProviderExtrasDecode() throws {
        let rows = try limits()
        XCTAssertEqual(rows.count, 15)

        let claude = try provider("claude", in: rows)
        XCTAssertEqual(claude.sourceDeviceId, "studio-mac")
        XCTAssertEqual(claude.explicitPlanLabel, "Max")
        XCTAssertNil(claude.accountLabel)
        XCTAssertNil(claude.workspaceKind)
        XCTAssertNil(claude.sourceDetail)
        XCTAssertNil(claude.region)
        XCTAssertEqual(claude.source, "web")
        XCTAssertFalse(claude.isStale)
        let credits = try XCTUnwrap(claude.resetCredits)
        XCTAssertEqual(credits.availableCount, 2)
        XCTAssertEqual(credits.nextExpiresAt, Self.date("2026-10-13T16:30:00.000Z"))
        XCTAssertEqual(credits.expirations, [Self.date("2026-10-13T16:30:00.000Z"), Self.date("2026-10-27T16:30:00.000Z")])
        XCTAssertEqual(credits.grants, [
            LimitResetGrant(
                id: "grant-outage", label: "Outage credit", resetsLeft: 1, resetsTotal: 2,
                startsAt: Self.date("2026-10-08T16:30:00.000Z"), endsAt: Self.date("2026-10-13T16:30:00.000Z"),
                clears: ["session", "weekly"], usableNow: true, useRequiresLimit: true, paused: false
            ),
            LimitResetGrant(
                id: "grant-welcome", label: "Welcome back", resetsLeft: 1, resetsTotal: 1,
                endsAt: Self.date("2026-10-27T16:30:00.000Z"), clears: ["session"], usableNow: false, paused: true
            )
        ])
        XCTAssertNil(claude.usageSummary)
        XCTAssertNil(claude.balance)

        let codex = try provider("codex", in: rows)
        XCTAssertEqual(codex.sourceDetail, "app")
        XCTAssertEqual(codex.source, "rpc")
        XCTAssertEqual(codex.resetCredits?.availableCount, 3)
        XCTAssertEqual(codex.resetCredits?.expirations.count, 3)
        XCTAssertEqual(codex.resetCredits?.grants, [])
        XCTAssertEqual(codex.windows.map(\.limitId), ["codex", "codex", "codex_bengalfox", "codex_bengalfox", "codex_reserve"])
        XCTAssertEqual(codex.windows.map(\.isAdditional), [false, false, true, true, true])
        XCTAssertEqual(codex.windows.map(\.windowMinutes), [300, 10080, 300, 10080, nil])

        let antigravity = try provider("antigravity", in: rows)
        XCTAssertEqual(antigravity.status, .unauthorized)
        XCTAssertEqual(antigravity.actionRequired, "accountVerification")
        XCTAssertEqual(antigravity.windows, [])

        let workbuddy = try provider("workbuddy", in: rows)
        XCTAssertEqual(workbuddy.status, .notConfigured)
        XCTAssertEqual(workbuddy.actionRequired, "appSessionEncrypted")
        XCTAssertEqual(workbuddy.source, "local")

        let cursor = try provider("cursor", in: rows)
        XCTAssertEqual(cursor.status, .sourceRateLimited)
        XCTAssertEqual(cursor.sourceDeviceId, "tokyo-mac")
        XCTAssertEqual(cursor.windows.map(\.metric), [nil, .spend])

        let mimo = try provider("mimo", in: rows)
        XCTAssertEqual(mimo.status, .error)
        XCTAssertEqual(mimo.explicitPlanLabel, "Lite")
        XCTAssertEqual(mimo.accountLabel, "MiMo Code")
        XCTAssertEqual(mimo.balance?.planStatus, .expired)
        XCTAssertEqual(mimo.balance?.planUsed, 100)
        XCTAssertEqual(mimo.balance?.planLimit, 100)
        XCTAssertEqual(mimo.balance?.planPercent, 100)

        let kimi = try provider("kimi", in: rows)
        XCTAssertTrue(kimi.isStale)
        XCTAssertEqual(kimi.sourceDeviceId, "old-laptop")
        XCTAssertEqual(kimi.accountLabel, "Kimi Code")

        let zai = try provider("zai", in: rows)
        XCTAssertEqual(zai.explicitPlanLabel, "GLM Coding Pro")
        XCTAssertEqual(zai.accountLabel, "Coding Plan")

        let zed = try provider("zed", in: rows)
        XCTAssertEqual(zed.windows[1].limitId, "zed.edit-predictions")
        XCTAssertEqual(zed.windows[1].detail, "unlimited")
        XCTAssertTrue(zed.windows[1].isUnlimited)
        XCTAssertFalse(zed.windows[1].showMeter)

        let copilot = try provider("copilot", in: rows)
        XCTAssertEqual(copilot.status, .unavailable)
        XCTAssertEqual(copilot.accountName, "octo-dev")

        let cline = try provider("cline", in: rows)
        XCTAssertEqual(cline.status, .unauthorized)
        XCTAssertEqual(cline.source, "api")

        let typesafe = try provider("typesafe", in: rows)
        XCTAssertEqual(typesafe.windows[0].boundaryKind, .expiry)
        XCTAssertFalse(typesafe.windows[0].showMeter)
    }

    func testBalanceExtrasDecode() throws {
        let rows = try limits()
        let openRouter = try XCTUnwrap(provider("openrouter", in: rows).balance)
        XCTAssertEqual(openRouter.amount, 13.8)
        XCTAssertEqual(openRouter.currency, "USD")
        XCTAssertEqual(openRouter.todaySpend, 0.4)
        XCTAssertEqual(openRouter.weekSpend, 2.1)
        XCTAssertEqual(openRouter.monthSpend, 6.2)
        XCTAssertEqual(openRouter.allTimeSpend, 18.75)
        XCTAssertEqual(openRouter.requestCount, 412)
        XCTAssertEqual(openRouter.trackingSince, Self.date("2026-08-11T16:30:00.000Z"))
        XCTAssertFalse(openRouter.monthSinceTracking)
        XCTAssertNil(openRouter.quotaGroup, "an empty group name is no group")
        XCTAssertTrue(openRouter.hasSpend)
        XCTAssertEqual(try provider("openrouter", in: rows).accountLabel, "API key")

        let deepSeekRow = try provider("deepseek", in: rows)
        XCTAssertEqual(deepSeekRow.status, .rateLimited)
        XCTAssertEqual(deepSeekRow.windows.count, 1, "a transient failure keeps the retained reading")
        let deepSeek = try XCTUnwrap(deepSeekRow.balance)
        XCTAssertEqual(deepSeek.currency, "CNY")
        XCTAssertNil(deepSeek.weekSpend)
        XCTAssertEqual(deepSeek.allTimeSpend, 140.1)
        XCTAssertTrue(deepSeek.monthSinceTracking)
        XCTAssertEqual(deepSeek.trackingSince, Self.date("2026-08-26T16:30:00.000Z"))
        XCTAssertEqual(deepSeek.giftBalance, 10)
        XCTAssertEqual(deepSeek.cashBalance, 76.42)
        XCTAssertNil(deepSeek.planStatus)

        let typesafe = try XCTUnwrap(provider("typesafe", in: rows).balance)
        XCTAssertEqual(typesafe.expiresAt, Self.date("2026-10-30T16:30:00.000Z"))
        XCTAssertEqual(typesafe.tranches, [
            LimitBalanceTranche(amount: 25, currency: "USD", expiresAt: Self.date("2026-10-30T16:30:00.000Z")),
            LimitBalanceTranche(amount: 12.5, currency: "USD", expiresAt: Self.date("2026-12-29T16:30:00.000Z")),
            LimitBalanceTranche(amount: 5, currency: "USD")
        ])

        let relay = try provider("thirdparty", in: rows)
        XCTAssertEqual(relay.adapterId, "newapi-account")
        XCTAssertEqual(relay.accountName, "relay-team")
        XCTAssertEqual(relay.accountLabel, "Relay")
        XCTAssertEqual(relay.usageSummary, LimitUsageSummary(
            period: .today, requests: 128, todayTokens: 2_400_000, weekTokens: 9_100_000,
            inputTokens: 310_000, outputTokens: 92000, cacheReadTokens: 1_950_000, cacheCreationTokens: 48000,
            totalTokens: 2_400_000, standardCost: 3.21, actualCost: 1.05, averageDurationMs: 2350
        ))
    }

    func testPlanLabelKeepsTheLegacyFallback() throws {
        let rows = try limits()
        XCTAssertEqual(try provider("claude", in: rows).planLabel, "Max")
        XCTAssertEqual(try provider("zai", in: rows).planLabel, "GLM Coding Pro", "the explicit plan wins")
        XCTAssertEqual(try provider("deepseek", in: rows).planLabel, "Pay-as-you-go", "legacy accountLabel")
        XCTAssertEqual(try provider("deepseek", in: rows).explicitPlanLabel, nil)
        XCTAssertNil(try provider("cline", in: rows).planLabel)

        var row = LimitProvider(id: "x", provider: "kimi", planLabel: "Plus", accountLabel: "Kimi Code")
        XCTAssertEqual(row.planLabel, "Plus")
        row.planLabel = nil
        XCTAssertNil(row.explicitPlanLabel)
        XCTAssertEqual(row.planLabel, "Kimi Code")
    }

    func testOwnEncodingRoundTripsEveryExtra() throws {
        let original = try limits()
        let decoded = try JSONDecoder().decode([LimitProvider].self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testRoundOneEncodingStillDecodes() throws {
        // What a round-1 app wrote into the App Group: the combined plan
        // under `planLabel`, none of the extras.
        let json = """
        {"id":"deepseek-abc","provider":"deepseek","displayName":"DeepSeek","planLabel":"Pay-as-you-go",
         "status":"ok","stale":true,"windows":[{"kind":"billing","metric":"credits","label":"Balance","remaining":5}],
         "balance":{"amount":5,"currency":"CNY","monthSpend":2}}
        """
        let row = try JSONDecoder().decode(LimitProvider.self, from: Data(json.utf8))
        XCTAssertEqual(row.planLabel, "Pay-as-you-go")
        XCTAssertNil(row.accountLabel)
        XCTAssertTrue(row.isStale)
        XCTAssertNil(row.resetCredits)
        XCTAssertNil(row.usageSummary)
        XCTAssertNil(row.sourceDeviceId)
        XCTAssertEqual(row.balance, LimitBalance(amount: 5, currency: "CNY", monthSpend: 2))

        // And a round-1 reader of a new encoding finds the plan where it looks.
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try provider("deepseek"))) as? [String: Any]
        XCTAssertNil(encoded?["planLabel"])
        XCTAssertEqual(encoded?["accountLabel"] as? String, "Pay-as-you-go")
    }

    func testWireNormalization() throws {
        let json = """
        {"provider":"thirdparty","adapter_id":"NewAPI","accountLabel":"Team","workspaceKind":"Personal",
         "source_detail":"CLI","region":"CN","sourceDeviceId":"box","status":"ok",
         "balance":{"amount":"12.5","currency":"usd","today_spend":1,"request_count":7.9,"quota_group":"vip",
           "tracking_since":1791936000,"month_since_tracking":true,"plan_status":"Bogus",
           "tranches":[{"amount":1,"expires_at":"2026-12-01T00:00:00Z"},{"currency":"usd"},{"amount":2},
                       {"amount":3,"currency":"cny","expiresAt":"2026-11-01T00:00:00Z"}]},
         "rate_limit_reset_credits":{"available":"2.9","next_expires_at":"2026-12-01T00:00:00Z",
           "expirations":["2026-11-20T00:00:00Z",{"status":"used","expiresAt":"2026-11-01T00:00:00Z"},
                          {"status":"Available","expires_at":"2026-11-25T00:00:00.000Z"},"2026-11-20T00:00:00.000Z",1795000000000,"bogus"],
           "grants":[{"id":"g","resets_left":-2,"resets_total":3.7,"clears":["session"," session ","","weekly"],"usable_now":"true"},"x"]},
         "usage_summary":{"period":"daily","requests":-4,"total_tokens":12.9,"standard_cost":-1,"average_duration_ms":"80"}}
        """
        let row = try JSONDecoder().decode(LimitProvider.self, from: Data(json.utf8))
        XCTAssertEqual(row.adapterId, "newapi")
        XCTAssertEqual(row.accountLabel, "Team")
        XCTAssertEqual(row.planLabel, "Team")
        XCTAssertNil(row.explicitPlanLabel)
        XCTAssertEqual(row.workspaceKind, "personal")
        XCTAssertEqual(row.sourceDetail, "cli")
        XCTAssertEqual(row.region, "cn")
        XCTAssertEqual(row.sourceDeviceId, "box")

        let balance = try XCTUnwrap(row.balance)
        XCTAssertEqual(balance.amount, 12.5)
        XCTAssertEqual(balance.currency, "USD")
        XCTAssertEqual(balance.todaySpend, 1)
        XCTAssertEqual(balance.requestCount, 7, "truncated")
        XCTAssertEqual(balance.quotaGroup, "vip")
        XCTAssertEqual(balance.trackingSince, Date(timeIntervalSince1970: 1_791_936_000))
        XCTAssertTrue(balance.monthSinceTracking)
        XCTAssertNil(balance.planStatus, "only active/expired")
        XCTAssertEqual(balance.tranches, [
            LimitBalanceTranche(amount: 3, currency: "CNY", expiresAt: Self.date("2026-11-01T00:00:00Z")),
            LimitBalanceTranche(amount: 1, expiresAt: Self.date("2026-12-01T00:00:00Z")),
            LimitBalanceTranche(amount: 2)
        ], "amount required; soonest expiry first; undated last")

        let credits = try XCTUnwrap(row.resetCredits)
        XCTAssertEqual(credits.availableCount, 2, "floored")
        XCTAssertEqual(credits.expirations, [
            Date(timeIntervalSince1970: 1_795_000_000),
            Self.date("2026-11-20T00:00:00Z"),
            Self.date("2026-11-25T00:00:00Z")
        ], "used credits dropped, duplicates merged, epoch milliseconds read, sorted")
        XCTAssertEqual(credits.nextExpiresAt, Date(timeIntervalSince1970: 1_795_000_000), "the sooner of the wire value and the first expiry")
        XCTAssertEqual(credits.grants, [LimitResetGrant(id: "g", resetsLeft: 0, resetsTotal: 3, clears: ["session", "weekly"], usableNow: true)])

        XCTAssertEqual(row.usageSummary, LimitUsageSummary(requests: 0, totalTokens: 12, standardCost: 0, averageDurationMs: 80))

        let empty = """
        {"provider":"codex","resetCredits":{"grants":[],"expirations":[]},"usageSummary":{"period":"","requests":null},
         "balance":{"tranches":[]}}
        """
        let bare = try JSONDecoder().decode(LimitProvider.self, from: Data(empty.utf8))
        XCTAssertNil(bare.resetCredits)
        XCTAssertNil(bare.usageSummary)
        XCTAssertNil(bare.balance)
    }

    func testResetDescriptionDecodes() throws {
        let window = try JSONDecoder().decode(LimitWindow.self, from: Data(#"{"kind":"weekly","resetDescription":"Resets Monday"}"#.utf8))
        XCTAssertEqual(window.resetDescription, "Resets Monday")
        XCTAssertEqual(try JSONDecoder().decode(LimitWindow.self, from: JSONEncoder().encode(window)), window)
        XCTAssertNil(try provider("claude").windows[0].resetDescription, "an empty description is none")
    }

    // MARK: compacted()

    func testCompactedStripsExtras() throws {
        let rows = try limits()
        for row in rows {
            let compact = row.compacted()
            XCTAssertNil(compact.sourceDeviceId, row.provider)
            XCTAssertNil(compact.resetCredits, row.provider)
            XCTAssertNil(compact.usageSummary, row.provider)
            XCTAssertEqual(compact.balance?.tranches ?? [], [], row.provider)
            XCTAssertNil(compact.balance?.quotaGroup, row.provider)
            XCTAssertLessThanOrEqual(compact.windows.count, 4)
            XCTAssertFalse(compact.windows.contains(where: \.isAdditional))
            // What stays: status, staleness, plan, the balance figures.
            XCTAssertEqual(compact.status, row.status)
            XCTAssertEqual(compact.isStale, row.isStale)
            XCTAssertEqual(compact.planLabel, row.planLabel)
            XCTAssertEqual(compact.actionRequired, row.actionRequired)
            XCTAssertEqual(compact.balance?.amount, row.balance?.amount)
            XCTAssertEqual(compact.balance?.monthSpend, row.balance?.monthSpend)
        }
        let claude = try provider("claude", in: rows).compacted()
        XCTAssertEqual(claude.accountEmail, "d***v@example.com")
        XCTAssertEqual(try provider("deepseek", in: rows).compacted().balance?.giftBalance, 10)

        // Nothing identifying, and none of the extras, reaches shared containers.
        let data = try JSONEncoder().encode(rows.map { $0.compacted() })
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for needle in ["dev@example.com", "someone@example.org", "accountKey", "sha256:", "sourceDeviceId", "studio-mac",
                       "resetCredits", "usageSummary", "tranches", "grant-outage"] {
            XCTAssertFalse(text.contains(needle), needle)
        }
    }

    func testCompactedHonoursHiddenItems() throws {
        let rows = try limits()
        let hidden: [String: [String]] = [
            "claude": [#"["weekly","Opus","",false]"#, "spend"],
            "codex": [#"["id","codex","session","",false,300]"#],
            "zai": ["bogus"]
        ]
        let claude = try provider("claude", in: rows)
        XCTAssertEqual(claude.visibleWindows(hiddenItems: hidden).map(\.label), [nil, nil])
        XCTAssertEqual(claude.compacted(hiddenItems: hidden).windows.map(\.kind), [.session, .weekly])
        XCTAssertEqual(claude.compacted(maxWindows: 1, hiddenItems: hidden).windows.map(\.kind), [.session])
        XCTAssertTrue(claude.isHidden(claude.windows[3], hiddenItems: hidden))
        XCTAssertEqual(claude.usageItemID(for: claude.windows[3]), "spend")

        let codex = try provider("codex", in: rows)
        XCTAssertEqual(codex.compacted(hiddenItems: hidden).windows.map(\.kind), [.weekly], "hidden, then additional buckets left out")
        XCTAssertEqual(codex.visibleWindows(hiddenItems: hidden).count, 4, "visibleWindows keeps additional buckets")

        let zai = try provider("zai", in: rows)
        XCTAssertEqual(zai.compacted(hiddenItems: hidden).windows, zai.windows, "a malformed id hides nothing")
        XCTAssertEqual(claude.compacted(hiddenItems: ["CLAUDE": ["spend"]]).windows.count, 4, "keys are stored lowercase")

        // Hidden items remove windows only: the balance still measures the meter.
        let openRouter = try provider("openrouter", in: rows).compacted(hiddenItems: ["openrouter": ["credits"]])
        XCTAssertEqual(openRouter.windows, [])
        XCTAssertEqual(openRouter.balance?.amount, 13.8)
    }

    // MARK: usage-items.json golden

    func testGoldenFixedItemIDs() throws {
        let golden = try Self.golden()
        XCTAssertEqual(golden["fixedItemIds"] as? [String], LimitUsageItems.fixedItemIDs)
    }

    func testGoldenWindowKeys() throws {
        let rows = try limits()
        let entries = try XCTUnwrap(Self.golden()["windows"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 23)
        for entry in entries {
            let providerName = try XCTUnwrap(entry["provider"] as? String)
            let accountKey = try XCTUnwrap(entry["accountKey"] as? String)
            let index = try XCTUnwrap(entry["index"] as? Int)
            let row = try XCTUnwrap(rows.first { $0.id == providerID(providerName, accountKey: accountKey) }, accountKey)
            let window = row.windows[index]
            let context = "\(providerName)[\(index)]"
            XCTAssertEqual(LimitUsageItems.legacyWindowKey(window), entry["legacyKey"] as? String, context)
            XCTAssertEqual(LimitUsageItems.windowKey(window), entry["windowKey"] as? String, context)
            XCTAssertEqual(LimitUsageItems.windowKeys(window), entry["windowKeys"] as? [String], context)
            let itemID = LimitUsageItems.itemID(for: window, provider: providerName)
            XCTAssertEqual(itemID, entry["itemId"] as? String, context)
            XCTAssertEqual(row.usageItemID(for: window), itemID, context)
            XCTAssertEqual(LimitUsageItems.fallbackLabel(provider: providerName, itemID: itemID)?.desktopText ?? "", entry["fallbackLabel"] as? String, context)
            XCTAssertEqual(LimitUsageItems.normalizeItemID(itemID), itemID, "\(context): a written id is already canonical")
        }
    }

    func testGoldenSpecialCases() throws {
        let entries = try XCTUnwrap(Self.golden()["specialCases"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 7)
        for entry in entries {
            let providerName = try XCTUnwrap(entry["provider"] as? String)
            let windowObject = try XCTUnwrap(entry["window"])
            let window = try JSONDecoder().decode(LimitWindow.self, from: JSONSerialization.data(withJSONObject: windowObject))
            let itemID = LimitUsageItems.itemID(for: window, provider: providerName)
            XCTAssertEqual(itemID, entry["itemId"] as? String, providerName)
            XCTAssertEqual(LimitUsageItems.windowKeys(window), entry["windowKeys"] as? [String], providerName)
            XCTAssertEqual(LimitUsageItems.fallbackLabel(provider: providerName, itemID: itemID)?.desktopText ?? "", entry["fallbackLabel"] as? String, providerName)
        }
    }

    func testGoldenNormalizeKeys() throws {
        let entries = try XCTUnwrap(Self.golden()["normalizeKeys"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 16)
        for entry in entries {
            let expected = try XCTUnwrap(entry["normalized"] as? String)
            guard let value = entry["value"] as? String else {
                // A non-string setting value (the golden's `42`) never reaches
                // the typed Swift API; the desktop maps it to "" too.
                XCTAssertEqual(expected, "")
                continue
            }
            XCTAssertEqual(LimitUsageItems.normalizeWindowKey(value), expected, value)
        }
    }

    func testGoldenFallbackLabels() throws {
        let entries = try XCTUnwrap(Self.golden()["fallbackLabels"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 8)
        for entry in entries {
            let itemID = try XCTUnwrap(entry["itemId"] as? String)
            for providerName in ["claude", "codex", "zai"] {
                XCTAssertEqual(
                    LimitUsageItems.fallbackLabel(provider: providerName, itemID: itemID)?.desktopText ?? "",
                    entry[providerName] as? String,
                    "\(providerName) \(itemID)"
                )
            }
        }
    }

    func testGoldenHiddenItemsSetting() throws {
        let golden = try Self.golden()
        let input = Self.hiddenValue(golden["hiddenInput"])
        let normalized = LimitUsageItems.normalizeHiddenItems(input)
        XCTAssertEqual(normalized, Self.hiddenValue(golden["normalizedHidden"]))

        let sets = try XCTUnwrap(golden["hiddenSets"] as? [String: [String]])
        for (providerName, expected) in sets {
            XCTAssertEqual(LimitUsageItems.hiddenItems(normalized, provider: providerName), expected, providerName)
            XCTAssertEqual(LimitUsageItems.hiddenSet(normalized, provider: providerName), Set(expected), providerName)
        }

        var value = normalized
        let sequence = try XCTUnwrap(golden["sequence"] as? [[String: Any]])
        XCTAssertEqual(sequence.count, 5)
        for step in sequence {
            let providerName = try XCTUnwrap(step["provider"] as? String)
            switch step["op"] as? String {
            case "setUsageItemHidden":
                let itemID = try XCTUnwrap(step["itemId"] as? String)
                let hidden = try XCTUnwrap(step["hidden"] as? Bool)
                value = LimitUsageItems.setHidden(value, provider: providerName, itemID: itemID, hidden: hidden)
            case "restoreUsageItemDefaults":
                value = LimitUsageItems.restoreDefaults(value, provider: providerName)
            default:
                XCTFail("unknown op \(String(describing: step["op"]))")
            }
            XCTAssertEqual(value, Self.hiddenValue(step["result"]), "\(step["op"] ?? "") \(providerName)")
        }

        let rows = try limits()
        let windows = try XCTUnwrap(golden["windows"] as? [[String: Any]])
        let checks = try XCTUnwrap(golden["hiddenChecks"] as? [[String: Any]])
        XCTAssertEqual(checks.count, windows.count)
        for (check, entry) in zip(checks, windows) {
            let providerName = try XCTUnwrap(check["provider"] as? String)
            let index = try XCTUnwrap(check["index"] as? Int)
            let accountKey = try XCTUnwrap(entry["accountKey"] as? String)
            let row = try XCTUnwrap(rows.first { $0.id == providerID(providerName, accountKey: accountKey) })
            XCTAssertEqual(
                LimitUsageItems.isHidden(row.windows[index], provider: providerName, hiddenItems: normalized),
                check["hidden"] as? Bool,
                "\(providerName)[\(index)]"
            )
        }
    }

    // MARK: Edge vectors (computed with node from src/shared/limits/usageItems.js)

    func testNormalizeWindowKeyEdgeVectors() {
        for (value, expected) in LimitUsageItemVectors.normalizeWindowKey {
            XCTAssertEqual(LimitUsageItems.normalizeWindowKey(value), expected, value)
        }
    }

    func testNormalizeItemIDEdgeVectors() {
        for (value, expected) in LimitUsageItemVectors.normalizeItemID {
            XCTAssertEqual(LimitUsageItems.normalizeItemID(value), expected, value)
            XCTAssertEqual(LimitUsageItems.hiddenItems(["claude": [value]], provider: "claude"), expected.isEmpty ? [] : [expected], value)
        }
    }

    func testFallbackLabelEdgeVectors() {
        for (providerName, itemID, expected) in LimitUsageItemVectors.fallbackLabels {
            XCTAssertEqual(LimitUsageItems.fallbackLabel(provider: providerName, itemID: itemID)?.desktopText ?? "", expected, "\(providerName) \(itemID)")
        }
    }

    func testWindowKeyEdgeVectors() throws {
        for vector in LimitUsageItemVectors.windows {
            let window = try JSONDecoder().decode(LimitWindow.self, from: Data(vector.window.utf8))
            XCTAssertEqual(LimitUsageItems.legacyWindowKey(window), vector.legacy, vector.window)
            XCTAssertEqual(LimitUsageItems.windowKey(window), vector.key, vector.window)
            XCTAssertEqual(LimitUsageItems.windowKeys(window), vector.keys, vector.window)
            XCTAssertEqual(LimitUsageItems.itemID(for: window, provider: vector.provider), vector.itemID, vector.window)
        }
    }

    func testHiddenSettingEdgeCases() {
        // node: normalizeLimitProviderHiddenItems({ Claude: ['spend'], claude: ['resets'] }) and on.
        var value = LimitUsageItems.normalizeHiddenItems(["Claude": ["spend"], "claude": ["resets"]])
        XCTAssertEqual(value, ["claude": ["resets"]], "the lowercase key is applied last")
        value = LimitUsageItems.setHidden(value, provider: "CLAUDE", itemID: " credits ", hidden: true)
        XCTAssertEqual(value, ["claude": ["resets", "credits"]])
        value = LimitUsageItems.setHidden(value, provider: "claude", itemID: "resets", hidden: false)
        XCTAssertEqual(value, ["claude": ["credits"]])
        value = LimitUsageItems.setHidden(value, provider: "codex", itemID: "bogus", hidden: true)
        XCTAssertEqual(value, ["claude": ["credits"]])
        value = LimitUsageItems.setHidden(value, provider: "kimi", itemID: #"["weekly","","",false]"#, hidden: true)
        XCTAssertEqual(value, ["claude": ["credits"], "kimi": [#"["weekly","","",false]"#]])
        value = LimitUsageItems.restoreDefaults(value, provider: "KIMI")
        XCTAssertEqual(value, ["claude": ["credits"]])

        let many = (0..<70).map { #"["daily","L\#($0)","",false]"# }
        XCTAssertEqual(LimitUsageItems.normalizeHiddenItems(["zai": many])["zai"]?.count, 64)
        XCTAssertEqual(LimitUsageItems.normalizeHiddenItems(["zai": many])["zai"]?.last, #"["daily","L63","",false]"#)
        XCTAssertFalse(LimitUsageItems.isHidden(LimitWindow(kind: .weekly), provider: "zai", hiddenItems: [:]))
    }

    func testLoneSurrogateKeysAreRejected() {
        // The desktop keeps a lone surrogate (`["weekly","\ud83d","",false]`);
        // a Swift String cannot hold one, so the key is treated as malformed.
        XCTAssertEqual(LimitUsageItems.normalizeWindowKey(#"["weekly","\uD83D","",false]"#), "")
        XCTAssertEqual(LimitUsageItems.normalizeWindowKey(#"["weekly","😀","",false]"#), "[\"weekly\",\"\u{1F600}\",\"\",false]")
    }

    func testStructuredLabels() {
        XCTAssertEqual(LimitUsageItems.fallbackLabel(provider: "claude", itemID: "credits"), .fixed(.credits))
        XCTAssertEqual(LimitUsageItems.fallbackLabel(provider: "kimi", itemID: #"["session","","",false]"#), .window(.kind(.fiveHour)))
        XCTAssertEqual(LimitUsageItems.fallbackLabel(provider: "zai", itemID: #"["daily","MCP calls","",false]"#), .window(.label("MCP calls")))
        XCTAssertEqual(
            LimitUsageItems.fallbackLabel(provider: "codex", itemID: #"["id","codex_bengalfox","weekly","",true,10080]"#),
            .additional(limitID: "codex_bengalfox", title: .kind(.weekly))
        )
        XCTAssertEqual(LimitUsageItems.fallbackLabel(provider: "claude", itemID: #"["custom","","",false]"#), .window(.rawKind("custom")))
        XCTAssertNil(LimitUsageItems.fallbackLabel(provider: "claude", itemID: "bogus"))
        XCTAssertEqual(LimitWindowTitle.of(LimitWindow(kind: .billing), provider: "zed"), .kind(.monthly))
        XCTAssertEqual(LimitWindowTitle.of(LimitWindow(kind: .session), provider: " ZAI "), .kind(.fiveHour))
        XCTAssertEqual(LimitWindowTitle.of(LimitWindow(kind: .weekly, label: "Opus"), provider: "claude"), .label("Opus"))
        XCTAssertEqual(LimitWindowKindName.allCases.map(\.desktopText), ["Session", "5-hour", "Daily", "Weekly", "Monthly"])
        XCTAssertEqual(LimitUsageItem(id: "spend", label: .fixed(.spend)).id, "spend")
    }
}

/// Inputs and outputs computed with node 22 from `src/shared/limits/usageItems.js`
/// (`$SP/p1-limits-vectors/gen.js`), pasted here. Lone-surrogate inputs are
/// left out (see `testLoneSurrogateKeysAreRejected`).
private enum LimitUsageItemVectors {
    // normalizeWindowKey(value) -> normalized
    static let normalizeWindowKey: [(String, String)] = [
        ("[\"sess\\u0069on\",\"\",\"\",false]", "[\"session\",\"\",\"\",false]"),
        (" [\"weekly\",\"Opus\",\"\",false] ", "[\"weekly\",\"Opus\",\"\",false]"),
        ("[ \"weekly\" , \"a\\\"b\\\\c\" , \"\" , true ]", "[\"weekly\",\"a\\\"b\\\\c\",\"\",true]"),
        ("[\"weekly\",\"\u{E9}\\u00e9 \\ud83d\\ude00\",\"\",false]", "[\"weekly\",\"\u{E9}\u{E9} \u{1F600}\",\"\",false]"),
        ("[\"weekly\",\"line\\nbreak\\u0001\",\"spend\",false]", "[\"weekly\",\"line\\nbreak\\u0001\",\"spend\",false]"),
        ("[\"weekly\",\"\t\",\"\",false]", ""),
        ("[\"weekly\",\"\",\"\",false,]", ""),
        ("[\"weekly\",\"\",\"\",0]", ""),
        ("[\"\",\"\",\"\",false]", ""),
        ("[\"id\",\" codex \",\"weekly\",\"\",true,1e400]", "[\"id\",\"codex\",\"weekly\",\"\",true,null]"),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,1.5]", "[\"id\",\"codex\",\"weekly\",\"\",true,1.5]"),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,1E3]", "[\"id\",\"codex\",\"weekly\",\"\",true,1000]"),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,-0]", ""),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,01]", ""),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,1e21]", "[\"id\",\"codex\",\"weekly\",\"\",true,1e+21]"),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,123456789012]", "[\"id\",\"codex\",\"weekly\",\"\",true,123456789012]"),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,0.000001]", "[\"id\",\"codex\",\"weekly\",\"\",true,0.000001]"),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,1e-7]", "[\"id\",\"codex\",\"weekly\",\"\",true,1e-7]"),
        ("[\"id\",\"x\",\"weekly\",null,false,null]", ""),
        ("[\"id\",\"\\u0020\",\"weekly\",\"\",false,null]", ""),
        ("[\"id\",\"x\",\"Weekly\",\"credits\",false,null]", "[\"id\",\"x\",\"Weekly\",\"credits\",false,null]"),
        ("[\"id\",\"x\",\"weekly\",\"\",false,null,1]", ""),
        ("[\"ID\",\"x\",\"weekly\",\"\",false,null]", ""),
        ("[\"id\",\"x\",\"weekly\",\"\",false,\"5\"]", ""),
        ("[\"a\",\"b\",\"c\",true]", "[\"a\",\"b\",\"c\",true]"),
        ("[\"weekly\",\"\",\"\",true] x", ""),
        ("[]", ""),
        ("\"credits\"", ""),
        ("[\"weekly\",\"\",\"\",fals]", ""),
        ("[\"weekly\",\"\\x\",\"\",false]", ""),
        ("[\"weekly\",\"\\u12\",\"\",false]", ""),
        ("[\"weekly\",[],\"\",false]", ""),
        ("\u{A0}[\"weekly\",\"\",\"\",false]", ""),
        ("\u{FEFF}[\"weekly\",\"\",\"\",false]", ""),
        ("\u{2028}[\"weekly\",\"\",\"\",false]", ""),
    ]
    // normalizeUsageItemId(value) -> normalized (read back through hiddenUsageItemSet)
    static let normalizeItemID: [(String, String)] = [
        (" credits ", "credits"),
        ("\u{FEFF}spend\u{A0}", "spend"),
        ("CREDITS", ""),
        ("resets\u{85}", ""),
        ("[\"sess\\u0069on\",\"\",\"\",false]", "[\"session\",\"\",\"\",false]"),
        (" [\"weekly\",\"Opus\",\"\",false] ", "[\"weekly\",\"Opus\",\"\",false]"),
        ("[ \"weekly\" , \"a\\\"b\\\\c\" , \"\" , true ]", "[\"weekly\",\"a\\\"b\\\\c\",\"\",true]"),
        ("[\"weekly\",\"\u{E9}\\u00e9 \\ud83d\\ude00\",\"\",false]", "[\"weekly\",\"\u{E9}\u{E9} \u{1F600}\",\"\",false]"),
        ("[\"weekly\",\"line\\nbreak\\u0001\",\"spend\",false]", "[\"weekly\",\"line\\nbreak\\u0001\",\"spend\",false]"),
        ("[\"weekly\",\"\t\",\"\",false]", ""),
        ("[\"weekly\",\"\",\"\",false,]", ""),
        ("[\"weekly\",\"\",\"\",0]", ""),
        ("[\"\",\"\",\"\",false]", ""),
        ("[\"id\",\" codex \",\"weekly\",\"\",true,1e400]", "[\"id\",\"codex\",\"weekly\",\"\",true,null]"),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,1.5]", "[\"id\",\"codex\",\"weekly\",\"\",true,1.5]"),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,1E3]", "[\"id\",\"codex\",\"weekly\",\"\",true,1000]"),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,-0]", ""),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,01]", ""),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,1e21]", "[\"id\",\"codex\",\"weekly\",\"\",true,1e+21]"),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,123456789012]", "[\"id\",\"codex\",\"weekly\",\"\",true,123456789012]"),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,0.000001]", "[\"id\",\"codex\",\"weekly\",\"\",true,0.000001]"),
        ("[\"id\",\"codex\",\"weekly\",\"\",true,1e-7]", "[\"id\",\"codex\",\"weekly\",\"\",true,1e-7]"),
        ("[\"id\",\"x\",\"weekly\",null,false,null]", ""),
        ("[\"id\",\"\\u0020\",\"weekly\",\"\",false,null]", ""),
        ("[\"id\",\"x\",\"Weekly\",\"credits\",false,null]", "[\"id\",\"x\",\"Weekly\",\"credits\",false,null]"),
        ("[\"id\",\"x\",\"weekly\",\"\",false,null,1]", ""),
        ("[\"ID\",\"x\",\"weekly\",\"\",false,null]", ""),
        ("[\"id\",\"x\",\"weekly\",\"\",false,\"5\"]", ""),
        ("[\"a\",\"b\",\"c\",true]", "[\"a\",\"b\",\"c\",true]"),
        ("[\"weekly\",\"\",\"\",true] x", ""),
        ("[]", ""),
        ("\"credits\"", ""),
        ("[\"weekly\",\"\",\"\",fals]", ""),
        ("[\"weekly\",\"\\x\",\"\",false]", ""),
        ("[\"weekly\",\"\\u12\",\"\",false]", ""),
        ("[\"weekly\",[],\"\",false]", ""),
        ("\u{A0}[\"weekly\",\"\",\"\",false]", "[\"weekly\",\"\",\"\",false]"),
        ("\u{FEFF}[\"weekly\",\"\",\"\",false]", "[\"weekly\",\"\",\"\",false]"),
        ("\u{2028}[\"weekly\",\"\",\"\",false]", "[\"weekly\",\"\",\"\",false]"),
    ]
    // usageItemFallbackLabel(provider, itemId) -> label
    static let fallbackLabels: [(String, String, String)] = [
        ("kimi", "[\"id\",\" x \",\"session\",\"\",true,null]", " x  \u{B7} 5-hour"),
        ("claude", "[\"id\",\" x \",\"session\",\"\",true,null]", " x  \u{B7} Session"),
        ("kimi", "[\"Session\",\"\",\"\",false]", "5-hour"),
        ("claude", "[\"Session\",\"\",\"\",false]", "Session"),
        ("kimi", "[\" Session \",\"\",\"\",false]", "5-hour"),
        ("claude", "[\" Session \",\"\",\"\",false]", "Session"),
        ("kimi", "[\"monthly\",\"\",\"\",false]", "monthly"),
        ("claude", "[\"monthly\",\"\",\"\",false]", "monthly"),
        ("kimi", "[\"billing\",\" Opus \",\"\",false]", "Opus"),
        ("claude", "[\"billing\",\" Opus \",\"\",false]", "Opus"),
        ("kimi", "[\"session\",\"\",\"\",true]", "5-hour"),
        ("claude", "[\"session\",\"\",\"\",true]", "Session"),
        ("kimi", "[\"id\",\"codex_spark\",\"session\",\"\",false,300]", "5-hour"),
        ("claude", "[\"id\",\"codex_spark\",\"session\",\"\",false,300]", "Session"),
        ("kimi", "[\"id\",\"codex_spark\",\"billing\",\"\",true,null]", "codex_spark \u{B7} Monthly"),
        ("claude", "[\"id\",\"codex_spark\",\"billing\",\"\",true,null]", "codex_spark \u{B7} Monthly"),
        ("kimi", "[\"custom\",\"\",\"\",true]", "custom"),
        ("claude", "[\"custom\",\"\",\"\",true]", "custom"),
        ("kimi", "[\"sess\\u0069on\",\"\",\"\",false]", "5-hour"),
        ("claude", "[\"sess\\u0069on\",\"\",\"\",false]", "Session"),
        ("kimi", " [\"weekly\",\"Opus\",\"\",false] ", "Opus"),
        ("claude", " [\"weekly\",\"Opus\",\"\",false] ", "Opus"),
        ("kimi", "[ \"weekly\" , \"a\\\"b\\\\c\" , \"\" , true ]", "a\"b\\c"),
        ("claude", "[ \"weekly\" , \"a\\\"b\\\\c\" , \"\" , true ]", "a\"b\\c"),
        ("kimi", "[\"weekly\",\"\u{E9}\\u00e9 \\ud83d\\ude00\",\"\",false]", "\u{E9}\u{E9} \u{1F600}"),
        ("claude", "[\"weekly\",\"\u{E9}\\u00e9 \\ud83d\\ude00\",\"\",false]", "\u{E9}\u{E9} \u{1F600}"),
        ("kimi", "[\"weekly\",\"line\\nbreak\\u0001\",\"spend\",false]", "line\nbreak\u{1}"),
        ("claude", "[\"weekly\",\"line\\nbreak\\u0001\",\"spend\",false]", "line\nbreak\u{1}"),
        ("kimi", "[\"weekly\",\"\t\",\"\",false]", ""),
        ("claude", "[\"weekly\",\"\t\",\"\",false]", ""),
        ("kimi", "[\"weekly\",\"\",\"\",false,]", ""),
        ("claude", "[\"weekly\",\"\",\"\",false,]", ""),
        ("kimi", "[\"weekly\",\"\",\"\",0]", ""),
        ("claude", "[\"weekly\",\"\",\"\",0]", ""),
        ("kimi", "[\"\",\"\",\"\",false]", ""),
        ("claude", "[\"\",\"\",\"\",false]", ""),
        ("kimi", "[\"id\",\" codex \",\"weekly\",\"\",true,1e400]", " codex  \u{B7} Weekly"),
        ("claude", "[\"id\",\" codex \",\"weekly\",\"\",true,1e400]", " codex  \u{B7} Weekly"),
        ("kimi", "[\"id\",\"codex\",\"weekly\",\"\",true,1.5]", "codex \u{B7} Weekly"),
        ("claude", "[\"id\",\"codex\",\"weekly\",\"\",true,1.5]", "codex \u{B7} Weekly"),
        ("kimi", "[\"id\",\"codex\",\"weekly\",\"\",true,1E3]", "codex \u{B7} Weekly"),
        ("claude", "[\"id\",\"codex\",\"weekly\",\"\",true,1E3]", "codex \u{B7} Weekly"),
        ("kimi", "[\"id\",\"codex\",\"weekly\",\"\",true,-0]", ""),
        ("claude", "[\"id\",\"codex\",\"weekly\",\"\",true,-0]", ""),
        ("kimi", "[\"id\",\"codex\",\"weekly\",\"\",true,01]", ""),
        ("claude", "[\"id\",\"codex\",\"weekly\",\"\",true,01]", ""),
        ("kimi", "[\"id\",\"codex\",\"weekly\",\"\",true,1e21]", "codex \u{B7} Weekly"),
        ("claude", "[\"id\",\"codex\",\"weekly\",\"\",true,1e21]", "codex \u{B7} Weekly"),
        ("kimi", "[\"id\",\"codex\",\"weekly\",\"\",true,123456789012]", "codex \u{B7} Weekly"),
        ("claude", "[\"id\",\"codex\",\"weekly\",\"\",true,123456789012]", "codex \u{B7} Weekly"),
        ("kimi", "[\"id\",\"codex\",\"weekly\",\"\",true,0.000001]", "codex \u{B7} Weekly"),
        ("claude", "[\"id\",\"codex\",\"weekly\",\"\",true,0.000001]", "codex \u{B7} Weekly"),
        ("kimi", "[\"id\",\"codex\",\"weekly\",\"\",true,1e-7]", "codex \u{B7} Weekly"),
        ("claude", "[\"id\",\"codex\",\"weekly\",\"\",true,1e-7]", "codex \u{B7} Weekly"),
        ("kimi", "[\"id\",\"x\",\"weekly\",null,false,null]", ""),
        ("claude", "[\"id\",\"x\",\"weekly\",null,false,null]", ""),
        ("kimi", "[\"id\",\"\\u0020\",\"weekly\",\"\",false,null]", ""),
        ("claude", "[\"id\",\"\\u0020\",\"weekly\",\"\",false,null]", ""),
        ("kimi", "[\"id\",\"x\",\"Weekly\",\"credits\",false,null]", "Weekly"),
        ("claude", "[\"id\",\"x\",\"Weekly\",\"credits\",false,null]", "Weekly"),
        ("kimi", "[\"id\",\"x\",\"weekly\",\"\",false,null,1]", ""),
        ("claude", "[\"id\",\"x\",\"weekly\",\"\",false,null,1]", ""),
        ("kimi", "[\"ID\",\"x\",\"weekly\",\"\",false,null]", ""),
        ("claude", "[\"ID\",\"x\",\"weekly\",\"\",false,null]", ""),
        ("kimi", "[\"id\",\"x\",\"weekly\",\"\",false,\"5\"]", ""),
        ("claude", "[\"id\",\"x\",\"weekly\",\"\",false,\"5\"]", ""),
        ("kimi", "[\"a\",\"b\",\"c\",true]", "b"),
        ("claude", "[\"a\",\"b\",\"c\",true]", "b"),
        ("kimi", "[\"weekly\",\"\",\"\",true] x", ""),
        ("claude", "[\"weekly\",\"\",\"\",true] x", ""),
        ("kimi", "[]", ""),
        ("claude", "[]", ""),
        ("kimi", "\"credits\"", ""),
        ("claude", "\"credits\"", ""),
        ("kimi", "[\"weekly\",\"\",\"\",fals]", ""),
        ("claude", "[\"weekly\",\"\",\"\",fals]", ""),
        ("kimi", "[\"weekly\",\"\\x\",\"\",false]", ""),
        ("claude", "[\"weekly\",\"\\x\",\"\",false]", ""),
        ("kimi", "[\"weekly\",\"\\u12\",\"\",false]", ""),
        ("claude", "[\"weekly\",\"\\u12\",\"\",false]", ""),
        ("kimi", "[\"weekly\",[],\"\",false]", ""),
        ("claude", "[\"weekly\",[],\"\",false]", ""),
        ("kimi", "\u{A0}[\"weekly\",\"\",\"\",false]", ""),
        ("claude", "\u{A0}[\"weekly\",\"\",\"\",false]", ""),
        ("kimi", "\u{FEFF}[\"weekly\",\"\",\"\",false]", ""),
        ("claude", "\u{FEFF}[\"weekly\",\"\",\"\",false]", ""),
        ("kimi", "\u{2028}[\"weekly\",\"\",\"\",false]", ""),
        ("claude", "\u{2028}[\"weekly\",\"\",\"\",false]", ""),
    ]
    // (provider, window JSON) -> legacy key, key, keys, item id
    static let windows: [(provider: String, window: String, legacy: String, key: String, keys: [String], itemID: String)] = [
        ("claude", "{\"kind\":\"weekly\",\"label\":\"Fable \\\"promo\\\" \\\\ x\"}", "[\"weekly\",\"Fable \\\"promo\\\" \\\\ x\",\"\",false]", "[\"weekly\",\"Fable \\\"promo\\\" \\\\ x\",\"\",false]", ["[\"weekly\",\"Fable \\\"promo\\\" \\\\ x\",\"\",false]"], "[\"weekly\",\"Fable \\\"promo\\\" \\\\ x\",\"\",false]"),
        ("codex", "{\"kind\":\"weekly\",\"limitId\":\"  codex_x  \",\"windowMinutes\":10080.5,\"additional\":true,\"label\":\"Spark\"}", "[\"weekly\",\"Spark\",\"\",true]", "[\"id\",\"codex_x\",\"weekly\",\"\",true,10080.5]", ["[\"id\",\"codex_x\",\"weekly\",\"\",true,10080.5]", "[\"weekly\",\"Spark\",\"\",true]"], "[\"id\",\"codex_x\",\"weekly\",\"\",true,10080.5]"),
        ("codex", "{\"kind\":\"session\",\"limitId\":\"c\",\"windowMinutes\":1e+21}", "[\"session\",\"\",\"\",false]", "[\"id\",\"c\",\"session\",\"\",false,1e+21]", ["[\"id\",\"c\",\"session\",\"\",false,1e+21]", "[\"session\",\"\",\"\",false]"], "[\"id\",\"c\",\"session\",\"\",false,1e+21]"),
        ("codex", "{\"kind\":\"session\",\"limitId\":\"c\",\"windowMinutes\":0.25}", "[\"session\",\"\",\"\",false]", "[\"id\",\"c\",\"session\",\"\",false,0.25]", ["[\"id\",\"c\",\"session\",\"\",false,0.25]", "[\"session\",\"\",\"\",false]"], "[\"id\",\"c\",\"session\",\"\",false,0.25]"),
        ("claude", "{\"kind\":\"billing\",\"metric\":\"credits\",\"label\":\"Usage credits\"}", "[\"billing\",\"Usage credits\",\"credits\",false]", "[\"billing\",\"Usage credits\",\"credits\",false]", ["[\"billing\",\"Usage credits\",\"credits\",false]"], "credits"),
        ("Claude", "{\"kind\":\"billing\",\"label\":\"Usage credits\"}", "[\"billing\",\"Usage credits\",\"\",false]", "[\"billing\",\"Usage credits\",\"\",false]", ["[\"billing\",\"Usage credits\",\"\",false]"], "spend"),
        (" CLINE ", "{\"kind\":\"billing\",\"metric\":\"spend\"}", "[\"billing\",\"\",\"spend\",false]", "[\"billing\",\"\",\"spend\",false]", ["[\"billing\",\"\",\"spend\",false]"], "credits"),
        ("openrouter", "{\"kind\":\"weekly\",\"label\":\"Credits\"}", "[\"weekly\",\"Credits\",\"\",false]", "[\"weekly\",\"Credits\",\"\",false]", ["[\"weekly\",\"Credits\",\"\",false]"], "credits"),
        ("zai", "{\"kind\":\"billing\",\"label\":\"Plan \u{65E5}\u{672C}\u{8A9E}\"}", "[\"billing\",\"Plan \u{65E5}\u{672C}\u{8A9E}\",\"\",false]", "[\"billing\",\"Plan \u{65E5}\u{672C}\u{8A9E}\",\"\",false]", ["[\"billing\",\"Plan \u{65E5}\u{672C}\u{8A9E}\",\"\",false]"], "[\"billing\",\"Plan \u{65E5}\u{672C}\u{8A9E}\",\"\",false]"),
    ]
}

import Foundation
import XCTest
@testable import TokenMonitorKit

/// The Limits presentation port (`LimitPresentation`) against the desktop:
/// the `limit-status.json` golden (rendered from the v2 Hub capture by
/// `providerPresentation.js`, `displayMode.js`, `balanceDisplay.js` and
/// `homeOverview.js`), plus vectors produced by running the desktop's own
/// `windowsView.js` (under a minimal fake DOM), `accountIdentity.js` and the
/// Home module on the fixture rows and on synthetic Hub-normalized rows. The
/// vector generator is `$SP/p2-limpres/gen.js` + `compact.py`.
final class LimitPresentationTests: XCTestCase {
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
        try XCTUnwrap(JSONSerialization.jsonObject(with: v2Data("limit-status.json", golden: true)) as? [String: Any])
    }

    private static func vectors() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(vectorsJSON.utf8)) as? [String: Any])
    }

    private static func date(_ iso: String) -> Date { ISODate.parse(iso)! }

    private static let now = date("2026-10-10T16:30:00.000Z")

    private static func stats() throws -> HubStats {
        try HubStats.decode(from: v2Data("stats.json"))
    }

    /// The fixture rows, then the synthetic ones, numbered as the Hub decode numbers them.
    private static func allProviders() throws -> [LimitProvider] {
        struct Synthetic: Decodable { let synthetic: [LimitProvider] }
        var rows = try stats().limits + JSONDecoder().decode(Synthetic.self, from: Data(vectorsJSON.utf8)).synthetic
        HubStats.assignUniqueIDs(&rows)
        return rows
    }

    /// The desktop Limits page's own English status words (`limitStatusLabel`),
    /// which iOS replaces with the localized Settings-tag vocabulary.
    private static let pageStatusWords: Set<String> = [
        "Live", "Disabled", "Not signed in", "No synced data", "Sign in again", "Limited", "Usage API limited", "Unavailable", "Error"
    ]

    /// Fingerprints differ by design (the Kit never keeps the account key).
    private static func normalizedTitle(_ text: String) -> String {
        text.replacingOccurrences(of: #"#[0-9a-z]+"#, with: "#*", options: .regularExpression)
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber).map(\.doubleValue)
    }

    private static func boundaryText(_ line: LimitPresentation.BoundaryLine?) -> String {
        switch line {
        case .boundary(let boundary)?: return boundary.desktopText
        case .description(let text)?: return text
        case nil: return ""
        }
    }

    private func assertPlanCell(_ cell: LimitPlanCell, _ desktop: String, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        if Self.pageStatusWords.contains(desktop) {
            guard case .status = cell else { return XCTFail("\(context): expected a status cell for \(desktop), got \(cell)", file: file, line: line) }
        } else {
            XCTAssertEqual(cell.desktopText, desktop, context, file: file, line: line)
        }
    }

    // MARK: Golden: limit-status.json

    func testDurationTextAndFillPercentGolden() throws {
        let golden = try Self.golden()
        for entry in try XCTUnwrap(golden["durationText"] as? [[String: Any]]) {
            let ms = try XCTUnwrap(Self.double(entry["ms"]))
            XCTAssertEqual(LimitPresentation.DurationParts(milliseconds: ms).desktopText, entry["text"] as? String, "\(ms)")
        }
        for entry in try XCTUnwrap(try Self.vectors()["durations"] as? [[String: Any]]) {
            let ms = try XCTUnwrap(Self.double(entry["ms"]))
            XCTAssertEqual(LimitPresentation.DurationParts(milliseconds: ms).desktopText, entry["text"] as? String, "\(ms)")
        }
        for entry in try XCTUnwrap(golden["fillPercent"] as? [[String: Any]]) {
            // `null` and `""` both read as 0 on the desktop (`Number(...)`).
            let showUsed = try XCTUnwrap(entry["showUsed"] as? Bool)
            let fill = LimitPresentation.fillPercent(
                remaining: Self.double(entry["remainingPercent"]),
                used: Self.double(entry["usedPercent"]),
                showUsed: showUsed
            )
            XCTAssertEqual(fill, try XCTUnwrap(Self.double(entry["fill"])), "\(entry)")
            XCTAssertEqual(LimitPresentation.mode(showUsed: showUsed) == .used ? "used" : "left", entry["suffix"] as? String)
        }
    }

    func testProviderPresentationGolden() throws {
        let golden = try Self.golden()
        let rows = try Self.stats().limits
        let goldenProviders = try XCTUnwrap(golden["providers"] as? [[String: Any]])
        XCTAssertEqual(rows.count, goldenProviders.count)
        let clocks = try XCTUnwrap(golden["clocks"] as? [String: String]).mapValues(Self.date)
        var checkedWindows = 0
        for (provider, expected) in zip(rows, goldenProviders) {
            let name = provider.provider
            XCTAssertEqual(name, expected["provider"] as? String)

            // Status chip, with the desktop key where the golden names one.
            let status = try XCTUnwrap(expected["statusLabel"] as? [String: Any])
            let chip = LimitPresentation.statusChip(provider)
            XCTAssertEqual(chip.label.desktopText, status["label"] as? String, name)
            XCTAssertEqual(chip.tone.rawValue, status["tone"] as? String, name)
            if let key = status["key"] as? String { XCTAssertEqual(chip.label.desktopKey, key, name) }
            XCTAssertEqual(LimitPresentation.status(provider).label, chip.label)
            XCTAssertEqual(chip.showsLiveDot, provider.status == .ok && !provider.isStale)

            // Freshness at every clock.
            for (clock, value) in try XCTUnwrap(expected["freshness"] as? [String: [String: String]]) {
                let freshness = LimitPresentation.freshness(provider, now: try XCTUnwrap(clocks[clock]))
                XCTAssertEqual(freshness.desktopText, value["text"], "\(name) \(clock)")
                XCTAssertEqual(freshness.age?.desktopText ?? "", value["age"], "\(name) \(clock)")
                XCTAssertEqual(freshness.tone.rawValue, value["tone"], "\(name) \(clock)")
            }

            XCTAssertEqual(LimitPresentation.sourceKind(provider)?.desktopText ?? "", expected["sourceLabel"] as? String, name)
            XCTAssertEqual(
                LimitPresentation.planDisplayLabel(provider: name, label: provider.explicitPlanLabel ?? ""),
                expected["planDisplayLabel"] as? String, name
            )
            XCTAssertEqual(
                provider.planLabel.map { LimitPresentation.planDisplayLabel(provider: name, label: $0) } ?? "",
                expected["planOrAccountDisplayLabel"] as? String, name
            )
            XCTAssertEqual(LimitPresentation.spendWindow(provider)?.label, expected["spendWindowLabel"] as? String, name)
            XCTAssertEqual(
                LimitPresentation.compactWindows(provider, windows: provider.windows).map(LimitUsageItems.windowKey),
                expected["compactWindowKeys"] as? [String], name
            )

            let windows = try XCTUnwrap(expected["windows"] as? [[String: Any]])
            XCTAssertEqual(provider.windows.count, windows.count, name)
            for (window, value) in zip(provider.windows, windows) {
                checkedWindows += 1
                let context = "\(name) \(window.id)"
                for (clock, text) in try XCTUnwrap(value["boundaryText"] as? [String: String]) {
                    let boundary = LimitPresentation.boundary(window: window, now: try XCTUnwrap(clocks[clock]))
                    XCTAssertEqual(boundary?.desktopText ?? "", text, "\(context) \(clock)")
                }
                XCTAssertEqual(
                    LimitPresentation.resetRemainingMs(window.resetsAt, now: Self.now),
                    Self.double(value["resetRemainingMs"]), context
                )
                XCTAssertEqual(
                    LimitPresentation.fillPercent(remaining: window.remainingPercent, used: window.usedPercent, showUsed: false),
                    try XCTUnwrap(Self.double(value["fillRemaining"])), accuracy: 1e-9, context
                )
                XCTAssertEqual(
                    LimitPresentation.fillPercent(remaining: window.remainingPercent, used: window.usedPercent, showUsed: true),
                    try XCTUnwrap(Self.double(value["fillUsed"])), accuracy: 1e-9, context
                )
                let home = LimitPresentation.homeRemainingPercent(window)
                if let expectedHome = Self.double(value["homeRemainingPercent"]) {
                    XCTAssertEqual(try XCTUnwrap(home, context), expectedHome, accuracy: 1e-9, context)
                } else {
                    XCTAssertNil(home, context)
                }
                if let codexName = value["codexDisplayName"] as? String {
                    XCTAssertEqual(LimitPresentation.codexAdditionalDisplayName(window.label ?? ""), codexName, context)
                }
                if value["creditsAmount"] != nil {
                    XCTAssertEqual(LimitPresentation.creditsAmount(provider, window: window), Self.double(value["creditsAmount"]), context)
                    XCTAssertEqual(LimitPresentation.creditsCurrency(provider, window: window), value["creditsCurrency"] as? String, context)
                    XCTAssertEqual(
                        try XCTUnwrap(LimitPresentation.creditsMeterPercent(provider, window: window)),
                        try XCTUnwrap(Self.double(value["creditsMeterPercent"])), accuracy: 1e-9, context
                    )
                    XCTAssertEqual(
                        BalanceFormat.format(
                            amount: LimitPresentation.creditsAmount(provider, window: window),
                            currency: LimitPresentation.creditsCurrency(provider, window: window)
                        ),
                        value["formatMoney"] as? String, context
                    )
                }
            }
        }
        XCTAssertEqual(checkedWindows, 23)
    }

    func testHomeAccountsGolden() throws {
        let home = try XCTUnwrap(try Self.golden()["home"] as? [String: Any])
        let rows = try Self.stats().limits
        // The golden's accounts carry the wire account key; the Kit derives its
        // row id from it, so the key is rebuilt from the golden provider list.
        let goldenProviders = try XCTUnwrap(try Self.golden()["providers"] as? [[String: Any]])
        let inputs = zip(rows, goldenProviders).map { provider, golden in
            LimitPresentation.HomeLimitAccountInput(
                key: "\(provider.provider):\(golden["accountKey"] as? String ?? "")",
                providerID: provider.provider,
                windows: provider.windows,
                balance: provider.balance
            )
        }
        func check(_ actual: [LimitPresentation.HomeLimitAccount], _ expected: [[String: Any]], _ name: String) throws {
            XCTAssertEqual(actual.map(\.key), expected.map { $0["key"] as? String ?? "" }, name)
            for (account, value) in zip(actual, expected) {
                XCTAssertEqual(account.providerID, value["providerId"] as? String, name)
                XCTAssertEqual(account.lowestRemaining, try XCTUnwrap(Self.double(value["lowestRemaining"])), accuracy: 1e-9, name)
                let windows = try XCTUnwrap(value["windows"] as? [[String: Any]])
                XCTAssertEqual(account.windows.count, windows.count, "\(name) \(account.key)")
                for (window, expectedWindow) in zip(account.windows, windows) {
                    let context = "\(name) \(account.key) \(window.rawLabel)"
                    XCTAssertEqual(window.kind.rawValue, expectedWindow["kind"] as? String, context)
                    XCTAssertEqual(window.metric?.rawValue ?? "", expectedWindow["metric"] as? String, context)
                    XCTAssertEqual(window.rawLabel, expectedWindow["label"] as? String, context)
                    if let remaining = Self.double(expectedWindow["remainingPercent"]) {
                        XCTAssertEqual(try XCTUnwrap(window.remainingPercent, context), remaining, accuracy: 1e-9, context)
                    } else {
                        XCTAssertNil(window.remainingPercent, context)
                    }
                    XCTAssertEqual(window.remaining, Self.double(expectedWindow["remaining"]), context)
                    XCTAssertEqual(window.currency ?? "", expectedWindow["currency"] as? String, context)
                    XCTAssertEqual(window.planExpired ? "expired" : "", expectedWindow["planStatus"] as? String, context)
                    XCTAssertEqual(window.showMeter, expectedWindow["showMeter"] as? Bool, context)
                }
            }
        }
        try check(LimitPresentation.homeAccounts(inputs, limit: 3), try XCTUnwrap(home["remaining3"] as? [[String: Any]]), "remaining3")
        try check(LimitPresentation.homeAccounts(inputs, limit: 12), try XCTUnwrap(home["remaining12"] as? [[String: Any]]), "remaining12")
        let configured = try XCTUnwrap(home["configured12Hidden"] as? [String: Any])
        let hidden = try XCTUnwrap(configured["hidden"] as? [String: [String]])
        try check(
            LimitPresentation.homeAccounts(inputs, limit: 12, sort: .configured) { provider, window in
                LimitUsageItems.isHidden(window, provider: provider, hiddenItems: hidden)
            },
            try XCTUnwrap(configured["rows"] as? [[String: Any]]),
            "configured12Hidden"
        )
    }

    // MARK: Desktop vectors

    func testStatusMatrixVectors() throws {
        let vectors = try Self.vectors()
        let statuses: [LimitStatus] = [.ok, .disabled, .notConfigured, .unauthorized, .rateLimited, .sourceRateLimited, .unavailable, .error]
        let lines = try XCTUnwrap(vectors["statusMatrix"] as? [String])
        XCTAssertEqual(lines.count, VendorCatalog.limitProviders.count * 3)
        for line in lines {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let expected = parts[2].split(separator: ";").map(String.init)
            XCTAssertEqual(expected.count, statuses.count, line)
            for (status, value) in zip(statuses, expected) {
                let provider = LimitProvider(id: "x", provider: parts[0], status: status, source: parts[1].isEmpty ? nil : parts[1])
                let chip = LimitPresentation.statusChip(provider)
                XCTAssertEqual("\(chip.label.desktopText):\(chip.tone.rawValue)", value, "\(parts[0]) \(parts[1]) \(status)")
            }
        }
        let stale = try XCTUnwrap(vectors["staleStatus"] as? [String])
        let staleChip = LimitPresentation.statusChip(LimitProvider(id: "x", provider: stale[0], status: .ok, isStale: true))
        XCTAssertEqual(staleChip.label.desktopText, stale[3])
        XCTAssertEqual(staleChip.tone, .stale)
        XCTAssertFalse(staleChip.showsLiveDot)
    }

    func testFreshnessAndPlanLabelVectors() throws {
        let vectors = try Self.vectors()
        for entry in try XCTUnwrap(vectors["ages"] as? [[String: Any]]) {
            let ms = try XCTUnwrap(Self.double(entry["ms"]))
            let provider = LimitProvider(id: "x", provider: "claude", updatedAt: Self.now.addingTimeInterval(-ms / 1000))
            XCTAssertEqual(LimitPresentation.freshness(provider, now: Self.now).desktopText, entry["text"] as? String, "\(ms)")
        }
        XCTAssertEqual(LimitPresentation.freshness(LimitProvider(id: "x", provider: "claude"), now: Self.now), .unknown)
        XCTAssertEqual(LimitPresentation.freshness(LimitProvider(id: "x", provider: "claude", isStale: true), now: Self.now).desktopText, "Stale")
        for entry in try XCTUnwrap(vectors["planLabels"] as? [[String: String]]) {
            XCTAssertEqual(
                LimitPresentation.planDisplayLabel(provider: try XCTUnwrap(entry["provider"]), label: try XCTUnwrap(entry["label"])),
                entry["text"], "\(entry)"
            )
        }
    }

    func testLimitsCardVectors() throws {
        let vectors = try Self.vectors()
        let providers = try Self.allProviders()
        let devices = try Self.stats().devices
        let expectedRows = try XCTUnwrap(vectors["providers"] as? [[String: Any]])
        XCTAssertEqual(providers.count, expectedRows.count)
        var matchedRows = 0
        for (provider, expected) in zip(providers, expectedRows) {
            let name = "\(provider.provider) \(expected["accountKey"] as? String ?? "")"
            XCTAssertEqual(provider.provider, expected["provider"] as? String)

            // Rows drawn from a window: name, value, meter, boundary, detail.
            let windows = LimitPresentation.visibleWindows(provider, prefs: .defaults)
            for (rows, showUsed) in [(expected["rowsLeft"], false), (expected["rowsUsed"], true)] {
                for row in rows as? [[String: Any]] ?? [] {
                    guard let item = row["item"] as? String,
                          let window = windows.first(where: { provider.usageItemID(for: $0) == item }) else { continue }
                    // Balance and spend rows the card builds from the balance block.
                    if item == "spend" && !(window.isSpend || LimitPresentation.isLegacySpendWindow(window)) { continue }
                    matchedRows += 1
                    let context = "\(name) \(item) used=\(showUsed)"
                    if !showUsed, !LimitUsageItems.fixedItemIDs.contains(item) {
                        XCTAssertEqual(LimitPresentation.windowName(window, provider: provider).desktopText, row["itemLabel"] as? String, context)
                    }
                    XCTAssertEqual(LimitPresentation.headline(window: window, provider: provider, showUsed: showUsed).desktopText,
                                   row["value"] as? String ?? "", context)
                    let fill = LimitPresentation.meterFill(window: window, provider: provider, showUsed: showUsed)
                    if row["note"] as? Bool == true {
                        XCTAssertNil(fill.fraction, context)
                    } else {
                        XCTAssertEqual(try XCTUnwrap(fill.fraction, context), try XCTUnwrap(Self.double(row["scale"])), accuracy: 1e-9, context)
                        if let tone = Self.double(row["tone"]) { XCTAssertEqual(fill.toneOpacity, tone, context) }
                    }
                    if !showUsed {
                        XCTAssertEqual(Self.boundaryText(LimitPresentation.boundaryLine(window: window, now: Self.now)),
                                       row["reset"] as? String ?? "", context)
                    }
                    XCTAssertEqual(
                        LimitPresentation.windowDetail(window: window, provider: provider, showUsed: showUsed, now: Self.now)?.desktopText() ?? "",
                        row["detail"] as? String ?? "", context
                    )
                }
            }

            // windowText.js details by window index (the money/balance details are covered above).
            for (key, showUsed) in [("detailsLeft", false), ("detailsUsed", true)] {
                let details = expected[key] as? [String: String] ?? [:]
                for (index, window) in provider.windows.enumerated() where !window.isCredits {
                    XCTAssertEqual(
                        LimitPresentation.windowDetail(window: window, provider: provider, showUsed: showUsed, now: Self.now)?.desktopText(),
                        details[String(index)], "\(name) \(key) \(index)"
                    )
                }
            }

            let items = LimitPresentation.usageItems(for: provider).map { [$0.id, $0.label.desktopText] }
            let expectedItems = (expected["usageItems"] as? [[String: String]] ?? []).map { [$0["id"] ?? "", $0["label"] ?? ""] }
            XCTAssertEqual(items, expectedItems, name)

            assertPlanCell(LimitPresentation.planCell(provider, grouped: false), expected["accountPlanSolo"] as? String ?? "", "\(name) solo")
            assertPlanCell(LimitPresentation.planCell(provider, grouped: true), expected["accountPlanGrouped"] as? String ?? "", "\(name) grouped")
            if let plan = expected["planCell"] as? String, !Self.pageStatusWords.contains(plan),
               LimitPresentation.thirdPartyPlan(provider) == nil {
                XCTAssertEqual(LimitPresentation.planLabel(provider) ?? "", plan, name)
            }

            let status = try XCTUnwrap(expected["status"] as? [String])
            XCTAssertEqual(LimitPresentation.statusChip(provider).label.desktopText, status[0], name)
            XCTAssertEqual(LimitPresentation.statusChip(provider).tone.rawValue, status[1], name)
            XCTAssertEqual(LimitPresentation.sourceKind(provider)?.desktopText ?? "", expected["sourceLabel"] as? String ?? "", name)
            XCTAssertEqual(LimitPresentation.metaLine(provider, now: Self.now, showSource: false, devices: devices)?.desktopText,
                           expected["metaPlain"] as? String, name)
            XCTAssertEqual(LimitPresentation.metaLine(provider, now: Self.now, showSource: true, devices: devices)?.desktopText,
                           expected["metaSource"] as? String, name)

            let compact = LimitPresentation.compactWindows(provider, windows: provider.windows)
            let compactIndexes = compact.map { window in provider.windows.firstIndex { $0.id == window.id } ?? -2 }
            let expectedIndexes = expected["compact"] as? [Int] ?? []
            XCTAssertEqual(compactIndexes.count, expectedIndexes.count, name)
            for (actual, desktop) in zip(compactIndexes, expectedIndexes) where desktop >= 0 {
                XCTAssertEqual(actual, desktop, name)
            }

            if let names = expected["codexNames"] as? [Any] {
                for (window, desktop) in zip(provider.windows, names) {
                    guard let desktop = desktop as? String else { continue }
                    XCTAssertEqual(LimitPresentation.windowName(window, provider: provider).desktopText, desktop, name)
                }
            }
        }
        XCTAssertGreaterThan(matchedRows, 100)
    }

    func testAccountTitleVectors() throws {
        let providers = try Self.allProviders()
        let titles = try XCTUnwrap(try Self.vectors()["titles"] as? [[Any]])
        XCTAssertFalse(titles.isEmpty)
        for entry in titles {
            let id = try XCTUnwrap(entry[0] as? String)
            let index = try XCTUnwrap(entry[2] as? Int)
            let mask = try XCTUnwrap(entry[3] as? Bool)
            let peers = providers.filter { $0.provider == id }
            let title = LimitPresentation.accountTitle(peers[index], peers: peers, index: index, mask: mask)
            XCTAssertEqual(Self.normalizedTitle(title.desktopText), Self.normalizedTitle(try XCTUnwrap(entry[4] as? String)), "\(entry)")
        }
    }

    func testHomeRowVectors() throws {
        let providers = try Self.allProviders()
        let scenarios = try XCTUnwrap(try Self.vectors()["home"] as? [[String: Any]])
        XCTAssertEqual(scenarios.count, 5)
        for scenario in scenarios {
            let name = try XCTUnwrap(scenario["name"] as? String)
            let overrides = try XCTUnwrap(scenario["prefs"] as? [String: Any])
            var prefs = DisplayPreferences.defaults
            prefs.homeLimitAccountCount = 12
            prefs.homeLimitDisplayMode = .bars
            prefs.showHomeLimitBars = true
            if let value = overrides["homeLimitAccountCount"] as? Int { prefs.homeLimitAccountCount = value }
            if let value = overrides["showLimitUsed"] as? Bool { prefs.showLimitUsed = value }
            if let value = overrides["homeLimitProviderOrder"] as? [String] { prefs.homeLimitProviderOrder = value }
            if let value = overrides["hiddenHomeLimitProviders"] as? [String] { prefs.hiddenHomeLimitProviders = value }
            if let value = overrides["limitProviderHiddenItems"] as? [String: [String]] { prefs.limitProviderHiddenItems = value }
            if let value = overrides["showToolIcons"] as? Bool { prefs.showToolIcons = value }
            if let value = overrides["maskLimitAccountEmails"] as? Bool { prefs.maskLimitAccountEmails = value }
            if let value = overrides["limitProviderOrder"] as? [String] { prefs.limitProviderOrder = value }
            if let value = overrides["showHomeLimitProviderNames"] as? Bool { prefs.showHomeLimitProviderNames = value }

            let rows = LimitPresentation.homeRows(providers, prefs: prefs)
            let expected = try XCTUnwrap(scenario["rows"] as? [[String: Any]])
            XCTAssertEqual(rows.map(\.id), expected.map { $0["key"] as? String ?? "" }, name)
            for (row, value) in zip(rows, expected) {
                let context = "\(name) \(row.id)"
                XCTAssertEqual(row.providerID, value["providerId"] as? String, context)
                XCTAssertEqual(row.iconID, value["iconId"] as? String, context)
                XCTAssertEqual(Self.normalizedTitle(row.name.desktopText), Self.normalizedTitle(value["name"] as? String ?? ""), context)
                assertPlanCell(row.plan, value["plan"] as? String ?? "", context)
                XCTAssertEqual(row.lowestRemaining, try XCTUnwrap(Self.double(value["lowestRemaining"])), accuracy: 1e-9, context)
                let windows = try XCTUnwrap(value["windows"] as? [[String: Any]])
                XCTAssertEqual(row.windows.count, windows.count, context)
                for (window, expectedWindow) in zip(row.windows, windows) {
                    let label = expectedWindow["label"] as? String ?? ""
                    // The desktop prints an unlabelled billing window's raw kind
                    // ("billing"); iOS names it like the other kinds.
                    if label == "billing" {
                        XCTAssertEqual(window.label, .kind(.billing), context)
                    } else {
                        XCTAssertEqual(window.label.desktopText, label, context)
                    }
                    XCTAssertEqual(LimitPresentation.homeValue(window, showUsed: prefs.showLimitUsed).desktopText,
                                   expectedWindow["value"] as? String, "\(context) \(label)")
                    XCTAssertEqual(LimitPresentation.homeSeverity(remainingPercent: window.remainingPercent)?.rawValue ?? "",
                                   expectedWindow["severity"] as? String, "\(context) \(label)")
                    let meter = LimitPresentation.homeMeter(window, showUsed: prefs.showLimitUsed)
                    if let expectedMeter = expectedWindow["meter"] as? [String: Any] {
                        XCTAssertEqual(try XCTUnwrap(meter?.percent, context), try XCTUnwrap(Self.double(expectedMeter["fill"])), accuracy: 1e-9, context)
                        XCTAssertEqual(meter?.toneOpacity, Self.double(expectedMeter["tone"]), context)
                    } else {
                        XCTAssertNil(meter, "\(context) \(label)")
                    }
                    var reset: String
                    switch LimitPresentation.homeBoundaryLine(window, now: Self.now) {
                    case .boundary(let boundary)?: reset = boundary.desktopText
                    case .description(let text)?: reset = "Reset \(text)"
                    case nil: reset = ""
                    }
                    if !reset.isEmpty, let period = window.periodLabel { reset = "\(period.desktopText) · \(reset)" }
                    XCTAssertEqual(reset, expectedWindow["reset"] as? String, "\(context) \(label)")
                }
            }
        }
    }

    func testHomeProviderOrderVectors() throws {
        for entry in try XCTUnwrap(try Self.vectors()["homeOrders"] as? [[String: [String]]]) {
            XCTAssertEqual(LimitPresentation.normalizedHomeProviderOrder(try XCTUnwrap(entry["order"])), entry["normalized"], "\(entry)")
        }
        var prefs = DisplayPreferences.defaults
        prefs.limitProviderOrder = ["mimo"]
        XCTAssertEqual(LimitPresentation.homeProviderOrder(prefs), ["mimo"])
        XCTAssertEqual(LimitPresentation.homeSort(prefs), .remaining)
        prefs.homeLimitProviderOrder = ["zed"]
        XCTAssertEqual(LimitPresentation.homeProviderOrder(prefs), ["zed"])
        XCTAssertEqual(LimitPresentation.homeSort(prefs), .configured)
        prefs.homeLimitProviderOrder = LimitPresentation.catalogProviderIDs
        XCTAssertEqual(LimitPresentation.homeProviderOrder(prefs), ["mimo"])
        XCTAssertEqual(LimitPresentation.homeSort(prefs), .remaining)
    }

    // MARK: Meters, rings and severity

    func testMeterModesAndTones() throws {
        let percent = LimitWindow(kind: .session, usedPercent: 30, remainingPercent: 70)
        let codex = LimitProvider(id: "codex-1", provider: "codex", windows: [percent])
        let left = LimitPresentation.meterFill(window: percent, provider: codex, showUsed: false)
        XCTAssertEqual(left, MeterFill(fraction: 0.7, percent: 70, mode: .remaining, toneOpacity: 0.95))
        let used = LimitPresentation.meterFill(window: percent, provider: codex, showUsed: true)
        XCTAssertEqual(used, MeterFill(fraction: 0.3, percent: 30, mode: .used, toneOpacity: 0.95))
        XCTAssertEqual(LimitPresentation.headline(window: percent, provider: codex, showUsed: true), .percent(30, .used))

        // Money windows stay in remaining mode; a meter-less window is a note row.
        let credits = LimitWindow(kind: .billing, label: "Credits", metric: .credits, usedPercent: 25, remainingPercent: 75, remaining: 7.5, currency: "USD")
        let openrouter = LimitProvider(id: "or-1", provider: "openrouter", windows: [credits])
        let money = LimitPresentation.meterFill(window: credits, provider: openrouter, showUsed: true)
        XCTAssertEqual(money.mode, .remaining)
        XCTAssertEqual(money.fraction, 0.75)
        XCTAssertEqual(LimitPresentation.headline(window: credits, provider: openrouter, showUsed: true), .money(7.5, currency: "USD"))
        let spend = LimitWindow(kind: .billing, label: "Usage credits", metric: .spend, usedPercent: 40, remainingPercent: 60, used: 8, limit: 20, currency: "USD")
        let claude = LimitProvider(id: "claude-1", provider: "claude", windows: [spend])
        XCTAssertEqual(LimitPresentation.meterFill(window: spend, provider: claude, showUsed: true).mode, .remaining)
        XCTAssertEqual(LimitPresentation.meterFill(window: spend, provider: claude, showUsed: true).toneOpacity, 0.5)
        XCTAssertEqual(LimitPresentation.headline(window: spend, provider: claude, showUsed: false).desktopText, "$8.00 / $20.00")
        let note = LimitWindow(kind: .billing, label: "Overage", used: 2, remaining: 0.5, showMeter: false)
        let kiro = LimitProvider(id: "kiro-1", provider: "kiro", windows: [note])
        XCTAssertTrue(LimitPresentation.meterFill(window: note, provider: kiro, showUsed: false).isNoteRow)
        XCTAssertEqual(LimitPresentation.headline(window: note, provider: kiro, showUsed: false).desktopText, "2 credits · $0.50")
        // A window with no percentage at all draws no meter (the desktop paints "0% left").
        let bare = LimitWindow(kind: .weekly)
        XCTAssertNil(LimitPresentation.meterFill(window: bare, provider: codex, showUsed: false).fraction)
        XCTAssertEqual(LimitPresentation.headline(window: bare, provider: codex, showUsed: false), .none)
        XCTAssertEqual(LimitPresentation.toneOpacity(window: LimitWindow(kind: .weekly, isAdditional: true), provider: codex), 0.78)
    }

    func testRingsAlwaysFillByWhatIsLeft() {
        let window = LimitWindow(kind: .weekly, usedPercent: 80, remainingPercent: 20)
        let provider = LimitProvider(id: "claude-1", provider: "claude", windows: [window])
        let ring = LimitPresentation.gaugeFill(window: window, provider: provider, showUsed: true)
        XCTAssertEqual(ring.remainingFraction, 0.2)
        XCTAssertEqual(ring.percent, 80)
        XCTAssertEqual(ring.mode, .used)
        let left = LimitPresentation.gaugeFill(window: window, provider: provider, showUsed: false)
        XCTAssertEqual(left.remainingFraction, 0.2)
        XCTAssertEqual(left.percent, 20)
        // A balance is metered against the month's funds: 30 / (30 + 10).
        let credits = LimitWindow(kind: .billing, metric: .credits, remaining: 30, currency: "CNY")
        let deepseek = LimitProvider(id: "ds-1", provider: "deepseek", windows: [credits], balance: LimitBalance(amount: 30, currency: "CNY", monthSpend: 10))
        let balanceRing = LimitPresentation.gaugeFill(window: credits, provider: deepseek, showUsed: true)
        XCTAssertEqual(balanceRing.remainingFraction, 0.75)
        XCTAssertEqual(balanceRing.mode, .remaining)
        XCTAssertNil(LimitPresentation.gaugeFill(window: LimitWindow(kind: .weekly, showMeter: false), provider: provider, showUsed: false).remainingFraction)
    }

    func testHomeSeverityKeysOnRemaining() {
        XCTAssertEqual(LimitPresentation.homeSeverity(remainingPercent: 0), .critical)
        XCTAssertEqual(LimitPresentation.homeSeverity(remainingPercent: 19.99), .critical)
        XCTAssertEqual(LimitPresentation.homeSeverity(remainingPercent: 20), .low)
        XCTAssertEqual(LimitPresentation.homeSeverity(remainingPercent: 49.9), .low)
        XCTAssertNil(LimitPresentation.homeSeverity(remainingPercent: 50))
        XCTAssertNil(LimitPresentation.homeSeverity(remainingPercent: nil))
        XCTAssertEqual(LimitPresentation.homeSeverity(remainingPercent: -5), .critical)
    }

    // MARK: Balance, reset credits, usage summaries

    func testBalanceRows() throws {
        let rows = try Self.stats().limits
        let deepseek = try XCTUnwrap(rows.first { $0.provider == "deepseek" })
        XCTAssertEqual(LimitPresentation.balanceRows(deepseek), [
            .gift(amount: 10, currency: "CNY"),
            .cash(amount: 76.42, currency: "CNY"),
            .spend(period: .today, amount: 1.2, currency: "CNY"),
            .spend(period: .month, amount: 23.6, currency: "CNY"),
            .spend(period: .allTime, amount: 140.1, currency: "CNY"),
            .trackingSince(Self.date("2026-08-26T16:30:00.000Z"), partialMonth: true)
        ])
        XCTAssertEqual(LimitPresentation.spendSummary(try XCTUnwrap(deepseek.balance)), [.today, .month])
        let openrouter = try XCTUnwrap(rows.first { $0.provider == "openrouter" })
        XCTAssertEqual(LimitPresentation.balanceRows(openrouter), [
            .spend(period: .today, amount: 0.4, currency: "USD"),
            .spend(period: .week, amount: 2.1, currency: "USD"),
            .spend(period: .month, amount: 6.2, currency: "USD"),
            .spend(period: .allTime, amount: 18.75, currency: "USD"),
            .trackingSince(Self.date("2026-08-11T16:30:00.000Z"), partialMonth: false),
            .requests(412)
        ])
        let typesafe = try XCTUnwrap(rows.first { $0.provider == "typesafe" })
        XCTAssertEqual(LimitPresentation.balanceRows(typesafe), [
            .tranche(amount: 25, currency: "USD", expiresAt: Self.date("2026-10-30T16:30:00.000Z")),
            .tranche(amount: 12.5, currency: "USD", expiresAt: Self.date("2026-12-29T16:30:00.000Z")),
            .tranche(amount: 5, currency: "USD", expiresAt: nil),
            .expires(Self.date("2026-10-30T16:30:00.000Z"))
        ])
        // A balance with no credits window shows its own Balance row; hidden items drop rows.
        let claude = LimitProvider(id: "claude-1", provider: "claude", balance: LimitBalance(amount: 12, currency: "USD", monthSpend: 3))
        XCTAssertEqual(LimitPresentation.balanceRows(claude), [.balance(amount: 12, currency: "USD"), .spend(period: .month, amount: 3, currency: "USD")])
        XCTAssertEqual(LimitPresentation.balanceRows(claude, hiddenItems: ["claude": ["credits"]]), [.spend(period: .month, amount: 3, currency: "USD")])
        XCTAssertEqual(LimitPresentation.balanceRows(claude, hiddenItems: ["claude": ["credits", "spend"]]), [])
        let summary = LimitBalance(todaySpend: nil, weekSpend: 1, monthSpend: nil, allTimeSpend: 2)
        XCTAssertEqual(LimitPresentation.spendSummary(summary), [.week, .allTime])
    }

    func testResetCreditLines() throws {
        let rows = try Self.stats().limits
        let codex = try XCTUnwrap(rows.first { $0.provider == "codex" })
        let codexLine = try XCTUnwrap(LimitPresentation.resetCredits(codex, now: Self.now))
        XCTAssertEqual(codexLine.count, 3)
        XCTAssertEqual(codexLine.desktopText, "3 resets 2d 0h · 9d 0h · 40d 0h")
        XCTAssertEqual(codexLine.overflow, 0)
        XCTAssertTrue(codexLine.grants.isEmpty)
        XCTAssertNil(LimitPresentation.resetCredits(codex, now: Self.now, hiddenItems: ["codex": ["resets"]]))
        // After the first expiry it reads "now".
        let later = try XCTUnwrap(LimitPresentation.resetCredits(codex, now: Self.date("2026-10-12T16:30:00.000Z")))
        XCTAssertEqual(later.expiries.first, .now)

        let claude = try XCTUnwrap(rows.first { $0.provider == "claude" })
        let claudeLine = try XCTUnwrap(LimitPresentation.resetCredits(claude, now: Self.now))
        XCTAssertEqual(claudeLine.desktopText, "2 resets 3d 0h · 17d 0h")
        XCTAssertEqual(claudeLine.grants, [
            LimitPresentation.ResetGrantRow(
                label: "Outage credit", resetsLeft: 1, endsAt: Self.date("2026-10-13T16:30:00.000Z"),
                remaining: .duration(LimitPresentation.DurationParts(totalMinutes: 3 * 1440)),
                clears: [.other("session"), .other("weekly")], usability: .atLimitOnly
            ),
            LimitPresentation.ResetGrantRow(
                label: "Welcome back", resetsLeft: 1, endsAt: Self.date("2026-10-27T16:30:00.000Z"),
                remaining: .paused, clears: [.other("session")], usability: .notRightNow
            )
        ])

        let many = LimitProvider(id: "codex-9", provider: "codex", resetCredits: LimitResetCredits(
            availableCount: 5,
            expirations: (1...5).map { Self.now.addingTimeInterval(Double($0) * 3600) },
            grants: [LimitResetGrant(clears: ["five_hour", "seven_day", "seven_day_overage_included", "seven_day_opus", "odd_new_window", "__"])]
        ))
        let line = try XCTUnwrap(LimitPresentation.resetCredits(many, now: Self.now))
        XCTAssertEqual(line.desktopText, "5 resets 1h 0m · 2h 0m · 3h 0m · +2")
        XCTAssertEqual(line.grants.first?.clears, [.session, .weekly, .opusWeekly, .other("odd new window")])
        XCTAssertNil(line.grants.first?.remaining)
        XCTAssertNil(LimitPresentation.resetCredits(LimitProvider(id: "c", provider: "codex", resetCredits: LimitResetCredits(availableCount: 0)), now: Self.now))
        XCTAssertEqual(LimitPresentation.ResetClearLabel(key: "seven_day_overage_included"), .fableWeekly)
    }

    func testUsageSummaryRows() throws {
        let rows = try Self.stats().limits
        let relay = try XCTUnwrap(rows.first { $0.provider == "thirdparty" })
        XCTAssertEqual(LimitPresentation.usageSummaryRows(relay), [
            .todayTokens(2_400_000),
            .weekTokens(9_100_000),
            .requests(128),
            .totalTokens(2_400_000),
            .inputTokens(310_000),
            .outputTokens(92_000),
            .cacheTokens(1_998_000),
            .averageDuration(2350),
            .standardCost(3.21, currency: "USD"),
            .actualCost(1.05, currency: "USD")
        ])
        XCTAssertEqual(LimitPresentation.usageSummaryRows(relay, hiddenItems: ["thirdparty": ["spend"]]), [])
        XCTAssertEqual(LimitPresentation.averageDurationDesktopText(2350), "2.4 s")
        XCTAssertEqual(LimitPresentation.averageDurationDesktopText(850.4), "850 ms")
        XCTAssertEqual(LimitPresentation.averageDurationDesktopText(12_345), "12 s")
    }

    // MARK: Provenance, ordering, visible windows

    func testProvenanceAndMeta() throws {
        let stats = try Self.stats()
        let kimi = try XCTUnwrap(stats.limits.first { $0.provider == "kimi" })
        let provenance = try XCTUnwrap(LimitPresentation.provenance(kimi, devices: stats.devices))
        XCTAssertEqual(provenance.deviceID, "old-laptop")
        XCTAssertEqual(provenance.deviceName, stats.devices.first { $0.id == "old-laptop" }?.displayName)
        XCTAssertEqual(provenance.source, .api)
        XCTAssertNil(LimitPresentation.provenance(LimitProvider(id: "x", provider: "claude"), devices: stats.devices))
        let meta = try XCTUnwrap(LimitPresentation.metaLine(kimi, now: Self.now, showSource: true, devices: stats.devices))
        XCTAssertEqual(meta.freshness, .stale(age: .hours(1)))
        XCTAssertNil(meta.source)
        XCTAssertTrue(LimitPresentation.showsMetaLine(kimi))
        let cursor = try XCTUnwrap(stats.limits.first { $0.provider == "cursor" })
        XCTAssertFalse(LimitPresentation.showsMetaLine(cursor))
        XCTAssertNil(LimitPresentation.metaLine(cursor, now: Self.now, showSource: true))
        let antigravity = try XCTUnwrap(stats.limits.first { $0.provider == "antigravity" })
        XCTAssertTrue(LimitPresentation.antigravityNeedsVerification(antigravity))
        XCTAssertFalse(LimitPresentation.antigravityNeedsVerification(cursor))
    }

    func testProviderOrderAndVisibleWindows() throws {
        let rows = try Self.allProviders()
        let ordered = LimitPresentation.ordered(rows, order: ["zed", "codex"])
        XCTAssertEqual(Array(ordered.prefix(4).map(\.provider)), ["zed", "zed", "codex", "codex"])
        // Accounts of one provider stay together in Hub order.
        XCTAssertEqual(ordered.filter { $0.provider == "codex" }.map(\.id), rows.filter { $0.provider == "codex" }.map(\.id))
        let catalog = LimitPresentation.ordered(rows, order: [])
        let catalogIndex = catalog.map { VendorCatalog.limitProviderSortIndex($0.provider) }
        XCTAssertEqual(catalogIndex, catalogIndex.sorted())
        let unknown = LimitPresentation.ordered([LimitProvider(id: "n", provider: "newvendor"), LimitProvider(id: "c", provider: "claude")], order: [])
        XCTAssertEqual(unknown.map(\.provider), ["claude", "newvendor"])

        let codex = try XCTUnwrap(rows.first { $0.provider == "codex" })
        var prefs = DisplayPreferences.defaults
        XCTAssertEqual(LimitPresentation.visibleWindows(codex, prefs: prefs).count, 5)
        prefs.showCodexAdditionalLimits = false
        XCTAssertEqual(LimitPresentation.visibleWindows(codex, prefs: prefs).count, 2)
        prefs.limitProviderHiddenItems = ["codex": [LimitUsageItems.windowKey(codex.windows[0])]]
        XCTAssertEqual(LimitPresentation.visibleWindows(codex, prefs: prefs).map(\.id), [codex.windows[1].id])
        XCTAssertEqual(LimitPresentation.usageItems(for: codex, showCodexAdditional: false).map(\.id),
                       [LimitUsageItems.windowKey(codex.windows[0]), LimitUsageItems.windowKey(codex.windows[1]), "resets"])

        // MiMo's lapsed plan is a meter-less "Expired" row before the balance.
        let mimo = try XCTUnwrap(rows.first { $0.provider == "mimo" })
        let mimoWindows = LimitPresentation.visibleWindows(mimo, prefs: .defaults)
        XCTAssertEqual(mimoWindows.map(\.label), ["Token Plan", "Balance"])
        XCTAssertEqual(LimitPresentation.headline(window: mimoWindows[0], provider: mimo, showUsed: false), .planExpired)
        XCTAssertTrue(LimitPresentation.meterFill(window: mimoWindows[0], provider: mimo, showUsed: false).isNoteRow)
        var hidePlan = DisplayPreferences.defaults
        hidePlan.limitProviderHiddenItems = ["mimo": [LimitUsageItems.windowKey(LimitUsageItems.KeyFields(kind: "billing", label: "Token Plan"))]]
        XCTAssertEqual(LimitPresentation.visibleWindows(mimo, prefs: hidePlan).map(\.label), ["Balance"])
    }

    func testAccountTitlesAndMasking() {
        XCTAssertEqual(LimitPresentation.maskedEmail(" dev@example.com "), "d***v@example.com")
        XCTAssertEqual(LimitPresentation.maskedEmail("z@example.com"), "z***@example.com")
        XCTAssertEqual(LimitPresentation.maskedEmail("@example.com"), "@example.com")
        XCTAssertEqual(LimitPresentation.maskedEmail("name"), "name")
        // Anonymous duplicates fall back to the row number.
        var rows = [
            LimitProvider(id: "claude-anonymous", provider: "claude", accountEmail: "a@b.co"),
            LimitProvider(id: "claude-anonymous", provider: "claude", accountEmail: "a@b.co")
        ]
        HubStats.assignUniqueIDs(&rows)
        XCTAssertEqual(LimitPresentation.accountTitle(rows[1], peers: rows, index: 1, mask: false).desktopText, "a@b.co · #2")
        XCTAssertEqual(LimitPresentation.accountTitle(rows[0], peers: rows, index: 0, mask: false).parts, [.text("a@b.co"), .disambiguator("1")])
        let personal = LimitProvider(id: "codex-1", provider: "codex", workspaceKind: "personal")
        XCTAssertEqual(LimitPresentation.accountTitle(personal, peers: [personal], index: 0, mask: true).parts, [.personalWorkspace])
        let nameless = LimitProvider(id: "kimi-1", provider: "kimi")
        XCTAssertTrue(LimitPresentation.accountTitle(nameless, peers: [nameless], index: 2, mask: false).isFallback)
        XCTAssertNil(LimitPresentation.accountTitle(nameless, mask: false))
        XCTAssertEqual(LimitPresentation.accountTitle(LimitProvider(id: "c", provider: "claude", accountEmail: "dev@example.com"), mask: true), "d***v@example.com")
        let environment = LimitProvider(id: "or-1", provider: "openrouter", accountName: "environment")
        XCTAssertEqual(LimitPresentation.accountTitle(environment, peers: [environment], index: 0, mask: false).parts, [.environment])
    }

    func testStatusLabelKeys() {
        XCTAssertEqual(LimitStatusLabel.verifyInAntigravity.desktopKey, "settings.antigravity.verificationRequired")
        XCTAssertEqual(LimitStatusLabel.encryptedByApp.desktopKey, "settings.limits.status.appSessionEncrypted")
        XCTAssertEqual(LimitStatusLabel.runKiroLogin.desktopKey, "settings.limits.status.runKiroLogin")
        XCTAssertEqual(LimitPresentation.StatusChip.noSyncedData.tone, .sync)
        for label in LimitStatusLabel.allCases { XCTAssertFalse(label.desktopText.isEmpty) }
    }

    func testWindowNamesAndPeriods() {
        XCTAssertEqual(LimitPeriodName.of(LimitWindow(kind: .weekly, windowMinutes: 300)), .named(.fiveHour))
        XCTAssertEqual(LimitPeriodName.of(LimitWindow(kind: .weekly, windowMinutes: 20160)).desktopText, "2-week")
        XCTAssertEqual(LimitPeriodName.of(LimitWindow(kind: .weekly, windowMinutes: 4320)).desktopText, "3-day")
        XCTAssertEqual(LimitPeriodName.of(LimitWindow(kind: .weekly, windowMinutes: 120)).desktopText, "2-hour")
        XCTAssertEqual(LimitPeriodName.of(LimitWindow(kind: .weekly, windowMinutes: 90)).desktopText, "90-minute")
        XCTAssertEqual(LimitPeriodName.of(LimitWindow(kind: .billing, windowMinutes: 43200)), .named(.monthly))
        XCTAssertEqual(LimitPeriodName.of(LimitWindow(kind: .daily)), .named(.daily))
        XCTAssertEqual(LimitPeriodName.of(LimitWindow(kind: .session, windowMinutes: 2.5)), .named(.session))
        XCTAssertEqual(
            LimitWindowName.group(name: "Gemini Pro", period: .fiveHour).usageItemLabel,
            .additional(limitID: "Gemini Pro", title: .kind(.fiveHour))
        )
    }

    /// The checklist keeps the desktop's flattened English label and carries
    /// the structured window name beside it, so targets can word an odd
    /// cadence in the UI language.
    func testUsageItemsCarryTheStructuredWindowName() {
        let codex = LimitProvider(
            id: "codex-a",
            provider: "codex",
            windows: [
                LimitWindow(kind: .session, windowMinutes: 300, limitId: "codex"),
                LimitWindow(kind: .session, label: "Spark", windowMinutes: 180, isAdditional: true, limitId: "codex_spark"),
                LimitWindow(kind: .weekly, label: "Spark", windowMinutes: 10080, isAdditional: true, limitId: "codex_spark")
            ],
            balance: LimitBalance(amount: 5, currency: "USD")
        )
        let items = LimitPresentation.usageItems(for: codex)
        XCTAssertEqual(items.count, 4, "\(items)")
        XCTAssertEqual(items[0].windowName, .title(.kind(.session)))
        XCTAssertEqual(items[1].label, .additional(limitID: "Spark", title: .label("3-hour")), "desktop wording kept")
        XCTAssertEqual(items[1].windowName, .pool(name: "Spark", period: .hours(3)))
        XCTAssertEqual(items[2].windowName, .pool(name: "Spark", period: .named(.weekly)))
        XCTAssertEqual(items[3].id, LimitUsageFixedItem.credits.rawValue)
        XCTAssertNil(items[3].windowName, "fixed rows have no window name")
        XCTAssertEqual(LimitUsageItem(id: "spend", label: .fixed(.spend)).windowName, nil)
    }
}

// Generated by `$SP/p2-limpres/gen.js` (desktop JS at the v2 capture clock)
// and compacted by `compact.py`; regenerate rather than edit.
private let vectorsJSON = ##"""
{
"now": "2026-10-10T16:30:00.000Z",
"synthetic": [
{"provider":"codex","accountKey":"sha256:c0dexa11","accountEmail":"dev@example.com","workspaceKind":"personal","status":"ok","source":"rpc","sourceDetail":"cli","updatedAt":"2026-10-10T16:27:00.000Z","windows":[{"kind":"session","limitId":"codex","usedPercent":82,"remainingPercent":18,"resetsAt":"2026-10-10T17:40:00.000Z","windowMinutes":300},{"kind":"weekly","limitId":"codex","usedPercent":40,"remainingPercent":60,"resetsAt":"2026-10-12T18:30:00.000Z","windowMinutes":10080},{"kind":"session","limitId":"codex_bengalfox","additional":true,"label":"GPT-5.3-Codex-Spark","usedPercent":10,"remainingPercent":90,"windowMinutes":300},{"kind":"weekly","limitId":"codex_bengalfox","additional":true,"label":"GPT-5.3-Codex-Spark","usedPercent":20,"remainingPercent":80,"windowMinutes":10080},{"kind":"weekly","limitId":"codex_reserve","additional":true,"label":"gpt-reserve","usedPercent":30,"remainingPercent":70,"windowMinutes":20160}],"sourceDeviceId":"build-box"},
{"provider":"codex","accountKey":"sha256:c0dexb22","accountName":"Acme Team","accountEmail":"dev@example.com","status":"ok","source":"rpc","sourceDetail":"managed","updatedAt":"2026-10-10T16:29:00.000Z","windows":[{"kind":"session","limitId":"codex","usedPercent":5,"remainingPercent":95,"windowMinutes":300}]},
{"provider":"codex","accountKey":"sha256:c0dexc33","accountEmail":"dav@example.com","status":"rateLimited","source":"rpc","sourceDetail":"unknown","updatedAt":"2026-10-10T15:40:00.000Z","windows":[{"kind":"weekly","limitId":"codex","usedPercent":97,"remainingPercent":3,"windowMinutes":10080}],"stale":true},
{"provider":"codex","status":"unauthorized","source":"rpc"},
{"provider":"claude","accountKey":"sha256:fixtureclaudeaaaa","planLabel":"pro","accountEmail":"pat@example.com","status":"ok","source":"oauth","updatedAt":"2026-10-10T16:28:00.000Z","windows":[{"kind":"session","usedPercent":12,"remainingPercent":88},{"kind":"weekly","usedPercent":55,"remainingPercent":45}]},
{"provider":"claude","accountKey":"sha256:fixtureclaudebbbb","accountEmail":"pat@example.com","status":"ok","source":"cli","updatedAt":"2026-10-10T16:28:00.000Z","windows":[{"kind":"session","usedPercent":99,"remainingPercent":1}]},
{"provider":"opencode","accountKey":"sha256:open1","accountLabel":"Work profile","status":"ok","source":"web","updatedAt":"2026-10-10T16:26:00.000Z","windows":[{"kind":"session","used":4,"limit":12,"usedPercent":33,"remainingPercent":67},{"kind":"billing","usedPercent":10,"remainingPercent":90},{"kind":"billing","metric":"credits","label":"Balance","remaining":7.25,"currency":"USD"}]},
{"provider":"opencode","accountKey":"sha256:open2","accountLabel":"Go","accountName":"Side","status":"ok","source":"web","updatedAt":"2026-10-10T16:26:00.000Z","windows":[{"kind":"weekly","usedPercent":70,"remainingPercent":30}]},
{"provider":"openrouter","accountKey":"sha256:or1","accountLabel":"API key","accountName":"Environment","status":"ok","source":"api","updatedAt":"2026-10-10T16:29:00.000Z","windows":[{"kind":"daily","label":"Key limit","detail":"No limit","showMeter":false},{"kind":"billing","metric":"credits","label":"Credits","limit":10,"remaining":4,"usedPercent":60,"remainingPercent":40,"currency":"USD"}],"balance":{"amount":4,"currency":"USD","todaySpend":0.5,"monthSpend":6}},
{"provider":"openrouter","accountKey":"sha256:or2","accountLabel":"Team key","accountName":"Team key","status":"ok","source":"api","updatedAt":"2026-10-10T16:29:00.000Z","windows":[{"kind":"billing","metric":"credits","label":"Credits","remaining":0,"currency":"USD"}],"balance":{"amount":0,"currency":"USD"}},
{"provider":"volcengine","accountKey":"sha256:volc1","accountLabel":"Coding Plan","status":"ok","source":"api","updatedAt":"2026-10-10T16:24:00.000Z","windows":[{"kind":"session","usedPercent":15,"remainingPercent":85},{"kind":"daily","usedPercent":45,"remainingPercent":55},{"kind":"weekly","usedPercent":60,"remainingPercent":40},{"kind":"billing","usedPercent":75,"remainingPercent":25}]},
{"provider":"volcengine","accountKey":"sha256:volc2","accountLabel":"Agent Plan","status":"rateLimited","source":"cli","updatedAt":"2026-10-10T16:24:00.000Z","windows":[{"kind":"session","usedPercent":91,"remainingPercent":9}]},
{"provider":"mimo","accountKey":"sha256:mimo1","accountLabel":"Console","planLabel":"standard","accountName":"dev MiMo abc1234","accountEmail":"dev@example.com","status":"ok","source":"web","updatedAt":"2026-10-10T16:22:00.000Z","windows":[{"kind":"billing","metric":"credits","label":"Balance","remaining":12,"currency":"CNY"}],"balance":{"amount":12,"currency":"CNY","monthSpend":4,"giftBalance":2,"cashBalance":10,"planUsed":30,"planLimit":100}},
{"provider":"mimo","accountKey":"sha256:mimo2","accountLabel":"Desktop Membership","accountName":"dev MiMo abc1234","accountEmail":"dev@example.com","status":"ok","source":"web","updatedAt":"2026-10-10T16:22:00.000Z","windows":[{"kind":"weekly","label":"Membership","usedPercent":20,"remainingPercent":80}]},
{"provider":"thirdparty","adapterId":"newapi-token","accountKey":"sha256:tp1","accountName":"Relay A","status":"ok","source":"api","updatedAt":"2026-10-10T16:28:00.000Z","windows":[{"kind":"billing","metric":"credits","label":"Quota","limit":30,"remaining":9,"currency":"USD"}],"balance":{"amount":9,"currency":"USD","allTimeSpend":21,"requestCount":77,"quotaGroup":"vip"}},
{"provider":"thirdparty","adapterId":"sub2api","accountKey":"sha256:tp2","accountName":"Relay B","status":"ok","source":"api","updatedAt":"2026-10-10T16:28:00.000Z","windows":[{"kind":"billing","metric":"credits","label":"Balance","remaining":3.5,"currency":"USD"}],"balance":{"amount":3.5,"currency":"USD","monthSpend":10.5}},
{"provider":"thirdparty","accountKey":"sha256:tp3","planLabel":"API key","accountName":"Relay C","status":"unauthorized","source":"api","updatedAt":"2026-10-10T16:28:00.000Z"},
{"provider":"antigravity","accountKey":"sha256:ag1","accountEmail":"dev@example.com","status":"ok","source":"oauth","updatedAt":"2026-10-10T16:29:00.000Z","windows":[{"kind":"session","label":"Gemini Pro 5-hour","usedPercent":30,"remainingPercent":70,"resetsAt":"2026-10-10T18:10:00.000Z"},{"kind":"weekly","label":"Gemini Pro Weekly","usedPercent":85,"remainingPercent":15,"resetsAt":"2026-10-14T03:50:00.000Z"},{"kind":"session","label":"Claude 5-hour","usedPercent":50,"remainingPercent":50,"resetsAt":"2026-10-10T17:00:00.000Z"},{"kind":"session","label":"GPT-OSS 5-hour","usedPercent":5,"remainingPercent":95},{"kind":"weekly","label":"Claude Weekly","usedPercent":60,"remainingPercent":40}]},
{"provider":"zed","accountKey":"sha256:zed1","planLabel":"Zed Student","accountEmail":"z@example.com","status":"ok","source":"web","updatedAt":"2026-10-10T16:29:00.000Z","windows":[{"kind":"billing","label":"Token Spend","used":4,"limit":10,"usedPercent":40,"remainingPercent":60,"resetsAt":"2026-10-11T07:30:00.000Z","currency":"USD"},{"kind":"billing","limitId":"zed.edit-predictions","label":"Edit predictions","detail":"unlimited","showMeter":false}]},
{"provider":"kiro","accountKey":"sha256:kiro1","status":"ok","source":"cli","updatedAt":"2026-10-10T16:29:00.000Z","windows":[{"kind":"billing","label":"Credits","used":120.5,"limit":500,"usedPercent":24.1,"remainingPercent":75.9,"resetsAt":"2026-10-16T22:30:00.000Z"},{"kind":"billing","label":"Overage","used":12.5,"remaining":3.2,"showMeter":false}]},
{"provider":"commandcode","accountKey":"sha256:cc1","status":"ok","source":"web","updatedAt":"2026-10-10T16:29:00.000Z","windows":[{"kind":"session","usedPercent":10,"remainingPercent":90},{"kind":"billing","boundaryKind":"expiry","label":"Monthly grant","limit":70,"remaining":47.42,"usedPercent":32.26,"remainingPercent":67.74,"resetsAt":"2026-10-19T00:30:00.000Z","currency":"USD"}]},
{"provider":"kimi","accountKey":"sha256:kimi1","status":"ok","source":"api","updatedAt":"2026-10-10T16:29:00.000Z","windows":[{"kind":"session","usedPercent":70,"remainingPercent":30},{"kind":"billing","boundaryKind":"mixed","usedPercent":25,"remainingPercent":75,"resetsAt":"2026-10-10T16:30:30.000Z","detail":"Kimi 60% · Code 40%"}]},
{"provider":"grok","accountKey":"sha256:grok1","status":"ok","source":"rpc","updatedAt":"2026-10-10T16:29:00.000Z","windows":[{"kind":"billing","usedPercent":48,"remainingPercent":52}]},
{"provider":"factory","accountKey":"sha256:f1","status":"ok","source":"api","updatedAt":"2026-10-10T16:29:00.000Z","windows":[{"kind":"session","usedPercent":20,"remainingPercent":80},{"kind":"session","additional":true,"label":"Core","usedPercent":50,"remainingPercent":50},{"kind":"weekly","usedPercent":30,"remainingPercent":70},{"kind":"billing","usedPercent":40,"remainingPercent":60},{"kind":"billing","metric":"credits","label":"Extra usage balance","remaining":2,"currency":"USD"}]}
],
"providers": [
{"provider":"antigravity","accountKey":"sha256:fixture-antigravity-account","rowsLeft":[{"value":"--","scale":0,"tone":0.78}],"rowsUsed":[{"value":"--","scale":0}],"detailsLeft":{},"detailsUsed":{},"usageItems":[],"planCell":"Sign in again","accountPlanSolo":"Sign in again","accountPlanGrouped":"Sign in again","status":["Open Antigravity to verify","setup"],"sourceLabel":"OAuth","compact":[]},
{"provider":"claude","accountKey":"sha256:fixture-claude-account","rowsLeft":[{"item":"[\"session\",\"\",\"\",false]","itemLabel":"Session","value":"58% left","scale":0.58,"tone":0.95,"reset":"Reset 2h 30m"},{"item":"[\"weekly\",\"\",\"\",false]","itemLabel":"Weekly","value":"80% left","scale":0.795,"tone":0.68,"reset":"Reset 4d 3h"},{"item":"[\"weekly\",\"Opus\",\"\",false]","itemLabel":"Opus","value":"36% left","scale":0.36,"tone":0.68,"reset":"Reset 4d 3h"},{"item":"spend","itemLabel":"Usage credits","value":"$12.40 / $50.00","note":true},{"item":"resets","itemLabel":"Resets","note":true}],"rowsUsed":[{"item":"[\"session\",\"\",\"\",false]","value":"42% used","scale":0.42},{"item":"[\"weekly\",\"\",\"\",false]","value":"21% used","scale":0.205},{"item":"[\"weekly\",\"Opus\",\"\",false]","value":"64% used","scale":0.64},{"item":"spend","value":"$12.40 / $50.00","note":true},{"item":"resets","note":true}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"session\",\"\",\"\",false]","label":"Session"},{"id":"[\"weekly\",\"\",\"\",false]","label":"Weekly"},{"id":"[\"weekly\",\"Opus\",\"\",false]","label":"Opus"},{"id":"spend","label":"Usage credits"},{"id":"resets","label":"Resets"}],"planCell":"Max","accountPlanSolo":"Max","accountPlanGrouped":"Max","status":["Linked","ok"],"sourceLabel":"Web","metaPlain":"Updated just now","metaSource":"Updated just now · Web · studio-mac","compact":[0,1,2,3]},
{"provider":"cline","accountKey":"sha256:fixture-cline-key","rowsLeft":[],"rowsUsed":[],"detailsLeft":{},"detailsUsed":{},"usageItems":[],"planCell":"Sign in again","accountPlanSolo":"Sign in again","accountPlanGrouped":"Sign in again","status":["Update API key","setup"],"sourceLabel":"API","compact":[]},
{"provider":"codex","accountKey":"sha256:fixture-codex-account","rowsLeft":[{"item":"[\"id\",\"codex\",\"session\",\"\",false,300]","itemLabel":"Session","value":"92% left","scale":0.92,"tone":0.95,"reset":"Reset 4h 0m"},{"item":"[\"id\",\"codex\",\"weekly\",\"\",false,10080]","itemLabel":"Weekly","value":"39% left","scale":0.39,"tone":0.68,"reset":"Reset 2d 0h"},{"item":"[\"id\",\"codex_bengalfox\",\"session\",\"\",true,300]","itemLabel":"GPT-5.3-Codex-Spark · 5-hour","value":"100% left","scale":1,"tone":0.78,"reset":"Reset 5h 0m"},{"item":"[\"id\",\"codex_bengalfox\",\"weekly\",\"\",true,10080]","itemLabel":"GPT-5.3-Codex-Spark · Weekly","value":"97% left","scale":0.97,"tone":0.78,"reset":"Reset 6d 0h"},{"item":"[\"id\",\"codex_reserve\",\"weekly\",\"\",true,null]","itemLabel":"Luna Reserve","value":"88% left","scale":0.88,"tone":0.78,"reset":"Reset 1m"},{"item":"resets","itemLabel":"Resets","note":true}],"rowsUsed":[{"item":"[\"id\",\"codex\",\"session\",\"\",false,300]","value":"8% used","scale":0.08},{"item":"[\"id\",\"codex\",\"weekly\",\"\",false,10080]","value":"61% used","scale":0.61},{"item":"[\"id\",\"codex_bengalfox\",\"session\",\"\",true,300]","value":"0% used","scale":0},{"item":"[\"id\",\"codex_bengalfox\",\"weekly\",\"\",true,10080]","value":"3% used","scale":0.03},{"item":"[\"id\",\"codex_reserve\",\"weekly\",\"\",true,null]","value":"12% used","scale":0.12},{"item":"resets","note":true}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"id\",\"codex\",\"session\",\"\",false,300]","label":"Session"},{"id":"[\"id\",\"codex\",\"weekly\",\"\",false,10080]","label":"Weekly"},{"id":"[\"id\",\"codex_bengalfox\",\"session\",\"\",true,300]","label":"GPT-5.3-Codex-Spark · 5-hour"},{"id":"[\"id\",\"codex_bengalfox\",\"weekly\",\"\",true,10080]","label":"GPT-5.3-Codex-Spark · Weekly"},{"id":"[\"id\",\"codex_reserve\",\"weekly\",\"\",true,null]","label":"Luna Reserve"},{"id":"resets","label":"Resets"}],"planCell":"Plus","accountPlanSolo":"Plus","accountPlanGrouped":"Plus","status":["Live","ok"],"sourceLabel":"App","metaPlain":"Updated just now","metaSource":"Updated just now · App · studio-mac","compact":[0,1],"codexNames":[null,null,"GPT-5.3-Codex-Spark · 5-hour","GPT-5.3-Codex-Spark · Weekly","Luna Reserve"]},
{"provider":"copilot","accountKey":"sha256:fixture-copilot-account","rowsLeft":[],"rowsUsed":[],"detailsLeft":{},"detailsUsed":{},"usageItems":[],"planCell":"Unavailable","accountPlanSolo":"Unavailable","accountPlanGrouped":"Unavailable","status":["Unavailable","warn"],"sourceLabel":"API","compact":[]},
{"provider":"cursor","accountKey":"sha256:fixture-cursor-account","rowsLeft":[{"item":"[\"billing\",\"Cursor Models\",\"\",false]","itemLabel":"Cursor Models","value":"53% left","scale":0.53,"tone":0.68,"reset":"Reset 12d 0h"},{"item":"spend","itemLabel":"On-demand","value":"$3.20 / $20.00","note":true}],"rowsUsed":[{"item":"[\"billing\",\"Cursor Models\",\"\",false]","value":"47% used","scale":0.47},{"item":"spend","value":"$3.20 / $20.00","note":true}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"billing\",\"Cursor Models\",\"\",false]","label":"Cursor Models"},{"id":"spend","label":"On-demand"}],"planCell":"Usage API limited","accountPlanSolo":"Usage API limited","accountPlanGrouped":"Usage API limited","status":["Usage API limited","warn"],"sourceLabel":"Web","compact":[0,1]},
{"provider":"deepseek","accountKey":"sha256:fixture-deepseek-key","rowsLeft":[{"item":"credits","itemLabel":"Balance","value":"¥86.42","scale":0.7854935466278857,"tone":0.95},{"item":"spend","itemLabel":"Spend","value":"Today ¥1.20 · Month ¥23.60iToday¥1.20Month¥23.60All time¥140.10","note":true}],"rowsUsed":[{"item":"credits","value":"¥86.42","scale":0.7854935466278857},{"item":"spend","value":"Today ¥1.20 · Month ¥23.60iToday¥1.20Month¥23.60All time¥140.10","note":true}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"credits","label":"Balance"},{"id":"spend","label":"Spend"}],"planCell":"Limited","accountPlanSolo":"Limited","accountPlanGrouped":"Limited","status":["Limited","warn"],"sourceLabel":"API","compact":[0]},
{"provider":"kimi","accountKey":"sha256:fixture-kimi-key","rowsLeft":[{"item":"[\"session\",\"\",\"\",false]","itemLabel":"5-hour","value":"60% left","scale":0.6,"tone":0.95,"reset":"Reset 1h 50m"},{"item":"[\"weekly\",\"\",\"\",false]","itemLabel":"Weekly","value":"0% left","scale":0,"tone":0.68,"reset":"Reset 1d 5h"}],"rowsUsed":[{"item":"[\"session\",\"\",\"\",false]","value":"40% used","scale":0.4},{"item":"[\"weekly\",\"\",\"\",false]","value":"100% used","scale":1}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"session\",\"\",\"\",false]","label":"5-hour"},{"id":"[\"weekly\",\"\",\"\",false]","label":"Weekly"}],"planCell":"Kimi Code","accountPlanSolo":"Kimi Code","accountPlanGrouped":"Kimi Code","status":["Stale","stale"],"sourceLabel":"API","metaPlain":"Stale · 1h ago","metaSource":"Stale · 1h ago · old-laptop","compact":[0,1]},
{"provider":"mimo","accountKey":"sha256:fixture-mimo-account","rowsLeft":[{"item":"[\"billing\",\"Token Plan\",\"\",false]","itemLabel":"Token Plan","value":"Expired","note":true},{"item":"credits","itemLabel":"Balance","value":"¥3.50","scale":1,"tone":0.68}],"rowsUsed":[{"item":"[\"billing\",\"Token Plan\",\"\",false]","value":"Expired","note":true},{"item":"credits","value":"¥3.50","scale":1}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"billing\",\"Token Plan\",\"\",false]","label":"Token Plan"},{"id":"credits","label":"Balance"}],"planCell":"Error","accountPlanSolo":"Error","accountPlanGrouped":"Error","status":["Unavailable","warn"],"sourceLabel":"Web","compact":[0]},
{"provider":"openrouter","accountKey":"sha256:fixture-openrouter-key","rowsLeft":[{"item":"credits","itemLabel":"Balance","value":"$13.80","scale":0.69,"tone":0.95},{"item":"spend","itemLabel":"Spend","value":"Today $0.40 · Month $6.20iToday$0.40Week$2.10Month$6.20All time$18.75","note":true}],"rowsUsed":[{"item":"credits","value":"$13.80","scale":0.69},{"item":"spend","value":"Today $0.40 · Month $6.20iToday$0.40Week$2.10Month$6.20All time$18.75","note":true}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"credits","label":"Balance"},{"id":"spend","label":"Spend"}],"planCell":"API key","accountPlanSolo":"API key","accountPlanGrouped":"API key","status":["Live","ok"],"sourceLabel":"API","metaPlain":"Updated 1m ago","metaSource":"Updated 1m ago · API · studio-mac","compact":[0]},
{"provider":"thirdparty","accountKey":"sha256:fixture-relay-account","rowsLeft":[{"item":"credits","itemLabel":"Balance","value":"$42.50","scale":0.425,"tone":0.95},{"item":"spend","itemLabel":"Spend","value":"Month $31.20iTotal quota$100.00Month requests128Month tokens2,400,000Input tokens310,000Output tokens92,000Cache tokens1,998,000Avg response2.4 sStandard cost$3.21","note":true}],"rowsUsed":[{"item":"credits","value":"$42.50","scale":0.425},{"item":"spend","value":"Month $31.20iTotal quota$100.00Month requests128Month tokens2,400,000Input tokens310,000Output tokens92,000Cache tokens1,998,000Avg response2.4 sStandard cost$3.21","note":true}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"credits","label":"Balance"},{"id":"spend","label":"Spend"}],"planCell":"Relay","accountPlanSolo":"New API · Account","accountPlanGrouped":"New API · Account","status":["Live","ok"],"sourceLabel":"API","metaPlain":"Updated 5m ago","metaSource":"Updated 5m ago · API · build-box","compact":[0]},
{"provider":"typesafe","accountKey":"sha256:fixture-typesafe-account","rowsLeft":[{"item":"credits","itemLabel":"Balance","value":"$42.50","scale":1,"tone":0.95,"reset":"Expires 20d 0h","detail":"$25.00"}],"rowsUsed":[{"item":"credits","value":"$42.50","scale":1,"detail":"$25.00"}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"credits","label":"Balance"}],"planCell":"Credits","accountPlanSolo":"Credits","accountPlanGrouped":"Credits","status":["Live","ok"],"sourceLabel":"Web","metaPlain":"Updated 1m ago","metaSource":"Updated 1m ago · Web · studio-mac","compact":[0]},
{"provider":"workbuddy","accountKey":"","rowsLeft":[],"rowsUsed":[],"detailsLeft":{},"detailsUsed":{},"usageItems":[],"planCell":"Not signed in","accountPlanSolo":"Not signed in","accountPlanGrouped":"Not signed in","status":["Encrypted by app","warn"],"sourceLabel":"Local","compact":[]},
{"provider":"zai","accountKey":"sha256:fixture-zai-key","rowsLeft":[{"item":"[\"session\",\"\",\"\",false]","itemLabel":"5-hour","value":"65% left","scale":0.65,"tone":0.95,"reset":"Reset 3h 0m"},{"item":"[\"daily\",\"MCP calls\",\"\",false]","itemLabel":"MCP calls","value":"86% left","scale":0.86,"tone":0.78,"reset":"Reset 7h 30m"},{"item":"[\"weekly\",\"\",\"\",false]","itemLabel":"Weekly","value":"88% left","scale":0.88,"tone":0.68,"reset":"Reset 5d 0h"}],"rowsUsed":[{"item":"[\"session\",\"\",\"\",false]","value":"35% used","scale":0.35},{"item":"[\"daily\",\"MCP calls\",\"\",false]","value":"14% used","scale":0.14},{"item":"[\"weekly\",\"\",\"\",false]","value":"12% used","scale":0.12}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"session\",\"\",\"\",false]","label":"5-hour"},{"id":"[\"daily\",\"MCP calls\",\"\",false]","label":"MCP calls"},{"id":"[\"weekly\",\"\",\"\",false]","label":"Weekly"}],"planCell":"Pro","accountPlanSolo":"Pro","accountPlanGrouped":"Pro","status":["Live","ok"],"sourceLabel":"API","metaPlain":"Updated 5m ago","metaSource":"Updated 5m ago · API · build-box","compact":[0,1,2]},
{"provider":"zed","accountKey":"sha256:fixture-zed-account","rowsLeft":[{"item":"[\"billing\",\"Prompts\",\"\",false]","itemLabel":"Prompts","value":"80% left","scale":0.8,"tone":0.95,"reset":"Reset 18d 0h","detail":"$400.00 / $500.00"},{"item":"[\"id\",\"zed.edit-predictions\",\"billing\",\"\",false,null]","itemLabel":"Edit predictions","value":"Unlimited","note":true}],"rowsUsed":[{"item":"[\"billing\",\"Prompts\",\"\",false]","value":"20% used","scale":0.2,"detail":"$100.00 / $500.00"},{"item":"[\"id\",\"zed.edit-predictions\",\"billing\",\"\",false,null]","value":"Unlimited","note":true}],"detailsLeft":{"0":"$400.00 / $500.00"},"detailsUsed":{"0":"$100.00 / $500.00"},"usageItems":[{"id":"[\"billing\",\"Prompts\",\"\",false]","label":"Prompts"},{"id":"[\"id\",\"zed.edit-predictions\",\"billing\",\"\",false,null]","label":"Edit predictions"}],"planCell":"Pro","accountPlanSolo":"Pro","accountPlanGrouped":"Pro","status":["Linked","ok"],"sourceLabel":"Web","metaPlain":"Updated just now","metaSource":"Updated just now · Web · tokyo-mac","compact":[0,-1]},
{"provider":"codex","accountKey":"sha256:c0dexa11","rowsLeft":[{"item":"[\"id\",\"codex\",\"session\",\"\",false,300]","itemLabel":"Session","value":"18% left","scale":0.18,"tone":0.95,"reset":"Reset 1h 10m"},{"item":"[\"id\",\"codex\",\"weekly\",\"\",false,10080]","itemLabel":"Weekly","value":"60% left","scale":0.6,"tone":0.68,"reset":"Reset 2d 2h"},{"item":"[\"id\",\"codex_bengalfox\",\"session\",\"\",true,300]","itemLabel":"GPT-5.3-Codex-Spark · 5-hour","value":"90% left","scale":0.9,"tone":0.78},{"item":"[\"id\",\"codex_bengalfox\",\"weekly\",\"\",true,10080]","itemLabel":"GPT-5.3-Codex-Spark · Weekly","value":"80% left","scale":0.8,"tone":0.78},{"item":"[\"id\",\"codex_reserve\",\"weekly\",\"\",true,20160]","itemLabel":"Luna Reserve","value":"70% left","scale":0.7,"tone":0.78}],"rowsUsed":[{"item":"[\"id\",\"codex\",\"session\",\"\",false,300]","value":"82% used","scale":0.82},{"item":"[\"id\",\"codex\",\"weekly\",\"\",false,10080]","value":"40% used","scale":0.4},{"item":"[\"id\",\"codex_bengalfox\",\"session\",\"\",true,300]","value":"10% used","scale":0.1},{"item":"[\"id\",\"codex_bengalfox\",\"weekly\",\"\",true,10080]","value":"20% used","scale":0.2},{"item":"[\"id\",\"codex_reserve\",\"weekly\",\"\",true,20160]","value":"30% used","scale":0.3}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"id\",\"codex\",\"session\",\"\",false,300]","label":"Session"},{"id":"[\"id\",\"codex\",\"weekly\",\"\",false,10080]","label":"Weekly"},{"id":"[\"id\",\"codex_bengalfox\",\"session\",\"\",true,300]","label":"GPT-5.3-Codex-Spark · 5-hour"},{"id":"[\"id\",\"codex_bengalfox\",\"weekly\",\"\",true,10080]","label":"GPT-5.3-Codex-Spark · Weekly"},{"id":"[\"id\",\"codex_reserve\",\"weekly\",\"\",true,20160]","label":"Luna Reserve"}],"planCell":"","accountPlanSolo":"","accountPlanGrouped":"","status":["Live","ok"],"sourceLabel":"CLI","metaPlain":"Updated 3m ago","metaSource":"Updated 3m ago · CLI · build-box","compact":[0,1],"codexNames":[null,null,"GPT-5.3-Codex-Spark · 5-hour","GPT-5.3-Codex-Spark · Weekly","Luna Reserve"]},
{"provider":"codex","accountKey":"sha256:c0dexb22","rowsLeft":[{"item":"[\"id\",\"codex\",\"session\",\"\",false,300]","itemLabel":"Session","value":"95% left","scale":0.95,"tone":0.95}],"rowsUsed":[{"item":"[\"id\",\"codex\",\"session\",\"\",false,300]","value":"5% used","scale":0.05}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"id\",\"codex\",\"session\",\"\",false,300]","label":"Session"}],"planCell":"","accountPlanSolo":"","accountPlanGrouped":"","status":["Live","ok"],"sourceLabel":"Managed","metaPlain":"Updated 1m ago","metaSource":"Updated 1m ago · Managed","compact":[0],"codexNames":[null]},
{"provider":"codex","accountKey":"sha256:c0dexc33","rowsLeft":[{"item":"[\"id\",\"codex\",\"weekly\",\"\",false,10080]","itemLabel":"Weekly","value":"3% left","scale":0.03,"tone":0.68}],"rowsUsed":[{"item":"[\"id\",\"codex\",\"weekly\",\"\",false,10080]","value":"97% used","scale":0.97}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"id\",\"codex\",\"weekly\",\"\",false,10080]","label":"Weekly"}],"planCell":"Limited","accountPlanSolo":"Limited","accountPlanGrouped":"Limited","status":["Stale","stale"],"sourceLabel":"RPC","metaPlain":"Stale · 50m ago","metaSource":"Stale · 50m ago","compact":[0],"codexNames":[null]},
{"provider":"codex","accountKey":"","rowsLeft":[],"rowsUsed":[],"detailsLeft":{},"detailsUsed":{},"usageItems":[],"planCell":"Sign in again","accountPlanSolo":"Sign in again","accountPlanGrouped":"Sign in again","status":["Sign in again","setup"],"sourceLabel":"RPC","compact":[],"codexNames":[]},
{"provider":"claude","accountKey":"sha256:fixtureclaudeaaaa","rowsLeft":[{"item":"[\"session\",\"\",\"\",false]","itemLabel":"Session","value":"88% left","scale":0.88,"tone":0.95},{"item":"[\"weekly\",\"\",\"\",false]","itemLabel":"Weekly","value":"45% left","scale":0.45,"tone":0.68}],"rowsUsed":[{"item":"[\"session\",\"\",\"\",false]","value":"12% used","scale":0.12},{"item":"[\"weekly\",\"\",\"\",false]","value":"55% used","scale":0.55}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"session\",\"\",\"\",false]","label":"Session"},{"id":"[\"weekly\",\"\",\"\",false]","label":"Weekly"}],"planCell":"Pro","accountPlanSolo":"Pro","accountPlanGrouped":"Pro","status":["Live","ok"],"sourceLabel":"OAuth","metaPlain":"Updated 2m ago","metaSource":"Updated 2m ago · OAuth","compact":[0,1]},
{"provider":"claude","accountKey":"sha256:fixtureclaudebbbb","rowsLeft":[{"item":"[\"session\",\"\",\"\",false]","itemLabel":"Session","value":"1% left","scale":0.01,"tone":0.95}],"rowsUsed":[{"item":"[\"session\",\"\",\"\",false]","value":"99% used","scale":0.99}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"session\",\"\",\"\",false]","label":"Session"}],"planCell":"","accountPlanSolo":"","accountPlanGrouped":"","status":["Live","ok"],"sourceLabel":"CLI","metaPlain":"Updated 2m ago","metaSource":"Updated 2m ago · CLI","compact":[0]},
{"provider":"opencode","accountKey":"sha256:open1","rowsLeft":[{"item":"[\"session\",\"\",\"\",false]","itemLabel":"Session","value":"67% left","scale":0.67,"tone":0.95},{"item":"[\"billing\",\"\",\"\",false]","itemLabel":"Monthly","value":"90% left","scale":0.9,"tone":0.5},{"item":"credits","itemLabel":"Balance","value":"$7.25","note":true}],"rowsUsed":[{"item":"[\"session\",\"\",\"\",false]","value":"33% used","scale":0.33},{"item":"[\"billing\",\"\",\"\",false]","value":"10% used","scale":0.1},{"item":"credits","value":"$7.25","note":true}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"session\",\"\",\"\",false]","label":"Session"},{"id":"[\"billing\",\"\",\"\",false]","label":"Monthly"},{"id":"credits","label":"Balance"}],"planCell":"Work profile","accountPlanSolo":"Work profile","accountPlanGrouped":"","status":["Linked","ok"],"sourceLabel":"Web","metaPlain":"Updated 4m ago","metaSource":"Updated 4m ago · Web","compact":[0,1,2]},
{"provider":"opencode","accountKey":"sha256:open2","rowsLeft":[{"item":"[\"weekly\",\"\",\"\",false]","itemLabel":"Weekly","value":"30% left","scale":0.3,"tone":0.68}],"rowsUsed":[{"item":"[\"weekly\",\"\",\"\",false]","value":"70% used","scale":0.7}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"weekly\",\"\",\"\",false]","label":"Weekly"}],"planCell":"Go","accountPlanSolo":"Go","accountPlanGrouped":"Go","status":["Linked","ok"],"sourceLabel":"Web","metaPlain":"Updated 4m ago","metaSource":"Updated 4m ago · Web","compact":[0]},
{"provider":"openrouter","accountKey":"sha256:or1","rowsLeft":[{"item":"credits","itemLabel":"Balance","value":"$4.00","scale":0.4,"tone":0.95},{"item":"[\"daily\",\"Key limit\",\"\",false]","itemLabel":"Key limit","value":"No limit","note":true},{"item":"spend","itemLabel":"Spend","value":"Today $0.50 · Month $6.00","note":true}],"rowsUsed":[{"item":"credits","value":"$4.00","scale":0.4},{"item":"[\"daily\",\"Key limit\",\"\",false]","value":"No limit","note":true},{"item":"spend","value":"Today $0.50 · Month $6.00","note":true}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"credits","label":"Balance"},{"id":"[\"daily\",\"Key limit\",\"\",false]","label":"Key limit"},{"id":"spend","label":"Spend"}],"planCell":"API key","accountPlanSolo":"API key","accountPlanGrouped":"API key","status":["Live","ok"],"sourceLabel":"API","metaPlain":"Updated 1m ago","metaSource":"Updated 1m ago · API","compact":[0,1]},
{"provider":"openrouter","accountKey":"sha256:or2","rowsLeft":[{"item":"credits","itemLabel":"Balance","value":"$0.00","scale":0,"tone":0.95}],"rowsUsed":[{"item":"credits","value":"$0.00","scale":0}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"credits","label":"Balance"}],"planCell":"Team key","accountPlanSolo":"Team key","accountPlanGrouped":"","status":["Live","ok"],"sourceLabel":"API","metaPlain":"Updated 1m ago","metaSource":"Updated 1m ago · API","compact":[0]},
{"provider":"volcengine","accountKey":"sha256:volc1","rowsLeft":[{"item":"[\"session\",\"\",\"\",false]","itemLabel":"5-hour","value":"85% left","scale":0.85,"tone":0.95},{"item":"[\"daily\",\"\",\"\",false]","itemLabel":"Daily","value":"55% left","scale":0.55,"tone":0.78},{"item":"[\"weekly\",\"\",\"\",false]","itemLabel":"Weekly","value":"40% left","scale":0.4,"tone":0.68},{"item":"[\"billing\",\"\",\"\",false]","itemLabel":"Monthly","value":"25% left","scale":0.25,"tone":0.68}],"rowsUsed":[{"item":"[\"session\",\"\",\"\",false]","value":"15% used","scale":0.15},{"item":"[\"daily\",\"\",\"\",false]","value":"45% used","scale":0.45},{"item":"[\"weekly\",\"\",\"\",false]","value":"60% used","scale":0.6},{"item":"[\"billing\",\"\",\"\",false]","value":"75% used","scale":0.75}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"session\",\"\",\"\",false]","label":"5-hour"},{"id":"[\"daily\",\"\",\"\",false]","label":"Daily"},{"id":"[\"weekly\",\"\",\"\",false]","label":"Weekly"},{"id":"[\"billing\",\"\",\"\",false]","label":"Monthly"}],"planCell":"Coding Plan","accountPlanSolo":"Coding Plan","accountPlanGrouped":"","status":["Live","ok"],"sourceLabel":"API","metaPlain":"Updated 6m ago","metaSource":"Updated 6m ago · API","compact":[0,1,2,3]},
{"provider":"volcengine","accountKey":"sha256:volc2","rowsLeft":[{"item":"[\"session\",\"\",\"\",false]","itemLabel":"5-hour","value":"9% left","scale":0.09,"tone":0.95}],"rowsUsed":[{"item":"[\"session\",\"\",\"\",false]","value":"91% used","scale":0.91}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"session\",\"\",\"\",false]","label":"5-hour"}],"planCell":"Limited","accountPlanSolo":"Limited","accountPlanGrouped":"Limited","status":["Limited","warn"],"sourceLabel":"arkcli","compact":[0]},
{"provider":"mimo","accountKey":"sha256:mimo1","rowsLeft":[{"item":"[\"billing\",\"Token Plan\",\"\",false]","itemLabel":"Token Plan","value":"70% left","scale":0.7,"tone":0.68},{"item":"credits","itemLabel":"Balance","value":"¥12.00","scale":0.75,"tone":0.68,"detail":"Gift ¥2.00 · Cash ¥10.00"},{"item":"spend","itemLabel":"Spend","value":"Month ¥4.00","note":true}],"rowsUsed":[{"item":"[\"billing\",\"Token Plan\",\"\",false]","value":"30% used","scale":0.3},{"item":"credits","value":"¥12.00","scale":0.75,"detail":"Gift ¥2.00 · Cash ¥10.00"},{"item":"spend","value":"Month ¥4.00","note":true}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"billing\",\"Token Plan\",\"\",false]","label":"Token Plan"},{"id":"credits","label":"Balance"},{"id":"spend","label":"Spend"}],"planCell":"Standard","accountPlanSolo":"Standard","accountPlanGrouped":"Standard","status":["Linked","ok"],"sourceLabel":"Web","metaPlain":"Updated 8m ago","metaSource":"Updated 8m ago · Web","compact":[0]},
{"provider":"mimo","accountKey":"sha256:mimo2","rowsLeft":[{"item":"[\"weekly\",\"Membership\",\"\",false]","itemLabel":"Membership","value":"80% left","scale":0.8,"tone":0.68}],"rowsUsed":[{"item":"[\"weekly\",\"Membership\",\"\",false]","value":"20% used","scale":0.2}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"weekly\",\"Membership\",\"\",false]","label":"Membership"}],"planCell":"","accountPlanSolo":"","accountPlanGrouped":"","status":["Linked","ok"],"sourceLabel":"Web","metaPlain":"Updated 8m ago","metaSource":"Updated 8m ago · Web","compact":[0]},
{"provider":"thirdparty","accountKey":"sha256:tp1","rowsLeft":[{"item":"credits","itemLabel":"Quota","value":"$9.00","scale":1,"tone":0.95},{"item":"spend","itemLabel":"Spend","value":"All time $21.00iTotal quota$30.00Requests77Groupvip","note":true}],"rowsUsed":[{"item":"credits","value":"$9.00","scale":1},{"item":"spend","value":"All time $21.00iTotal quota$30.00Requests77Groupvip","note":true}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"credits","label":"Quota"},{"id":"spend","label":"Spend"}],"planCell":"","accountPlanSolo":"New API · API key","accountPlanGrouped":"New API · API key","status":["Live","ok"],"sourceLabel":"API","metaPlain":"Updated 2m ago","metaSource":"Updated 2m ago · API","compact":[0]},
{"provider":"thirdparty","accountKey":"sha256:tp2","rowsLeft":[{"item":"credits","itemLabel":"Balance","value":"$3.50","scale":0.25,"tone":0.95},{"item":"spend","itemLabel":"Spend","value":"Month $10.50","note":true}],"rowsUsed":[{"item":"credits","value":"$3.50","scale":0.25},{"item":"spend","value":"Month $10.50","note":true}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"credits","label":"Balance"},{"id":"spend","label":"Spend"}],"planCell":"","accountPlanSolo":"Sub2API · Account","accountPlanGrouped":"Sub2API · Account","status":["Live","ok"],"sourceLabel":"API","metaPlain":"Updated 2m ago","metaSource":"Updated 2m ago · API","compact":[0]},
{"provider":"thirdparty","accountKey":"sha256:tp3","rowsLeft":[],"rowsUsed":[],"detailsLeft":{},"detailsUsed":{},"usageItems":[],"planCell":"Sign in again","accountPlanSolo":"Sign in again","accountPlanGrouped":"Sign in again","status":["Update credential","setup"],"sourceLabel":"API","compact":[]},
{"provider":"antigravity","accountKey":"sha256:ag1","rowsLeft":[{"item":"[\"session\",\"Gemini Pro 5-hour\",\"\",false]","itemLabel":"Gemini Pro · 5-hour","value":"70% left","scale":0.7,"tone":0.95,"reset":"Reset 1h 40m"},{"item":"[\"weekly\",\"Gemini Pro Weekly\",\"\",false]","itemLabel":"Gemini Pro · Weekly","value":"15% left","scale":0.15,"tone":0.78,"reset":"Reset 3d 11h"},{"item":"[\"session\",\"Claude 5-hour\",\"\",false]","itemLabel":"Claude · 5-hour","value":"50% left","scale":0.5,"tone":0.95,"reset":"Reset 30m"},{"item":"[\"weekly\",\"Claude Weekly\",\"\",false]","itemLabel":"Claude · Weekly","value":"40% left","scale":0.4,"tone":0.78},{"item":"[\"session\",\"GPT-OSS 5-hour\",\"\",false]","itemLabel":"GPT-OSS · 5-hour","value":"95% left","scale":0.95,"tone":0.95}],"rowsUsed":[{"item":"[\"session\",\"Gemini Pro 5-hour\",\"\",false]","value":"30% used","scale":0.3},{"item":"[\"weekly\",\"Gemini Pro Weekly\",\"\",false]","value":"85% used","scale":0.85},{"item":"[\"session\",\"Claude 5-hour\",\"\",false]","value":"50% used","scale":0.5},{"item":"[\"weekly\",\"Claude Weekly\",\"\",false]","value":"60% used","scale":0.6},{"item":"[\"session\",\"GPT-OSS 5-hour\",\"\",false]","value":"5% used","scale":0.05}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"session\",\"Gemini Pro 5-hour\",\"\",false]","label":"Gemini Pro · 5-hour"},{"id":"[\"weekly\",\"Gemini Pro Weekly\",\"\",false]","label":"Gemini Pro · Weekly"},{"id":"[\"session\",\"Claude 5-hour\",\"\",false]","label":"Claude · 5-hour"},{"id":"[\"weekly\",\"Claude Weekly\",\"\",false]","label":"Claude · Weekly"},{"id":"[\"session\",\"GPT-OSS 5-hour\",\"\",false]","label":"GPT-OSS · 5-hour"}],"planCell":"","accountPlanSolo":"","accountPlanGrouped":"","status":["Live","ok"],"sourceLabel":"OAuth","metaPlain":"Updated 1m ago","metaSource":"Updated 1m ago · OAuth","compact":[1,2]},
{"provider":"zed","accountKey":"sha256:zed1","rowsLeft":[{"item":"[\"billing\",\"Token Spend\",\"\",false]","itemLabel":"Token Spend","value":"60% left","scale":0.6,"tone":0.95,"reset":"Reset 15h 0m","detail":"$6.00 / $10.00"},{"item":"[\"id\",\"zed.edit-predictions\",\"billing\",\"\",false,null]","itemLabel":"Edit predictions","value":"Unlimited","note":true}],"rowsUsed":[{"item":"[\"billing\",\"Token Spend\",\"\",false]","value":"40% used","scale":0.4,"detail":"$4.00 / $10.00"},{"item":"[\"id\",\"zed.edit-predictions\",\"billing\",\"\",false,null]","value":"Unlimited","note":true}],"detailsLeft":{"0":"$6.00 / $10.00"},"detailsUsed":{"0":"$4.00 / $10.00"},"usageItems":[{"id":"[\"billing\",\"Token Spend\",\"\",false]","label":"Token Spend"},{"id":"[\"id\",\"zed.edit-predictions\",\"billing\",\"\",false,null]","label":"Edit predictions"}],"planCell":"Student","accountPlanSolo":"Student","accountPlanGrouped":"Student","status":["Linked","ok"],"sourceLabel":"Web","metaPlain":"Updated 1m ago","metaSource":"Updated 1m ago · Web","compact":[0,-1]},
{"provider":"kiro","accountKey":"sha256:kiro1","rowsLeft":[{"item":"[\"billing\",\"Credits\",\"\",false]","itemLabel":"Credits","value":"76% left","scale":0.759,"tone":0.68,"reset":"Reset 6d 6h","detail":"379.5/500"},{"item":"[\"billing\",\"Overage\",\"\",false]","itemLabel":"Overage","value":"12.5 credits · $3.20","note":true}],"rowsUsed":[{"item":"[\"billing\",\"Credits\",\"\",false]","value":"24% used","scale":0.24099999999999994,"detail":"120.5/500"},{"item":"[\"billing\",\"Overage\",\"\",false]","value":"12.5 credits · $3.20","note":true}],"detailsLeft":{"0":"379.5/500"},"detailsUsed":{"0":"120.5/500"},"usageItems":[{"id":"[\"billing\",\"Credits\",\"\",false]","label":"Credits"},{"id":"[\"billing\",\"Overage\",\"\",false]","label":"Overage"}],"planCell":"","accountPlanSolo":"","accountPlanGrouped":"","status":["Live","ok"],"sourceLabel":"CLI","metaPlain":"Updated 1m ago","metaSource":"Updated 1m ago · CLI","compact":[0,1]},
{"provider":"commandcode","accountKey":"sha256:cc1","rowsLeft":[{"item":"[\"session\",\"\",\"\",false]","itemLabel":"5-hour","value":"90% left","scale":0.9,"tone":0.95},{"item":"[\"billing\",\"Monthly grant\",\"\",false]","itemLabel":"Monthly grant","value":"68% left","scale":0.6774,"tone":0.5,"reset":"Expires 8d 8h","detail":"$47.42 / $70.00"}],"rowsUsed":[{"item":"[\"session\",\"\",\"\",false]","value":"10% used","scale":0.1},{"item":"[\"billing\",\"Monthly grant\",\"\",false]","value":"32% used","scale":0.32260000000000005,"detail":"$22.58 / $70.00"}],"detailsLeft":{"1":"$47.42 / $70.00"},"detailsUsed":{"1":"$22.58 / $70.00"},"usageItems":[{"id":"[\"session\",\"\",\"\",false]","label":"5-hour"},{"id":"[\"billing\",\"Monthly grant\",\"\",false]","label":"Monthly grant"}],"planCell":"","accountPlanSolo":"","accountPlanGrouped":"","status":["Live","ok"],"sourceLabel":"Web","metaPlain":"Updated 1m ago","metaSource":"Updated 1m ago · Web","compact":[0,1]},
{"provider":"kimi","accountKey":"sha256:kimi1","rowsLeft":[{"item":"[\"session\",\"\",\"\",false]","itemLabel":"5-hour","value":"30% left","scale":0.3,"tone":0.95},{"item":"[\"billing\",\"\",\"\",false]","itemLabel":"Monthly","value":"75% left","scale":0.75,"tone":0.5,"reset":"Changes in 1m","detail":"Kimi 60% · Code 40%"}],"rowsUsed":[{"item":"[\"session\",\"\",\"\",false]","value":"70% used","scale":0.7},{"item":"[\"billing\",\"\",\"\",false]","value":"25% used","scale":0.25,"detail":"Kimi 60% · Code 40%"}],"detailsLeft":{"1":"Kimi 60% · Code 40%"},"detailsUsed":{"1":"Kimi 60% · Code 40%"},"usageItems":[{"id":"[\"session\",\"\",\"\",false]","label":"5-hour"},{"id":"[\"billing\",\"\",\"\",false]","label":"Monthly"}],"planCell":"","accountPlanSolo":"","accountPlanGrouped":"","status":["Live","ok"],"sourceLabel":"API","metaPlain":"Updated 1m ago","metaSource":"Updated 1m ago · API","compact":[0,1]},
{"provider":"grok","accountKey":"sha256:grok1","rowsLeft":[{"item":"[\"billing\",\"\",\"\",false]","itemLabel":"Monthly","value":"52% left","scale":0.52,"tone":0.68}],"rowsUsed":[{"item":"[\"billing\",\"\",\"\",false]","value":"48% used","scale":0.48}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"billing\",\"\",\"\",false]","label":"Monthly"}],"planCell":"","accountPlanSolo":"","accountPlanGrouped":"","status":["Live","ok"],"sourceLabel":"CLI","metaPlain":"Updated 1m ago","metaSource":"Updated 1m ago · CLI","compact":[0]},
{"provider":"factory","accountKey":"sha256:f1","rowsLeft":[{"item":"[\"session\",\"\",\"\",false]","itemLabel":"Session","value":"80% left","scale":0.8,"tone":0.95},{"item":"[\"weekly\",\"\",\"\",false]","itemLabel":"Weekly","value":"70% left","scale":0.7,"tone":0.68},{"item":"[\"billing\",\"\",\"\",false]","itemLabel":"Monthly","value":"60% left","scale":0.6,"tone":0.5},{"item":"[\"session\",\"Core\",\"\",true]","itemLabel":"Core","value":"50% left","scale":0.5,"tone":0.95},{"item":"credits","itemLabel":"Extra usage balance","value":"$2.00","note":true}],"rowsUsed":[{"item":"[\"session\",\"\",\"\",false]","value":"20% used","scale":0.2},{"item":"[\"weekly\",\"\",\"\",false]","value":"30% used","scale":0.3},{"item":"[\"billing\",\"\",\"\",false]","value":"40% used","scale":0.4},{"item":"[\"session\",\"Core\",\"\",true]","value":"50% used","scale":0.5},{"item":"credits","value":"$2.00","note":true}],"detailsLeft":{},"detailsUsed":{},"usageItems":[{"id":"[\"session\",\"\",\"\",false]","label":"Session"},{"id":"[\"weekly\",\"\",\"\",false]","label":"Weekly"},{"id":"[\"billing\",\"\",\"\",false]","label":"Monthly"},{"id":"[\"session\",\"Core\",\"\",true]","label":"Core"},{"id":"credits","label":"Extra usage balance"}],"planCell":"","accountPlanSolo":"","accountPlanGrouped":"","status":["Live","ok"],"sourceLabel":"API","metaPlain":"Updated 1m ago","metaSource":"Updated 1m ago · API","compact":[0,1,2,3,4]}
],
"titles": [
["antigravity","sha256:fixture-antigravity-account",0,false,"dev@example.com · #fixtur"],
["antigravity","sha256:ag1",1,false,"dev@example.com · #ag1"],
["antigravity","sha256:fixture-antigravity-account",0,true,"d***v@example.com · #fixtur"],
["antigravity","sha256:ag1",1,true,"d***v@example.com · #ag1"],
["claude","sha256:fixture-claude-account",0,false,"dev@example.com"],
["claude","sha256:fixtureclaudeaaaa",1,false,"pat@example.com · #fixtureclaudea"],
["claude","sha256:fixtureclaudebbbb",2,false,"pat@example.com · #fixtureclaudeb"],
["claude","sha256:fixture-claude-account",0,true,"d***v@example.com"],
["claude","sha256:fixtureclaudeaaaa",1,true,"p***t@example.com · #fixtureclaudea"],
["claude","sha256:fixtureclaudebbbb",2,true,"p***t@example.com · #fixtureclaudeb"],
["cline","sha256:fixture-cline-key",0,false,"Account 1"],
["cline","sha256:fixture-cline-key",0,true,"Account 1"],
["codex","sha256:fixture-codex-account",0,false,"dev@example.com"],
["codex","sha256:c0dexa11",1,false,"dev@example.com · Personal"],
["codex","sha256:c0dexb22",2,false,"dev@example.com · Acme Team"],
["codex","sha256:c0dexc33",3,false,"dav@example.com"],
["codex","",4,false,"Account 5"],
["codex","sha256:fixture-codex-account",0,true,"d***v@example.com · #fixtur"],
["codex","sha256:c0dexa11",1,true,"d***v@example.com · Personal"],
["codex","sha256:c0dexb22",2,true,"d***v@example.com · Acme Team"],
["codex","sha256:c0dexc33",3,true,"d***v@example.com · #c0dexc"],
["codex","",4,true,"Account 5"],
["copilot","sha256:fixture-copilot-account",0,false,"octo-dev"],
["copilot","sha256:fixture-copilot-account",0,true,"octo-dev"],
["cursor","sha256:fixture-cursor-account",0,false,"someone@example.org"],
["cursor","sha256:fixture-cursor-account",0,true,"s***e@example.org"],
["deepseek","sha256:fixture-deepseek-key",0,false,"Account 1"],
["deepseek","sha256:fixture-deepseek-key",0,true,"Account 1"],
["kimi","sha256:fixture-kimi-key",0,false,"Account 1"],
["kimi","sha256:kimi1",1,false,"Account 2"],
["kimi","sha256:fixture-kimi-key",0,true,"Account 1"],
["kimi","sha256:kimi1",1,true,"Account 2"],
["mimo","sha256:fixture-mimo-account",0,false,"MiMo Code"],
["mimo","sha256:mimo1",1,false,"dev@example.com · dev MiMo abc1234 · Console"],
["mimo","sha256:mimo2",2,false,"dev@example.com · dev MiMo abc1234 · Desktop Membership"],
["mimo","sha256:fixture-mimo-account",0,true,"MiMo Code"],
["mimo","sha256:mimo1",1,true,"d***v@example.com · dev MiMo abc1234 · Console"],
["mimo","sha256:mimo2",2,true,"d***v@example.com · dev MiMo abc1234 · Desktop Membership"],
["openrouter","sha256:fixture-openrouter-key",0,false,"API key"],
["openrouter","sha256:or1",1,false,"Environment"],
["openrouter","sha256:or2",2,false,"Team key"],
["openrouter","sha256:fixture-openrouter-key",0,true,"API key"],
["openrouter","sha256:or1",1,true,"Environment"],
["openrouter","sha256:or2",2,true,"Team key"],
["thirdparty","sha256:fixture-relay-account",0,false,"relay-team"],
["thirdparty","sha256:tp1",1,false,"Relay A"],
["thirdparty","sha256:tp2",2,false,"Relay B"],
["thirdparty","sha256:tp3",3,false,"Relay C"],
["thirdparty","sha256:fixture-relay-account",0,true,"relay-team"],
["thirdparty","sha256:tp1",1,true,"Relay A"],
["thirdparty","sha256:tp2",2,true,"Relay B"],
["thirdparty","sha256:tp3",3,true,"Relay C"],
["typesafe","sha256:fixture-typesafe-account",0,false,"dev@example.com"],
["typesafe","sha256:fixture-typesafe-account",0,true,"d***v@example.com"],
["workbuddy","",0,false,"Account 1"],
["workbuddy","",0,true,"Account 1"],
["zai","sha256:fixture-zai-key",0,false,"Account 1"],
["zai","sha256:fixture-zai-key",0,true,"Account 1"],
["zed","sha256:fixture-zed-account",0,false,"dev@example.com"],
["zed","sha256:zed1",1,false,"z@example.com"],
["zed","sha256:fixture-zed-account",0,true,"d***v@example.com"],
["zed","sha256:zed1",1,true,"z***@example.com"],
["opencode","sha256:open1",0,false,"Work profile"],
["opencode","sha256:open2",1,false,"Side"],
["opencode","sha256:open1",0,true,"Work profile"],
["opencode","sha256:open2",1,true,"Side"],
["volcengine","sha256:volc1",0,false,"Coding Plan"],
["volcengine","sha256:volc2",1,false,"Agent Plan"],
["volcengine","sha256:volc1",0,true,"Coding Plan"],
["volcengine","sha256:volc2",1,true,"Agent Plan"],
["kiro","sha256:kiro1",0,false,"Account 1"],
["kiro","sha256:kiro1",0,true,"Account 1"],
["commandcode","sha256:cc1",0,false,"Account 1"],
["commandcode","sha256:cc1",0,true,"Account 1"],
["grok","sha256:grok1",0,false,"Account 1"],
["grok","sha256:grok1",0,true,"Account 1"],
["factory","sha256:f1",0,false,"Account 1"],
["factory","sha256:f1",0,true,"Account 1"]
],
"statusMatrix": [
"claude||Live:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"claude|web|Linked:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"claude|api|Live:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"codex||Live:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"codex|web|Live:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"codex|api|Live:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"opencode||Live:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"opencode|web|Linked:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"opencode|api|Live:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"cursor||Linked:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"cursor|web|Linked:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"cursor|api|Linked:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"antigravity||Live:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"antigravity|web|Live:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"antigravity|api|Live:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"cline||Live:ok;Disabled:muted;Add API key:setup;Open Cline:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"cline|web|Live:ok;Disabled:muted;Add API key:setup;Open Cline:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"cline|api|Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"factory||Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"factory|web|Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"factory|api|Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"kimi||Live:ok;Disabled:muted;Add credential:setup;Update credential:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"kimi|web|Live:ok;Disabled:muted;Add credential:setup;Update credential:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"kimi|api|Live:ok;Disabled:muted;Add credential:setup;Update credential:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"grok||Live:ok;Disabled:muted;Run grok login:setup;Re-login:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"grok|web|Live:ok;Disabled:muted;Run grok login:setup;Re-login:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"grok|api|Live:ok;Disabled:muted;Run grok login:setup;Re-login:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"copilot||Live:ok;Disabled:muted;Sign in:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"copilot|web|Live:ok;Disabled:muted;Sign in:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"copilot|api|Live:ok;Disabled:muted;Sign in:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"zed||Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"zed|web|Linked:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"zed|api|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"commandcode||Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"commandcode|web|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"commandcode|api|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"mimo||Live:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Unavailable:warn",
"mimo|web|Linked:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Unavailable:warn",
"mimo|api|Live:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Unavailable:warn",
"zai||Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"zai|web|Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"zai|api|Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"zaiteam||Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"zaiteam|web|Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"zaiteam|api|Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"kiro||Live:ok;Disabled:muted;Run kiro-cli login:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"kiro|web|Live:ok;Disabled:muted;Run kiro-cli login:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"kiro|api|Live:ok;Disabled:muted;Run kiro-cli login:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"workbuddy||Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"workbuddy|web|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"workbuddy|api|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"qoder||Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"qoder|web|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"qoder|api|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"deepseek||Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"deepseek|web|Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"deepseek|api|Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"devin||Live:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"devin|web|Live:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"devin|api|Live:ok;Disabled:muted;Not set up:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"minimax||Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"minimax|web|Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"minimax|api|Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"typesafe||Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"typesafe|web|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"typesafe|api|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"openrouter||Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"openrouter|web|Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"openrouter|api|Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"volcengine||Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"volcengine|web|Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"volcengine|api|Live:ok;Disabled:muted;Add API key:setup;Update API key:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"ollama||Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"ollama|web|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"ollama|api|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"trae||Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"trae|web|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"trae|api|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"alibaba||Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"alibaba|web|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"alibaba|api|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"stepfun||Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"stepfun|web|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"stepfun|api|Live:ok;Disabled:muted;Sign in:setup;Sign in again:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"thirdparty||Live:ok;Disabled:muted;Add credential:setup;Update credential:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"thirdparty|web|Live:ok;Disabled:muted;Add credential:setup;Update credential:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn",
"thirdparty|api|Live:ok;Disabled:muted;Add credential:setup;Update credential:setup;Limited:warn;Usage API limited:warn;Unavailable:warn;Error:warn"
],
"staleStatus": [
"antigravity",
"ok",
"stale",
"Stale"
],
"home": [
{"name":"defaults","prefs":{},"rows":[{"key":"kimi:0","providerId":"kimi","iconId":"kimi","name":"Account 1","plan":"Kimi Code","lowestRemaining":0,"windows":[{"label":"Session","value":"60% left","severity":"","meter":{"fill":60,"tone":0.95},"reset":"Reset 1h 50m"},{"label":"Weekly","value":"0% left","severity":"critical","meter":{"fill":0,"tone":0.68},"reset":"Reset 1d 5h"}]},{"key":"openrouter:2","providerId":"openrouter","iconId":"openrouter","name":"Team key","plan":"","lowestRemaining":0,"windows":[{"label":"Credits","value":"$0.00","severity":"critical","meter":{"fill":0,"tone":0.68},"reset":""}]},{"key":"claude:2","providerId":"claude","iconId":"claude","name":"pat@example.com · #fixtureclaudeb","plan":"","lowestRemaining":1,"windows":[{"label":"Session","value":"1% left","severity":"critical","meter":{"fill":1,"tone":0.95},"reset":""}]},{"key":"codex:3","providerId":"codex","iconId":"codex","name":"dav@example.com","plan":"Limited","lowestRemaining":3,"windows":[{"label":"Weekly","value":"3% left","severity":"critical","meter":{"fill":3,"tone":0.68},"reset":""}]},{"key":"volcengine:1","providerId":"volcengine","iconId":"volcengine","name":"Agent Plan","plan":"Limited","lowestRemaining":9,"windows":[{"label":"Session","value":"9% left","severity":"critical","meter":{"fill":9,"tone":0.95},"reset":""}]},{"key":"antigravity:1","providerId":"antigravity","iconId":"antigravity","name":"dev@example.com · #ag1","plan":"","lowestRemaining":15,"windows":[{"label":"Gemini Pro","value":"15% left","severity":"critical","meter":{"fill":15,"tone":0.68},"reset":"Weekly · Reset 3d 11h"},{"label":"Claude","value":"50% left","severity":"","meter":{"fill":50,"tone":0.95},"reset":"5-hour · Reset 30m"}]},{"key":"codex:1","providerId":"codex","iconId":"codex","name":"dev@example.com · Personal","plan":"","lowestRemaining":18,"windows":[{"label":"Session","value":"18% left","severity":"critical","meter":{"fill":18,"tone":0.95},"reset":"Reset 1h 10m"},{"label":"Weekly","value":"60% left","severity":"","meter":{"fill":60,"tone":0.68},"reset":"Reset 2d 2h"}]},{"key":"thirdparty:2","providerId":"thirdparty","iconId":"sub2api","name":"Relay B","plan":"Sub2API · Account","lowestRemaining":25,"windows":[{"label":"Balance","value":"$3.50","severity":"low","meter":{"fill":25,"tone":0.68},"reset":""}]},{"key":"opencode:1","providerId":"opencode","iconId":"opencode","name":"Side","plan":"Go","lowestRemaining":30,"windows":[{"label":"Weekly","value":"30% left","severity":"low","meter":{"fill":30,"tone":0.68},"reset":""}]},{"key":"kimi:1","providerId":"kimi","iconId":"kimi","name":"Account 2","plan":"","lowestRemaining":30,"windows":[{"label":"Session","value":"30% left","severity":"low","meter":{"fill":30,"tone":0.95},"reset":""},{"label":"billing","value":"75% left","severity":"","meter":{"fill":75,"tone":0.68},"reset":"Changes in 1m"}]},{"key":"codex:0","providerId":"codex","iconId":"codex","name":"dev@example.com","plan":"Plus","lowestRemaining":39,"windows":[{"label":"Session","value":"92% left","severity":"","meter":{"fill":92,"tone":0.95},"reset":"Reset 4h 0m"},{"label":"Weekly","value":"39% left","severity":"low","meter":{"fill":39,"tone":0.68},"reset":"Reset 2d 0h"}]},{"key":"openrouter:1","providerId":"openrouter","iconId":"openrouter","name":"Environment","plan":"API key","lowestRemaining":40,"windows":[{"label":"Credits","value":"$4.00","severity":"low","meter":{"fill":40,"tone":0.68},"reset":""}]}]},
{"name":"count3Used","prefs":{"homeLimitAccountCount":3,"showLimitUsed":true},"rows":[{"key":"kimi:0","providerId":"kimi","iconId":"kimi","name":"Account 1","plan":"Kimi Code","lowestRemaining":0,"windows":[{"label":"Session","value":"40% used","severity":"","meter":{"fill":40,"tone":0.95},"reset":"Reset 1h 50m"},{"label":"Weekly","value":"100% used","severity":"critical","meter":{"fill":100,"tone":0.68},"reset":"Reset 1d 5h"}]},{"key":"openrouter:2","providerId":"openrouter","iconId":"openrouter","name":"Team key","plan":"","lowestRemaining":0,"windows":[{"label":"Credits","value":"$0.00","severity":"critical","meter":{"fill":0,"tone":0.68},"reset":""}]},{"key":"claude:2","providerId":"claude","iconId":"claude","name":"pat@example.com · #fixtureclaudeb","plan":"","lowestRemaining":1,"windows":[{"label":"Session","value":"99% used","severity":"critical","meter":{"fill":99,"tone":0.95},"reset":""}]}]},
{"name":"customOrderHidden","prefs":{"homeLimitProviderOrder":["zed","codex","claude"],"hiddenHomeLimitProviders":["kimi","deepseek"],"limitProviderHiddenItems":{"claude":["[\"weekly\",\"Opus\",\"\",false]"],"codex":["[\"id\",\"codex\",\"session\",\"\",false,300]"]},"showToolIcons":false,"maskLimitAccountEmails":true,"showLimitUsed":true},"rows":[{"key":"zed:0","providerId":"zed","iconId":"zed","name":"Zed · d***v@example.com","plan":"Pro","lowestRemaining":80,"windows":[{"label":"Prompts","value":"20% used","severity":"","meter":{"fill":20,"tone":0.68},"reset":"Reset 18d 0h"},{"label":"Edit predictions","value":"Unlimited","severity":"","meter":null,"reset":""}]},{"key":"zed:1","providerId":"zed","iconId":"zed","name":"Zed · z***@example.com","plan":"Student","lowestRemaining":60,"windows":[{"label":"Token Spend","value":"40% used","severity":"","meter":{"fill":40,"tone":0.68},"reset":"Reset 15h 0m"},{"label":"Edit predictions","value":"Unlimited","severity":"","meter":null,"reset":""}]},{"key":"codex:0","providerId":"codex","iconId":"codex","name":"Codex · d***v@example.com · #fixtur","plan":"Plus","lowestRemaining":39,"windows":[{"label":"Weekly","value":"61% used","severity":"low","meter":{"fill":61,"tone":0.68},"reset":"Reset 2d 0h"}]},{"key":"codex:1","providerId":"codex","iconId":"codex","name":"Codex · d***v@example.com · Personal","plan":"","lowestRemaining":60,"windows":[{"label":"Weekly","value":"40% used","severity":"","meter":{"fill":40,"tone":0.68},"reset":"Reset 2d 2h"}]},{"key":"codex:3","providerId":"codex","iconId":"codex","name":"Codex · d***v@example.com · #c0dexc","plan":"Limited","lowestRemaining":3,"windows":[{"label":"Weekly","value":"97% used","severity":"critical","meter":{"fill":97,"tone":0.68},"reset":""}]},{"key":"claude:0","providerId":"claude","iconId":"claude","name":"Claude · d***v@example.com","plan":"Max","lowestRemaining":58,"windows":[{"label":"Session","value":"42% used","severity":"","meter":{"fill":42,"tone":0.95},"reset":"Reset 2h 30m"},{"label":"Weekly","value":"21% used","severity":"","meter":{"fill":20.5,"tone":0.68},"reset":"Reset 4d 3h"}]},{"key":"claude:1","providerId":"claude","iconId":"claude","name":"Claude · p***t@example.com · #fixtureclaudea","plan":"Pro","lowestRemaining":45,"windows":[{"label":"Session","value":"12% used","severity":"","meter":{"fill":12,"tone":0.95},"reset":""},{"label":"Weekly","value":"55% used","severity":"low","meter":{"fill":55,"tone":0.68},"reset":""}]},{"key":"claude:2","providerId":"claude","iconId":"claude","name":"Claude · p***t@example.com · #fixtureclaudeb","plan":"","lowestRemaining":1,"windows":[{"label":"Session","value":"99% used","severity":"critical","meter":{"fill":99,"tone":0.95},"reset":""}]},{"key":"opencode:0","providerId":"opencode","iconId":"opencode","name":"OpenCode · Work profile","plan":"","lowestRemaining":67,"windows":[{"label":"Session","value":"33% used","severity":"","meter":{"fill":33,"tone":0.95},"reset":""},{"label":"billing","value":"10% used","severity":"","meter":{"fill":10,"tone":0.68},"reset":""}]},{"key":"opencode:1","providerId":"opencode","iconId":"opencode","name":"OpenCode · Side","plan":"Go","lowestRemaining":30,"windows":[{"label":"Weekly","value":"70% used","severity":"low","meter":{"fill":70,"tone":0.68},"reset":""}]},{"key":"cursor:0","providerId":"cursor","iconId":"cursor","name":"Cursor","plan":"Usage API limited","lowestRemaining":53,"windows":[{"label":"Cursor Models","value":"47% used","severity":"","meter":{"fill":47,"tone":0.68},"reset":"Reset 12d 0h"}]},{"key":"antigravity:1","providerId":"antigravity","iconId":"antigravity","name":"Antigravity · d***v@example.com · #ag1","plan":"","lowestRemaining":15,"windows":[{"label":"Gemini Pro","value":"85% used","severity":"critical","meter":{"fill":85,"tone":0.68},"reset":"Weekly · Reset 3d 11h"},{"label":"Claude","value":"50% used","severity":"","meter":{"fill":50,"tone":0.95},"reset":"5-hour · Reset 30m"}]}]},
{"name":"limitOrderOnly","prefs":{"limitProviderOrder":["mimo","codex"],"showHomeLimitProviderNames":true},"rows":[{"key":"kimi:0","providerId":"kimi","iconId":"kimi","name":"Kimi · Account 1","plan":"Kimi Code","lowestRemaining":0,"windows":[{"label":"Session","value":"60% left","severity":"","meter":{"fill":60,"tone":0.95},"reset":"Reset 1h 50m"},{"label":"Weekly","value":"0% left","severity":"critical","meter":{"fill":0,"tone":0.68},"reset":"Reset 1d 5h"}]},{"key":"openrouter:2","providerId":"openrouter","iconId":"openrouter","name":"OpenRouter · Team key","plan":"","lowestRemaining":0,"windows":[{"label":"Credits","value":"$0.00","severity":"critical","meter":{"fill":0,"tone":0.68},"reset":""}]},{"key":"claude:2","providerId":"claude","iconId":"claude","name":"Claude · pat@example.com · #fixtureclaudeb","plan":"","lowestRemaining":1,"windows":[{"label":"Session","value":"1% left","severity":"critical","meter":{"fill":1,"tone":0.95},"reset":""}]},{"key":"codex:3","providerId":"codex","iconId":"codex","name":"Codex · dav@example.com","plan":"Limited","lowestRemaining":3,"windows":[{"label":"Weekly","value":"3% left","severity":"critical","meter":{"fill":3,"tone":0.68},"reset":""}]},{"key":"volcengine:1","providerId":"volcengine","iconId":"volcengine","name":"Volcengine · Agent Plan","plan":"Limited","lowestRemaining":9,"windows":[{"label":"Session","value":"9% left","severity":"critical","meter":{"fill":9,"tone":0.95},"reset":""}]},{"key":"antigravity:1","providerId":"antigravity","iconId":"antigravity","name":"Antigravity · dev@example.com · #ag1","plan":"","lowestRemaining":15,"windows":[{"label":"Gemini Pro","value":"15% left","severity":"critical","meter":{"fill":15,"tone":0.68},"reset":"Weekly · Reset 3d 11h"},{"label":"Claude","value":"50% left","severity":"","meter":{"fill":50,"tone":0.95},"reset":"5-hour · Reset 30m"}]},{"key":"codex:1","providerId":"codex","iconId":"codex","name":"Codex · dev@example.com · Personal","plan":"","lowestRemaining":18,"windows":[{"label":"Session","value":"18% left","severity":"critical","meter":{"fill":18,"tone":0.95},"reset":"Reset 1h 10m"},{"label":"Weekly","value":"60% left","severity":"","meter":{"fill":60,"tone":0.68},"reset":"Reset 2d 2h"}]},{"key":"thirdparty:2","providerId":"thirdparty","iconId":"sub2api","name":"Third-party APIs · Relay B","plan":"Sub2API · Account","lowestRemaining":25,"windows":[{"label":"Balance","value":"$3.50","severity":"low","meter":{"fill":25,"tone":0.68},"reset":""}]},{"key":"opencode:1","providerId":"opencode","iconId":"opencode","name":"OpenCode · Side","plan":"Go","lowestRemaining":30,"windows":[{"label":"Weekly","value":"30% left","severity":"low","meter":{"fill":30,"tone":0.68},"reset":""}]},{"key":"kimi:1","providerId":"kimi","iconId":"kimi","name":"Kimi · Account 2","plan":"","lowestRemaining":30,"windows":[{"label":"Session","value":"30% left","severity":"low","meter":{"fill":30,"tone":0.95},"reset":""},{"label":"billing","value":"75% left","severity":"","meter":{"fill":75,"tone":0.68},"reset":"Changes in 1m"}]},{"key":"codex:0","providerId":"codex","iconId":"codex","name":"Codex · dev@example.com","plan":"Plus","lowestRemaining":39,"windows":[{"label":"Session","value":"92% left","severity":"","meter":{"fill":92,"tone":0.95},"reset":"Reset 4h 0m"},{"label":"Weekly","value":"39% left","severity":"low","meter":{"fill":39,"tone":0.68},"reset":"Reset 2d 0h"}]},{"key":"openrouter:1","providerId":"openrouter","iconId":"openrouter","name":"OpenRouter · Environment","plan":"API key","lowestRemaining":40,"windows":[{"label":"Credits","value":"$4.00","severity":"low","meter":{"fill":40,"tone":0.68},"reset":""}]}]},
{"name":"homeOrderEqualsCatalog","prefs":{"homeLimitProviderOrder":["claude","codex","opencode","cursor","antigravity","cline","factory","kimi","grok","copilot","zed","commandcode","mimo","zai","zaiteam","kiro","workbuddy","qoder","deepseek","devin","minimax","typesafe","openrouter","volcengine","ollama","trae","alibaba","stepfun","thirdparty"],"homeLimitAccountCount":5},"rows":[{"key":"kimi:0","providerId":"kimi","iconId":"kimi","name":"Account 1","plan":"Kimi Code","lowestRemaining":0,"windows":[{"label":"Session","value":"60% left","severity":"","meter":{"fill":60,"tone":0.95},"reset":"Reset 1h 50m"},{"label":"Weekly","value":"0% left","severity":"critical","meter":{"fill":0,"tone":0.68},"reset":"Reset 1d 5h"}]},{"key":"openrouter:2","providerId":"openrouter","iconId":"openrouter","name":"Team key","plan":"","lowestRemaining":0,"windows":[{"label":"Credits","value":"$0.00","severity":"critical","meter":{"fill":0,"tone":0.68},"reset":""}]},{"key":"claude:2","providerId":"claude","iconId":"claude","name":"pat@example.com · #fixtureclaudeb","plan":"","lowestRemaining":1,"windows":[{"label":"Session","value":"1% left","severity":"critical","meter":{"fill":1,"tone":0.95},"reset":""}]},{"key":"codex:3","providerId":"codex","iconId":"codex","name":"dav@example.com","plan":"Limited","lowestRemaining":3,"windows":[{"label":"Weekly","value":"3% left","severity":"critical","meter":{"fill":3,"tone":0.68},"reset":""}]},{"key":"volcengine:1","providerId":"volcengine","iconId":"volcengine","name":"Agent Plan","plan":"Limited","lowestRemaining":9,"windows":[{"label":"Session","value":"9% left","severity":"critical","meter":{"fill":9,"tone":0.95},"reset":""}]}]}
],
"durations": [
{"ms":0,"text":"<1m"},
{"ms":1,"text":"<1m"},
{"ms":29999,"text":"<1m"},
{"ms":30000,"text":"1m"},
{"ms":89999,"text":"1m"},
{"ms":90000,"text":"2m"},
{"ms":3599999,"text":"1h 0m"},
{"ms":3600000,"text":"1h 0m"},
{"ms":86399999,"text":"1d 0h"},
{"ms":86400000,"text":"1d 0h"},
{"ms":90061000,"text":"1d 1h"},
{"ms":1000000000000,"text":"11574d 1h"}
],
"ages": [
{"ms":0,"text":"Updated just now"},
{"ms":44999,"text":"Updated just now"},
{"ms":45000,"text":"Updated 1m ago"},
{"ms":89999,"text":"Updated 1m ago"},
{"ms":90000,"text":"Updated 2m ago"},
{"ms":3569999,"text":"Updated 59m ago"},
{"ms":3570000,"text":"Updated 1h ago"},
{"ms":84540000,"text":"Updated 23h ago"},
{"ms":84600000,"text":"Updated 1d ago"},
{"ms":129600000,"text":"Updated 2d ago"},
{"ms":259200000,"text":"Updated 3d ago"}
],
"planLabels": [
{"provider":"zai","label":"GLM Coding Lite","text":"Lite"},
{"provider":"zai","label":"glm  coding   max","text":"max"},
{"provider":"zai","label":"GLM Coding ","text":"GLM Coding"},
{"provider":"zai","label":"Z.ai Pro","text":"Z.ai Pro"},
{"provider":"zed","label":"Zed Student","text":"Student"},
{"provider":"zed","label":"zed","text":"Zed"},
{"provider":"zed","label":"Zedd Pro","text":"Zedd Pro"},
{"provider":"claude","label":"max","text":"Max"},
{"provider":"claude","label":"ümax","text":"ümax"},
{"provider":"claude","label":"a@b.c","text":"a@b.c"},
{"provider":"claude","label":"  pro  ","text":"Pro"},
{"provider":"codex","label":"","text":""},
{"provider":"typesafe","label":"credits","text":"Credits"}
],
"homeOrders": [
{"order":[],"normalized":[]},
{"order":["claude"],"normalized":["claude"]},
{"order":["claude","codex","opencode","cursor","antigravity","cline","factory","kimi","grok","copilot","zed","commandcode","mimo","zai","zaiteam","kiro","workbuddy","qoder","deepseek","devin","minimax","typesafe","openrouter","volcengine","ollama","trae","alibaba","stepfun","thirdparty"],"normalized":[]},
{"order":["claude","codex","opencode","cursor","antigravity","cline","factory","kimi","grok","copilot","zed","commandcode","mimo","zai","zaiteam","kiro","workbuddy","qoder","deepseek","devin","minimax","typesafe","openrouter","volcengine","ollama","trae","alibaba","stepfun","thirdparty","nope"],"normalized":[]},
{"order":["CLAUDE","codex","opencode","cursor","antigravity","cline","factory","kimi","grok","copilot","zed","commandcode","mimo","zai","zaiteam","kiro","workbuddy","qoder","deepseek","devin","minimax","typesafe","openrouter","volcengine","ollama","trae","alibaba","stepfun","thirdparty"],"normalized":[]},
{"order":["codex","claude"],"normalized":["codex","claude"]}
]
}
"""##

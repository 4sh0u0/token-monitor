import Foundation
import XCTest
@testable import TokenMonitorKit

// Golden parity for the device, client-health and live-rate ports against
// `Fixtures/v2/golden/client-health.json` and `live-rate.json`, which were
// rendered by running the desktop modules on `Fixtures/v2/stats.json`
// (see `Fixtures/v2/README.txt`).

// MARK: - Client health and devices

final class ClientHealthPresentationTests: XCTestCase {
    func testToneTablesMatchTheDesktop() throws {
        let golden = try DeviceGolden.object("client-health.json")
        let overallTones = try XCTUnwrap(golden["overallTones"] as? [String: String])
        XCTAssertEqual(overallTones.count, ClientHealthOverall.allCases.count)
        for overall in ClientHealthOverall.allCases {
            XCTAssertEqual(overall.tone.rawValue, overallTones[overall.rawValue], overall.rawValue)
        }
        let diagnosticTones = try XCTUnwrap(golden["diagnosticTones"] as? [String: String])
        XCTAssertEqual(Set(diagnosticTones.keys), Set(ClientHealthDiagnostic.allCases.map(\.rawValue)))
        for code in ClientHealthDiagnostic.allCases {
            XCTAssertEqual(code.tone.rawValue, diagnosticTones[code.rawValue], code.rawValue)
        }
    }

    func testClientHealthGolden() throws {
        let golden = try DeviceGolden.object("client-health.json")
        let goldenDevices = try XCTUnwrap(golden["devices"] as? [[String: Any]])
        let devices = try DeviceGolden.rawDevices()
        XCTAssertEqual(goldenDevices.count, 4)

        for goldenDevice in goldenDevices {
            let id = try XCTUnwrap(goldenDevice["deviceId"] as? String)
            let device = try XCTUnwrap(devices.first { $0.id == id }, id)
            XCTAssertEqual(device.displayName, goldenDevice["label"] as? String, id)
            XCTAssertEqual(
                DevicePresentation.platformLabel(platform: device.platform, osName: device.osName, osVersion: device.osVersion),
                goldenDevice["platformLabel"] as? String, id
            )
            XCTAssertEqual(DevicePresentation.platformLabel(device), goldenDevice["platformLabel"] as? String, id)
            XCTAssertEqual(device.trackedClients, goldenDevice["trackedClients"] as? [String], id)

            // Status tags, including an unknown status ("paused").
            let statuses = try XCTUnwrap(goldenDevice["clientStatus"] as? [String: String])
            let goldenTags = try XCTUnwrap(goldenDevice["statusTags"] as? [String: Any])
            XCTAssertEqual(Set(goldenTags.keys), Set(statuses.keys).union(["zz-unknown"]), id)
            for (client, expected) in goldenTags {
                let tag = ClientStatusTag.tag(client: client, status: client == "zz-unknown" ? "paused" : statuses[client])
                if let expected = expected as? [String: String] {
                    XCTAssertEqual(tag.map { "settings.tools.status.\($0.rawValue)" }, expected["key"], "\(id) \(client)")
                    XCTAssertEqual(tag?.tone.rawValue, expected["tone"], "\(id) \(client)")
                } else {
                    XCTAssertNil(tag, "\(id) \(client)")
                }
            }
            let deviceTags = ClientStatusTag.tags(for: device)
            XCTAssertEqual(Set(deviceTags.keys), Set(statuses.keys), id)

            // Counts for the tracked tools, and with an `unknown` one added.
            XCTAssertEqual((goldenDevice["hasHealth"] as? Bool), device.clientHealth != nil, id)
            XCTAssertEqual(
                ClientHealthPresentation.counts(device: device).map(DeviceGolden.counts),
                goldenDevice["counts"] as? [String: Int], id
            )
            XCTAssertEqual(
                ClientHealthPresentation.counts(report: device.clientHealth, tracked: device.trackedClients + ["antigravity"]).map(DeviceGolden.counts),
                goldenDevice["countsWithUnknown"] as? [String: Int], id
            )

            // Details per client (health ids, tracked ids and an absent one).
            let details = try XCTUnwrap(goldenDevice["details"] as? [String: [String: Any]])
            for (client, entry) in details {
                let label = "\(id) \(client)"
                XCTAssertEqual(ClientHealthPresentation.hasHealth(report: device.clientHealth, clientID: client), entry["has"] as? Bool, label)
                let detail = ClientHealthPresentation.detail(device: device, clientID: client)
                guard let expected = entry["detail"] as? [String: Any] else {
                    XCTAssertNil(detail, label)
                    continue
                }
                let actual = try XCTUnwrap(detail, label)
                try DeviceGolden.assertDetail(actual, matches: expected, label)
            }
        }
    }

    func testNotesFollowTheQuietRuleAndSkipUnknownCodes() {
        let unavailable = ClientHealthEntry(
            overall: .unavailable,
            sourceState: "missing",
            diagnostics: ["source-missing", "no-usage-observed", "sync-failed", "made-up-code"]
        )
        XCTAssertEqual(ClientHealthPresentation.notes(entry: unavailable).map(\.code), [.syncFailed])

        let waiting = ClientHealthEntry(overall: .waiting, diagnostics: ["no-usage-observed", "wsl-detected-no-data", "sync-lock-present"])
        let notes = ClientHealthPresentation.notes(entry: waiting)
        XCTAssertEqual(notes.map(\.code), [.noUsageObserved, .wslDetectedNoData, .syncLockPresent])
        XCTAssertEqual(notes.map(\.group), [.data, .data, .collection])
        XCTAssertEqual(notes.map(\.tone), [.muted, .neutral, .warn])

        let detail = ClientHealthPresentation.detail(entry: waiting)
        XCTAssertEqual(detail.groups, [.source, .collection, .data])
        XCTAssertEqual(detail.notes(in: .data).count, 2)
        XCTAssertEqual(detail.notes(in: .collection).map(\.code), [.syncLockPresent])
        XCTAssertNil(detail.data.periods, "no usage supplied: the panel prints liveTokens")
        XCTAssertEqual(detail.tone, .neutral)
    }

    func testDetailNormalizesStatesAndChecks() {
        let entry = ClientHealthEntry(
            overall: .attention,
            sourceState: "sideways",
            detectedCount: 1,
            checkedCount: 2,
            checks: [ClientHealthCheck(id: "a", exists: true), ClientHealthCheck(id: "a", exists: false), ClientHealthCheck(id: "b", exists: false)],
            collectionState: "notTracked",
            syncFailureStage: "spawn",
            syncDetailCode: "ENOENT",
            syncExitCode: 127,
            lastActivityDay: ""
        )
        let usage = [
            ClientHealthPeriodUsage(period: .allTime, tokens: 30, costUsd: 3),
            ClientHealthPeriodUsage(period: .today, tokens: 10, costUsd: -1)
        ]
        let detail = ClientHealthPresentation.detail(entry: entry, usage: usage)
        XCTAssertEqual(detail.source.state, .unknown)
        XCTAssertEqual(detail.source.checks, [ClientHealthCheck(id: "a", exists: true), ClientHealthCheck(id: "b", exists: false)])
        XCTAssertEqual(detail.collection.state, .notTracked)
        XCTAssertEqual(detail.collection.failureStage, "spawn")
        XCTAssertEqual(detail.collection.detailCode, "ENOENT")
        XCTAssertEqual(detail.collection.exitCode, 127)
        XCTAssertNil(detail.data.lastActivityDay)
        XCTAssertEqual(detail.data.periods, [
            ClientHealthPeriodUsage(period: .today, tokens: 10, costUsd: 0),
            ClientHealthPeriodUsage(period: .month, tokens: 0, costUsd: 0),
            ClientHealthPeriodUsage(period: .allTime, tokens: 30, costUsd: 3)
        ])
        XCTAssertEqual(ClientHealthCollectionState(wire: "ok"), .ok)
        XCTAssertEqual(ClientHealthCollectionState(wire: "later"), .unknown)
        XCTAssertEqual(ClientHealthSourceState(wire: nil), .unknown)
    }

    func testCountsEdgeCases() {
        XCTAssertNil(ClientHealthPresentation.counts(report: nil, tracked: ["claude"]))
        let report = ClientHealthReport(clients: [
            "claude": ClientHealthEntry(overall: .healthy),
            "codex": ClientHealthEntry(overall: .attention),
            "kimi": ClientHealthEntry(overall: .waiting)
        ])
        // Trimmed, lower-cased and de-duplicated; blanks ignored.
        XCTAssertEqual(
            ClientHealthPresentation.counts(report: report, tracked: [" Claude ", "claude", "", "codex", "kimi"]),
            ClientHealthCounts(healthy: 1, review: 2, unavailable: 0)
        )
        XCTAssertEqual(ClientHealthPresentation.counts(report: report, tracked: [])?.total, 0)
        XCTAssertNil(ClientHealthPresentation.counts(report: report, tracked: ["claude", "cursor"]), "a tracked tool without an entry")
    }

    func testRelativeDay() {
        XCTAssertEqual(ClientHealthPresentation.relativeDay("2026-10-10", todayKey: "2026-10-10"), .today)
        XCTAssertEqual(ClientHealthPresentation.relativeDay("2026-10-09", todayKey: "2026-10-10"), .yesterday)
        XCTAssertEqual(ClientHealthPresentation.relativeDay("2026-10-04", todayKey: "2026-10-10"), .daysAgo(6))
        XCTAssertEqual(ClientHealthPresentation.relativeDay("2026-02-28", todayKey: "2026-03-01"), .yesterday)
        XCTAssertEqual(ClientHealthPresentation.relativeDay("2026-10-11", todayKey: "2026-10-10"), .date("2026-10-11"))
        XCTAssertEqual(ClientHealthPresentation.relativeDay("soon", todayKey: "2026-10-10"), .date("soon"))
    }

    func testToolStatusesOfADevice() throws {
        let studio = try XCTUnwrap(DeviceGolden.rawDevices().first { $0.id == "studio-mac" })
        let statuses = ClientHealthPresentation.toolStatuses(device: studio)
        // Catalog order; gemini is not in the catalog's client list, so last.
        XCTAssertEqual(statuses.map(\.clientID), ["claude", "codex", "opencode", "cursor", "antigravity", "gemini"])
        XCTAssertEqual(statuses.filter(\.isTracked).map(\.clientID), ["claude", "codex", "opencode", "cursor", "gemini"])
        let byID = Dictionary(uniqueKeysWithValues: statuses.map { ($0.clientID, $0) })
        XCTAssertEqual(byID["cursor"]?.tag, .signIn)
        XCTAssertEqual(byID["antigravity"]?.tag, .openApp)
        XCTAssertEqual(byID["gemini"]?.tag, .waiting)
        XCTAssertEqual(byID["opencode"]?.health?.overall, .attention)
        XCTAssertEqual(byID["antigravity"]?.health?.overall, .unknown)

        let buildBox = try XCTUnwrap(DeviceGolden.rawDevices().first { $0.id == "build-box" })
        let buildStatuses = ClientHealthPresentation.toolStatuses(device: buildBox)
        XCTAssertEqual(buildStatuses.map(\.clientID), ["claude", "hermes", "qwen", "gemini"])
        XCTAssertTrue(buildStatuses.allSatisfy { $0.health == nil })
        XCTAssertEqual(buildStatuses.first { $0.clientID == "qwen" }?.tag, .waiting)
    }

    func testStatusTagMatchesTheDesktopRules() {
        XCTAssertEqual(ClientStatusTag.tag(client: "Cursor", status: "missing"), .signIn)
        XCTAssertEqual(ClientStatusTag.tag(client: "antigravity", status: "missing"), .openApp)
        XCTAssertEqual(ClientStatusTag.tag(client: "claude", status: "missing"), .missing)
        XCTAssertEqual(ClientStatusTag.tag(client: "cursor", status: "active"), .active)
        XCTAssertNil(ClientStatusTag.tag(client: "claude", status: nil))
        XCTAssertNil(ClientStatusTag.tag(client: "claude", status: "Active"), "statuses match exactly")
        XCTAssertEqual(ClientStatusTag.missing.tone, .muted)
        XCTAssertEqual(ClientStatusTag.signIn.tone, .setup)
    }
}

final class DevicePresentationTests: XCTestCase {
    func testToolRowsGolden() throws {
        let golden = try DeviceGolden.object("client-health.json")
        let goldenDevices = try XCTUnwrap(golden["devices"] as? [[String: Any]])
        let devices = try DeviceGolden.rawDevices()
        var sawUnclassified = false

        for goldenDevice in goldenDevices {
            let id = try XCTUnwrap(goldenDevice["deviceId"] as? String)
            let device = try XCTUnwrap(devices.first { $0.id == id })
            let toolRows = try XCTUnwrap(goldenDevice["toolRows"] as? [String: [String: Any]])
            for kind in UsagePeriodKind.allCases {
                let label = "\(id) \(kind.rawValue)"
                let expected = try XCTUnwrap(toolRows[kind.rawValue], label)
                let breakdown = DevicePresentation.toolBreakdown(device: device, period: kind)
                XCTAssertEqual(breakdown.totalTokens, expected["totalTokens"] as? Int, label)
                XCTAssertTrue(breakdown.modelsAvailable, label)
                XCTAssertNil(breakdown.emptyState, label)
                XCTAssertEqual(DevicePresentation.toolRows(device: device, period: kind), breakdown.tools, label)
                let tools = try XCTUnwrap(expected["tools"] as? [[String: Any]], label)
                XCTAssertEqual(breakdown.tools.map(\.id), tools.map { $0["key"] as? String ?? "" }, label)
                for (row, tool) in zip(breakdown.tools, tools) {
                    let rowLabel = "\(label) \(row.id)"
                    XCTAssertEqual(row.id, tool["client"] as? String, rowLabel)
                    if row.isUnattributed {
                        sawUnclassified = true
                        XCTAssertNil(row.clientID, rowLabel)
                        XCTAssertEqual(tool["name"] as? String, "Unclassified", rowLabel)
                    } else {
                        XCTAssertEqual(row.clientID, row.id, rowLabel)
                        XCTAssertEqual(VendorCatalog.clientLabel(row.id), tool["name"] as? String, rowLabel)
                    }
                    XCTAssertEqual(row.tokens, tool["value"] as? Int, rowLabel)
                    XCTAssertEqual(row.percent, try XCTUnwrap(tool["percent"] as? Double), accuracy: 1e-9, rowLabel)
                    let models = try XCTUnwrap(tool["models"] as? [[Any]], rowLabel)
                    XCTAssertEqual(row.models.map(\.model), models.map { $0[0] as? String ?? "" }, rowLabel)
                    XCTAssertEqual(row.models.map(\.tokens), models.map { $0[1] as? Int ?? -1 }, rowLabel)
                }
            }
        }
        XCTAssertTrue(sawUnclassified, "build-box carries a synthetic Unclassified row")
    }

    func testExpiredPeriodsReadAsEmpty() throws {
        // The Hub decode applies the aggregate expiry rule: old-laptop's
        // `today` window ended (the desktop list would still show it).
        let stats = try DeviceGolden.stats(.app)
        let oldLaptop = try XCTUnwrap(stats.device(id: "old-laptop"))
        let today = DevicePresentation.toolBreakdown(device: oldLaptop, period: .today)
        XCTAssertEqual(today.totalTokens, 0)
        XCTAssertEqual(today.tools, [])
        XCTAssertEqual(today.emptyState, .noTools)
        XCTAssertFalse(today.modelsAvailable)
        let row = DevicePresentation.row(oldLaptop, period: .today)
        XCTAssertTrue(row.isExpired)
        XCTAssertTrue(row.isStale)
        XCTAssertEqual(row.tokens, 0)
        // Its month has not ended.
        XCTAssertEqual(DevicePresentation.toolBreakdown(device: oldLaptop, period: .month).totalTokens, 10_800_000)
        XCTAssertFalse(DevicePresentation.row(oldLaptop, period: .month).isExpired)
    }

    func testBreakdownWithoutDetailsHasNoModels() throws {
        // `.compact` (widgets) does not decode per-device detail.
        let stats = try DeviceGolden.stats(.compact)
        let studio = try XCTUnwrap(stats.device(id: "studio-mac"))
        let breakdown = DevicePresentation.toolBreakdown(device: studio, period: .today)
        XCTAssertEqual(breakdown.tools.map(\.id), ["claude", "codex", "opencode"])
        XCTAssertFalse(breakdown.modelsAvailable)
        XCTAssertTrue(breakdown.tools.allSatisfy { $0.models.isEmpty })
    }

    func testSyntheticUnclassifiedAndEmptyStates() {
        let onlyRemainder = DevicePresentation.toolBreakdown(totalTokens: 500, clients: [], clientModels: [:], modelsAvailable: false)
        XCTAssertEqual(onlyRemainder.tools, [DeviceToolRow(id: DeviceToolRow.unattributedID, tokens: 500, percent: 100, models: [])])
        XCTAssertNil(onlyRemainder.emptyState)

        XCTAssertEqual(DevicePresentation.toolBreakdown(totalTokens: 0, clients: [], clientModels: [:], modelsAvailable: true).emptyState, .noTools)
        XCTAssertEqual(DeviceToolBreakdown(totalTokens: 10, tools: [], modelsAvailable: false).emptyState, .detailsUnavailable)

        // Tools that over-count the total: no remainder; zero tools dropped;
        // ties by catalog name; models positive only, tokens then name.
        let clients = [
            UsageShare.client("codex", tokens: 60, costUsd: 1),
            UsageShare.client("claude", tokens: 60, costUsd: nil),
            UsageShare.client("kimi", tokens: 0, costUsd: 2)
        ]
        let models: [String: [String: UsageBreakdownEntry]] = [
            "claude": [
                "b-model": UsageBreakdownEntry(tokens: 30, costUsd: 0),
                "A-model": UsageBreakdownEntry(tokens: 30, costUsd: 0),
                "zero": UsageBreakdownEntry(tokens: 0, costUsd: 1)
            ]
        ]
        let breakdown = DevicePresentation.toolBreakdown(totalTokens: 100, clients: clients, clientModels: models, modelsAvailable: true)
        XCTAssertEqual(breakdown.tools.map(\.id), ["claude", "codex"], "Claude Code < Codex")
        XCTAssertEqual(breakdown.tools.first?.models.map(\.model), ["A-model", "b-model"])
        XCTAssertEqual(breakdown.tools.map(\.percent), [60, 60])
    }

    func testRowsHomeDevicesOrderingAndCounts() throws {
        let stats = try DeviceGolden.stats(.app)
        XCTAssertEqual(DevicePresentation.rows(stats: stats, period: .month).map(\.id), ["studio-mac", "build-box", "tokyo-mac", "old-laptop"])
        XCTAssertEqual(DevicePresentation.rows(stats: stats, period: .today).map(\.id), ["studio-mac", "build-box", "tokyo-mac", "old-laptop"])
        XCTAssertEqual(DevicePresentation.homeDevices(stats: stats, period: .today).map(\.id), ["studio-mac", "build-box", "tokyo-mac"])
        XCTAssertEqual(DevicePresentation.homeDevices(stats: stats, period: .month, limit: 2).map(\.id), ["studio-mac", "build-box"])
        XCTAssertEqual(DevicePresentation.homeDevices(stats: stats, period: .month, limit: 0), [])

        XCTAssertEqual(DevicePresentation.ordered(stats.devices).map(\.id), ["studio-mac", "tokyo-mac", "build-box", "old-laptop"])
        XCTAssertEqual(DevicePresentation.onlineCount(stats: stats), DeviceCounts(online: 3, total: 4))

        let studio = try XCTUnwrap(DevicePresentation.rows(stats: stats, period: .today).first)
        XCTAssertEqual(studio.name, "studio-mac")
        XCTAssertEqual(studio.tokens, 61_792_000)
        XCTAssertEqual(studio.costUsd, stats.device(id: "studio-mac")?.today.costUsd)
        XCTAssertEqual(studio.osIconAssetName, "vendor-os-apple")
        XCTAssertFalse(studio.isStale)
        XCTAssertEqual(studio.meta, DeviceMeta(
            operatingSystem: "macOS 26.0",
            runtime: .widget,
            agentVersion: "0.70.0",
            syncedAt: DeviceGolden.date("2026-10-10T16:29:40.000Z"),
            uploadInterval: .live
        ))
        let buildBox = try XCTUnwrap(stats.device(id: "build-box"))
        XCTAssertEqual(DevicePresentation.meta(buildBox).runtime, .agent)
        XCTAssertEqual(DevicePresentation.uploadInterval(buildBox), .minutes(10))
        XCTAssertEqual(DevicePresentation.meta(buildBox).operatingSystem, "Ubuntu 24.04")
        XCTAssertEqual(DevicePresentation.uploadInterval(try XCTUnwrap(stats.device(id: "old-laptop"))), .unknown)
        XCTAssertEqual(
            DevicePresentation.meta(buildBox).syncedAge(now: DeviceGolden.date("2026-10-10T16:30:00.000Z")),
            .minutes(5)
        )
    }

    func testHomeDevicesTieBreaks() {
        func device(_ id: String, tokens: Int, stale: Bool, seen: TimeInterval? = nil) -> DeviceSummary {
            DeviceSummary(id: id, isStale: stale, lastSeen: seen.map(Date.init(timeIntervalSince1970:)), today: DeviceUsage(tokens: tokens))
        }
        let devices = [device("a", tokens: 5, stale: true), device("b", tokens: 5, stale: false), device("c", tokens: 9, stale: true), device("d", tokens: 5, stale: false)]
        XCTAssertEqual(DevicePresentation.homeDevices(devices: devices, period: .today).map(\.id), ["c", "b", "d", "a"])
        XCTAssertEqual(DevicePresentation.rows(devices: devices, period: .today).map(\.id), ["c", "a", "b", "d"], "ties keep Hub order")

        let ordered = [
            device("old", tokens: 0, stale: true, seen: 300),
            device("zeta", tokens: 0, stale: false, seen: 100),
            device("Alpha", tokens: 0, stale: false, seen: 100),
            device("never", tokens: 0, stale: false),
            device("fresh", tokens: 0, stale: false, seen: 200)
        ]
        XCTAssertEqual(DevicePresentation.ordered(ordered).map(\.id), ["fresh", "Alpha", "zeta", "never", "old"])
    }

    func testOSIconAssetNameMirrorsOsIconFor() {
        XCTAssertEqual(DevicePresentation.osIconAssetName(platform: "darwin-arm64"), "vendor-os-apple")
        XCTAssertEqual(DevicePresentation.osIconAssetName(platform: "Darwin"), "vendor-os-apple")
        XCTAssertEqual(DevicePresentation.osIconAssetName(platform: "win32-x64"), "vendor-os-windows")
        XCTAssertEqual(DevicePresentation.osIconAssetName(platform: "linux-x64"), "vendor-os-linux")
        XCTAssertEqual(DevicePresentation.osIconAssetName(platform: "freebsd-amd64"), "vendor-os-linux")
        XCTAssertEqual(DevicePresentation.osIconAssetName(platform: "openbsd"), "vendor-os-linux")
        XCTAssertNil(DevicePresentation.osIconAssetName(platform: "sunos-x64"))
        XCTAssertNil(DevicePresentation.osIconAssetName(platform: "-darwin"))
        XCTAssertNil(DevicePresentation.osIconAssetName(platform: ""))
        XCTAssertNil(DevicePresentation.osIconAssetName(platform: nil))
        // The family stays the raw platform for the BSDs (label and family
        // are not changed by the icon rule).
        XCTAssertEqual(DevicePlatformFamily(platform: "freebsd-amd64"), .other)
    }

    func testPlatformLabelPort() {
        XCTAssertEqual(DevicePresentation.platformLabel(platform: "darwin-arm64", osName: nil, osVersion: "15.1"), "macOS 15.1")
        XCTAssertEqual(DevicePresentation.platformLabel(platform: "Win32-x64", osName: "  ", osVersion: nil), "Windows")
        XCTAssertEqual(DevicePresentation.platformLabel(platform: "freebsd-x64", osName: nil, osVersion: nil), "freebsd-x64")
        XCTAssertEqual(DevicePresentation.platformLabel(platform: "linux-x64", osName: " Fedora ", osVersion: " 41 "), "Fedora 41")
        XCTAssertEqual(DevicePresentation.platformLabel(platform: nil, osName: nil, osVersion: nil), "")
        XCTAssertNil(DevicePresentation.platformLabel(DeviceSummary(id: "x")))
    }

    func testRuntimeIntervalAndAge() {
        XCTAssertEqual(DevicePresentation.runtime("electron-widget"), .widget)
        XCTAssertEqual(DevicePresentation.runtime("headless-agent"), .agent)
        XCTAssertEqual(DevicePresentation.runtime(" cli "), .other("cli"))
        XCTAssertNil(DevicePresentation.runtime(""))
        XCTAssertNil(DevicePresentation.runtime(nil as String?))

        XCTAssertEqual(DevicePresentation.uploadInterval(seconds: 0), .live)
        XCTAssertEqual(DevicePresentation.uploadInterval(seconds: 1200), .minutes(20))
        XCTAssertEqual(DevicePresentation.uploadInterval(seconds: 1800), .minutes(30))
        XCTAssertEqual(DevicePresentation.uploadInterval(seconds: 10), .minutes(1))
        XCTAssertEqual(DevicePresentation.uploadInterval(seconds: nil), .unknown)
        XCTAssertEqual(DevicePresentation.uploadInterval(seconds: .nan), .unknown)

        let now = Date(timeIntervalSince1970: 1_000_000)
        func age(_ seconds: TimeInterval) -> DeviceSyncedAge? {
            DevicePresentation.syncedAge(since: now.addingTimeInterval(-seconds), now: now)
        }
        XCTAssertNil(DevicePresentation.syncedAge(since: nil, now: now))
        XCTAssertEqual(age(-30), .justNow, "a future stamp")
        XCTAssertEqual(age(44.9), .justNow)
        XCTAssertEqual(age(45), .minutes(1))
        XCTAssertEqual(age(89), .minutes(1))
        XCTAssertEqual(age(90), .minutes(2), "Math.round rounds half up")
        XCTAssertEqual(age(59 * 60 + 29), .minutes(59))
        XCTAssertEqual(age(59 * 60 + 30), .hours(1))
        XCTAssertEqual(age(23 * 3600 + 29 * 60), .hours(23))
        XCTAssertEqual(age(23 * 3600 + 30 * 60), .days(1))
        XCTAssertEqual(age(3 * 86_400 + 11 * 3600), .days(3))
        XCTAssertEqual(age(3 * 86_400 + 12 * 3600), .days(4))
    }

    func testLocaleOrderApproximatesLocaleCompare() {
        // Node: ['b', 'A', 'a', '_x', '10', 'é', 'e'].sort((a, b) => a.localeCompare(b))
        // → ['_x', '10', 'a', 'A', 'b', 'e', 'é']
        let sorted = ["b", "A", "a", "_x", "10", "é", "e"].sorted(by: DevicePresentation.localeAscending)
        XCTAssertEqual(sorted, ["_x", "10", "a", "A", "b", "e", "é"])
        // Accents and punctuation as Node orders them (the Tools screen's model).
        XCTAssertEqual(["claude-x", "cafes", "claude_x", "café"].sorted(by: DevicePresentation.localeAscending),
                       ["café", "cafes", "claude_x", "claude-x"])
    }
}

// MARK: - Live token rate

final class LiveTokenRateTests: XCTestCase {
    func testSelectionsGolden() throws {
        let golden = try DeviceGolden.object("live-rate.json")
        let selections = try XCTUnwrap(golden["selections"] as? [String: [String: Any]])
        let stats = try DeviceGolden.stats(.compact)
        let cases: [(String, LiveRateScope, DeviceScope)] = [
            ("all", .all, .all),
            ("deviceScopeStudio", .device, .device("studio-mac")),
            ("deviceScopeStale", .device, .device("old-laptop")),
            ("deviceScopeMissing", .device, .device("gone-device"))
        ]
        for (name, rateScope, deviceScope) in cases {
            let expected = try XCTUnwrap(selections[name], name)
            let selection = LiveTokenRate.selection(stats: stats, rateScope: rateScope, deviceScope: deviceScope)
            XCTAssertEqual(selection.source, expected["source"] as? String, name)
            let entries = try XCTUnwrap(expected["entries"] as? [[String: String]], name)
            XCTAssertEqual(selection.entries.map(\.id), entries.map { $0["id"] ?? "" }, name)
            XCTAssertEqual(selection.entries.map(\.name), entries.map { $0["name"] ?? "" }, name)
            XCTAssertEqual(LiveTokenRate.entries(stats: stats, rateScope: rateScope, deviceScope: deviceScope), selection.entries, name)
        }
        // "Selected device" without a scoped device means all.
        XCTAssertEqual(LiveTokenRate.selection(stats: stats, rateScope: .device, deviceScope: .all).source, "devices:all")
        XCTAssertEqual(LiveTokenRate.effectiveScope(rateScope: .device, deviceScope: .all), .all)
        XCTAssertEqual(LiveTokenRate.effectiveScope(rateScope: .device, deviceScope: .device("x")), .device)
        XCTAssertEqual(LiveTokenRate.effectiveScope(rateScope: .all, deviceScope: .device("x")), .all)
    }

    func testAverageRatesGolden() throws {
        let golden = try DeviceGolden.object("live-rate.json")
        let rates = try XCTUnwrap(golden["rates"] as? [String: [String: Double]])
        let stats = try DeviceGolden.stats(.compact)
        func check(_ counters: ThroughputCounters?, _ key: String) throws {
            let expected = try XCTUnwrap(rates[key], key)
            XCTAssertEqual(LiveTokenRate.tokensPerSecond(counters), try XCTUnwrap(expected["tokenRatePerSecond"]), accuracy: 1e-9, key)
            XCTAssertEqual(LiveTokenRate.burnPerMinute(counters), try XCTUnwrap(expected["tokenBurnPerMinute"]), accuracy: 1e-6, key)
        }
        try check(stats.today.throughput, "aggregate")
        for device in stats.devices { try check(device.today.throughput, device.id) }
        XCTAssertEqual(rates.count, stats.devices.count + 1)

        XCTAssertEqual(LiveTokenRate.tokensPerSecond(nil), 0)
        XCTAssertEqual(LiveTokenRate.tokensPerSecond(ThroughputCounters(timedTokens: 1, timedOutputTokens: 1e15, timedDurationMs: 1)), 1e12)
        XCTAssertEqual(LiveTokenRate.cappedRate(.nan), 0)
        XCTAssertEqual(LiveTokenRate.cappedRate(-3), 0)
    }

    func testGroupTrackerGolden() throws {
        let golden = try DeviceGolden.object("live-rate.json")
        let steps = try XCTUnwrap(golden["groupSteps"] as? [[String: Any]])
        let stats = try DeviceGolden.stats(.compact)
        let selection = LiveTokenRate.selection(stats: stats, rateScope: .all, deviceScope: .all)
        let order = selection.entries.map(\.id)
        let names = Dictionary(uniqueKeysWithValues: selection.entries.map { ($0.id, $0.name) })
        var inputs = Dictionary(uniqueKeysWithValues: selection.entries.map { ($0.id, $0.input) })
        func entries() -> [LiveTokenRateEntry] {
            order.compactMap { id in inputs[id].map { LiveTokenRateEntry(id: id, name: names[id] ?? id, input: $0) } }
        }

        let clock = RateClock()
        var group = LiveTokenRateGroupTracker(activeWindow: 8, clearAfter: 180, now: clock.read)
        let studio = "device:studio-mac", build = "device:build-box", tokyo = "device:tokyo-mac"

        // The generator's script (`$SP/fixturegen-r2/goldens.js` liveRateGolden).
        typealias Step = (t: Double, observe: Bool, mutate: () -> Void)
        let script: [Step] = [
            (0, false, {}),
            (1000, true, {
                inputs[studio] = DeviceGolden.bump(inputs[studio], ThroughputCounters(timedTokens: 9000, timedOutputTokens: 300, timedDurationMs: 5000), models: [
                    "claude-sonnet-4-5": ThroughputCounters(timedTokens: 6000, timedOutputTokens: 200, timedDurationMs: 3000),
                    "gpt-5-codex": ThroughputCounters(timedTokens: 3000, timedOutputTokens: 100, timedDurationMs: 2000)
                ])
            }),
            (3000, true, {
                inputs[build] = DeviceGolden.bump(inputs[build], ThroughputCounters(timedTokens: 4000, timedOutputTokens: 120, timedDurationMs: 2400), models: [
                    "deepseek-chat": ThroughputCounters(timedTokens: 4000, timedOutputTokens: 120, timedDurationMs: 2400)
                ])
            }),
            (4000, true, {}),
            (9500, true, {}),
            (12000, false, {}),
            (13000, true, { inputs[tokyo] = DeviceGolden.bump(inputs[tokyo], ThroughputCounters(timedTokens: 2000)) }),
            (14000, true, {
                inputs[studio] = DeviceGolden.bump(inputs[studio], ThroughputCounters(timedTokens: -9000, timedOutputTokens: -300, timedDurationMs: -5000))
            }),
            (15000, true, { inputs[build] = nil }),
            (200_000, false, {})
        ]
        XCTAssertEqual(steps.count, script.count)

        for (index, (expected, step)) in zip(steps, script).enumerated() {
            let label = "step \(index) \(expected["label"] as? String ?? "")"
            XCTAssertEqual(expected["t"] as? Double, step.t, label)
            clock.ms = step.t
            step.mutate()
            if index == 0 {
                group.reset(entries())
                XCTAssertTrue(expected["observe"] is NSNull, label)
            } else if step.observe {
                let result = group.observe(entries())
                let observe = try XCTUnwrap(expected["observe"] as? [String: Any], label)
                XCTAssertEqual(result.changed, observe["changed"] as? Bool, label)
                XCTAssertFalse(result.didReset, label)
                try DeviceGolden.assertSample(result.sample, observe["sample"], "\(label) observe")
            } else {
                XCTAssertTrue(expected["observe"] is NSNull, label)
            }
            let sample = group.currentSample()
            try DeviceGolden.assertSample(sample, expected["sample"], label)
            let nextExpiry = group.nextExpiry()
            if let ms = expected["nextExpiryAt"] as? Double {
                XCTAssertEqual(try XCTUnwrap(nextExpiry, label).timeIntervalSinceReferenceDate * 1000, ms, accuracy: 1e-6, label)
            } else {
                XCTAssertNil(nextExpiry, label)
            }
            XCTAssertEqual(
                DeviceGolden.tooltip(LiveTokenRate.tooltipEntries(sample: sample, mode: .speed), unit: "tok/s"),
                try DeviceGolden.goldenTooltip(expected["tooltipSpeed"]), "\(label) speed tooltip"
            )
            XCTAssertEqual(
                DeviceGolden.tooltip(LiveTokenRate.tooltipEntries(sample: sample, mode: .burn), unit: "TPM"),
                try DeviceGolden.goldenTooltip(expected["tooltipBurn"]), "\(label) burn tooltip"
            )
        }
    }

    func testSingleTrackerGolden() throws {
        let golden = try DeviceGolden.object("live-rate.json")
        let steps = try XCTUnwrap(golden["singleSteps"] as? [[String: Any]])
        let stats = try DeviceGolden.stats(.compact)
        var input: LiveTokenRateInput? = LiveTokenRateInput(try XCTUnwrap(stats.device(id: "studio-mac")).today)
        let clock = RateClock()
        var tracker = LiveTokenRateTracker(now: clock.read)
        tracker.reset(input)
        XCTAssertNil(tracker.sample)
        XCTAssertNil(tracker.value(.speed))

        for step in steps {
            let t = try XCTUnwrap(step["t"] as? Double)
            let change = try XCTUnwrap(step["change"] as? [String: Double])
            let delta = ThroughputCounters(
                timedTokens: change["timedTokens"] ?? 0,
                timedOutputTokens: change["timedOutputTokens"] ?? 0,
                timedDurationMs: change["timedDurationMs"] ?? 0
            )
            clock.ms = t
            input = DeviceGolden.bump(input, delta, models: ["claude-opus-4-1": delta])
            let sample = tracker.observe(input)
            let expected = try XCTUnwrap(step["sample"] as? [String: Any])
            let label = "t=\(t)"
            let actual = try XCTUnwrap(sample, label)
            XCTAssertEqual(actual, tracker.sample, label)
            XCTAssertEqual(actual.speed, try XCTUnwrap(expected["speed"] as? Double), accuracy: 1e-9, label)
            XCTAssertEqual(actual.burn, try XCTUnwrap(expected["burn"] as? Double), accuracy: 1e-6, label)
            XCTAssertEqual(actual.sampledAt.timeIntervalSinceReferenceDate * 1000, try XCTUnwrap(expected["sampledAt"] as? Double), accuracy: 1e-6, label)
            XCTAssertEqual(actual.revision, expected["revision"] as? Int, label)
            XCTAssertEqual(actual.delta.timedTokens, expected["timedTokens"] as? Double, label)
            XCTAssertEqual(actual.delta.timedOutputTokens, expected["timedOutputTokens"] as? Double, label)
            XCTAssertEqual(actual.delta.timedDurationMs, expected["timedDurationMs"] as? Double, label)
            try DeviceGolden.assertModels(actual.models, expected["models"], label)
            XCTAssertEqual(tracker.value(.speed) ?? -1, try XCTUnwrap(step["speed"] as? Double), accuracy: 1e-9, label)
            XCTAssertEqual(tracker.value(.burn) ?? -1, try XCTUnwrap(step["burn"] as? Double), accuracy: 1e-6, label)
        }
    }

    func testTrackerEdgeCases() {
        let clock = RateClock()
        var tracker = LiveTokenRateTracker(now: clock.read)
        let base = ThroughputCounters(timedTokens: 1000, timedOutputTokens: 100, timedDurationMs: 1000)
        // A first observation is only a baseline.
        XCTAssertNil(tracker.observe(LiveTokenRateInput(counters: base, modelThroughput: nil)))
        // No previous model attribution: the sample has no models.
        let next = ThroughputCounters(timedTokens: 2000, timedOutputTokens: 200, timedDurationMs: 2000)
        let first = tracker.observe(LiveTokenRateInput(counters: next, modelThroughput: ["m": next]))
        XCTAssertEqual(first?.models, [])
        XCTAssertEqual(first?.speed, 100)
        XCTAssertEqual(first?.burn, 60000)
        // A model that appears with historical counters larger than the
        // whole delta is skipped; one whose duration did not move too.
        let third = ThroughputCounters(timedTokens: 3000, timedOutputTokens: 300, timedDurationMs: 3000)
        let second = tracker.observe(LiveTokenRateInput(counters: third, modelThroughput: [
            "m": ThroughputCounters(timedTokens: 2500, timedOutputTokens: 250, timedDurationMs: 2500),
            "historical": ThroughputCounters(timedTokens: 50_000, timedOutputTokens: 10, timedDurationMs: 10),
            "idle": ThroughputCounters(timedTokens: 0, timedOutputTokens: 0, timedDurationMs: 0)
        ]))
        XCTAssertEqual(second?.models.map(\.model), ["m"])
        XCTAssertEqual(second?.revision, 2)
        // Missing counters clear the sample and the baseline.
        XCTAssertNil(tracker.observe(LiveTokenRateInput(counters: nil)))
        XCTAssertNil(tracker.sample)
        XCTAssertNil(tracker.observe(LiveTokenRateInput(counters: third)), "a new baseline")
        XCTAssertNil(tracker.observe(nil))

        // An aggregate period counts only when its throughput is complete.
        XCTAssertNil(LiveTokenRateInput(UsagePeriod(timedTokens: 5, timedOutputTokens: 1, timedDurationMs: 5, hasCompleteThroughput: false)).counters)
        XCTAssertEqual(
            LiveTokenRateInput(UsagePeriod(timedTokens: 5, timedOutputTokens: 1, timedDurationMs: 5, hasCompleteThroughput: true)).counters,
            ThroughputCounters(timedTokens: 5, timedOutputTokens: 1, timedDurationMs: 5)
        )
    }

    func testGroupSourceChangesStartOver() throws {
        let stats = try DeviceGolden.stats(.compact)
        let clock = RateClock()
        var group = LiveTokenRateGroupTracker(now: clock.read)
        let all = LiveTokenRate.selection(stats: stats, rateScope: .all, deviceScope: .all)
        let first = group.observe(all, context: "hub-a")
        XCTAssertTrue(first.didReset)
        XCTAssertNil(first.sample)
        XCTAssertEqual(group.sourceKey, "hub-a|devices:all")

        // Same source: observed (studio grows).
        clock.ms = 1000
        var grown = all
        let studioIndex = try XCTUnwrap(grown.entries.firstIndex { $0.id == "device:studio-mac" })
        grown.entries[studioIndex].input = DeviceGolden.bump(grown.entries[studioIndex].input,
            ThroughputCounters(timedTokens: 600, timedOutputTokens: 60, timedDurationMs: 1000))
        let second = group.observe(grown, context: "hub-a")
        XCTAssertFalse(second.didReset)
        XCTAssertTrue(second.changed)
        XCTAssertEqual(second.sample?.speed, 60)
        XCTAssertEqual(second.sample?.deviceCount, 1)
        XCTAssertEqual(second.sample?.devices, [], "no model moved")
        XCTAssertEqual(LiveTokenRate.tooltipEntries(sample: second.sample, mode: .speed), [])

        // A different scope (or Hub) is a new baseline: no carried reading.
        let scoped = LiveTokenRate.selection(stats: stats, rateScope: .device, deviceScope: .device("studio-mac"))
        let third = group.observe(scoped, context: "hub-a")
        XCTAssertTrue(third.didReset)
        XCTAssertNil(third.sample)
        XCTAssertEqual(group.sourceKey, "hub-a|device:studio-mac")
        XCTAssertTrue(group.observe(scoped, context: "hub-b").didReset)
        group.clear()
        XCTAssertNil(group.sourceKey)
        XCTAssertNil(group.currentSample())
    }

    func testGroupNormalizesEntriesAndSanitizesWindows() {
        let clock = RateClock()
        var group = LiveTokenRateGroupTracker(activeWindow: 0, clearAfter: 1, now: clock.read)
        XCTAssertEqual(group.activeWindow, 8)
        XCTAssertEqual(group.clearAfter, 180)
        let custom = LiveTokenRateGroupTracker(activeWindow: 4, clearAfter: 4, now: clock.read)
        XCTAssertEqual(custom.activeWindow, 4)
        XCTAssertEqual(custom.clearAfter, 180)

        let counters = ThroughputCounters(timedTokens: 10, timedOutputTokens: 1, timedDurationMs: 10)
        group.reset([
            LiveTokenRateEntry(id: " a ", name: "", input: LiveTokenRateInput(counters: counters)),
            LiveTokenRateEntry(id: "a", name: "dup", input: LiveTokenRateInput(counters: nil)),
            LiveTokenRateEntry(id: " ", name: "blank", input: LiveTokenRateInput(counters: counters))
        ])
        clock.ms = 500
        let grown = ThroughputCounters(timedTokens: 20, timedOutputTokens: 2, timedDurationMs: 20)
        let result = group.observe([LiveTokenRateEntry(id: "a", name: "", input: LiveTokenRateInput(counters: grown, modelThroughput: [:]))])
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.sample?.speed, 100)
        XCTAssertEqual(result.sample?.revision, 1)
        XCTAssertEqual(result.sample?.idle, false)
        XCTAssertEqual(result.sample?.expiresAt, RateClock.date(500 + 8000))
        // Idle after the active window, gone after clearAfter.
        clock.ms = 8500
        XCTAssertEqual(group.currentSample()?.idle, true)
        XCTAssertEqual(group.nextExpiry(), RateClock.date(500 + 180_000))
        clock.ms = 180_500
        XCTAssertNil(group.currentSample())
    }

    func testTooltipGroupingFollowsTheLiveDeviceCount() {
        let model = LiveTokenRateModelRate(model: "m", speed: 5, burn: 7)
        let sample = LiveTokenRateSample(
            speed: 5, burn: 7, sampledAt: Date(), devices: [.init(id: "device:a", name: "a", models: [model])],
            deviceCount: 2, revision: 1, expiresAt: Date(), idle: false
        )
        // Two live devices but only one with models: still grouped.
        XCTAssertEqual(LiveTokenRate.tooltipEntries(sample: sample, mode: .burn), [.device(name: "a", separated: false), .model("m", rate: 7)])
        var single = sample
        single.deviceCount = 1
        XCTAssertEqual(LiveTokenRate.tooltipEntries(sample: single, mode: .speed), [.model("m", rate: 5)])
        XCTAssertEqual(LiveTokenRate.tooltipEntries(sample: nil, mode: .speed), [])
    }
}

// MARK: - Helpers

/// A settable clock in the golden's milliseconds.
private final class RateClock: @unchecked Sendable {
    var ms: Double = 0

    static func date(_ ms: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: ms / 1000)
    }

    var read: @Sendable () -> Date {
        { [self] in RateClock.date(self.ms) }
    }
}

private enum DeviceGolden {
    static func data(_ name: String, subdirectory: String) throws -> Data {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let url = Bundle.module.url(
            forResource: parts[0],
            withExtension: parts.count > 1 ? parts[1] : nil,
            subdirectory: subdirectory
        ) else {
            throw NSError(domain: "DeviceGolden", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(subdirectory)/\(name)"])
        }
        return try Data(contentsOf: url)
    }

    static func object(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(name, subdirectory: "Fixtures/v2/golden")) as? [String: Any])
    }

    static func stats(_ options: HubDecodingOptions) throws -> HubStats {
        try HubStats.decode(from: data("stats.json", subdirectory: "Fixtures/v2"), options: options)
    }

    private struct RawDevices: Decodable {
        let devices: [DeviceSummary]
    }

    /// `stats.json` devices exactly as sent, with every detail and without
    /// the Hub decode's period expiry, which the desktop device views do not
    /// apply either (the goldens show old-laptop's ended `today`).
    static func rawDevices() throws -> [DeviceSummary] {
        try HubDecodingOptions.app.makeDecoder()
            .decode(RawDevices.self, from: data("stats.json", subdirectory: "Fixtures/v2"))
            .devices
    }

    static func date(_ iso: String) -> Date {
        ISODate.parse(iso)!
    }

    static func counts(_ counts: ClientHealthCounts) -> [String: Int] {
        ["healthy": counts.healthy, "review": counts.review, "unavailable": counts.unavailable]
    }

    static func assertDetail(_ detail: ClientHealthDetail, matches expected: [String: Any], _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(detail.overall.rawValue, expected["overall"] as? String, label, file: file, line: line)
        XCTAssertEqual(detail.tone.rawValue, expected["tone"] as? String, label, file: file, line: line)
        let groups = try XCTUnwrap(expected["groups"] as? [[String: Any]], label)
        XCTAssertEqual(detail.groups.map(\.rawValue), groups.map { $0["id"] as? String ?? "" }, label, file: file, line: line)
        let keys = ["source": "settings.tools.health.source", "collection": "settings.tools.health.sync", "data": "settings.tools.health.usage"]
        for group in groups {
            let id = group["id"] as? String ?? ""
            XCTAssertEqual(keys[id], group["key"] as? String, "\(label) \(id) key", file: file, line: line)
            switch id {
            case "source":
                XCTAssertEqual(detail.source.state.rawValue, group["state"] as? String, "\(label) source", file: file, line: line)
                XCTAssertEqual(detail.source.detectedCount, group["detectedCount"] as? Int, "\(label) source", file: file, line: line)
                XCTAssertEqual(detail.source.checkedCount, group["checkedCount"] as? Int, "\(label) source", file: file, line: line)
                let checks = try XCTUnwrap(group["checks"] as? [[String: Any]], label)
                XCTAssertEqual(detail.source.checks.map(\.id), checks.map { $0["id"] as? String ?? "" }, "\(label) checks", file: file, line: line)
                XCTAssertEqual(detail.source.checks.map(\.exists), checks.map { $0["exists"] as? Bool ?? false }, "\(label) checks", file: file, line: line)
                XCTAssertTrue(checks.allSatisfy { ($0["paths"] as? [Any])?.isEmpty == true }, "\(label) the Hub sends no paths", file: file, line: line)
            case "collection":
                XCTAssertEqual(detail.collection.state.rawValue, group["state"] as? String, "\(label) collection", file: file, line: line)
                func stamp(_ key: String) -> Date? {
                    (group[key] as? String).flatMap { $0.isEmpty ? nil : ISODate.parse($0) }
                }
                XCTAssertEqual(detail.collection.lastAttemptAt, stamp("lastAttemptAt"), "\(label) lastAttemptAt", file: file, line: line)
                XCTAssertEqual(detail.collection.lastSuccessAt, stamp("lastSuccessAt"), "\(label) lastSuccessAt", file: file, line: line)
            case "data":
                XCTAssertEqual(detail.data.liveTokens, group["tokens"] as? Int, "\(label) tokens", file: file, line: line)
                let day = group["lastActivityDay"] as? String
                XCTAssertEqual(detail.data.lastActivityDay, (day?.isEmpty ?? true) ? nil : day, "\(label) day", file: file, line: line)
                let periods = try XCTUnwrap(group["periods"] as? [[String: Any]], label)
                let actual = try XCTUnwrap(detail.data.periods, label)
                XCTAssertEqual(actual.map(\.period.rawValue), periods.map { $0["period"] as? String ?? "" }, "\(label) periods", file: file, line: line)
                for (cell, expectedCell) in zip(actual, periods) {
                    XCTAssertEqual(cell.tokens, expectedCell["tokens"] as? Int, "\(label) \(cell.period)", file: file, line: line)
                    XCTAssertEqual(cell.costUsd, try XCTUnwrap(expectedCell["cost"] as? Double), accuracy: 1e-9, "\(label) \(cell.period)", file: file, line: line)
                }
            default:
                XCTFail("\(label) unexpected group \(id)", file: file, line: line)
            }
        }
        let notes = try XCTUnwrap(expected["notes"] as? [[String: String]], label)
        XCTAssertEqual(detail.notes.map(\.code.rawValue), notes.map { $0["code"] ?? "" }, "\(label) notes", file: file, line: line)
        XCTAssertEqual(detail.notes.map(\.group.rawValue), notes.map { $0["group"] ?? "" }, "\(label) notes", file: file, line: line)
        XCTAssertEqual(detail.notes.map(\.tone.rawValue), notes.map { $0["tone"] ?? "" }, "\(label) notes", file: file, line: line)
    }

    /// The generator's `bump()`: adds to the counters and, when the period
    /// has `modelThroughput`, to the named models (from zero when new).
    static func bump(_ input: LiveTokenRateInput?, _ delta: ThroughputCounters, models: [String: ThroughputCounters] = [:]) -> LiveTokenRateInput? {
        guard var input else { return nil }
        if let counters = input.counters {
            input.counters = add(counters, delta)
        }
        if var map = input.modelThroughput {
            for (model, change) in models { map[model] = add(map[model] ?? .zero, change) }
            input.modelThroughput = map
        }
        return input
    }

    static func bump(_ input: LiveTokenRateInput, _ delta: ThroughputCounters) -> LiveTokenRateInput {
        bump(Optional(input), delta) ?? input
    }

    private static func add(_ left: ThroughputCounters, _ right: ThroughputCounters) -> ThroughputCounters {
        ThroughputCounters(
            timedTokens: left.timedTokens + right.timedTokens,
            timedOutputTokens: left.timedOutputTokens + right.timedOutputTokens,
            timedDurationMs: left.timedDurationMs + right.timedDurationMs
        )
    }

    static func assertSample(_ sample: LiveTokenRateSample?, _ expected: Any?, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        guard let expected = expected as? [String: Any] else {
            XCTAssertTrue(expected is NSNull, "\(label): golden sample", file: file, line: line)
            XCTAssertNil(sample, label, file: file, line: line)
            return
        }
        let actual = try XCTUnwrap(sample, label, file: file, line: line)
        XCTAssertEqual(actual.speed, try XCTUnwrap(expected["speed"] as? Double), accuracy: 1e-9, "\(label) speed", file: file, line: line)
        XCTAssertEqual(actual.burn, try XCTUnwrap(expected["burn"] as? Double), accuracy: 1e-6, "\(label) burn", file: file, line: line)
        XCTAssertEqual(actual.sampledAt.timeIntervalSinceReferenceDate * 1000, try XCTUnwrap(expected["sampledAt"] as? Double), accuracy: 1e-6, "\(label) sampledAt", file: file, line: line)
        XCTAssertEqual(actual.expiresAt.timeIntervalSinceReferenceDate * 1000, try XCTUnwrap(expected["expiresAt"] as? Double), accuracy: 1e-6, "\(label) expiresAt", file: file, line: line)
        XCTAssertEqual(actual.deviceCount, expected["deviceCount"] as? Int, "\(label) deviceCount", file: file, line: line)
        XCTAssertEqual(actual.revision, expected["revision"] as? Int, "\(label) revision", file: file, line: line)
        XCTAssertEqual(actual.idle, expected["idle"] as? Bool, "\(label) idle", file: file, line: line)
        let devices = try XCTUnwrap(expected["devices"] as? [[String: Any]], label)
        XCTAssertEqual(actual.devices.map(\.id), devices.map { $0["id"] as? String ?? "" }, "\(label) devices", file: file, line: line)
        XCTAssertEqual(actual.devices.map(\.name), devices.map { $0["name"] as? String ?? "" }, "\(label) devices", file: file, line: line)
        for (device, expectedDevice) in zip(actual.devices, devices) {
            try assertModels(device.models, expectedDevice["models"], "\(label) \(device.id)", file: file, line: line)
        }
    }

    /// Models compare by id: the desktop keeps wire order, the Kit sorts.
    static func assertModels(_ models: [LiveTokenRateModelRate], _ expected: Any?, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let rows = try XCTUnwrap(expected as? [[String: Any]], label, file: file, line: line)
            .sorted { ($0["model"] as? String ?? "") < ($1["model"] as? String ?? "") }
        XCTAssertEqual(models.map(\.model), rows.map { $0["model"] as? String ?? "" }, "\(label) models", file: file, line: line)
        for (model, row) in zip(models, rows) {
            XCTAssertEqual(model.speed, try XCTUnwrap(row["speed"] as? Double), accuracy: 1e-9, "\(label) \(model.model)", file: file, line: line)
            XCTAssertEqual(model.burn, try XCTUnwrap(row["burn"] as? Double), accuracy: 1e-6, "\(label) \(model.model)", file: file, line: line)
        }
    }

    /// Renders entries the way the golden's `formatRate` did:
    /// `Math.round(v).toLocaleString('en-US')` plus the unit.
    static func tooltip(_ entries: [LiveTokenRateTooltipEntry], unit: String) -> [String] {
        let formatter = DisplayFormatter()
        return entries.map { entry in
            switch entry {
            case let .device(name, separated): return "device \(name) \(separated)"
            case let .model(model, rate): return "\(model) = \(formatter.fullTokens(rate)) \(unit)"
            }
        }
    }

    static func goldenTooltip(_ value: Any?) throws -> [String] {
        let entries = try XCTUnwrap(value as? [Any])
        return try entries.map { entry in
            if let heading = entry as? [String: Any] {
                return "device \(heading["full"] as? String ?? "") \(heading["separated"] as? Bool ?? false)"
            }
            let pair = try XCTUnwrap(entry as? [String])
            return "\(pair[0]) = \(pair[1])"
        }
    }
}

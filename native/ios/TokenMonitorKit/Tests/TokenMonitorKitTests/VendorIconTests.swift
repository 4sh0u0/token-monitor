import Foundation
import XCTest
@testable import TokenMonitorKit

final class VendorIconTests: XCTestCase {
    /// The targets whose `VendorIcons.xcassets` the generator writes.
    private static let catalogTargets = ["TokenMonitor", "TokenMonitorWidget", "TokenMonitorWatch"]

    /// `native/ios/`, found from this file so the check reads the committed catalogs.
    private static let iosRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // TokenMonitorKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // TokenMonitorKit
        .deletingLastPathComponent() // ios

    func testEveryMarkMapsToAnAssetOnTheLimitsPage() {
        for mark in VendorCatalog.marks {
            let name = VendorCatalog.iconAssetName(for: mark.id, context: .limits)
            XCTAssertNotNil(name, mark.id)
            XCTAssertTrue(name?.hasPrefix("vendor-") ?? false, mark.id)
        }
    }

    func testUsageRowsOnlyDrawMarksWithABrandColour() {
        for mark in VendorCatalog.marks {
            let name = VendorCatalog.iconAssetName(for: mark.id)
            if mark.brandColorHex == nil {
                XCTAssertNil(name, "\(mark.id) has no colour, so a usage row draws a dot")
            } else {
                XCTAssertNotNil(name, mark.id)
            }
        }
        XCTAssertNil(VendorCatalog.iconAssetName(for: "factory"))
        XCTAssertEqual(VendorCatalog.iconAssetName(for: "factory", context: .limits), "vendor-droid")
        XCTAssertNil(VendorCatalog.iconAssetName(for: "sub2api"))
        XCTAssertEqual(VendorCatalog.iconAssetName(for: "sub2api", context: .limits), "vendor-sub2api")
    }

    func testArtworkFollowsMaskThenIconThenID() {
        XCTAssertEqual(VendorCatalog.iconAssetName(for: "claude"), "vendor-claude")
        XCTAssertEqual(VendorCatalog.iconAssetName(for: "hermes"), "vendor-hermes-agent")
        XCTAssertEqual(VendorCatalog.iconAssetName(for: "mimo"), "vendor-xiaomi")
        XCTAssertEqual(VendorCatalog.iconAssetName(for: "zcode"), "vendor-zai")
        XCTAssertEqual(VendorCatalog.iconAssetName(for: "zaiteam"), "vendor-zai")
        XCTAssertEqual(VendorCatalog.iconAssetName(for: "xai"), "vendor-grok")
        XCTAssertEqual(VendorCatalog.iconAssetName(for: "grok"), "vendor-xai")
    }

    func testTheLimitsPageDrawsGrokWithItsOwnArtwork() {
        XCTAssertEqual(VendorCatalog.iconAssetName(for: "grok", context: .limits), "vendor-grok")
        XCTAssertEqual(VendorCatalog.iconAssetName(for: "grok", context: .usage), "vendor-xai")
        XCTAssertEqual(VendorCatalog.iconAssetName(for: "xai", context: .limits), "vendor-grok")
        XCTAssertEqual(VendorCatalog.iconAssetName(for: "claude", context: .limits), "vendor-claude")
    }

    func testUnknownIDsDrawADot() {
        XCTAssertNil(VendorCatalog.iconAssetName(for: "brand-new-tool"))
        XCTAssertNil(VendorCatalog.iconAssetName(for: "brand-new-tool", context: .limits))
        XCTAssertNil(VendorCatalog.iconAssetName(for: "token-monitor"), "the Σ mark is SF Symbol `sum`")
        XCTAssertNil(VendorCatalog.iconAssetName(for: ""))
    }

    func testDeviceAndProjectMarks() {
        XCTAssertEqual(VendorCatalog.osIconAssetNames, [
            .macOS: "vendor-os-apple",
            .windows: "vendor-os-windows",
            .linux: "vendor-os-linux"
        ])
        XCTAssertNil(VendorCatalog.osIconAssetNames[.other])
        XCTAssertEqual(VendorCatalog.projectIconAssetName, "vendor-project")
    }

    func testTrackedClientsAreMarksWithUsageIcons() {
        XCTAssertEqual(VendorCatalog.trackedClientIDs.first, "claude")
        XCTAssertEqual(Set(VendorCatalog.trackedClientIDs).count, VendorCatalog.trackedClientIDs.count)
        for id in VendorCatalog.trackedClientIDs {
            XCTAssertNotNil(VendorCatalog.iconAssetName(for: id), id)
        }
    }

    /// Every name the Kit hands out exists as a template image in each target's
    /// catalog, so a view never asks for an image Xcode did not compile.
    func testEveryAssetNameExistsInEachTargetCatalog() throws {
        var names = Set(VendorCatalog.marks.flatMap { mark in
            [VendorIconContext.usage, .limits].compactMap { VendorCatalog.iconAssetName(for: mark.id, context: $0) }
        })
        names.formUnion(VendorCatalog.osIconAssetNames.values)
        names.insert(VendorCatalog.projectIconAssetName)

        let fileManager = FileManager.default
        for target in Self.catalogTargets {
            let catalog = Self.iosRoot.appendingPathComponent(target).appendingPathComponent("VendorIcons.xcassets")
            guard fileManager.fileExists(atPath: catalog.path) else {
                throw XCTSkip("\(catalog.path) is not available to this test run")
            }
            for name in names.sorted() {
                let imageset = catalog.appendingPathComponent("\(name).imageset")
                let contents = try Data(contentsOf: imageset.appendingPathComponent("Contents.json"))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: contents) as? [String: Any], "\(target)/\(name)")
                let properties = try XCTUnwrap(json["properties"] as? [String: Any], "\(target)/\(name)")
                XCTAssertEqual(properties["template-rendering-intent"] as? String, "template", "\(target)/\(name)")
                XCTAssertEqual(properties["preserves-vector-representation"] as? Bool, true, "\(target)/\(name)")
                let images = try XCTUnwrap(json["images"] as? [[String: Any]], "\(target)/\(name)")
                let filename = try XCTUnwrap(images.first?["filename"] as? String, "\(target)/\(name)")
                XCTAssertTrue(filename.hasSuffix(".svg"), "\(target)/\(name)")
                XCTAssertTrue(
                    fileManager.fileExists(atPath: imageset.appendingPathComponent(filename).path),
                    "\(target)/\(name)/\(filename)"
                )
            }
        }
    }
}

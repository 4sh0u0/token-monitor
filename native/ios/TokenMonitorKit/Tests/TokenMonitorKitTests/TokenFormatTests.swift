import Foundation
import XCTest
@testable import TokenMonitorKit

final class TokenFormatTests: XCTestCase {
    private let en = Fixture.enUS

    func testCompactTokens() {
        let cases: [(Int, String)] = [
            (0, "0"),
            (999, "999"),
            (1000, "1K"),
            (1200, "1.2K"),
            (1234, "1.2K"),
            (12_345, "12.3K"),
            (123_456, "123.5K"),
            (999_999, "1M"),
            (1_234_567, "1.23M"),
            (45_600_000, "45.6M"),
            (123_456_789, "123M"),
            (4_500_000_000, "4.5B"),
            (4_233_100_000, "4.23B"),
            (-1234, "-1.2K")
        ]
        for (value, expected) in cases {
            XCTAssertEqual(TokenFormat.compactTokens(value, locale: en), expected, "\(value)")
        }
        XCTAssertEqual(TokenFormat.compactTokens(1_234_567, locale: Locale(identifier: "de_DE")), "1,23M")
    }

    func testLocalizedCompactUnits() {
        XCTAssertEqual(TokenFormat.compactTokens(12_345, units: .localized, locale: Locale(identifier: "ja_JP")), "1.23万")
        XCTAssertEqual(TokenFormat.compactTokens(123_456_789, units: .localized, locale: Locale(identifier: "zh-Hans")), "1.23亿")
        XCTAssertEqual(TokenFormat.compactTokens(123_456_789, units: .localized, locale: Locale(identifier: "zh_CN")), "1.23亿")
        XCTAssertEqual(TokenFormat.compactTokens(123_456_789, units: .localized, locale: Locale(identifier: "zh-Hant")), "1.23億")
        XCTAssertEqual(TokenFormat.compactTokens(50_000, units: .localized, locale: Locale(identifier: "ko_KR")), "5만")
        XCTAssertEqual(TokenFormat.compactTokens(9_999, units: .localized, locale: Locale(identifier: "ja_JP")), "9999")
        XCTAssertEqual(TokenFormat.compactTokens(50_000, units: .localized, locale: en), "50K", "other languages stay western")
    }

    func testFullTokens() {
        XCTAssertEqual(TokenFormat.fullTokens(1_234_567, locale: en), "1,234,567")
    }

    func testUSD() {
        XCTAssertEqual(TokenFormat.usd(0.42, locale: en), "$0.42")
        XCTAssertEqual(TokenFormat.usd(12.34, locale: en), "$12.34")
        XCTAssertEqual(TokenFormat.usd(1234.5, locale: en), "$1,234.50")
        XCTAssertEqual(TokenFormat.usd(0, locale: en), "$0.00")
        XCTAssertEqual(TokenFormat.usd(0.0042, locale: en), "$0.0042", "sub-cent costs stay visible")
        XCTAssertEqual(TokenFormat.compactUSD(999, locale: en), "$999.00")
        XCTAssertEqual(TokenFormat.compactUSD(1234.5, locale: en), "$1.2K")
        XCTAssertEqual(TokenFormat.compactUSD(3_450_000, locale: en), "$3.45M")
        XCTAssertEqual(TokenFormat.compactUSD(-1234.5, locale: en), "-$1.2K")
    }

    func testMoneyInItsOwnCurrency() {
        XCTAssertEqual(TokenFormat.money(86.42, currency: "CNY", locale: en), "CN¥86.42")
        XCTAssertEqual(TokenFormat.money(680, currency: "CREDITS", locale: en), "680.00")
        XCTAssertEqual(TokenFormat.money(1, currency: "POINTS", locale: en), "POINTS 1.00")
        XCTAssertEqual(TokenFormat.money(1, currency: nil, locale: en), "$1.00")
        XCTAssertEqual(TokenFormat.compactMoney(12_345, currency: "CREDITS", locale: en), "12.3K")
    }

    func testPercentAndRate() {
        XCTAssertEqual(TokenFormat.percent(42, locale: en), "42%")
        XCTAssertEqual(TokenFormat.percent(42.5, fractionDigits: 1, locale: en), "42.5%")
        XCTAssertEqual(TokenFormat.percent(100, locale: en), "100%")
        XCTAssertEqual(TokenFormat.tokensPerSecond(62, locale: en), "62")
        XCTAssertEqual(TokenFormat.tokensPerSecond(7.36, locale: en), "7.4")
        XCTAssertEqual(TokenFormat.tokensPerSecond(250.4, locale: en), "250")
        XCTAssertEqual(TokenFormat.tokensPerSecond(1500, locale: en), "1.5K")
        XCTAssertEqual(TokenFormat.tokensPerSecond(0, locale: en), "0")
    }

    func testCountdown() {
        let now = Fixture.date("2026-10-09T00:00:00Z")
        XCTAssertEqual(TokenFormat.countdown(to: now.addingTimeInterval(9000), from: now, locale: en), "2h 30m")
        XCTAssertEqual(TokenFormat.countdown(to: now.addingTimeInterval(9010), from: now, locale: en), "2h 31m", "rounds up to whole minutes")
        XCTAssertEqual(TokenFormat.countdown(to: now.addingTimeInterval(30), from: now, locale: en), "1m")
        XCTAssertEqual(TokenFormat.countdown(to: now.addingTimeInterval(-60), from: now, locale: en), "1m")
        XCTAssertEqual(TokenFormat.countdown(to: now.addingTimeInterval(3 * 86_400 + 4 * 3600 + 5 * 60), from: now, locale: en), "3d 4h")
        XCTAssertFalse(TokenFormat.countdown(to: now.addingTimeInterval(9000), from: now, locale: Locale(identifier: "ja_JP")).contains("h"))
    }

    func testRelativeAndMoment() {
        let now = Fixture.date("2026-10-09T09:00:00Z")
        let later = TokenFormat.relative(now.addingTimeInterval(3 * 3600), to: now, locale: en)
        let earlier = TokenFormat.relative(now.addingTimeInterval(-3 * 3600), to: now, locale: en)
        XCTAssertTrue(later.contains("3"), later)
        XCTAssertTrue(earlier.contains("3"), earlier)
        XCTAssertNotEqual(later, earlier)

        let calendar = Fixture.utc
        let sameDay = TokenFormat.moment(Fixture.date("2026-10-09T14:00:00Z"), relativeTo: now, calendar: calendar, locale: en)
        let thisWeek = TokenFormat.moment(Fixture.date("2026-10-12T14:00:00Z"), relativeTo: now, calendar: calendar, locale: en)
        let later2 = TokenFormat.moment(Fixture.date("2026-10-30T14:00:00Z"), relativeTo: now, calendar: calendar, locale: en)
        XCTAssertTrue(sameDay.contains("2:00"), sameDay)
        XCTAssertFalse(sameDay.contains("Oct"), sameDay)
        XCTAssertTrue(thisWeek.contains("Mon"), thisWeek)
        XCTAssertTrue(later2.contains("Oct") && later2.contains("30"), later2)
    }
}

final class VendorCatalogTests: XCTestCase {
    func testLabels() {
        XCTAssertEqual(VendorCatalog.clientLabel("claude"), "Claude Code")
        XCTAssertEqual(VendorCatalog.toolLabel("claude"), "Claude")
        XCTAssertEqual(VendorCatalog.toolLabel("grok"), "Grok")
        XCTAssertEqual(VendorCatalog.clientLabel("grok"), "Grok Build")
        XCTAssertEqual(VendorCatalog.toolLabel("hermes"), "Hermes Agent")
        XCTAssertEqual(VendorCatalog.clientLabel("gemini"), "Gemini")
        XCTAssertEqual(VendorCatalog.clientLabel("brand-new-tool"), "brand-new-tool")
        XCTAssertEqual(VendorCatalog.limitProviderLabel("zai"), "GLM")
        XCTAssertEqual(VendorCatalog.limitProviderLabel("factory"), "Factory Droid")
        XCTAssertEqual(VendorCatalog.vendorLabel("xai"), "xAI")
        XCTAssertEqual(VendorCatalog.limitProviders.first?.id, "claude")
        XCTAssertEqual(VendorCatalog.limitProviders.first?.settingsLabel, "Claude Code")
        XCTAssertLessThan(VendorCatalog.limitProviderSortIndex("codex"), VendorCatalog.limitProviderSortIndex("openrouter"))
        XCTAssertEqual(VendorCatalog.limitProviderSortIndex("unknown"), Int.max)
    }

    func testPaints() {
        XCTAssertEqual(VendorCatalog.paint(for: "claude"), .hex("#cc7c5e"))
        XCTAssertEqual(VendorCatalog.paint(for: "cursor"), .ink, "near-black marks use the light ink")
        XCTAssertEqual(VendorCatalog.paint(for: "cline"), .hex("#53616d"), "widgetColor wins on dark surfaces")
        XCTAssertEqual(VendorCatalog.brandColorHex(for: "cline"), "#9d4edd")
        XCTAssertEqual(VendorCatalog.paint(for: "factory"), .ink)
        XCTAssertEqual(VendorCatalog.paint(for: "newapi"), .hex(VendorCatalog.defaultColorHex))
        XCTAssertEqual(VendorCatalog.paint(for: "nope"), .hex("#6ab4f0"))
        XCTAssertEqual(VendorCatalog.paint(for: nil), .hex("#6ab4f0"))
        XCTAssertEqual(VendorCatalog.mark(for: "pi")?.brandColorHex, "#000000", "3-digit hex is expanded")
    }

    func testModelVendorRulesMirrorTheDesktop() {
        let cases: [(String, String?)] = [
            ("claude-sonnet-4-5", "claude"),
            ("Claude-Opus-4-1", "claude"),
            ("gpt-5-codex", "codex"),
            ("o3-mini", "codex"),
            ("o4", "codex"),
            ("cursor-auto", "cursor"),
            ("auto", "cursor"),
            ("gemini-2.5-pro", "gemini"),
            ("grok-code-fast-1", "xai"),
            ("deepseek-chat", "deepseek"),
            ("llama-3.3-70b", "meta"),
            ("codestral-latest", "mistral"),
            ("qwq-32b", "qwen"),
            ("kimi-k2-turbo", "kimi"),
            ("k3-256k", "kimi"),
            ("glm-4.6", "zai"),
            ("mimo-v2", "xiaomi"),
            ("minimax-m2", "minimax"),
            ("doubao-seed-1.6", "doubao"),
            ("hy3-preview", "hunyuan"),
            ("swe-1.5", "devin"),
            ("big-pickle", "opencode"),
            ("mystery-model-x", nil),
            ("workglm-4", nil)
        ]
        for (model, vendor) in cases {
            XCTAssertEqual(VendorCatalog.modelVendor(for: model), vendor, model)
        }
    }

    func testEveryGeneratedModelVendorPatternCompiles() {
        // The resolver drops a pattern NSRegularExpression rejects; a JavaScript
        // construct it does not support must fail here, not misattribute models.
        XCTAssertFalse(VendorCatalog.generatedModelVendorRules.isEmpty)
        XCTAssertEqual(VendorCatalog.modelVendorExpressions.count, VendorCatalog.generatedModelVendorRules.count)
    }

    func testFallbackModelColoursMatchTheDesktopHash() {
        XCTAssertEqual(VendorCatalog.fallbackModelColorHex(for: "mystery-model-x"), "#f0d66a")
        XCTAssertEqual(VendorCatalog.fallbackModelColorHex(for: "foo"), "#6ab4f0")
        XCTAssertEqual(VendorCatalog.fallbackModelColorHex(for: "Some-Very-Long-Model-Name-That-Overflows-Int32-Hash-2026"), "#5fbf8a")
        XCTAssertEqual(VendorCatalog.fallbackModelColorHex(for: "日本語モデル"), "#5fbf8a")
        XCTAssertEqual(VendorCatalog.modelPaint(for: "claude-sonnet-4-5"), .hex("#cc7c5e"))
        XCTAssertEqual(VendorCatalog.modelPaint(for: "grok-4"), .ink)
    }

    func testRGBAColorParsing() {
        XCTAssertEqual(RGBAColor(hex: "#ffffff"), RGBAColor(red: 1, green: 1, blue: 1))
        XCTAssertEqual(RGBAColor(hex: "000"), RGBAColor(red: 0, green: 0, blue: 0))
        XCTAssertEqual(RGBAColor(hex: "#00000080")?.alpha ?? 0, 128.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(RGBAColor(hex: "#cc7c5e")?.red ?? 0, 204.0 / 255, accuracy: 1e-9)
        XCTAssertNil(RGBAColor(hex: "#12345"))
        XCTAssertNil(RGBAColor(hex: "zzzzzz"))
        XCTAssertEqual(RGBAColor.fallback, RGBAColor(hex: "#6ab4f0"))
    }

    func testStableHashMatchesTheJavaScriptPort() {
        XCTAssertEqual(StableHash.hex("claude|key:sha256:fixture-claude-account"), "527d83d5fcc2")
    }
}

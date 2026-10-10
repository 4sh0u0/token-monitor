import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TokenMonitorKit

/// The model-alias resolver against the desktop (`src/electron/renderer/modelAliases.js`)
/// and the shared sync documents against the captured Hub responses.
final class ModelAliasTests: XCTestCase {
    // MARK: Golden (Fixtures/v2/golden/aliases.json)

    func testResolverMatchesDesktopGoldenForEveryGrouping() throws {
        let golden = try SyncFixture.goldenObject("aliases.json")
        let document = try ModelAliasDocument.decode(from: SyncFixture.data("model-aliases.json"))
        let goldenDocument = try XCTUnwrap(golden["document"] as? [String: Any])
        XCTAssertEqual(document.aliases, goldenDocument["modelAliases"] as? [String: String])
        XCTAssertEqual(document.grouping.rawValue, goldenDocument["modelAliasGrouping"] as? String)

        let observed = try XCTUnwrap(golden["observedModels"] as? [String])
        let groupings = try XCTUnwrap(golden["groupings"] as? [String: Any])
        XCTAssertEqual(Set(groupings.keys), Set(ModelAliasGrouping.allCases.map(\.rawValue)))
        for grouping in ModelAliasGrouping.allCases {
            let expected = try XCTUnwrap(groupings[grouping.rawValue] as? [String: Any])
            // The golden passes no observed ids when grouping is off, as aliasPlan does.
            let resolver = ModelAliasResolver(
                aliases: document.aliases,
                observedModels: grouping == .off ? [] : observed,
                grouping: grouping
            )
            let inferred = try XCTUnwrap(expected["inferred"] as? [String: String])
            XCTAssertEqual(pairsDictionary(resolver.inferredAliases), inferred, "\(grouping)")
            XCTAssertEqual(pairsDictionary(ModelAliasResolver.inferAliases(observed, grouping: grouping)), inferred, "\(grouping)")
            XCTAssertTrue(resolver.isActive, "\(grouping)")

            let resolve = try XCTUnwrap(expected["resolve"] as? [String: String])
            XCTAssertEqual(resolve.count, 29)
            for (model, canonical) in resolve {
                assertSameUnits(resolver.resolve(model), canonical, "\(grouping) \(model)")
            }
            // The document's own grouping goes through init(document:).
            if grouping == document.grouping {
                let fromDocument = ModelAliasResolver(document: document, observedModels: observed)
                XCTAssertEqual(fromDocument, resolver)
                XCTAssertEqual(document.resolver(observedModels: observed), resolver)
            }
        }
    }

    func testNormalizationGroupingAndMatchKeyGoldens() throws {
        let golden = try SyncFixture.goldenObject("aliases.json")
        let document = try ModelAliasDocument.decode(from: SyncFixture.data("model-aliases.json"))

        // normalizeModelAliases({...doc, ' ': 'x', 'Same-Name': 'same.name', 'GLM-4.6-cc': 'dup', bad: 3});
        // `bad: 3` is not a string pair, so it only exists on the decoding path (below).
        let input = document.aliasPairs + [
            ModelAliasPair(alias: " ", canonical: "x"),
            ModelAliasPair(alias: "Same-Name", canonical: "same.name"),
            ModelAliasPair(alias: "GLM-4.6-cc", canonical: "dup")
        ]
        let normalized = ModelAliasResolver.normalizeAliases(input)
        XCTAssertEqual(pairsDictionary(normalized), golden["normalizedAliases"] as? [String: String])
        XCTAssertEqual(normalized.map(\.alias), ["claude-sonnet-4-5-20250929", "glm-4.6-cc", "gpt-5-codex-high"])

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: SyncFixture.data("model-aliases.json")) as? [String: Any])
        var value = try XCTUnwrap(object["value"] as? [String: Any])
        var aliases = try XCTUnwrap(value["modelAliases"] as? [String: Any])
        aliases["bad"] = 3
        aliases["nested"] = ["x": "y"]
        value["modelAliases"] = aliases
        object["value"] = value
        let decoded = try ModelAliasDocument.decode(from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.aliases, document.aliases)

        for row in try XCTUnwrap(golden["groupingNormalization"] as? [[String: Any]]) {
            let value = row["value"] as? String
            XCTAssertEqual(ModelAliasGrouping(normalizing: value).rawValue, row["output"] as? String, "\(String(describing: value))")
        }

        for row in try XCTUnwrap(golden["matchKeyViaResolver"] as? [[String: String]]) {
            let model = try XCTUnwrap(row["model"])
            let resolver = ModelAliasResolver(aliases: [model: "TARGET-X"], grouping: .off)
            XCTAssertEqual(resolver.resolve(model.uppercased()), row["resolved"], model)
        }
    }

    // MARK: Desktop vectors
    // Computed with Node 22 (ICU 77) by loading the unmodified modelAliases.js with
    // its internal helpers (matchKey, modelLeaf, discoveredModelIds) added to the
    // export list.

    func testMatchKeyFollowsJavaScriptStringSemantics() {
        let cases: [(String, String)] = [
            ("claude-sonnet-4-5", "claude-sonnet-4-5"),
            ("Claude Sonnet 4.5", "claude-sonnet-4-5"),
            ("a__b..c  d", "a-b-c-d"),
            ("-x-", "x"),
            ("  --A..B__C--  ", "a-b-c"),
            ("GPT-4.1", "gpt-4-1"),
            ("openrouter/Anthropic/Claude_Sonnet.4.5", "openrouter/anthropic/claude-sonnet-4-5"),
            ("a\u{A0}b", "a-b"),
            ("a\u{3000}b", "a-b"),
            ("a\u{2028}b", "a-b"),
            ("a\u{FEFF}b", "a-b"),
            ("\u{FEFF}gpt-4\u{FEFF}", "gpt-4"),
            ("\u{85}gpt\u{85}", "\u{85}gpt\u{85}"),
            ("a\u{85}b", "a\u{85}b"),
            ("a\u{180E}b", "a\u{180E}b"),
            ("a\u{200B}b", "a\u{200B}b"),
            ("\u{391}\u{3A3}", "\u{3B1}\u{3C2}"),
            ("\u{39F}\u{394}\u{39F}\u{3A3}.4", "\u{3BF}\u{3B4}\u{3BF}\u{3C2}-4"),
            ("\u{39F}\u{394}\u{39F}\u{3A3}A", "\u{3BF}\u{3B4}\u{3BF}\u{3C3}a"),
            ("\u{3A3}", "\u{3C3}"),
            ("A\u{345}\u{3A3}", "a\u{345}\u{3C2}"),
            ("\u{391}\u{3A3}\u{301}", "\u{3B1}\u{3C2}\u{301}"),
            ("\u{130}stanbul", "i\u{307}stanbul"),
            ("\u{1E9E}", "\u{DF}"),
            ("\u{1C5}", "\u{1C6}"),
            ("\u{10400}x", "\u{10428}x"),
            ("\u{216B}", "\u{217B}"),
            ("K", "k"),
            ("", ""),
            ("   ", ""),
            ("...", ""),
            ("a/./b", "a/-/b"),
            ("a - b", "a-b"),
            ("x\u{9}\u{A}\u{D}\u{B}\u{C}y", "x-y")
        ]
        for (input, expected) in cases {
            assertSameUnits(ModelAliasResolver.matchKey(input), expected, input)
        }
    }

    func testModelLeaf() {
        let cases: [(String, String)] = [
            ("", ""), ("   ", ""), ("gpt-4", "gpt-4"), ("openai/gpt-4", "gpt-4"), ("a/b/", "b"), ("///", "///"),
            (" /x/ ", "x"), ("a/ b", " b"), ("a//b", "b"), ("/lead", "lead"), ("trail/", "trail"), ("a/b/c.d", "c.d")
        ]
        for (input, expected) in cases {
            assertSameUnits(ModelAliasResolver.modelLeaf(input), expected, input)
        }
    }

    private struct InferCase {
        var name: String
        var grouping: ModelAliasGrouping
        var models: [String]
        var expected: [(String, String)]
    }

    func testInferenceMatchesDesktopVectors() {
        let cases: [InferCase] = [
            InferCase(
                name: "case and separators", grouping: .duplicates,
                models: ["GPT-4.1", "gpt-4.1", "gpt_4_1", "openai/gpt-4.1", "Azure/GPT-4.1"],
                expected: [
                    ("GPT-4.1", "gpt-4.1"), ("gpt_4_1", "gpt-4.1"), ("openai/gpt-4.1", "gpt-4.1"), ("Azure/GPT-4.1", "gpt-4.1")
                ]
            ),
            InferCase(
                name: "case and separators", grouping: .prefix,
                models: ["GPT-4.1", "gpt-4.1", "gpt_4_1", "openai/gpt-4.1", "Azure/GPT-4.1"],
                expected: [
                    ("GPT-4.1", "gpt-4.1"), ("gpt_4_1", "gpt-4.1"), ("openai/gpt-4.1", "gpt-4.1"), ("Azure/GPT-4.1", "gpt-4.1")
                ]
            ),
            InferCase(
                name: "prefix only canonical absent", grouping: .duplicates,
                models: ["openai/gpt-4o", "azure/gpt-4o"],
                expected: [
                    ("openai/gpt-4o", "gpt-4o"), ("azure/gpt-4o", "gpt-4o")
                ]
            ),
            InferCase(
                name: "prefix only canonical absent", grouping: .prefix,
                models: ["openai/gpt-4o", "azure/gpt-4o"],
                expected: [
                    ("openai/gpt-4o", "gpt-4o"), ("azure/gpt-4o", "gpt-4o")
                ]
            ),
            InferCase(
                name: "single prefixed", grouping: .duplicates,
                models: ["moonshotai/kimi-k2"],
                expected: []
            ),
            InferCase(
                name: "single prefixed", grouping: .prefix,
                models: ["moonshotai/kimi-k2"],
                expected: [
                    ("moonshotai/kimi-k2", "kimi-k2")
                ]
            ),
            InferCase(
                name: "duplicates trimmed", grouping: .duplicates,
                models: ["  x-model ", "x-model", "X-Model", "vendor/x.model"],
                expected: [
                    ("X-Model", "x-model"), ("vendor/x.model", "x-model")
                ]
            ),
            InferCase(
                name: "duplicates trimmed", grouping: .prefix,
                models: ["  x-model ", "x-model", "X-Model", "vendor/x.model"],
                expected: [
                    ("X-Model", "x-model"), ("vendor/x.model", "x-model")
                ]
            ),
            InferCase(
                name: "uppercase only", grouping: .duplicates,
                models: ["Claude-Opus", "CLAUDE-OPUS"],
                expected: [
                    ("Claude-Opus", "CLAUDE-OPUS")
                ]
            ),
            InferCase(
                name: "uppercase only", grouping: .prefix,
                models: ["Claude-Opus", "CLAUDE-OPUS"],
                expected: [
                    ("Claude-Opus", "CLAUDE-OPUS")
                ]
            ),
            InferCase(
                name: "final sigma", grouping: .duplicates,
                models: ["\u{39F}\u{394}\u{39F}\u{3A3}", "\u{3BF}\u{3B4}\u{3BF}\u{3C2}", "vendor/\u{39F}\u{3B4}\u{3BF}\u{3C2}"],
                expected: [
                    ("\u{39F}\u{394}\u{39F}\u{3A3}", "\u{3BF}\u{3B4}\u{3BF}\u{3C2}"),
                    ("vendor/\u{39F}\u{3B4}\u{3BF}\u{3C2}", "\u{3BF}\u{3B4}\u{3BF}\u{3C2}")
                ]
            ),
            InferCase(
                name: "final sigma", grouping: .prefix,
                models: ["\u{39F}\u{394}\u{39F}\u{3A3}", "\u{3BF}\u{3B4}\u{3BF}\u{3C2}", "vendor/\u{39F}\u{3B4}\u{3BF}\u{3C2}"],
                expected: [
                    ("\u{39F}\u{394}\u{39F}\u{3A3}", "\u{3BF}\u{3B4}\u{3BF}\u{3C2}"),
                    ("vendor/\u{39F}\u{3B4}\u{3BF}\u{3C2}", "\u{3BF}\u{3B4}\u{3BF}\u{3C2}")
                ]
            ),
            InferCase(
                name: "dotted leaf vs separator-free", grouping: .duplicates,
                models: ["vendor/a.b", "a-b", "A_B"],
                expected: [
                    ("vendor/a.b", "a-b"), ("A_B", "a-b")
                ]
            ),
            InferCase(
                name: "dotted leaf vs separator-free", grouping: .prefix,
                models: ["vendor/a.b", "a-b", "A_B"],
                expected: [
                    ("vendor/a.b", "a-b"), ("A_B", "a-b")
                ]
            ),
            InferCase(
                name: "empty identity skipped", grouping: .duplicates,
                models: ["...", "v/.", "-", "v/x", "x"],
                expected: [
                    ("v/x", "x")
                ]
            ),
            InferCase(
                name: "empty identity skipped", grouping: .prefix,
                models: ["...", "v/.", "-", "v/x", "x"],
                expected: [
                    ("v/x", "x")
                ]
            ),
            InferCase(
                name: "length tiebreak", grouping: .duplicates,
                models: ["p/abc--d", "abc-d", "q/abc..d"],
                expected: [
                    ("p/abc--d", "abc-d"), ("q/abc..d", "abc-d")
                ]
            ),
            InferCase(
                name: "length tiebreak", grouping: .prefix,
                models: ["p/abc--d", "abc-d", "q/abc..d"],
                expected: [
                    ("p/abc--d", "abc-d"), ("q/abc..d", "abc-d")
                ]
            ),
            InferCase(
                name: "astral", grouping: .duplicates,
                models: ["\u{1F600}-pro", "\u{1F600}_PRO", "v/\u{1F600}.pro"],
                expected: [
                    ("\u{1F600}_PRO", "\u{1F600}-pro"), ("v/\u{1F600}.pro", "\u{1F600}-pro")
                ]
            ),
            InferCase(
                name: "astral", grouping: .prefix,
                models: ["\u{1F600}-pro", "\u{1F600}_PRO", "v/\u{1F600}.pro"],
                expected: [
                    ("\u{1F600}_PRO", "\u{1F600}-pro"), ("v/\u{1F600}.pro", "\u{1F600}-pro")
                ]
            ),
            InferCase(
                name: "kelvin", grouping: .duplicates,
                models: ["\u{212A}imi", "kimi", "Kimi"],
                expected: [
                    ("\u{212A}imi", "kimi"), ("Kimi", "kimi")
                ]
            ),
            InferCase(
                name: "kelvin", grouping: .prefix,
                models: ["\u{212A}imi", "kimi", "Kimi"],
                expected: [
                    ("\u{212A}imi", "kimi"), ("Kimi", "kimi")
                ]
            ),
        ]
        for testCase in cases {
            let inferred = ModelAliasResolver.inferAliases(testCase.models, grouping: testCase.grouping)
            XCTAssertEqual(
                inferred.map { [Array($0.alias.utf16), Array($0.canonical.utf16)] },
                testCase.expected.map { [Array($0.0.utf16), Array($0.1.utf16)] },
                "\(testCase.name) \(testCase.grouping)"
            )
            XCTAssertTrue(ModelAliasResolver.inferAliases(testCase.models, grouping: .off).isEmpty)
        }
    }

    private struct ResolveCase {
        var grouping: ModelAliasGrouping
        var expected: [(String, String)]
    }

    func testResolverKeepsCodeUnitIdentity() {
        // createModelAliasResolver({'gpt-4.1': 'gpt-4-1-canonical', 'kimi-k2': 'Kimi K2', 'é': 'precomposed'}, observed, grouping)
        let aliases = [
            ModelAliasPair(alias: "gpt-4.1", canonical: "gpt-4-1-canonical"),
            ModelAliasPair(alias: "kimi-k2", canonical: "Kimi K2"),
            ModelAliasPair(alias: "\u{E9}", canonical: "precomposed")
        ]
        let observed = ["openai/gpt-4.1", "GPT-4.1", "moonshot/kimi-k2", "kimi-k2", "e\u{301}", "cafe\u{301}", "caf\u{E9}"]
        let cases: [ResolveCase] = [
            ResolveCase(grouping: .off, expected: [
                ("openai/gpt-4.1", "openai/gpt-4.1"), ("GPT-4.1", "gpt-4-1-canonical"), ("moonshot/kimi-k2", "moonshot/kimi-k2"),
                ("kimi-k2", "kimi-k2"), ("e\u{301}", "e\u{301}"), ("cafe\u{301}", "cafe\u{301}"), ("caf\u{E9}", "caf\u{E9}"),
                ("GPT_4.1", "gpt-4-1-canonical"), ("Moonshot/Kimi-K2", "Moonshot/Kimi-K2"), ("\u{E9}", "precomposed"), ("E\u{301}", "E\u{301}"),
                ("unknown", "unknown"), ("", "")
            ]),
            ResolveCase(grouping: .duplicates, expected: [
                ("openai/gpt-4.1", "gpt-4-1-canonical"), ("GPT-4.1", "gpt-4-1-canonical"), ("moonshot/kimi-k2", "kimi-k2"), ("kimi-k2", "kimi-k2"),
                ("e\u{301}", "e\u{301}"), ("cafe\u{301}", "cafe\u{301}"), ("caf\u{E9}", "caf\u{E9}"), ("GPT_4.1", "gpt-4-1-canonical"),
                ("Moonshot/Kimi-K2", "kimi-k2"), ("\u{E9}", "precomposed"), ("E\u{301}", "E\u{301}"), ("unknown", "unknown"), ("", "")
            ]),
            ResolveCase(grouping: .prefix, expected: [
                ("openai/gpt-4.1", "gpt-4-1-canonical"), ("GPT-4.1", "gpt-4-1-canonical"), ("moonshot/kimi-k2", "kimi-k2"), ("kimi-k2", "kimi-k2"),
                ("e\u{301}", "e\u{301}"), ("cafe\u{301}", "cafe\u{301}"), ("caf\u{E9}", "caf\u{E9}"), ("GPT_4.1", "gpt-4-1-canonical"),
                ("Moonshot/Kimi-K2", "kimi-k2"), ("\u{E9}", "precomposed"), ("E\u{301}", "E\u{301}"), ("unknown", "unknown"), ("", "")
            ]),
        ]
        for testCase in cases {
            let resolver = ModelAliasResolver(
                aliases: aliases,
                observedModels: testCase.grouping == .off ? [] : observed,
                grouping: testCase.grouping
            )
            // "kimi-k2" → "Kimi K2" is an alias of itself and is dropped.
            XCTAssertEqual(resolver.explicitAliases.map(\.alias).count, 2)
            for (model, expected) in testCase.expected {
                assertSameUnits(resolver.resolve(model), expected, "\(testCase.grouping) \(model)")
            }
        }
    }

    func testNormalizeAliasesBoundsAndOrder() {
        let long = String(repeating: "m", count: 256)
        let tooLong = String(repeating: "m", count: 257)
        let emoji128 = String(repeating: "\u{1F600}", count: 128)
        let emoji129 = String(repeating: "\u{1F600}", count: 129)
        let input: [(String, String)] = [
            ("gpt-4", "GPT_4"), ("  a  ", "  b  "), ("A", "c"), (" ", "x"), ("x", " "), ("Same-Name", "same.name"),
            (long, "ok-long"), (tooLong, "too-long"), (emoji128, "emoji-ok"), (emoji129, "emoji-too-long"),
            ("\u{E9}", "e-acute"), ("e\u{301}", "e-combining"),
            ("\u{39F}\u{394}\u{39F}\u{3A3}", "greek"), ("\u{3BF}\u{3B4}\u{3BF}\u{3C2}", "greek-dup")
        ]
        let expected: [(String, String)] = [
            ("a", "b"), (long, "ok-long"), (emoji128, "emoji-ok"), ("\u{E9}", "e-acute"), ("e\u{301}", "e-combining"),
            ("\u{39F}\u{394}\u{39F}\u{3A3}", "greek")
        ]
        let normalized = ModelAliasResolver.normalizeAliases(input.map { ModelAliasPair(alias: $0.0, canonical: $0.1) })
        XCTAssertEqual(
            normalized.map { [Array($0.alias.utf16), Array($0.canonical.utf16)] },
            expected.map { [Array($0.0.utf16), Array($0.1.utf16)] }
        )

        // Object.fromEntries/Object.entries list array-index keys first, ascending.
        let indexed = ModelAliasResolver.normalizeAliases([("b", "x"), ("10", "y"), ("9", "z"), ("  7  ", "w")].map {
            ModelAliasPair(alias: $0.0, canonical: $0.1)
        })
        XCTAssertEqual(indexed.map(\.alias), ["7", "9", "10", "b"])
        XCTAssertEqual(
            ModelAliasResolver.hubOrder(["b", "4294967295", "4294967294", "9007199254740991", "1", "01", "-1", "a", "10", "9"]),
            ["1", "9", "10", "4294967294", "-1", "01", "4294967295", "9007199254740991", "a", "b"]
        )

        // The cap: the first 4096 valid aliases survive.
        let many = (0..<5000).map { ModelAliasPair(alias: "model-\($0)", canonical: "target") }
        let capped = ModelAliasResolver.normalizeAliases(many)
        XCTAssertEqual(capped.count, ModelAliasResolver.maxAliases)
        XCTAssertEqual(capped.last?.alias, "model-4095")
    }

    func testDiscoveredModelIDs() {
        let long = String(repeating: "m", count: 256)
        let input = ["  a ", "a", "b", "", "   ", long, long + "m", "\u{E9}", "e\u{301}", "b"]
        let discovered = ModelAliasResolver.discoveredModelIDs(input)
        XCTAssertEqual(discovered.map { Array($0.utf16) }, ["a", "b", long, "\u{E9}", "e\u{301}"].map { Array($0.utf16) })
        XCTAssertEqual(ModelAliasResolver.discoveredModelIDs((0..<20_000).map { "m\($0)" }).count, ModelAliasResolver.maxDiscoveredModels)
    }

    func testCanonicalCandidateRanking() {
        let identity = "gpt-4-1"
        XCTAssertEqual(ModelAliasResolver.compareCanonicalCandidates("gpt-4.1", "openai/gpt-4.1", identity: identity), -1)
        XCTAssertEqual(ModelAliasResolver.compareCanonicalCandidates("GPT-4.1", "gpt-4.1", identity: identity), 1)
        XCTAssertEqual(ModelAliasResolver.compareCanonicalCandidates("gpt-4-1", "gpt-4.1", identity: identity), -1)
        XCTAssertEqual(ModelAliasResolver.compareCanonicalCandidates("a/gpt-4.1", "b/gpt-4.1", identity: identity), 0)
        // A separator-free leaf, then the shorter leaf, then code-unit order of
        // the lowercased leaf and of the leaf itself.
        XCTAssertEqual(ModelAliasResolver.compareCanonicalCandidates("x/a--b", "y/a-_b", identity: "a-b"), -1)
        XCTAssertEqual(ModelAliasResolver.compareCanonicalCandidates("abc-d", "abc--d", identity: "abc-d"), -1)
        XCTAssertEqual(ModelAliasResolver.compareCanonicalCandidates("x/a.b", "y/a_b", identity: "a-b"), -1)
        XCTAssertEqual(ModelAliasResolver.compareCanonicalCandidates("x/a.B", "y/A.b", identity: "a-b"), 1)
    }

    func testInactiveResolverAndUninitializedDocument() throws {
        XCTAssertFalse(ModelAliasResolver.inactive.isActive)
        XCTAssertEqual(ModelAliasResolver.inactive.resolve(" GPT-4 "), " GPT-4 ")

        // Duplicates needs two spellings; a single prefixed id stays as is.
        let lone = ModelAliasResolver(aliases: [String: String](), observedModels: ["openai/gpt-4.1"], grouping: .duplicates)
        XCTAssertFalse(lone.isActive)
        XCTAssertEqual(lone.resolve("openai/gpt-4.1"), "openai/gpt-4.1")
        let prefixed = ModelAliasResolver(aliases: [String: String](), observedModels: ["openai/gpt-4.1"], grouping: .prefix)
        XCTAssertTrue(prefixed.isActive)
        XCTAssertEqual(prefixed.resolve("OpenAI/GPT_4.1"), "gpt-4.1")

        let body = Data(#"{"ok":true,"version":1,"revision":0,"updatedAt":"","value":null}"#.utf8)
        let document = try ModelAliasDocument.decode(from: body)
        XCTAssertEqual(document, .uninitialized)
        XCTAssertFalse(document.isInitialized)
        XCTAssertNil(document.updatedAt)
        XCTAssertEqual(document.grouping, .off)
        XCTAssertTrue(document.aliasPairs.isEmpty)
        let resolver = ModelAliasResolver(document: document, observedModels: ["openai/gpt-4.1", "gpt-4.1"])
        XCTAssertFalse(resolver.isActive)
        XCTAssertEqual(resolver.resolve("openai/gpt-4.1"), "openai/gpt-4.1")

        // An explicitly empty group is initialized (positive revision).
        let empty = try ModelAliasDocument.decode(from: Data(#"{"ok":true,"version":1,"revision":3,"updatedAt":"2026-10-10T16:29:50.000Z","value":{"modelAliases":{},"modelAliasGrouping":"off"}}"#.utf8))
        XCTAssertTrue(empty.isInitialized)
        XCTAssertEqual(empty.revision, 3)
        XCTAssertFalse(empty.resolver().isActive)
    }

    // MARK: Documents

    func testModelAliasDocumentDecodesCapture() throws {
        let document = try ModelAliasDocument.decode(from: SyncFixture.data("model-aliases.json"))
        XCTAssertEqual(document.revision, 1)
        XCTAssertEqual(document.updatedAt, ISODate.parse("2026-10-10T16:29:50.000Z"))
        XCTAssertTrue(document.isInitialized)
        XCTAssertEqual(document.grouping, .duplicates)
        XCTAssertEqual(document.aliases, [
            "claude-sonnet-4-5-20250929": "claude-sonnet-4-5",
            "glm-4.6-cc": "glm-4.6",
            "gpt-5-codex-high": "gpt-5-codex"
        ])
        XCTAssertEqual(document.aliasPairs.count, 3)

        // The cached form is the wire form and round-trips.
        let reencoded = try JSONEncoder().encode(document)
        XCTAssertEqual(try ModelAliasDocument.decode(from: reencoded), document)
        let uninitialized = try JSONEncoder().encode(ModelAliasDocument.uninitialized)
        XCTAssertEqual(try ModelAliasDocument.decode(from: uninitialized), .uninitialized)
    }

    func testModelAliasDocumentRejectsWhatTheDesktopCallsUnsupported() throws {
        let bodies = [
            #"{"ok":true,"version":2,"revision":1,"updatedAt":"","value":null}"#,
            #"{"ok":true,"revision":1,"updatedAt":"","value":null}"#,
            #"{"ok":true,"version":1,"revision":-1,"updatedAt":"","value":null}"#,
            #"{"ok":true,"version":1,"revision":1.5,"updatedAt":"","value":null}"#,
            #"{"ok":true,"version":1,"revision":"1","updatedAt":"","value":null}"#,
            #"{"ok":true,"version":1,"revision":1,"updatedAt":""}"#,
            #"{"ok":true,"version":1,"revision":1,"updatedAt":"","value":[]}"#,
            #"[]"#
        ]
        for body in bodies {
            XCTAssertThrowsError(try ModelAliasDocument.decode(from: Data(body.utf8)), body)
        }

        // Inside a valid envelope the value is read leniently.
        let lenient = try ModelAliasDocument.decode(from: Data(#"{"version":1,"revision":2,"updatedAt":"bad","value":{"modelAliases":[1],"modelAliasGrouping":" PREFIX "}}"#.utf8))
        XCTAssertTrue(lenient.isInitialized)
        XCTAssertTrue(lenient.aliases.isEmpty)
        XCTAssertEqual(lenient.grouping, .prefix)
        XCTAssertNil(lenient.updatedAt)
        let unknownGrouping = try ModelAliasDocument.decode(from: Data(#"{"version":1,"revision":2,"updatedAt":"","value":{"modelAliases":{"a":"b"},"modelAliasGrouping":"auto"}}"#.utf8))
        XCTAssertEqual(unknownGrouping.grouping, .off)
        XCTAssertEqual(unknownGrouping.aliases, ["a": "b"])
    }

    func testRefetchFollowsAdvertisedRevision() throws {
        let document = try ModelAliasDocument.decode(from: SyncFixture.data("model-aliases.json"))
        XCTAssertTrue(ModelAliasDocument.needsFetch(cached: nil, advertisedRevision: nil))
        XCTAssertTrue(ModelAliasDocument.needsFetch(cached: nil, advertisedRevision: 1))
        XCTAssertFalse(ModelAliasDocument.needsFetch(cached: document, advertisedRevision: 1))
        XCTAssertTrue(ModelAliasDocument.needsFetch(cached: document, advertisedRevision: 2))
        // An absent marker (older Hub) is no news.
        XCTAssertFalse(ModelAliasDocument.needsFetch(cached: document, advertisedRevision: nil))
        XCTAssertFalse(ModelAliasDocument.needsFetch(cached: .uninitialized, advertisedRevision: nil))
        XCTAssertFalse(ModelAliasDocument.needsFetch(cached: .uninitialized, advertisedRevision: 0))

        let revisions = ["modelAliases": 4, "customPricing": -1]
        XCTAssertEqual(SharedSettingsKind.modelAliases.advertisedRevision(in: revisions), 4)
        XCTAssertNil(SharedSettingsKind.customPricing.advertisedRevision(in: revisions))
        XCTAssertNil(SharedSettingsKind.modelAliases.advertisedRevision(in: nil))
        XCTAssertEqual(SharedSettingsKind.modelAliases.endpoint, .syncSettingsModelAliases)
        XCTAssertEqual(SharedSettingsKind.customPricing.endpoint, .syncSettingsCustomPricing)
    }

    func testCustomPricingDocument() throws {
        let document = try CustomPricingDocument.decode(from: SyncFixture.data("custom-pricing.json"))
        XCTAssertEqual(document.revision, 1)
        XCTAssertEqual(document.updatedAt, ISODate.parse("2026-10-10T16:29:55.000Z"))
        XCTAssertTrue(document.isInitialized)
        XCTAssertEqual(document.entries, [
            CustomPricingEntry(modelId: "big-pickle", inputPerM: 0, outputPerM: 0),
            CustomPricingEntry(modelId: "glm-4.6", inputPerM: 0.6, outputPerM: 2.2, cacheReadPerM: 0.11),
            CustomPricingEntry(modelId: "mystery-model-x", inputPerM: 0.5, outputPerM: 2)
        ])
        XCTAssertEqual(try CustomPricingDocument.decode(from: JSONEncoder().encode(document)), document)

        let uninitialized = try CustomPricingDocument.decode(from: Data(#"{"ok":true,"version":1,"revision":0,"updatedAt":"","value":null}"#.utf8))
        XCTAssertNil(uninitialized.entries)
        XCTAssertFalse(uninitialized.isInitialized)
        XCTAssertEqual(uninitialized.revision, 0)

        let lenient = try CustomPricingDocument.decode(from: Data(#"""
        {"version":1,"revision":2,"updatedAt":"","value":[
          {"modelId":"a","inputPerM":-1,"outputPerM":"2","cacheReadPerM":null,"cacheWrite1hPerM":4},
          {"inputPerM":1}, 5, {"modelId":"  b  ","outputPerM":0.001}]}
        """#.utf8))
        XCTAssertEqual(lenient.entries, [
            CustomPricingEntry(modelId: "a", cacheWrite1hPerM: 4),
            CustomPricingEntry(modelId: "b", outputPerM: 0.001)
        ])
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(CustomPricingEntry(modelId: "a", cacheWrite1hPerM: 4)), encoding: .utf8))
        XCTAssertFalse(encoded.contains("inputPerM"))

        XCTAssertThrowsError(try CustomPricingDocument.decode(from: Data(#"{"version":1,"revision":2,"updatedAt":"","value":{}}"#.utf8)))
    }

    func testSyncContentCapabilities() throws {
        let capture = try SyncContentCapabilities.decode(from: SyncFixture.data("sync-content.json"))
        XCTAssertEqual(capture, SyncContentCapabilities(version: 1, sessionTitlesEnabled: true, sharedSettings: true))
        XCTAssertTrue(capture.isSupported)

        let disabled = try SyncContentCapabilities.decode(from: Data(#"{"ok":true,"version":1,"sessionTitles":{"enabled":false},"sharedSettings":true}"#.utf8))
        XCTAssertFalse(disabled.sessionTitlesEnabled)
        XCTAssertTrue(disabled.isSupported)

        for body in [
            #"{"ok":true,"version":1,"sharedSettings":true}"#,
            #"{"ok":true,"version":1,"sessionTitles":{"enabled":"true"},"sharedSettings":true}"#,
            #"{"ok":true,"version":2,"sessionTitles":{"enabled":true},"sharedSettings":true}"#,
            #"{"ok":true,"version":1,"sessionTitles":{"enabled":true},"sharedSettings":false}"#
        ] {
            let capabilities = try SyncContentCapabilities.decode(from: Data(body.utf8))
            XCTAssertFalse(capabilities.isSupported, body)
        }
    }

    // MARK: Cache

    func testCacheIsTiedToHubKey() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelAliasCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ModelAliasCache(directory: directory)
        XCTAssertNil(cache.load(hubKey: "hub-a"))
        XCTAssertTrue(cache.needsRefresh(hubKey: "hub-a", advertisedRevision: nil))
        XCTAssertNoThrow(try cache.clear())

        let document = try ModelAliasDocument.decode(from: SyncFixture.data("model-aliases.json"))
        try cache.save(document, hubKey: "hub-a")
        XCTAssertEqual(cache.fileURL.lastPathComponent, "model-aliases.json")
        XCTAssertEqual(cache.load(hubKey: "hub-a"), document)
        XCTAssertNil(cache.load(hubKey: "hub-b"))
        XCTAssertEqual(cache.loadEntry(), ModelAliasCache.Entry(hubKey: "hub-a", document: document))
        XCTAssertFalse(cache.needsRefresh(hubKey: "hub-a", advertisedRevision: 1))
        XCTAssertFalse(cache.needsRefresh(hubKey: "hub-a", advertisedRevision: nil))
        XCTAssertTrue(cache.needsRefresh(hubKey: "hub-a", advertisedRevision: 2))
        XCTAssertTrue(cache.needsRefresh(hubKey: "hub-b", advertisedRevision: 1))

        // Saving for another Hub replaces the file.
        try cache.save(.uninitialized, hubKey: "hub-b")
        XCTAssertNil(cache.load(hubKey: "hub-a"))
        XCTAssertEqual(cache.load(hubKey: "hub-b"), .uninitialized)

        try Data("not json".utf8).write(to: cache.fileURL)
        XCTAssertNil(cache.load(hubKey: "hub-b"))
        XCTAssertNil(cache.loadEntry())

        try cache.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.fileURL.path))
        XCTAssertEqual(ModelAliasCache.shared.fileURL.lastPathComponent, ModelAliasCache.fileName)
    }

    // MARK: Client

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        StubURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    private func client() throws -> HubClient {
        HubClient(connection: try HubConnection(userInput: "http://hub.test:17321", secret: "s3cret"), session: session)
    }

    func testClientReadsSharedSettings() async throws {
        StubURLProtocol.stub(path: "/api/sync/content", status: 200, body: try SyncFixture.data("sync-content.json"))
        StubURLProtocol.stub(path: "/api/sync/settings/modelAliases", status: 200, body: try SyncFixture.data("model-aliases.json"))
        StubURLProtocol.stub(path: "/api/sync/settings/customPricing", status: 200, body: try SyncFixture.data("custom-pricing.json"))
        let client = try client()

        let capabilities = try await client.syncContent()
        XCTAssertTrue(capabilities.sessionTitlesEnabled)
        let document = try await client.modelAliasDocument()
        XCTAssertEqual(document.grouping, .duplicates)
        let pricing = try await client.customPricing()
        XCTAssertEqual(pricing.revision, 1)
        XCTAssertEqual(pricing.entries?.map(\.modelId), ["big-pickle", "glm-4.6", "mystery-model-x"])

        let requests = StubURLProtocol.recordedRequests
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/sync/content", "/api/sync/settings/modelAliases", "/api/sync/settings/customPricing"])
        XCTAssertEqual(Set(requests.map { $0.value(forHTTPHeaderField: "Authorization") }), ["Bearer s3cret"])
        XCTAssertEqual(Set(requests.map { $0.value(forHTTPHeaderField: "Accept") }), ["application/json"])
        XCTAssertEqual(Set(requests.map(\.httpMethod)), ["GET"])
    }

    func testClientErrors() async throws {
        let client = try client()
        StubURLProtocol.stub(path: "/api/sync/settings/modelAliases", status: 404, body: Data(#"{"error":"not_found"}"#.utf8))
        StubURLProtocol.stub(path: "/api/sync/content", status: 405, body: Data())
        StubURLProtocol.stub(path: "/api/sync/settings/customPricing", status: 200, body: Data(#"{"ok":true}"#.utf8))
        do {
            _ = try await client.modelAliasDocument()
            XCTFail("expected 404")
        } catch let error as HubClientError {
            XCTAssertEqual(error, .http(status: 404))
            XCTAssertTrue(error.isUnsupportedEndpoint)
        }
        do {
            _ = try await client.syncContent()
            XCTFail("expected 405")
        } catch let error as HubClientError {
            XCTAssertTrue(error.isUnsupportedEndpoint)
        }
        do {
            _ = try await client.customPricing()
            XCTFail("expected a decoding error")
        } catch let error as HubClientError {
            guard case .decoding = error else { return XCTFail("\(error)") }
            XCTAssertFalse(error.isUnsupportedEndpoint)
        }
        XCTAssertFalse(HubClientError.http(status: 500).isUnsupportedEndpoint)
        XCTAssertFalse(HubClientError.unauthorized.isUnsupportedEndpoint)
    }

    // MARK: Helpers

    private func pairsDictionary(_ pairs: [ModelAliasPair]) -> [String: String] {
        Dictionary(pairs.map { ($0.alias, $0.canonical) }, uniquingKeysWith: { first, _ in first })
    }

    /// JS `===`: Swift's `==` would equate canonically equivalent strings.
    private func assertSameUnits(_ actual: String, _ expected: String, _ message: String = "", line: UInt = #line) {
        XCTAssertEqual(Array(actual.utf16), Array(expected.utf16), "\(message): \(actual.debugDescription) vs \(expected.debugDescription)", line: line)
    }
}

/// Round-2 fixtures (`Fixtures/v2`, goldens in `Fixtures/v2/golden`).
private enum SyncFixture {
    static func data(_ name: String, golden: Bool = false) throws -> Data {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let url = Bundle.module.url(
            forResource: parts[0],
            withExtension: parts.count > 1 ? parts[1] : nil,
            subdirectory: golden ? "Fixtures/v2/golden" : "Fixtures/v2"
        ) else {
            throw NSError(domain: "SyncFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name)"])
        }
        return try Data(contentsOf: url)
    }

    static func goldenObject(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(name, golden: true)) as? [String: Any])
    }
}

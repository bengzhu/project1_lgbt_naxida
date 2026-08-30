#!/usr/bin/env python3
"""Static and pure-policy contract for the v3.320 Japanese line frontier."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def function_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing function signature: {signature}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1 : index]
    raise AssertionError(f"unterminated function body: {signature}")


def japanese_letter_density(text: str) -> float:
    def is_letter(character: str) -> bool:
        codepoint = ord(character)
        return any(
            lower <= codepoint <= upper
            for lower, upper in (
                (0x3041, 0x3096),
                (0x30A1, 0x30FA),
                (0x30FD, 0x30FF),
                (0x3400, 0x4DBF),
                (0x4E00, 0x9FFF),
                (0xF900, 0xFAFF),
                (0xFF66, 0xFF9D),
            )
        )

    letter_count = sum(is_letter(character) for character in text)
    if not letter_count:
        return 0.0

    def is_technical_word(character: str) -> bool:
        codepoint = ord(character)
        return any(
            lower <= codepoint <= upper
            for lower, upper in (
                (0x30, 0x39),
                (0x41, 0x5A),
                (0x61, 0x7A),
                (0xFF10, 0xFF19),
                (0xFF21, 0xFF3A),
                (0xFF41, 0xFF5A),
            )
        )

    visible = [
        character
        for character in text
        if not character.isspace() and not is_technical_word(character)
    ]
    if not visible:
        return 0.0
    support_count = sum(
        0x3099 <= ord(character) <= 0x309C or ord(character) == 0x30FC
        for character in visible
    )
    return (letter_count + support_count) / len(visible)


class JapaneseLineMeaningfulDensityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.normalizer = read("AITRANS/Models/JapaneseOCRTextNormalizer.swift")
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.test_log = read("md/test/test.md")
        cls.update_log = read("update_log.md")

    def test_shared_density_uses_real_letters_and_visible_denominator(self) -> None:
        body = function_body(
            self.normalizer,
            "static func japaneseLetterDensity(_ text: String) -> Double",
        )
        self.assertIn("letterCount > 0", body)
        self.assertIn("counts.visible", body)
        self.assertIn("CharacterSet.whitespacesAndNewlines.contains(scalar)", body)
        self.assertIn("containsASCIIWordScalar(scalar)", body)
        self.assertIn("containsFullwidthWordScalar(scalar)", body)
        self.assertIn("0x3099...0x309C, 0x30FC", body)
        self.assertIn("japaneseLetterCount(text)", body)
        self.assertIn("Double(letterCount + counts.support) / Double(counts.visible)", body)

    def test_density_examples_keep_punctuation_as_denominator(self) -> None:
        self.assertEqual(japanese_letter_density("！！"), 0.0)
        self.assertAlmostEqual(japanese_letter_density("日！！"), 1 / 3)
        self.assertGreaterEqual(japanese_letter_density("日本語。"), 0.5)
        self.assertGreaterEqual(japanese_letter_density("GPT-4日本語"), 0.5)
        self.assertGreaterEqual(japanese_letter_density("キャー！！"), 0.5)
        self.assertEqual(japanese_letter_density("ーー"), 0.0)
        self.assertEqual(japanese_letter_density("  …  "), 0.0)

    def test_detector_owner_requires_meaningful_line_density(self) -> None:
        body = function_body(
            self.vision,
            "private static func isReliableJapaneseMangaOCRResult(\n",
        )
        for marker in (
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(result.text)",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(result.text) >= 0.5",
            "japaneseScriptDensity(in: result.text) >= 0.5",
        ):
            self.assertIn(marker, body)
        self.assertLess(
            body.index("japaneseLetterDensity"),
            body.index("japaneseScriptDensity"),
        )

    def test_line_coverage_requires_meaningful_line_density(self) -> None:
        body = function_body(
            self.vision,
            "private static func isReliableJapaneseLineCoverageResult(\n",
        )
        for marker in (
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(text)",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5",
            "japaneseScriptDensity(in: text) >= 0.5",
            "candidateLength < 2 || resultLength >= 2",
        ):
            self.assertIn(marker, body)

    def test_line_frontier_requires_meaningful_text_before_geometry(self) -> None:
        body = function_body(
            self.vision,
            "private static func japaneseLinePathRegion(\n",
        )
        for marker in (
            "observationRole == .verticalLine",
            "confidence >= 0.48",
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(text)",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5",
            "japaneseScriptDensity(in: text) >= 0.5",
            "lineRegionRect?.normalizedToUnit()",
            "observation.rect.normalizedToUnit()",
            "isVerticalLineCandidate(region)",
        ):
            self.assertIn(marker, body)
        self.assertLess(
            body.index("japaneseLetterDensity"),
            body.index("lineRegionRect?.normalizedToUnit()"),
        )

    def test_line_frontier_is_shared_by_detector_and_tile_recovery(self) -> None:
        detector = function_body(
            self.vision,
            "private static func detectJapanesePixelFirstVerticalRegions(\n",
        )
        tiles = function_body(
            self.vision,
            "private static func recognizeJapaneseVerticalTileFallback(\n",
        )
        self.assertIn("japaneseLinePathRegion(observation)", detector)
        self.assertIn("japaneseLinePathRegion(observation)", tiles)
        self.assertIn("overlapRatio($0, mappedRect) >= 0.60", detector)
        self.assertIn("overlapRatio($0, tileRect) >= 0.60", tiles)

    def test_bounded_recovery_and_scoped_replacement_use_same_density(self) -> None:
        weak_trigger = function_body(
            self.vision,
            "private static func needsJapaneseWeakBlockRecovery(\n",
        )
        weak_candidate = function_body(
            self.vision,
            "private static func isBetterJapaneseWeakBlockRecovery(\n",
        )
        scoped = function_body(
            self.vision,
            "private static func isUsableJapaneseScopedText(\n",
        )
        direct_scoped = function_body(
            self.vision,
            "private static func recognizeTextBlockDetached(\n        image: CGImage",
        )
        self.assertIn("japaneseLetterDensity(text) < 0.5", weak_trigger)
        self.assertIn("japaneseLetterDensity(candidateText) >= 0.5", weak_candidate)
        self.assertIn("japaneseLetterDensity(text) >= 0.5", scoped)
        self.assertIn("japaneseLetterDensity(text) >= 0.5", direct_scoped)
        block_scoped = function_body(
            self.vision,
            "private static func isUsableJapaneseScopedBlockCandidate(\n",
        )
        self.assertIn("isUsableJapaneseScopedText(", block_scoped)

    def test_line_budget_and_orientation_recovery_use_meaningful_density(self) -> None:
        candidates = function_body(
            self.vision,
            "private static func japaneseMangaLineOCRCandidates(\n",
        )
        orientation = function_body(
            self.vision,
            "private static func needsJapaneseOrientationFallback(\n",
        )
        self.assertIn("japaneseLetterDensity(text) >= 0.5", candidates)
        self.assertIn("japaneseLetterDensity(best.text) < 0.5", orientation)

    def test_ordinary_candidate_and_request_caps_are_not_expanded(self) -> None:
        page_selector = function_body(self.vision, "private static func selectOCRCandidate(\n")
        self.assertNotIn("japaneseLetterDensity", page_selector)
        self.assertIn("maximumJapaneseMangaLineOCRRequests = 8", self.vision)
        self.assertIn("maximumJapaneseWeakBlockRecoveryRequests = 4", self.vision)
        self.assertIn("translateImageBlockWithQA(", self.store)

    def test_research_and_product_boundaries_remain_separate(self) -> None:
        for source in (self.normalizer, self.vision):
            self.assertNotIn("groundTruth", source)
            self.assertNotIn("KOHARU_DATA_ROOT", source)
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
        self.assertNotIn("test/koharu_artifacts", self.vision)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.355", "3.355"],
        )
        for marker in (
            "scripts/test-v3320-japanese-line-meaningful-density-contract.py",
            "v3.320",
            "japanese-benchmark-v3.320-",
        ):
            self.assertIn(
                marker,
                self.workflow + self.flow + self.route + self.test_log + self.update_log,
            )

    def test_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3320-japanese-line-meaningful-density-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)

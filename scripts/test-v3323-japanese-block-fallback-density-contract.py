#!/usr/bin/env python3
"""Static and pure-policy contract for the v3.323 block fallback gate."""

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


def is_japanese_letter(character: str) -> bool:
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


def japanese_letter_density(text: str) -> float:
    letter_count = sum(is_japanese_letter(character) for character in text)
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


def japanese_script_density(text: str) -> float:
    if not text:
        return 0.0
    japanese_count = 0
    for character in text:
        codepoint = ord(character)
        if any(
            lower <= codepoint <= upper
            for lower, upper in (
                (0x3000, 0x303F),
                (0x3040, 0x30FF),
                (0x3400, 0x4DBF),
                (0x4E00, 0x9FFF),
                (0xF900, 0xFAFF),
                (0xFF61, 0xFF9F),
            )
        ):
            japanese_count += 1
    return japanese_count / len(text)


def commits_block_fallback(text: str) -> bool:
    cleaned = text.strip()
    return (
        bool(cleaned)
        and any(is_japanese_letter(character) for character in cleaned)
        and japanese_letter_density(cleaned) >= 0.5
        and japanese_script_density(cleaned) >= 0.5
    )


class JapaneseBlockFallbackDensityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
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

    def test_punctuation_heavy_results_are_not_block_fallbacks(self) -> None:
        self.assertEqual(japanese_script_density("。、"), 1.0)
        self.assertEqual(japanese_script_density("日。、"), 1.0)
        self.assertFalse(commits_block_fallback("。、"))
        self.assertFalse(commits_block_fallback("日。、"))
        self.assertTrue(commits_block_fallback("日本語。"))
        self.assertTrue(commits_block_fallback("ニコッ"))

    def test_block_primary_is_filtered_before_fallback_and_commit(self) -> None:
        body = function_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )
        for marker in (
            "let meaningfulPrimary = meaningfulJapaneseRecoveryObservations(",
            "var blockFallback = meaningfulPrimary",
            "needsJapaneseOrientationFallback(meaningfulPrimary)",
        ):
            self.assertIn(marker, body)
        self.assertNotIn("var blockFallback = primary", body)
        self.assertLess(
            body.index("let meaningfulPrimary = meaningfulJapaneseRecoveryObservations("),
            body.index("needsJapaneseOrientationFallback(meaningfulPrimary)"),
        )

    def test_block_opposite_is_filtered_before_commit(self) -> None:
        body = function_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )
        for marker in (
            "let opposite = recognizeJapaneseCropPass(",
            "contentsOf: meaningfulJapaneseRecoveryObservations(opposite)",
        ):
            self.assertIn(marker, body)
        self.assertLess(
            body.index("let opposite = recognizeJapaneseCropPass("),
            body.index("meaningfulJapaneseRecoveryObservations(opposite)"),
        )

    def test_only_filtered_fallback_can_replace_lines_or_reach_fusion(self) -> None:
        body = function_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )
        for marker in (
            "blockFallback = deduplicateJapaneseObservations(blockFallback)",
            "lineRefined: blockFallback",
            "fallbackOwners: blockFallback.map(\\.verticalTextRegionOwner)",
            "refined.append(contentsOf: blockFallback)",
        ):
            self.assertIn(marker, body)
        self.assertLess(
            body.index("var blockFallback = meaningfulPrimary"),
            body.index("lineRefined: blockFallback"),
        )
        self.assertLess(
            body.index("lineRefined: blockFallback"),
            body.index("refined.append(contentsOf: blockFallback)"),
        )

    def test_empty_filtered_fallback_keeps_partial_lines(self) -> None:
        body = function_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )
        for marker in (
            "blockFallbackCanReplacePartialLines(",
            "refined.removeAll {",
            "$0.observationRole == .verticalLine",
            "$0.verticalTextRegionOwner == blockOwner",
        ):
            self.assertIn(marker, body)
        self.assertLess(
            body.index("blockFallbackCanReplacePartialLines("),
            body.index("refined.removeAll {"),
        )

    def test_block_request_owner_and_coverage_bounds_are_unchanged(self) -> None:
        body = function_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )
        for marker in (
            ".prefix(16)",
            "var orientationFallbacksRemaining = 8",
            "verticalTextRegionOwner: block.verticalTextRegionOwner",
            "allowsBlockCropResults: true",
        ):
            self.assertIn(marker, body)
        self.assertEqual(body.count("orientationFallbacksRemaining -= 1"), 1)

    def test_translation_persistence_and_research_bounds_are_unchanged(self) -> None:
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)
        self.assertNotIn("groundTruth", self.vision)
        self.assertNotIn("KOHARU_DATA_ROOT", self.vision)
        self.assertNotIn("test/koharu_artifacts", self.vision)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.358", "3.358"],
        )
        combined = (
            self.workflow
            + self.flow
            + self.route
            + self.test_log
            + self.update_log
        )
        for marker in (
            "scripts/test-v3323-japanese-block-fallback-density-contract.py",
            "v3.323",
            "japanese-benchmark-v3.323-",
        ):
            self.assertIn(marker, combined)

    def test_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3323-japanese-block-fallback-density-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)

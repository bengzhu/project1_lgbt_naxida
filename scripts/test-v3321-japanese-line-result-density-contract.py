#!/usr/bin/env python3
"""Static and pure-policy contract for the v3.321 Manga line result gate."""

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


def commits_manga_line_result(text: str, confidence: float) -> bool:
    cleaned = text.strip()
    return (
        bool(cleaned)
        and confidence >= 0.55
        and any(is_japanese_letter(character) for character in cleaned)
        and japanese_letter_density(cleaned) >= 0.5
        and japanese_script_density(cleaned) >= 0.5
    )


class JapaneseLineResultDensityContractTests(unittest.TestCase):
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

    def test_legacy_script_density_alone_accepts_japanese_punctuation(self) -> None:
        self.assertEqual(japanese_script_density("。、"), 1.0)
        self.assertEqual(japanese_script_density("日。、"), 1.0)
        self.assertEqual(japanese_letter_density("。、"), 0.0)
        self.assertAlmostEqual(japanese_letter_density("日。、"), 1 / 3)
        self.assertFalse(commits_manga_line_result("。、", 0.99))
        self.assertFalse(commits_manga_line_result("日。、", 0.99))

    def test_meaningful_line_results_and_confidence_remain_accepted(self) -> None:
        self.assertTrue(commits_manga_line_result("日本語。", 0.55))
        self.assertTrue(commits_manga_line_result("ニコッ", 0.80))
        self.assertFalse(commits_manga_line_result("日本語。", 0.549))
        self.assertFalse(commits_manga_line_result("", 0.99))

    def test_manga_line_commit_requires_shared_meaningful_density(self) -> None:
        body = function_body(
            self.vision,
            "private static func recognizeJapaneseMangaLineOCR(\n",
        )
        markers = (
            "let text = Self.cleanRecognizedBlockText(result.text)",
            "result.confidence.isFinite",
            "result.confidence >= 0.55",
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(text)",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5",
            "japaneseScriptDensity(in: text) >= 0.5",
        )
        for marker in markers:
            self.assertIn(marker, body)
        self.assertLess(
            body.index("japaneseLetterDensity(text)"),
            body.index("unmatchedCandidates.firstIndex"),
        )
        self.assertLess(
            body.index("japaneseScriptDensity(in: text)"),
            body.index("unmatchedCandidates.firstIndex"),
        )

    def test_only_matched_accepted_results_become_vertical_lines(self) -> None:
        body = function_body(
            self.vision,
            "private static func recognizeJapaneseMangaLineOCR(\n",
        )
        for marker in (
            "unmatchedCandidates.remove(at: candidateIndex)",
            "observations.append(",
            "sourceDirectionHint: .vertical",
            "observationRole: .verticalLine",
            "verticalTextRegionOwner: result.verticalTextRegionOwner",
            "engine: .bundledMangaOCR",
        ):
            self.assertIn(marker, body)
        self.assertLess(
            body.index("unmatchedCandidates.remove(at: candidateIndex)"),
            body.index("observations.append("),
        )

    def test_rejected_line_keeps_existing_block_fallback_boundary(self) -> None:
        body = function_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )
        for marker in (
            "let lineRefined = try await Self.recognizeJapaneseVerticalLineCrops(",
            "hasCompleteJapaneseLineCoverage(",
            "guard !hasLineOCRResult else { continue }",
            "var orientationFallbacksRemaining = 8",
            "var blockFallback = meaningfulPrimary",
        ):
            self.assertIn(marker, body)
        self.assertLess(
            body.index("let lineRefined"),
            body.index("hasCompleteJapaneseLineCoverage("),
        )
        self.assertLess(
            body.index("guard !hasLineOCRResult else { continue }"),
            body.index("var blockFallback = meaningfulPrimary"),
        )

    def test_request_cancel_translation_and_persistence_bounds_are_unchanged(self) -> None:
        line_body = function_body(
            self.vision,
            "private static func recognizeJapaneseMangaLineOCR(\n",
        )
        self.assertIn("maximumJapaneseMangaLineOCRRequests = 8", self.vision)
        self.assertIn("var orientationFallbacksRemaining = 12", self.vision)
        self.assertEqual(line_body.count("MangaOCRService.shared.recognize("), 1)
        self.assertIn("catch is CancellationError", line_body)
        self.assertIn("throw CancellationError()", line_body)
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)

    def test_research_and_product_boundaries_remain_separate(self) -> None:
        self.assertNotIn("groundTruth", self.vision)
        self.assertNotIn("KOHARU_DATA_ROOT", self.vision)
        self.assertNotIn("test/koharu_artifacts", self.vision)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.325", "3.325"],
        )
        combined = (
            self.workflow
            + self.flow
            + self.route
            + self.test_log
            + self.update_log
        )
        for marker in (
            "scripts/test-v3321-japanese-line-result-density-contract.py",
            "v3.321",
            "japanese-benchmark-v3.321-",
        ):
            self.assertIn(marker, combined)

    def test_contract_has_no_process_entry(self) -> None:
        contract = read("scripts/test-v3321-japanese-line-result-density-contract.py")
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)

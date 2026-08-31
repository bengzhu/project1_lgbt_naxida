#!/usr/bin/env python3
"""Static and pure-policy contract for the v3.324 Vision line return gate."""

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


def japanese_letter_density(text: str) -> float:
    letter_count = sum(is_japanese_letter(character) for character in text)
    if not letter_count:
        return 0.0
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


def commits_vision_line(text: str) -> bool:
    cleaned = text.strip()
    return (
        bool(cleaned)
        and any(is_japanese_letter(character) for character in cleaned)
        and japanese_letter_density(cleaned) >= 0.5
        and japanese_script_density(cleaned) >= 0.5
    )


class JapaneseVisionLineDensityContractTests(unittest.TestCase):
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
        cls.line = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalLineCrops(\n",
        )

    def test_punctuation_noise_does_not_commit_as_a_vision_line(self) -> None:
        self.assertEqual(japanese_script_density("。、"), 1.0)
        self.assertEqual(japanese_letter_density("。、"), 0.0)
        self.assertAlmostEqual(japanese_letter_density("日。、"), 1 / 3)
        self.assertFalse(commits_vision_line("。、"))
        self.assertFalse(commits_vision_line("日。、"))
        self.assertFalse(commits_vision_line("ーー"))

    def test_meaningful_japanese_line_text_remains_eligible(self) -> None:
        self.assertTrue(commits_vision_line("日本語。"))
        self.assertTrue(commits_vision_line("ニコッ"))
        self.assertTrue(commits_vision_line("AI日本語"))
        self.assertFalse(commits_vision_line("AI"))

    def test_shared_recovery_gate_requires_actual_letters_and_density(self) -> None:
        wrapper = function_body(
            self.vision,
            "private static func meaningfulJapaneseRecoveryObservations(\n",
        )
        self.assertIn(
            "isMeaningfulJapaneseRecoveryText(observation.text)",
            wrapper,
        )
        body = function_body(
            self.vision,
            "private static func isMeaningfulJapaneseRecoveryText(\n",
        )
        for marker in (
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(text)",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5",
            "japaneseScriptDensity(in: text) >= 0.5",
        ):
            self.assertIn(marker, body)

    def test_perspective_line_is_filtered_before_commit_or_axis_suppression(self) -> None:
        perspective = self.line.index("recognizeJapanesePerspectiveLineCrop(")
        gate = self.line.index("let meaningfulPerspective")
        commit = self.line.index(
            "refined.append(contentsOf: meaningfulPerspective)"
        )
        suppress = self.line.index(
            "needsJapaneseOrientationFallback(meaningfulPerspective)"
        )
        self.assertLess(perspective, gate)
        self.assertLess(gate, commit)
        self.assertLess(commit, suppress)
        self.assertIn(
            "meaningfulJapaneseRecoveryObservations(\n                    [perspective]",
            self.line,
        )
        self.assertNotIn("refined.append(perspective)", self.line)
        self.assertNotIn("needsJapaneseOrientationFallback([perspective])", self.line)

    def test_axis_primary_and_opposite_are_filtered_before_commit(self) -> None:
        axis_start = self.line.index("let primary = recognizeJapaneseCropPass(")
        axis = self.line[axis_start:]
        for marker in (
            "let meaningfulPrimary = meaningfulJapaneseRecoveryObservations(",
            "refined.append(contentsOf: meaningfulPrimary)",
            "needsJapaneseOrientationFallback(meaningfulPrimary)",
            "let opposite = recognizeJapaneseCropPass(",
            "contentsOf: meaningfulJapaneseRecoveryObservations(opposite)",
        ):
            self.assertIn(marker, axis)
        self.assertLess(
            axis.index("let meaningfulPrimary"),
            axis.index("refined.append(contentsOf: meaningfulPrimary)"),
        )
        self.assertLess(
            axis.index("needsJapaneseOrientationFallback(meaningfulPrimary)"),
            axis.index("let opposite = recognizeJapaneseCropPass("),
        )
        self.assertNotIn("refined.append(contentsOf: primary)", axis)
        self.assertNotIn("needsJapaneseOrientationFallback(primary)", axis)

    def test_rejected_line_keeps_existing_orientation_and_block_recovery(self) -> None:
        self.assertEqual(
            self.line.count("meaningfulJapaneseRecoveryObservations("),
            3,
        )
        self.assertIn("var orientationFallbacksRemaining = 12", self.line)
        page = function_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )
        for marker in (
            "let lineRefined = try await Self.recognizeJapaneseVerticalLineCrops(",
            "hasCompleteJapaneseLineCoverage(",
            "guard !hasLineOCRResult else { continue }",
            "var blockFallback = meaningfulPrimary",
        ):
            self.assertIn(marker, page)

    def test_page_ocr_and_request_budgets_are_not_expanded(self) -> None:
        page_selector = function_body(
            self.vision,
            "private static func selectOCRCandidate(\n",
        )
        self.assertNotIn("meaningfulJapaneseRecoveryObservations", page_selector)
        self.assertIn("maximumJapaneseMangaLineOCRRequests = 8", self.vision)
        self.assertIn("boundedJapaneseVisionLineCandidates(", self.line)
        self.assertIn(".prefix(24)", self.line)
        axis_start = self.line.index("let primary = recognizeJapaneseCropPass(")
        self.assertEqual(self.line[axis_start:].count("recognizeJapaneseCropPass("), 2)

    def test_translation_persistence_and_research_boundaries_stay_separate(self) -> None:
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)
        self.assertNotIn("groundTruth", self.vision)
        self.assertNotIn("KOHARU_DATA_ROOT", self.vision)
        self.assertNotIn("test/koharu_artifacts", self.vision)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.379", "3.379"],
        )
        combined = (
            self.workflow
            + self.flow
            + self.route
            + self.test_log
            + self.update_log
        )
        for marker in (
            "scripts/test-v3324-japanese-vision-line-density-contract.py",
            "v3.324",
            "japanese-benchmark-v3.324-",
        ):
            self.assertIn(marker, combined)

    def test_contract_has_no_process_entry(self) -> None:
        contract = read("scripts/test-v3324-japanese-vision-line-density-contract.py")
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)

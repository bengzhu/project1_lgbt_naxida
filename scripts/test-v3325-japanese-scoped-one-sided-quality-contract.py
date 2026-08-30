#!/usr/bin/env python3
"""Static and pure-policy contract for v3.325 one-sided scoped OCR gates."""

from pathlib import Path
import math
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
    letters = sum(is_japanese_letter(character) for character in text)
    if not letters:
        return 0.0
    visible = [
        character
        for character in text
        if not character.isspace() and not is_technical_word(character)
    ]
    if not visible:
        return 0.0
    support = sum(
        0x3099 <= ord(character) <= 0x309C or ord(character) == 0x30FC
        for character in visible
    )
    return (letters + support) / len(visible)


def japanese_script_density(text: str) -> float:
    if not text:
        return 0.0
    japanese = sum(
        any(
            lower <= ord(character) <= upper
            for lower, upper in (
                (0x3000, 0x303F),
                (0x3040, 0x30FF),
                (0x3400, 0x4DBF),
                (0x4E00, 0x9FFF),
                (0xF900, 0xFAFF),
                (0xFF61, 0xFF9F),
            )
        )
        for character in text
    )
    return japanese / len(text)


def is_usable_one_sided_candidate(text: str, confidence: float) -> bool:
    cleaned = text.strip()
    return (
        bool(cleaned)
        and math.isfinite(confidence)
        and confidence >= 0.55
        and any(is_japanese_letter(character) for character in cleaned)
        and japanese_letter_density(cleaned) >= 0.5
        and japanese_script_density(cleaned) >= 0.5
    )


class JapaneseScopedOneSidedQualityContractTests(unittest.TestCase):
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
        cls.selector = function_body(
            cls.vision,
            "private static func selectJapaneseScopedBlockCandidate(\n",
        )

    def test_low_confidence_or_nonfinite_one_sided_candidate_is_rejected(self) -> None:
        self.assertFalse(is_usable_one_sided_candidate("日本語", 0.5499))
        self.assertFalse(is_usable_one_sided_candidate("日本語", math.nan))
        self.assertFalse(is_usable_one_sided_candidate("日本語", math.inf))

    def test_low_script_density_one_sided_candidate_is_rejected(self) -> None:
        self.assertGreaterEqual(japanese_letter_density("日本abcde"), 0.5)
        self.assertLess(japanese_script_density("日本abcde"), 0.5)
        self.assertFalse(is_usable_one_sided_candidate("日本abcde", 0.99))
        self.assertFalse(is_usable_one_sided_candidate("。、", 0.99))

    def test_quality_candidate_remains_eligible(self) -> None:
        self.assertTrue(is_usable_one_sided_candidate("日本語", 0.55))
        self.assertTrue(is_usable_one_sided_candidate("AI日本語", 0.90))
        self.assertTrue(is_usable_one_sided_candidate("ニコッ", 0.80))

    def test_missing_manga_branch_requires_full_usable_gate(self) -> None:
        branch = self.selector[
            self.selector.index("guard let mangaCandidate else") :
            self.selector.index("guard let visionCandidate else")
        ]
        self.assertIn("guard let visionCandidate", branch)
        self.assertIn("isUsableJapaneseScopedBlockCandidate(visionCandidate)", branch)
        self.assertIn("return nil", branch)
        self.assertNotIn("isMeaningfulJapaneseScopedBlockCandidate", branch)

    def test_missing_vision_branch_requires_full_usable_gate(self) -> None:
        start = self.selector.index("guard let visionCandidate else")
        end = self.selector.index(
            "guard isUsableJapaneseScopedBlockCandidate(visionCandidate)",
            start,
        )
        branch = self.selector[start:end]
        self.assertIn("isUsableJapaneseScopedBlockCandidate(mangaCandidate)", branch)
        self.assertIn("? mangaCandidate", branch)
        self.assertIn(": nil", branch)
        self.assertNotIn("isMeaningfulJapaneseScopedBlockCandidate", branch)

    def test_two_candidate_comparison_and_page_fallback_remain_quality_gated(self) -> None:
        for marker in (
            "guard isUsableJapaneseScopedBlockCandidate(visionCandidate)",
            "guard isUsableJapaneseScopedBlockCandidate(mangaCandidate)",
            "isBetterJapaneseScopedBlockCandidate(",
            "? visionCandidate : mangaCandidate",
        ):
            self.assertIn(marker, self.selector)
        self.assertNotIn("isMeaningfulJapaneseScopedBlockCandidate", self.selector)
        page_selector = function_body(
            self.vision,
            "private static func selectOCRCandidate(\n",
        )
        self.assertIn("punctuation-only Japanese text is still valid input", page_selector)
        self.assertNotIn("isUsableJapaneseScopedBlockCandidate", page_selector)

    def test_shared_usable_gate_is_complete(self) -> None:
        gate = function_body(
            self.vision,
            "private static func isUsableJapaneseScopedText(\n",
        )
        for marker in (
            "postProcessJapaneseOCRText(sourceText)",
            "validOCRConfidence(confidence) != nil",
            "confidence >= 0.55",
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(text)",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5",
            "japaneseScriptDensity(in: text) >= 0.5",
        ):
            self.assertIn(marker, gate)
        block_gate = function_body(
            self.vision,
            "private static func isUsableJapaneseScopedBlockCandidate(\n",
        )
        self.assertIn("isUsableJapaneseScopedText(", block_gate)

    def test_request_cancel_translation_and_persistence_boundaries_are_unchanged(self) -> None:
        scoped = function_body(
            self.vision,
            "private static func recognizeTextBlockDetached(\n        image: CGImage,",
        )
        for marker in (
            "angles = [270, 90]",
            "angles = [0]",
            "angles = [270, 90, 0]",
            "try Task.checkCancellation()",
            "catch is CancellationError",
        ):
            self.assertIn(marker, scoped)
        self.assertNotIn("while ", scoped)
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)
        for forbidden in ("TranslationSessionStore", "translate(", "persist("):
            self.assertNotIn(forbidden, self.selector)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.363", "3.363"],
        )
        combined = (
            self.workflow
            + self.flow
            + self.route
            + self.test_log
            + self.update_log
        )
        for marker in (
            "scripts/test-v3325-japanese-scoped-one-sided-quality-contract.py",
            "v3.325",
            "japanese-benchmark-v3.325-",
        ):
            self.assertIn(marker, combined)

    def test_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3325-japanese-scoped-one-sided-quality-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)

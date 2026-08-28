#!/usr/bin/env python3
"""Static and pure-policy contract for v3.327 scoped Vision pool gates."""

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
    visible = [
        character
        for character in text
        if not character.isspace() and not is_technical_word(character)
    ]
    if not visible:
        return 0.0
    letters = sum(is_japanese_letter(character) for character in visible)
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


def is_usable(candidate: tuple[str, float]) -> bool:
    text, confidence = candidate
    cleaned = text.strip()
    return (
        bool(cleaned)
        and math.isfinite(confidence)
        and confidence >= 0.55
        and any(is_japanese_letter(character) for character in cleaned)
        and japanese_letter_density(cleaned) >= 0.5
        and japanese_script_density(cleaned) >= 0.5
    )


def japanese_candidate_score(candidate: tuple[str, float]) -> float:
    text, confidence = candidate
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
    punctuation = sum(
        0x3000 <= ord(character) <= 0x303F
        or 0xFF61 <= ord(character) <= 0xFF65
        for character in text
    )
    density = japanese / len(text) if text else 0.0
    punctuation_density = punctuation / len(text) if text else 0.0
    return min(max(confidence, 0.0), 1.0) * 0.82 + density * 0.14 + punctuation_density * 0.04


def select_scoped_top_candidate(
    candidates: list[tuple[str, float]],
) -> tuple[str, float] | None:
    usable = [candidate for candidate in candidates if is_usable(candidate)]
    if not usable:
        return None
    best_confidence = max(confidence for _, confidence in usable)
    window = [
        candidate
        for candidate in usable
        if candidate[1] >= best_confidence - 0.14
    ]
    return max(window, key=japanese_candidate_score)


def select_scoped_observation(
    observations: list[tuple[str, float, float]],
) -> tuple[str, float, float] | None:
    usable = [
        observation
        for observation in observations
        if is_usable((observation[0], observation[1]))
    ]
    return max(usable, key=lambda observation: observation[2]) if usable else None


class JapaneseScopedVisionPoolQualityContractTests(unittest.TestCase):
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
        cls.scoped = function_body(
            cls.vision,
            "private static func recognizeTextBlockDetached(\n        image: CGImage,",
        )
        cls.recognize = function_body(
            cls.vision,
            "private static func recognizeObservations(\n",
        )
        cls.pool_selector = function_body(
            cls.vision,
            "private static func selectJapaneseScopedVisionCandidate(\n",
        )
        cls.shared_gate = function_body(
            cls.vision,
            "private static func isUsableJapaneseScopedText(\n",
        )

    def test_weak_top_candidate_no_longer_masks_usable_alternative(self) -> None:
        selected = select_scoped_top_candidate(
            [("日本abcde", 0.99), ("日本語", 0.86)]
        )
        self.assertEqual(selected, ("日本語", 0.86))
        self.assertEqual(
            select_scoped_top_candidate([("。、", 0.99), ("ニコッ", 0.70)]),
            ("ニコッ", 0.70),
        )

    def test_no_usable_top_candidate_produces_no_vision_observation(self) -> None:
        self.assertIsNone(
            select_scoped_top_candidate(
                [("。、", 0.99), ("日本語", 0.54), ("日本abcde", 0.98)]
            )
        )
        self.assertIsNone(select_scoped_top_candidate([("日本語", math.nan)]))

    def test_usable_filter_precedes_existing_top_candidate_comparator(self) -> None:
        self.assertIn("if requiresUsableJapaneseScopedText", self.recognize)
        self.assertIn(
            "candidate = Self.selectJapaneseScopedVisionCandidate(",
            self.recognize,
        )
        self.assertIn("candidate = Self.selectOCRCandidate(", self.recognize)
        self.assertIn("let usableCandidates = candidates.filter", self.pool_selector)
        gate = self.pool_selector.index("isUsableJapaneseScopedText(")
        compare = self.pool_selector.index(
            "selectOCRCandidate(from: usableCandidates, japanese: true)"
        )
        self.assertLess(gate, compare)

    def test_weak_high_score_observation_no_longer_masks_usable_read(self) -> None:
        selected = select_scoped_observation(
            [("。、", 0.99, 1.40), ("日本abcde", 0.99, 1.30), ("今度こそ", 0.70, 0.90)]
        )
        self.assertEqual(selected, ("今度こそ", 0.70, 0.90))
        self.assertIsNone(select_scoped_observation([("。、", 0.99, 1.40)]))

    def test_scoped_pool_filters_before_best_reducer_and_preserves_manga_fallback(self) -> None:
        filter_index = self.scoped.index("let eligibleObservations = japanese")
        best_index = self.scoped.index("Self.bestObservation(", filter_index)
        self.assertLess(filter_index, best_index)
        self.assertIn("Self.isUsableJapaneseScopedText(", self.scoped[filter_index:best_index])
        self.assertIn("prefersJapanese: japanese", self.scoped[best_index:])
        self.assertIn("return japanese ? mangaCandidate : nil", self.scoped)

    def test_scoped_request_enables_pool_gate_without_expanding_angles(self) -> None:
        for marker in (
            "requiresUsableJapaneseScopedText: japanese",
            "angles = [270, 90]",
            "angles = [0]",
            "angles = [270, 90, 0]",
        ):
            self.assertIn(marker, self.scoped)
        self.assertEqual(self.scoped.count("recognizeObservations("), 1)

    def test_shared_gate_covers_confidence_letters_and_both_densities(self) -> None:
        for marker in (
            "validOCRConfidence(confidence) != nil",
            "confidence >= 0.55",
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(text)",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5",
            "japaneseScriptDensity(in: text) >= 0.5",
        ):
            self.assertIn(marker, self.shared_gate)
        block_gate = function_body(
            self.vision,
            "private static func isUsableJapaneseScopedBlockCandidate(\n",
        )
        self.assertIn("isUsableJapaneseScopedText(", block_gate)

    def test_page_punctuation_cancel_translation_and_persistence_stay_fixed(self) -> None:
        recognize_start = self.vision.index(
            "private static func recognizeObservations(\n"
        )
        signature_end = self.vision.index(
            ") throws -> [VisionOCRObservation]",
            recognize_start,
        )
        signature = self.vision[recognize_start:signature_end]
        self.assertIn("requiresUsableJapaneseScopedText: Bool = false", signature)
        page_selector = function_body(
            self.vision,
            "private static func selectOCRCandidate(\n",
        )
        self.assertIn("punctuation-only Japanese text is still valid input", page_selector)
        self.assertIn("try Task.checkCancellation()", self.scoped)
        self.assertIn("catch is CancellationError", self.scoped)
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.338", "3.338"],
        )
        combined = (
            self.workflow
            + self.flow
            + self.route
            + self.test_log
            + self.update_log
        )
        for marker in (
            "scripts/test-v3327-japanese-scoped-vision-pool-quality-contract.py",
            "v3.327",
            "japanese-benchmark-v3.327-",
        ):
            self.assertIn(marker, combined)

    def test_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3327-japanese-scoped-vision-pool-quality-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Static and pure-policy contract for v3.328 recovery Vision pool gates."""

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


def is_meaningful(text: str) -> bool:
    cleaned = text.strip()
    return (
        bool(cleaned)
        and any(is_japanese_letter(character) for character in cleaned)
        and japanese_letter_density(cleaned) >= 0.5
        and japanese_script_density(cleaned) >= 0.5
    )


def japanese_candidate_score(candidate: tuple[str, float]) -> float:
    text, confidence = candidate
    script_density = japanese_script_density(text)
    punctuation_density = sum(
        0x3000 <= ord(character) <= 0x303F
        or 0xFF61 <= ord(character) <= 0xFF65
        for character in text
    ) / len(text) if text else 0.0
    return min(max(confidence, 0.0), 1.0) * 0.82 + script_density * 0.14 + punctuation_density * 0.04


def select_recovery_candidate(
    candidates: list[tuple[str, float]],
) -> tuple[str, float] | None:
    meaningful = [candidate for candidate in candidates if is_meaningful(candidate[0])]
    if not meaningful:
        return None
    best_confidence = max(confidence for _, confidence in meaningful)
    confidence_window = [
        candidate
        for candidate in meaningful
        if candidate[1] >= best_confidence - 0.14
    ]
    return max(confidence_window, key=japanese_candidate_score)


class JapaneseRecoveryVisionPoolQualityContractTests(unittest.TestCase):
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
        cls.recognize = function_body(
            cls.vision,
            "private static func recognizeObservations(\n",
        )
        cls.pool_selector = function_body(
            cls.vision,
            "private static func selectJapaneseRecoveryVisionCandidate(\n",
        )
        cls.shared_gate = function_body(
            cls.vision,
            "private static func isMeaningfulJapaneseRecoveryText(\n",
        )
        cls.observation_gate = function_body(
            cls.vision,
            "private static func meaningfulJapaneseRecoveryObservations(\n",
        )
        cls.crop_pass = function_body(
            cls.vision,
            "private static func recognizeJapaneseCropPass(\n",
        )
        cls.perspective = function_body(
            cls.vision,
            "private static func recognizeJapanesePerspectiveLineCrop(\n",
        )

    def test_punctuation_top_candidate_no_longer_masks_recovery_text(self) -> None:
        self.assertEqual(
            select_recovery_candidate([("。、", 0.99), ("ニコッ", 0.42)]),
            ("ニコッ", 0.42),
        )

    def test_low_density_top_candidate_no_longer_masks_recovery_text(self) -> None:
        self.assertEqual(
            select_recovery_candidate([("日本abcde", 0.98), ("今度こそ", 0.41)]),
            ("今度こそ", 0.41),
        )
        self.assertIsNone(select_recovery_candidate([("。、", 0.99), ("日本abcde", 0.98)]))

    def test_meaningful_filter_precedes_existing_candidate_comparator(self) -> None:
        self.assertIn("let meaningfulCandidates = candidates.filter", self.pool_selector)
        gate = self.pool_selector.index("isMeaningfulJapaneseRecoveryText(")
        compare = self.pool_selector.index(
            "selectOCRCandidate(from: meaningfulCandidates, japanese: true)"
        )
        self.assertLess(gate, compare)

    def test_recovery_gate_keeps_confidence_policy_at_existing_callers(self) -> None:
        self.assertNotIn("confidence", self.shared_gate)
        self.assertIn("observation.confidence >= 0.40", self.vision)
        self.assertIn("observation.confidence >= 0.48", self.vision)
        self.assertIn("confidence >= 0.55", self.vision)
        self.assertIn("validOCRConfidence(result.confidence)", self.vision)

    def test_candidate_and_observation_filters_share_text_semantics(self) -> None:
        for marker in (
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(text)",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5",
            "japaneseScriptDensity(in: text) >= 0.5",
        ):
            self.assertIn(marker, self.shared_gate)
        self.assertIn("isMeaningfulJapaneseRecoveryText(observation.text)", self.observation_gate)

    def test_all_bounded_crop_passes_enable_recovery_pool_gate(self) -> None:
        self.assertIn(
            "requiresMeaningfulJapaneseRecoveryText: true",
            self.crop_pass,
        )
        self.assertEqual(self.vision.count("recognizeJapaneseCropPass("), 10)

    def test_perspective_line_pool_uses_same_recovery_gate(self) -> None:
        self.assertIn("recognizeObservations(", self.perspective)
        self.assertIn(
            "requiresMeaningfulJapaneseRecoveryText: true",
            self.perspective,
        )

    def test_page_and_scoped_selection_boundaries_stay_independent(self) -> None:
        recognize_start = self.vision.index("private static func recognizeObservations(\n")
        signature_end = self.vision.index(") throws -> [VisionOCRObservation]", recognize_start)
        signature = self.vision[recognize_start:signature_end]
        self.assertIn("requiresUsableJapaneseScopedText: Bool = false", signature)
        self.assertIn("requiresMeaningfulJapaneseRecoveryText: Bool = false", signature)
        page_selector = function_body(
            self.vision,
            "private static func selectOCRCandidate(\n",
        )
        self.assertIn("punctuation-only Japanese text is still valid input", page_selector)
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.363", "3.363"],
        )
        combined = self.workflow + self.flow + self.route + self.test_log + self.update_log
        for marker in (
            "scripts/test-v3328-japanese-recovery-vision-pool-quality-contract.py",
            "v3.328",
            "japanese-benchmark-v3.328-",
        ):
            self.assertIn(marker, combined)

    def test_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3328-japanese-recovery-vision-pool-quality-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Static and pure-policy contract for v3.329 Japanese duplicate fusion."""

from dataclasses import dataclass
import math
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


@dataclass(frozen=True)
class Observation:
    text: str
    confidence: float
    score: float
    role: str = "page"
    compact: bool = False


def should_prefer_meaningful_duplicate(
    candidate: Observation,
    incumbent: Observation,
) -> bool:
    return (
        candidate.role != "detectorTextRegion"
        and incumbent.role != "detectorTextRegion"
        and not candidate.compact
        and not incumbent.compact
        and is_meaningful(candidate.text)
        and not is_meaningful(incumbent.text)
        and math.isfinite(candidate.confidence)
        and candidate.confidence >= 0.40
        and candidate.confidence
        >= (incumbent.confidence if math.isfinite(incumbent.confidence) else 0) - 0.14
    )


def fuse_duplicate(observations: list[Observation]) -> Observation:
    ordered = sorted(observations, key=lambda item: item.score, reverse=True)
    incumbent = ordered[0]
    for candidate in ordered[1:]:
        if should_prefer_meaningful_duplicate(candidate, incumbent):
            incumbent = candidate
        elif candidate.score > incumbent.score:
            incumbent = candidate
    return incumbent


class JapaneseDuplicateFusionQualityContractTests(unittest.TestCase):
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
        cls.dedupe = function_body(
            cls.vision,
            "private static func deduplicateObservations(\n",
        )
        cls.preference = function_body(
            cls.vision,
            "private static func shouldPreferMeaningfulJapaneseDuplicate(\n",
        )

    def test_long_low_density_score_no_longer_masks_close_japanese_read(self) -> None:
        noisy = Observation("日本abcde", 0.98, 15.60)
        japanese = Observation("今度こそ", 0.86, 12.78)
        self.assertGreater(noisy.score, japanese.score)
        self.assertEqual(fuse_duplicate([noisy, japanese]), japanese)

    def test_far_lower_confidence_read_cannot_replace_strong_punctuation(self) -> None:
        punctuation = Observation("。、", 0.99, 11.52)
        weak = Observation("今度こそ", 0.70, 11.50)
        self.assertEqual(fuse_duplicate([punctuation, weak]), punctuation)
        self.assertFalse(
            should_prefer_meaningful_duplicate(
                Observation("今度こそ", math.nan, 20.0),
                punctuation,
            )
        )

    def test_punctuation_survives_when_no_qualified_duplicate_exists(self) -> None:
        punctuation = Observation("。、", 0.99, 11.52)
        latin_noise = Observation("abcde", 0.98, 12.19)
        self.assertEqual(fuse_duplicate([punctuation]), punctuation)
        self.assertFalse(should_prefer_meaningful_duplicate(latin_noise, punctuation))

    def test_preference_is_bounded_by_shared_text_gate_and_confidence_window(self) -> None:
        for marker in (
            "isMeaningfulJapaneseRecoveryText(candidate.text)",
            "!isMeaningfulJapaneseRecoveryText(incumbent.text)",
            "validOCRConfidence(candidate.confidence) != nil",
            "candidate.confidence >= 0.40",
            "candidate.confidence >= incumbentConfidence - 0.14",
        ):
            self.assertIn(marker, self.preference)

    def test_detector_and_compact_replacement_policies_remain_authoritative(self) -> None:
        for marker in (
            "candidate.observationRole != .detectorTextRegion",
            "incumbent.observationRole != .detectorTextRegion",
            "!candidate.isCompactJapaneseRecovery",
            "!incumbent.isCompactJapaneseRecovery",
        ):
            self.assertIn(marker, self.preference)
        detector = Observation("。、", 0.90, 20.0, role="detectorTextRegion")
        compact = Observation("。、", 0.90, 20.0, compact=True)
        candidate = Observation("ニコッ", 0.86, 10.0)
        self.assertFalse(should_prefer_meaningful_duplicate(candidate, detector))
        self.assertFalse(should_prefer_meaningful_duplicate(candidate, compact))

    def test_japanese_override_runs_only_after_duplicate_and_before_generic_score(self) -> None:
        duplicate = self.dedupe.index("guard let duplicateIndex")
        override = self.dedupe.index("if prefersJapanese,")
        generic = self.dedupe.index("} else if isBetterObservation(", override)
        self.assertLess(duplicate, override)
        self.assertLess(override, generic)
        self.assertIn("deduplicateObservations(observations, prefersJapanese: true)", self.vision)
        self.assertIn(": Self.deduplicateObservations(observations)", self.vision)

    def test_owner_and_detector_boundary_inheritance_are_unchanged(self) -> None:
        for marker in (
            "let inheritedOwner = observation.verticalTextRegionOwner",
            "winner.verticalTextRegionOwner = inheritedOwner",
            "let preservesDetectorTextRegionBoundary =",
            "output[duplicateIndex].preservesDetectorTextRegionBoundary =",
        ):
            self.assertIn(marker, self.dedupe)

    def test_page_recovery_translation_and_persistence_boundaries_stay_fixed(self) -> None:
        selector = function_body(
            self.vision,
            "private static func selectOCRCandidate(\n",
        )
        self.assertIn("punctuation-only Japanese text is still valid input", selector)
        self.assertIn("$0.confidence >= bestConfidence - 0.14", selector)
        self.assertIn("requiresMeaningfulJapaneseRecoveryText: Bool = false", self.vision)
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("translateJapaneseImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.355", "3.355"],
        )
        combined = self.workflow + self.flow + self.route + self.test_log + self.update_log
        for marker in (
            "scripts/test-v3329-japanese-duplicate-fusion-quality-contract.py",
            "v3.329",
            "japanese-benchmark-v3.329-",
        ):
            self.assertIn(marker, combined)

    def test_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3329-japanese-duplicate-fusion-quality-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)

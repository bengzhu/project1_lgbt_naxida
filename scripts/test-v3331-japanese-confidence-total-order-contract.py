#!/usr/bin/env python3
"""Static and pure-policy contract for v3.331 Japanese confidence ordering."""

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


@dataclass(frozen=True)
class Alternative:
    text: str
    confidence: float
    score: float


@dataclass(frozen=True)
class Observation:
    text: str
    confidence: float
    score: float


def old_select_alternative(
    alternatives: list[Alternative],
) -> Alternative | None:
    if not alternatives:
        return None
    best_confidence = max(item.confidence for item in alternatives)
    window = [
        item
        for item in alternatives
        if item.confidence >= best_confidence - 0.14
    ]
    return max(window, key=lambda item: item.score) if window else None


def is_valid_confidence(confidence: float) -> bool:
    return math.isfinite(confidence) and 0.0 <= confidence <= 1.0


def select_valid_alternative(
    alternatives: list[Alternative],
) -> Alternative | None:
    valid = [item for item in alternatives if is_valid_confidence(item.confidence)]
    if not valid:
        return None
    best_confidence = max(item.confidence for item in valid)
    window = [
        item
        for item in valid
        if item.confidence >= best_confidence - 0.14
    ]
    return max(window, key=lambda item: item.score) if window else None


def is_better_observation(lhs: Observation, rhs: Observation) -> bool:
    lhs_valid = is_valid_confidence(lhs.confidence)
    rhs_valid = is_valid_confidence(rhs.confidence)
    if lhs_valid != rhs_valid:
        return lhs_valid
    if lhs.score != rhs.score:
        return lhs.score > rhs.score
    return lhs.text < rhs.text


def best_observation(observations: list[Observation]) -> Observation | None:
    if not observations:
        return None
    best = observations[0]
    for candidate in observations[1:]:
        if is_better_observation(candidate, best):
            best = candidate
    return best


def needs_orientation_fallback(observations: list[Observation]) -> bool:
    best = best_observation(observations)
    return best is None or not is_valid_confidence(best.confidence) or best.confidence < 0.48


def weak_recovery_priority(confidence: float) -> float:
    return confidence if is_valid_confidence(confidence) else -math.inf


class JapaneseConfidenceTotalOrderContractTests(unittest.TestCase):
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
            "private static func selectOCRCandidate(\n",
        )
        cls.comparator = function_body(
            cls.vision,
            "private static func isBetterObservation(\n        _ lhs: VisionOCRObservation,\n        _ rhs: VisionOCRObservation,",
        )
        cls.score = function_body(
            cls.vision,
            "private static func observationScore(\n",
        )
        cls.orientation = function_body(
            cls.vision,
            "private static func needsJapaneseOrientationFallback(\n",
        )
        cls.weak_recovery = function_body(
            cls.vision,
            "private static func recoverWeakJapaneseBlocks(\n",
        )

    def test_nonfinite_alternative_cannot_poison_japanese_confidence_window(self) -> None:
        finite = Alternative("今度こそ", 0.91, 10.0)
        nan = Alternative("長いノイズ", math.nan, 99.0)
        infinity = Alternative("無限ノイズ", math.inf, 100.0)
        self.assertIsNone(old_select_alternative([nan, finite]))
        self.assertEqual(old_select_alternative([infinity, finite]), infinity)
        self.assertEqual(select_valid_alternative([nan, finite]), finite)
        self.assertEqual(select_valid_alternative([infinity, finite]), finite)
        self.assertIsNone(select_valid_alternative([nan, infinity]))

    def test_finite_page_window_and_punctuation_fallback_stay_bounded(self) -> None:
        punctuation = Alternative("。、", 0.92, 0.90)
        nearby = Alternative("今度こそ", 0.82, 0.95)
        distant = Alternative("遠い候補", 0.70, 1.00)
        self.assertEqual(
            select_valid_alternative([punctuation, nearby, distant]),
            nearby,
        )
        self.assertEqual(select_valid_alternative([punctuation]), punctuation)

    def test_finite_observation_always_beats_nonfinite_in_any_order(self) -> None:
        finite = Observation("今度こそ", 0.70, 10.0)
        nan = Observation("長い長い長いノイズ", math.nan, 100.0)
        infinity = Observation("もっと長いノイズ", math.inf, 200.0)
        for pool in ([nan, finite], [finite, nan], [infinity, finite], [finite, infinity]):
            self.assertEqual(best_observation(list(pool)), finite)

    def test_nonfinite_only_observation_still_requests_orientation_fallback(self) -> None:
        nan = Observation("今度こそ", math.nan, 10.0)
        infinity = Observation("日本語", math.inf, 20.0)
        finite = Observation("今度こそ", 0.70, 8.0)
        self.assertTrue(needs_orientation_fallback([nan]))
        self.assertTrue(needs_orientation_fallback([infinity]))
        self.assertFalse(needs_orientation_fallback([nan, finite]))

    def test_nonfinite_weak_blocks_receive_the_existing_budget_first(self) -> None:
        confidences = [0.50, math.nan, 0.42, math.inf, 0.45, 0.47]
        prioritized = sorted(confidences, key=weak_recovery_priority)[:4]
        self.assertTrue(math.isnan(prioritized[0]))
        self.assertTrue(math.isinf(prioritized[1]))
        self.assertEqual(prioritized[2:], [0.42, 0.45])

    def test_product_candidate_pool_filters_nonfinite_before_window(self) -> None:
        valid = self.selector.index("let validCandidates = candidates.filter")
        best = self.selector.index("validCandidates.map(\\.confidence).max()")
        window = self.selector.index("let confidenceWindow = validCandidates.filter")
        self.assertLess(valid, best)
        self.assertLess(best, window)
        self.assertIn("validOCRConfidence($0.confidence) != nil", self.selector[valid:best])
        self.assertIn("$0.confidence >= bestConfidence - 0.14", self.selector)
        self.assertIn("guard japanese else { return candidates.first }", self.selector)

    def test_observation_comparator_has_finite_first_total_order(self) -> None:
        valid = self.comparator.index("let lhsHasValidConfidence")
        score = self.comparator.index("let lhsScore = observationScore(")
        self.assertLess(valid, score)
        self.assertIn("let rhsHasValidConfidence", self.comparator)
        self.assertIn("return lhsHasValidConfidence", self.comparator)
        self.assertIn("validOCRConfidence(observation.confidence)", self.score)
        self.assertIn("?? 0", self.score)
        self.assertIn("+ confidence * 8", self.score)

    def test_orientation_thresholds_and_request_budgets_are_unchanged(self) -> None:
        self.assertIn("validOCRConfidence(best.confidence) == nil", self.orientation)
        self.assertIn("best.confidence < 0.48", self.orientation)
        for marker in (
            "var orientationFallbacksRemaining = 12",
            "var orientationFallbacksRemaining = 8",
            "var orientationFallbacksRemaining = 4",
            "private static let maximumJapaneseWeakBlockRecoveryRequests = 4",
        ):
            self.assertIn(marker, self.vision)
        for marker in (
            "let lhsConfidence = validOCRConfidence(lhs.element.confidence)",
            "let rhsConfidence = validOCRConfidence(rhs.element.confidence)",
            "?? -.infinity",
            "return lhsConfidence < rhsConfidence",
            "return lhs.offset < rhs.offset",
        ):
            self.assertIn(marker, self.weak_recovery)

    def test_fusion_translation_cancel_and_persistence_boundaries_stay_fixed(self) -> None:
        for marker in (
            "deduplicateJapaneseObservations(",
            "ImageOCRLayoutEngine.layout",
            "CancellationError",
        ):
            self.assertIn(marker, self.vision)
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("translateJapaneseImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.341", "3.341"],
        )
        combined = self.workflow + self.flow + self.route + self.test_log + self.update_log
        for marker in (
            "scripts/test-v3331-japanese-confidence-total-order-contract.py",
            "v3.331",
            "japanese-benchmark-v3.333-",
        ):
            self.assertIn(marker, combined)
        contract = read(
            "scripts/test-v3331-japanese-confidence-total-order-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)

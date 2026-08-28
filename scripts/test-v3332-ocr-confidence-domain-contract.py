#!/usr/bin/env python3
"""Static and pure-policy contract for v3.332 OCR confidence domain."""

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


def valid_confidence(confidence: float) -> float | None:
    if not math.isfinite(confidence) or not 0.0 <= confidence <= 1.0:
        return None
    return confidence


def normalized_confidence(confidence: float) -> float:
    return valid_confidence(confidence) or 0.0


@dataclass(frozen=True)
class Alternative:
    text: str
    confidence: float
    score: float


def select_alternative(alternatives: list[Alternative]) -> Alternative | None:
    valid = [
        alternative
        for alternative in alternatives
        if valid_confidence(alternative.confidence) is not None
    ]
    if not valid:
        return None
    best_confidence = max(item.confidence for item in valid)
    window = [
        item
        for item in valid
        if item.confidence >= best_confidence - 0.14
    ]
    return max(window, key=lambda item: item.score) if window else None


def weak_recovery_priority(confidence: float) -> float:
    return valid_confidence(confidence) \
        if valid_confidence(confidence) is not None \
        else -math.inf


class OCRConfidenceDomainContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.manga = read("AITRANS/Services/MangaOCRService.swift")
        cls.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        cls.summary = read("AITRANS/Models/ImageOCRResultSummary.swift")
        cls.summary_v300_evaluator = read("scripts/test-v300-image-ocr-rerun-evaluator.swift")
        cls.summary_v310_evaluator = read("scripts/test-v310-image-ocr-review-filter-evaluator.swift")
        cls.summary_v364_evaluator = read("scripts/test-v364-image-confidence-safety-evaluator.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.docs = (
            read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
            + read("update_log.md")
        )
        cls.validator = function_body(
            cls.vision,
            "private static func validOCRConfidence(_ confidence: Float)",
        )
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
        cls.recovery = function_body(
            cls.vision,
            "private static func recoverWeakJapaneseBlocks(\n",
        )
        cls.recognized_block = function_body(
            cls.vision,
            "private static func recognizedBlock(\n",
        )
        cls.manga_rank = function_body(
            cls.manga,
            "private static func validConfidenceRank(_ confidence: Float)",
        )
        cls.layout_normalizer = function_body(
            cls.layout,
            "private static func normalizedConfidence(_ rawConfidence: Float)",
        )
        cls.summary_normalizer = function_body(
            cls.summary,
            "static func normalizedConfidence(_ rawConfidence: Float)",
        )

    def test_probability_domain_accepts_only_closed_unit_interval(self) -> None:
        for confidence in (0.0, 0.42, 1.0):
            self.assertEqual(valid_confidence(confidence), confidence)
        for confidence in (-0.001, 1.001, math.nan, math.inf, -math.inf):
            self.assertIsNone(valid_confidence(confidence))

    def test_out_of_domain_alternative_cannot_own_existing_window(self) -> None:
        valid = Alternative("今度こそ", 0.91, 10.0)
        negative = Alternative("負値ノイズ", -0.2, 100.0)
        oversized = Alternative("過大ノイズ", 1.4, 200.0)
        self.assertEqual(select_alternative([oversized, valid, negative]), valid)
        self.assertIsNone(select_alternative([negative, oversized]))

    def test_valid_window_scores_and_thresholds_are_unchanged(self) -> None:
        punctuation = Alternative("。、", 0.92, 0.90)
        nearby = Alternative("今度こそ", 0.82, 0.95)
        distant = Alternative("遠い候補", 0.70, 1.00)
        self.assertEqual(select_alternative([punctuation, nearby, distant]), nearby)
        self.assertEqual(select_alternative([punctuation]), punctuation)

    def test_invalid_values_fail_closed_in_review_and_recovery_priority(self) -> None:
        for confidence in (-0.2, 1.2, math.nan, math.inf):
            self.assertEqual(normalized_confidence(confidence), 0.0)
            self.assertEqual(weak_recovery_priority(confidence), -math.inf)
        self.assertEqual(weak_recovery_priority(0.42), 0.42)

    def test_shared_product_validator_defines_closed_unit_interval(self) -> None:
        self.assertIn("confidence.isFinite", self.validator)
        self.assertIn("(0...1).contains(confidence)", self.validator)
        self.assertIn("return nil", self.validator)
        self.assertIn("return confidence", self.validator)
        self.assertEqual(self.vision.count("confidence.isFinite"), 1)

    def test_candidate_comparison_score_and_fallback_use_valid_domain(self) -> None:
        valid = self.selector.index("let validCandidates = candidates.filter")
        best = self.selector.index("validCandidates.map(\\.confidence).max()")
        window = self.selector.index("let confidenceWindow = validCandidates.filter")
        self.assertLess(valid, best)
        self.assertLess(best, window)
        self.assertIn("validOCRConfidence($0.confidence) != nil", self.selector)
        self.assertIn("$0.confidence >= bestConfidence - 0.14", self.selector)
        self.assertIn("guard japanese else { return candidates.first }", self.selector)
        self.assertIn("let lhsHasValidConfidence", self.comparator)
        self.assertIn("let rhsHasValidConfidence", self.comparator)
        self.assertIn("return lhsHasValidConfidence", self.comparator)
        self.assertIn("validOCRConfidence(observation.confidence)", self.score)
        self.assertIn("validOCRConfidence(best.confidence) == nil", self.orientation)

    def test_quality_gates_reject_finite_out_of_domain_values(self) -> None:
        signatures = (
            "private static func isUsableJapaneseScopedText(\n",
            "private static func isReliableJapaneseMangaOCRResult(\n",
            "private static func isReliableJapaneseLineCoverageResult(\n",
            "private static func japaneseLinePathRegion(\n",
            "private static func isUsableCompactJapaneseRecovery(\n",
            "private static func shouldPreferMeaningfulJapaneseDuplicate(\n",
        )
        for signature in signatures:
            body = function_body(self.vision, signature)
            self.assertIn("validOCRConfidence(", body, signature)
        self.assertIn(
            "let confidence = Self.validOCRConfidence(result.confidence)",
            self.vision,
        )

    def test_block_layout_summary_and_manga_rank_fail_closed(self) -> None:
        self.assertIn("validOCRConfidence(confidence)", self.recognized_block)
        self.assertIn("validOCRConfidence(block.confidence)", self.recognized_block)
        for body in (self.layout_normalizer, self.summary_normalizer):
            self.assertIn("rawConfidence.isFinite", body)
            self.assertIn("(0...1).contains(rawConfidence)", body)
            self.assertIn("return 0", body)
            self.assertIn("return rawConfidence", body)
            self.assertNotIn("min(max(rawConfidence", body)
        self.assertIn("confidence.isFinite", self.manga_rank)
        self.assertIn("(0...1).contains(confidence)", self.manga_rank)
        self.assertIn("return -.infinity", self.manga_rank)
        self.assertIn("summary.lowConfidenceBlockCount == 3", self.summary_v300_evaluator)
        self.assertIn("ImageOCRResultSummary.hasLowConfidence(overRange)", self.summary_v310_evaluator)
        self.assertIn("summary.averageConfidence == 0", self.summary_v364_evaluator)
        self.assertIn("summary.lowConfidenceBlockCount == 5", self.summary_v364_evaluator)

    def test_request_translation_cancel_and_persistence_boundaries_stay_fixed(self) -> None:
        for marker in (
            "var orientationFallbacksRemaining = 12",
            "var orientationFallbacksRemaining = 8",
            "var orientationFallbacksRemaining = 4",
            "private static let maximumJapaneseWeakBlockRecoveryRequests = 4",
            "CancellationError",
            "ImageOCRLayoutEngine.layout",
        ):
            self.assertIn(marker, self.vision)
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("translateJapaneseImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.338", "3.338"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3332-ocr-confidence-domain-contract.py",
            "v3.332",
            "japanese-benchmark-v3.333-",
        ):
            self.assertIn(marker, combined)
        contract = read("scripts/test-v3332-ocr-confidence-domain-contract.py")
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)

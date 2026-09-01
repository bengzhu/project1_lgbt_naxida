#!/usr/bin/env python3
"""Static and pure-policy contract for v3.334 layout confidence ordering."""

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


def valid_confidence(confidence: float) -> bool:
    return math.isfinite(confidence) and 0.0 <= confidence <= 1.0


def confidence_order_key(confidence: float) -> float:
    return confidence if valid_confidence(confidence) else -math.inf


@dataclass(frozen=True)
class TieCandidate:
    confidence: float


class LayoutConfidenceTotalOrderContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
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
        cls.layout_entry = function_body(
            cls.layout,
            "static func layout(\n",
        )
        cls.normalizer = function_body(
            cls.layout,
            "private static func normalizedConfidence(_ rawConfidence: Float)",
        )
        cls.order_key = function_body(
            cls.layout,
            "fileprivate static func confidenceOrderingKey(_ rawConfidence: Float)",
        )
        cls.observation_fallback = function_body(
            cls.layout,
            "private static func fallbackMangaObservationReadingOrder(\n",
        )
        cls.stable_key = function_body(
            cls.layout,
            "private static func stableKey(",
        )
        cls.block_fallback = function_body(
            cls.layout,
            "private static func fallbackMangaBlockReadingOrder(\n",
        )
        cls.cluster_block = function_body(
            cls.layout,
            "var block: ImageOCRLayoutBlock",
        )

    def test_closed_domain_and_total_order_key_are_pure(self) -> None:
        for confidence in (0.0, 0.42, 1.0):
            self.assertTrue(valid_confidence(confidence))
            self.assertEqual(confidence_order_key(confidence), confidence)
        for confidence in (-0.001, 1.001, math.nan, math.inf, -math.inf):
            self.assertFalse(valid_confidence(confidence))
            self.assertEqual(confidence_order_key(confidence), -math.inf)

    def test_valid_zero_beats_invalid_without_changing_valid_relative_order(self) -> None:
        invalid = [TieCandidate(math.nan), TieCandidate(1.4), TieCandidate(-0.2)]
        valid = [TieCandidate(0.0), TieCandidate(0.25), TieCandidate(0.9)]
        self.assertGreater(
            confidence_order_key(valid[0].confidence),
            confidence_order_key(invalid[0].confidence),
        )
        self.assertLess(
            confidence_order_key(valid[0].confidence),
            confidence_order_key(valid[1].confidence),
        )
        self.assertLess(
            confidence_order_key(valid[1].confidence),
            confidence_order_key(valid[2].confidence),
        )

    def test_layout_normalizes_before_direction_and_reading_order(self) -> None:
        normalize = self.layout_entry.index("safeObservation.confidence = normalizedConfidence(")
        resolve = self.layout_entry.index("let resolved = safeObservations.map")
        self.assertLess(normalize, resolve)
        self.assertIn("guard rawConfidence.isFinite", self.normalizer)
        self.assertIn("(0...1).contains(rawConfidence)", self.normalizer)
        self.assertIn("return 0", self.normalizer)

    def test_ordering_key_rejects_nonfinite_and_out_of_range_values(self) -> None:
        self.assertIn("rawConfidence.isFinite", self.order_key)
        self.assertIn("(0...1).contains(rawConfidence)", self.order_key)
        self.assertIn("return -.infinity", self.order_key)
        self.assertIn("return rawConfidence", self.order_key)

    def test_observation_fallback_never_compares_raw_confidence(self) -> None:
        self.assertIn("let lhsConfidence = confidenceOrderingKey(", self.observation_fallback)
        self.assertIn("let rhsConfidence = confidenceOrderingKey(", self.observation_fallback)
        self.assertIn("return lhsConfidence > rhsConfidence", self.observation_fallback)
        self.assertNotIn("return lhs.observation.confidence > rhs.observation.confidence", self.observation_fallback)

    def test_stable_key_carries_the_safe_confidence_key(self) -> None:
        self.assertIn("confidence: confidenceOrderingKey(value.observation.confidence)", self.stable_key)
        self.assertIn("return lhs.confidence < rhs.confidence", self.layout)

    def test_block_and_vertical_synthesis_use_the_same_key(self) -> None:
        self.assertIn("let lhsConfidence = confidenceOrderingKey(lhs.confidence)", self.block_fallback)
        self.assertIn("let rhsConfidence = confidenceOrderingKey(rhs.confidence)", self.block_fallback)
        self.assertIn("return lhsConfidence > rhsConfidence", self.block_fallback)
        self.assertIn("ImageOCRLayoutEngine.confidenceOrderingKey(", self.cluster_block)
        self.assertNotIn("return $0.observation.confidence > $1.observation.confidence", self.cluster_block)

    def test_existing_ocr_translation_budget_and_persistence_boundaries_stay_fixed(self) -> None:
        for marker in (
            "var orientationFallbacksRemaining = 12",
            "var orientationFallbacksRemaining = 8",
            "var orientationFallbacksRemaining = 4",
            "private static let maximumJapaneseWeakBlockRecoveryRequests = 4",
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
            ["3.388", "3.388"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3334-layout-confidence-total-order-contract.py",
            "v3.334",
            "japanese-benchmark-v3.334-",
        ):
            self.assertIn(marker, combined)
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, read("scripts/test-v3334-layout-confidence-total-order-contract.py"))


if __name__ == "__main__":
    unittest.main(verbosity=2)

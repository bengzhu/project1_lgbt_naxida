#!/usr/bin/env python3
"""Static and pure-policy contract for v3.333 detector confidence domain."""

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


def valid_detector_confidence(confidence: float) -> float | None:
    if not math.isfinite(confidence) or not 0.0 <= confidence <= 1.0:
        return None
    return confidence


@dataclass(frozen=True)
class Region:
    confidence: float
    y: float
    x: float
    height: float
    width: float


def region_key(region: Region) -> tuple[float, float, float, float, float]:
    confidence = valid_detector_confidence(region.confidence)
    rank = confidence if confidence is not None else -math.inf
    return (-rank, region.y, -region.x, -region.height, region.width)


class DetectorConfidenceDomainContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.detector = read("AITRANS/Services/ComicTextBubbleDetectorService.swift")
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.detector_runtime = cls.detector[
            cls.detector.index("private struct ComicTextBubbleDetectorRuntime") :
        ]
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.docs = (
            read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
            + read("update_log.md")
        )
        cls.detect_predictions = function_body(
            cls.detector,
            "private func detectPredictions(in image: CGImage)",
        )
        cls.detector_validator = function_body(
            cls.detector,
            "private static func validDetectorConfidence(_ confidence: Float)",
        )
        cls.detector_rank = function_body(
            cls.detector,
            "private static func detectorConfidenceRank(_ confidence: Float)",
        )
        cls.detector_regions = function_body(
            cls.detector_runtime,
            "func detectTextRegions(in image: CGImage)",
        )
        cls.manga_regions = function_body(
            cls.vision,
            "private static func japaneseMangaOCRRegions(\n",
        )
        cls.long_page = function_body(
            cls.vision,
            "private static func japaneseLongPageMangaOCRRegions(\n",
        )
        cls.balance = function_body(
            cls.vision,
            "private static func verticallyBalancedJapaneseMangaOCRRegions(\n",
        )
        cls.comparator = function_body(
            cls.vision,
            "private static func isBetterJapaneseMangaOCRRegion(\n",
        )

    def test_closed_probability_domain_rejects_every_invalid_class(self) -> None:
        for confidence in (0.0, 0.30, 0.55, 1.0):
            self.assertEqual(valid_detector_confidence(confidence), confidence)
        for confidence in (-0.001, 1.001, math.nan, math.inf, -math.inf):
            self.assertIsNone(valid_detector_confidence(confidence))

    def test_invalid_scores_cannot_starve_a_bounded_query_selection(self) -> None:
        scores = [math.nan, math.inf, -0.1, 1.2, 0.91, 0.73]
        selected = sorted(
            score
            for score in scores
            if valid_detector_confidence(score) is not None
        )[-2:]
        self.assertEqual(selected, [0.73, 0.91])

    def test_valid_regions_rank_before_invalid_then_keep_geometry_order(self) -> None:
        valid = Region(0.62, 0.8, 0.2, 0.4, 0.1)
        nan = Region(math.nan, 0.0, 0.9, 0.8, 0.2)
        oversized = Region(1.4, 0.1, 0.7, 0.7, 0.3)
        ordered = sorted([nan, valid, oversized], key=region_key)
        self.assertIs(ordered[0], valid)
        self.assertEqual(ordered[1:], [nan, oversized])

    def test_detector_filters_nonfinite_logits_before_top_query_budget(self) -> None:
        finite = self.detect_predictions.index("guard logit.isFinite else { continue }")
        validate = self.detect_predictions.index("Self.validDetectorConfidence(")
        append = self.detect_predictions.index("scored.append(")
        sort = self.detect_predictions.index("scored.sort")
        prefix = self.detect_predictions.index("scored.prefix(Self.queryCount)")
        self.assertLess(finite, validate)
        self.assertLess(validate, append)
        self.assertLess(append, sort)
        self.assertLess(sort, prefix)

    def test_detector_validator_and_final_boundary_are_fail_closed(self) -> None:
        self.assertIn("confidence.isFinite", self.detector_validator)
        self.assertIn("(0...1).contains(confidence)", self.detector_validator)
        self.assertIn("return nil", self.detector_validator)
        self.assertIn("validDetectorConfidence(confidence) ?? -.infinity", self.detector_rank)
        self.assertIn(
            ".compactMap { prediction -> ComicTextDetectorRegion? in",
            self.detector_regions,
        )
        self.assertIn(
            "Self.validDetectorConfidence(\n                    prediction.confidence",
            self.detector_regions,
        )
        self.assertIn("Self.detectorConfidenceRank($0.confidence)", self.detector_regions)
        self.assertIn("Self.detectorConfidenceRank($1.confidence)", self.detector_regions)

    def test_vision_revalidates_detector_regions_before_request_budget(self) -> None:
        compact = self.manga_regions.index(
            "detectorRegions.compactMap {\n"
            "            detectorRegion -> JapanesePixelFirstRegion? in"
        )
        validate = self.manga_regions.index("validOCRConfidence(")
        combine = self.manga_regions.index("return primary + supplemental")
        self.assertLess(compact, validate)
        self.assertLess(validate, combine)
        self.assertIn("detectorConfidence: detectorConfidence", self.manga_regions)
        self.assertNotIn("detectorConfidence: detectorRegion.confidence", self.manga_regions)

    def test_long_page_overflow_comparator_is_a_validity_first_total_order(self) -> None:
        self.assertIn("validOCRConfidence(lhs.detectorConfidence)", self.comparator)
        self.assertIn("validOCRConfidence(rhs.detectorConfidence)", self.comparator)
        valid_first = self.comparator.index("lhsDetectorConfidence != nil")
        confidence = self.comparator.index("lhsDetectorConfidence > rhsDetectorConfidence")
        geometry = self.comparator.index("lhs.rect.y < rhs.rect.y")
        self.assertLess(valid_first, confidence)
        self.assertLess(confidence, geometry)
        self.assertIn("overflow.sort(by: isBetterJapaneseMangaOCRRegion)", self.balance)

    def test_request_budgets_and_primary_precedence_are_unchanged(self) -> None:
        for marker in (
            "let requestsPerSlice = 12",
            "let maximumRequests = 48",
            "let remaining = requestLimit - selected.count",
            "case .comicTextBubble",
            "validOCRConfidence($0.detectorConfidence) != nil",
            "case .vision",
        ):
            self.assertIn(marker, self.long_page)
        self.assertLess(
            self.long_page.index("let primary = regions.filter"),
            self.long_page.index("let supplemental = regions.filter"),
        )

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.346", "3.346"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3333-detector-confidence-domain-contract.py",
            "v3.333",
            "japanese-benchmark-v3.333-",
        ):
            self.assertIn(marker, combined)
        contract = read("scripts/test-v3333-detector-confidence-domain-contract.py")
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)

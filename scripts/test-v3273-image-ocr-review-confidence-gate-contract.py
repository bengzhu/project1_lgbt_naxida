#!/usr/bin/env python3
"""Static contract for v3.273's OCR review confidence gate."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class ImageOCRReviewConfidenceGateContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.summary = read("AITRANS/Models/ImageOCRResultSummary.swift")
        cls.review_filter = read("AITRANS/Models/ImageOCRReviewFilter.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.view = read("AITRANS/Views/ImageTranslationViews.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.legacy_contract = read("scripts/test-v300-image-ocr-rerun-contract.py")
        cls.legacy_evaluator = read("scripts/test-v300-image-ocr-rerun-evaluator.swift")

    def test_review_default_matches_manga_ocr_quality_gate(self) -> None:
        self.assertIn(
            "static let lowConfidenceThreshold: Float = 0.55",
            self.summary,
        )
        self.assertGreaterEqual(
            self.summary.count("lowConfidenceThreshold: Float = Self.lowConfidenceThreshold"),
            3,
        )
        self.assertIn("return confidence < threshold", self.summary)
        self.assertIn("ImageOCRResultSummary.hasLowConfidence($0)", self.review_filter)
        self.assertIn("ImageOCRResultSummary.requiresReview($0)", self.review_filter)

    def test_all_review_surfaces_consume_the_shared_gate(self) -> None:
        self.assertIn("ImageOCRResultSummary.requiresReview", self.store)
        self.assertIn("ImageOCRResultSummary.requiresReview", self.view)
        self.assertIn("ImageOCRResultSummary.hasLowConfidence", self.view)
        self.assertNotIn("lowConfidenceThreshold: 0.5", self.store)
        self.assertNotIn("lowConfidenceThreshold: 0.5", self.view)

    def test_legacy_evaluator_keeps_the_exact_boundary_excluded(self) -> None:
        self.assertIn(
            "static let lowConfidenceThreshold: Float = 0.55",
            self.legacy_contract,
        )
        self.assertIn("block(confidence: 0.55, direction: .vertical)", self.legacy_evaluator)
        self.assertIn(
            "let expectedAverage = (Double(Float(0.55)) + 0.25) / 4.0",
            self.legacy_evaluator,
        )
        self.assertIn(
            'exactly 55 percent must pass',
            self.legacy_evaluator,
        )
        self.assertIn(
            "block(4, confidence: 0.55, direction: .horizontal)",
            read("scripts/test-v310-image-ocr-review-filter-evaluator.swift"),
        )
        self.assertIn(
            "let boundary = block(0.55, .horizontal)",
            read("scripts/test-v392-image-review-risk-filter-evaluator.swift"),
        )
        self.assertIn(
            'exactly 55 percent must not be classified as low confidence',
            read("scripts/test-v392-image-review-risk-filter-evaluator.swift"),
        )

    def test_ci_route_and_project_version_are_current(self) -> None:
        current = "scripts/test-v3273-image-ocr-review-confidence-gate-contract.py"
        self.assertIn(f"# if grep -Fx '{current}'", self.workflow)
        self.assertIn(f"if grep -Fx '{current}'", self.workflow)
        self.assertIn(f"python3 -B {current}", self.workflow)
        self.assertIn(
            "AITRANS/Models/ImageOCR(ResultSummary|ReviewFilter)\\.swift",
            self.workflow,
        )
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project),
            ["3.337", "3.337"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Static contract for v3.274's shared image-review threshold copy."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class ImageOCRReviewThresholdCopyContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.view = read("AITRANS/Views/ImageTranslationViews.swift")
        cls.summary = read("AITRANS/Models/ImageOCRResultSummary.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def test_review_copy_reads_the_shared_threshold(self) -> None:
        self.assertIn("private enum ImageOCRReviewPresentation", self.view)
        self.assertIn("static var lowConfidencePercent: Int", self.view)
        self.assertIn(
            "Double(ImageOCRResultSummary.lowConfidenceThreshold)",
            self.view,
        )
        self.assertEqual(
            self.view.count("ImageOCRReviewPresentation.lowConfidencePercent"),
            3,
        )
        self.assertNotIn("低于 50%", self.view)
        self.assertNotIn("低于 50%，", self.view)

    def test_copy_and_gate_have_the_same_55_percent_boundary(self) -> None:
        self.assertIn("static let lowConfidenceThreshold: Float = 0.55", self.summary)
        self.assertIn(
            "低于 \\(ImageOCRReviewPresentation.lowConfidencePercent)%",
            self.view,
        )
        self.assertIn(
            "低于 \\(ImageOCRReviewPresentation.lowConfidencePercent)%，",
            self.view,
        )

    def test_ci_route_and_project_version_are_current(self) -> None:
        current = "scripts/test-v3274-image-ocr-review-threshold-copy-contract.py"
        self.assertIn(f"if grep -Fx '{current}'", self.workflow)
        self.assertIn(f"python3 -B {current}", self.workflow)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project),
            ["3.306", "3.306"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

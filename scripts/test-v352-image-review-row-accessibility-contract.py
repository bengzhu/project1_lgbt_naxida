#!/usr/bin/env python3
"""Static contracts for v3.52 image review-row accessibility context."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def braced_body(source: str, marker: str) -> str:
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace:index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class ImageReviewRowAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_review_row_uses_dynamic_status_value(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        self.assertIn(".accessibilityElement(children: .combine)", row)
        self.assertIn(".accessibilityValue(accessibilityValue)", row)
        self.assertIn("private var accessibilityValue: String", row)

    def test_status_value_exposes_review_signals(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        value = braced_body(row, "private var accessibilityValue: String")
        self.assertIn("accessibilityConfidencePercent", value)
        self.assertIn("isManuallyCorrected", value)
        self.assertIn("ImageOCRResultSummary.hasLowConfidence(block)", value)
        self.assertIn("ImageOCRResultSummary.hasUnknownDirection(block)", value)
        self.assertIn("isReviewCompleted ? \"本次已复查\" : \"待复查\"", value)
        self.assertIn("block.translation.isEmpty", value)

    def test_confidence_is_clamped_before_percent_formatting(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        confidence = braced_body(row, "private var accessibilityConfidencePercent: Int")
        self.assertTrue(
            "min(max(Double(block.confidence), 0), 1)" in confidence
            or "ImageOCRResultSummary.normalizedConfidence(block.confidence)" in confidence
        )
        self.assertIn("rounded()", confidence)

    def test_version_and_ci_route_follow_v351(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.52;", self.project)
        old = "python3 -B scripts/test-v351-image-status-accessibility-contract.py"
        new = "python3 -B scripts/test-v352-image-review-row-accessibility-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

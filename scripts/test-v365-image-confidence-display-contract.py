#!/usr/bin/env python3
"""Contracts for v3.65 image confidence display consistency."""

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


class ImageConfidenceDisplayContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.sheet = braced_body(self.view, "private struct ImageOCRCorrectionSheet: View")

    def test_correction_sheet_uses_the_shared_safe_confidence_boundary(self) -> None:
        self.assertIn("Text(displayConfidence, format: .percent.precision(.fractionLength(0)))", self.sheet)
        self.assertIn(
            "Double(ImageOCRResultSummary.normalizedConfidence(block.confidence))",
            self.sheet,
        )
        self.assertNotIn(
            "Text(block.confidence, format: .percent.precision(.fractionLength(0)))",
            self.sheet,
        )

    def test_display_boundary_is_view_only_and_does_not_add_ocr_or_store_work(self) -> None:
        display = braced_body(self.sheet, "private var displayConfidence")
        for forbidden in [
            "VisionOCRService",
            "runImageTranslation",
            "persist",
            "groundTruth",
            "store.",
        ]:
            self.assertNotIn(forbidden, display)

    def test_version_and_ci_route_follow_v364(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.64;", self.project)
        old = "python3 -B scripts/test-v364-image-confidence-safety-contract.py"
        new = "python3 -B scripts/test-v365-image-confidence-display-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74|75|76|77|78|79|80)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Static contracts for v3.61 image direction review context."""

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


class ImageDirectionReviewContextContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        self.overlay = braced_body(self.view, "private struct ImageTranslationOverlayBlock: View")

    def test_direction_context_has_stable_titles_and_clamped_confidence(self) -> None:
        direction = braced_body(self.view, "private enum ImageOCRDirectionPresentation")
        title = braced_body(direction, "static func displayTitle(for block: ImageTranslationBlock)")
        context = braced_body(direction, "static func accessibilityContext(for block: ImageTranslationBlock)")

        for marker in ['"横排"', '"竖排"', '"方向待定"']:
            self.assertIn(marker, title)
        self.assertIn("rawConfidence.isFinite", context)
        self.assertIn("min(max(rawConfidence, 0), 1)", context)
        self.assertIn("方向置信度 \\(percent)%", context)

    def test_review_row_surfaces_known_direction_and_safe_display_confidence(self) -> None:
        self.assertIn("ImageOCRDirectionPresentation.accessibilityContext(for: block)", self.row)
        self.assertIn("ImageOCRDirectionPresentation.displayTitle(for: block)", self.row)
        self.assertIn('systemImage: "text.alignleft"', self.row)
        self.assertIn("Text(displayConfidence, format: .percent", self.row)
        self.assertTrue(
            "rawConfidence.isFinite" in self.row
            or "ImageOCRResultSummary.normalizedConfidence(block.confidence)" in self.row
        )

    def test_overlay_exposes_direction_context_without_mutating_ocr_or_store(self) -> None:
        value = braced_body(self.overlay, "private var accessibilityValue: String")
        self.assertIn("ImageOCRDirectionPresentation.accessibilityContext(for: block)", value)
        self.assertIn("ImageOCRResultSummary.hasUnknownDirection(block)", value)
        for forbidden in [
            "TranslationSessionStore",
            "VisionOCRService",
            "runImageTranslation",
            "setImageOverlayMode",
        ]:
            self.assertNotIn(forbidden, self.overlay)

    def test_version_and_ci_route_follow_v360(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.60;", self.project)
        old = "python3 -B scripts/test-v360-image-overlay-review-context-accessibility-contract.py"
        new = "python3 -B scripts/test-v361-image-direction-review-context-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

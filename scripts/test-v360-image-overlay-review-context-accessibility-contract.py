#!/usr/bin/env python3
"""Static contracts for v3.60 image overlay review context accessibility."""

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


class ImageOverlayReviewContextAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.preview = braced_body(self.view, "private struct ImageTranslationPreview: View")
        self.overlay = braced_body(self.view, "private struct ImageTranslationOverlayBlock: View")

    def test_preview_passes_review_and_correction_context_to_both_overlay_modes(self) -> None:
        self.assertIn("isReviewCompleted: reviewedBlockIDs.contains(block.id)", self.preview)
        self.assertIn(
            "isManuallyCorrected: store.imageTranslationCorrectedBlockIDs.contains(block.id)",
            self.preview,
        )
        self.assertEqual(self.overlay.count("let isReviewCompleted: Bool"), 1)
        self.assertEqual(self.overlay.count("let isManuallyCorrected: Bool"), 1)

    def test_overlay_value_matches_review_row_context_without_dropping_translation(self) -> None:
        value = braced_body(self.overlay, "private var accessibilityValue: String")
        self.assertIn("OCR 置信度 \\(accessibilityConfidencePercent)%", value)
        self.assertIn("if isManuallyCorrected", value)
        self.assertIn("ImageOCRResultSummary.hasLowConfidence(block)", value)
        self.assertIn("ImageOCRResultSummary.hasUnknownDirection(block)", value)
        self.assertIn('isReviewCompleted ? "本次已复查" : "待复查"', value)
        self.assertIn('block.translation.isEmpty ? "等待翻译" : "译文：\\(block.translation)"', value)

        confidence = braced_body(self.overlay, "private var accessibilityConfidencePercent: Int")
        self.assertTrue(
            "min(max(Double(block.confidence), 0), 1)" in confidence
            or "ImageOCRResultSummary.normalizedConfidence(block.confidence)" in confidence
        )
        self.assertIn("rounded()", confidence)

    def test_overlay_remains_view_only_and_keeps_stable_identity_and_location_hint(self) -> None:
        self.assertEqual(self.overlay.count('.accessibilityLabel("图片文字块 \\(accessibilityOriginalText)")'), 2)
        self.assertEqual(self.overlay.count(".accessibilityValue(accessibilityValue)"), 2)
        self.assertEqual(self.overlay.count(".accessibilityHint(accessibilityHint)"), 2)
        self.assertNotIn("TranslationSessionStore", self.overlay)
        self.assertNotIn("VisionOCRService", self.overlay)
        self.assertNotIn("runImageTranslation", self.overlay)
        self.assertNotIn("setImageOverlayMode", self.overlay)

    def test_version_and_ci_route_follow_v359(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.59;", self.project)
        old = "python3 -B scripts/test-v359-image-overlay-block-context-accessibility-contract.py"
        new = "python3 -B scripts/test-v360-image-overlay-review-context-accessibility-contract.py"
        route = "grep -E '^scripts/test-v3(4[7-9]|[5-7][0-9]|8[01])-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

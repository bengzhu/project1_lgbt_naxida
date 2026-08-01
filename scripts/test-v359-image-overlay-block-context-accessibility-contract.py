#!/usr/bin/env python3
"""Static contracts for v3.59 image overlay block accessibility identity."""

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


class ImageOverlayBlockContextAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.overlay = braced_body(self.view, "private struct ImageTranslationOverlayBlock: View")

    def test_overlay_modes_share_one_stable_image_block_identity(self) -> None:
        self.assertEqual(self.overlay.count('.accessibilityLabel("图片文字块 \\(accessibilityOriginalText)")'), 2)
        self.assertEqual(self.overlay.count(".accessibilityValue(accessibilityValue)"), 2)
        self.assertEqual(self.overlay.count(".accessibilityHint(accessibilityHint)"), 2)

    def test_overlay_context_preserves_translation_and_empty_ocr_fallback(self) -> None:
        value = braced_body(self.overlay, "private var accessibilityValue: String")
        self.assertTrue(
            'block.translation.isEmpty ? "等待翻译" : block.translation' in value
            or 'block.translation.isEmpty ? "等待翻译" : "译文：\\(block.translation)"' in value
        )
        original = braced_body(self.overlay, "private var accessibilityOriginalText: String")
        self.assertIn('block.original.isEmpty ? "空" : block.original', original)
        self.assertIn("isSelected ?", value)

    def test_overlay_context_does_not_mutate_store_or_run_ocr(self) -> None:
        self.assertNotIn("TranslationSessionStore", self.overlay)
        self.assertNotIn("VisionOCRService", self.overlay)
        self.assertNotIn("runImageTranslation", self.overlay)
        self.assertNotIn("setImageOverlayMode", self.overlay)

    def test_version_and_ci_route_follow_v358(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.58;", self.project)
        old = "python3 -B scripts/test-v358-image-review-row-context-accessibility-contract.py"
        new = "python3 -B scripts/test-v359-image-overlay-block-context-accessibility-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

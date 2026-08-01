#!/usr/bin/env python3
"""Contract for stable empty OCR context in image focus previews."""

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


class ImageFocusEmptyOCRContextContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.reference = braced_body(
            self.view,
            "private struct ImageOCRCorrectionReferencePreview: View",
        )
        self.focus = braced_body(
            self.view,
            "private struct ImageTranslationFocusPreview: View",
        )

    def test_reference_preview_has_stable_empty_ocr_value(self) -> None:
        self.assertIn(
            '.accessibilityValue("黄色边框为 OCR 文字区域，当前识别为 \\(accessibilityOriginalText)")',
            self.reference,
        )
        self.assertIn('block.original.isEmpty ? "空" : block.original', self.reference)
        self.assertNotIn(
            '.accessibilityValue("黄色边框为 OCR 文字区域，当前识别为 \\(block.original)")',
            self.reference,
        )

    def test_focus_preview_has_stable_empty_ocr_value(self) -> None:
        self.assertIn(
            '.accessibilityValue("\\(positionText)，\\(accessibilityOriginalText)")',
            self.focus,
        )
        self.assertIn('block.original.isEmpty ? "空" : block.original', self.focus)
        self.assertNotIn(
            '.accessibilityValue("\\(positionText)，\\(block.original)")',
            self.focus,
        )

    def test_focus_previews_remain_view_only(self) -> None:
        for body in (self.reference, self.focus):
            self.assertIn("ImageTranslationBlock", body)
            self.assertNotIn("TranslationSessionStore", body)
            self.assertNotIn("VisionOCRService", body)
            self.assertNotIn("FileManager", body)
            self.assertNotIn("runMangaOverlayProbe", body)
            self.assertNotIn("store.", body)

    def test_version_and_ci_route_follow_v374(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.75;", self.project)
        old = "python3 -B scripts/test-v374-image-empty-ocr-consistency-contract.py"
        new = "python3 -B scripts/test-v375-image-focus-empty-ocr-context-contract.py"
        route = "grep -E '^scripts/test-v3(4[7-9]|[5-7][0-9]|8[01])-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

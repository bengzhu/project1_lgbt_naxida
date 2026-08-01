#!/usr/bin/env python3
"""Contracts for v3.74 consistent empty OCR text across image surfaces."""

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


class EmptyOCRConsistencyContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.overlay = braced_body(self.view, "private struct ImageTranslationOverlayBlock: View")
        self.row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")

    def test_overlay_uses_empty_ocr_fallback_without_changing_translation_priority(self) -> None:
        self.assertGreaterEqual(self.overlay.count("displayOCRText"), 3)
        self.assertIn('block.original.isEmpty ? "空 OCR 原文" : block.original', self.overlay)
        self.assertIn("block.translation.isEmpty ? displayOCRText : block.translation", self.overlay)

    def test_result_row_uses_empty_ocr_fallback(self) -> None:
        self.assertIn("Text(displayOriginalText)", self.row)
        self.assertIn('block.original.isEmpty ? "空 OCR 原文" : block.original', self.row)
        self.assertIn('.accessibilityLabel("图片文字块 \\(accessibilityOriginalText)")', self.row)

    def test_non_empty_and_view_only_boundaries_remain(self) -> None:
        self.assertIn("block.original", self.overlay)
        self.assertIn("block.original", self.row)
        self.assertIn("ImageTranslationBlock", self.overlay)
        self.assertIn("ImageTranslationBlock", self.row)
        for body in (self.overlay, self.row):
            self.assertNotIn("TranslationSessionStore", body)
            self.assertNotIn("VisionOCRService", body)
            self.assertNotIn("FileManager", body)
            self.assertNotIn("runMangaOverlayProbe", body)
            self.assertNotIn("store.", body)

    def test_version_and_ci_route_follow_v373(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.74;", self.project)
        old = "python3 -B scripts/test-v373-image-ignored-empty-context-contract.py"
        new = "python3 -B scripts/test-v374-image-empty-ocr-consistency-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74|75)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

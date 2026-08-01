#!/usr/bin/env python3
"""Contracts for v3.70 image preview geometry-aware accessibility hints."""

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


class ImagePreviewGeometryHintContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_preview_hint_distinguishes_unlocatable_blocks(self) -> None:
        preview = braced_body(self.view, "private struct ImageTranslationPreview: View")
        hint = braced_body(preview, "private var previewAccessibilityHint: String")
        self.assertIn("geometryUnavailableCount", hint)
        self.assertIn("ImageOCRGeometryPresentation.isLocatable(for: $0)", hint)
        self.assertIn("有效文字块可打开局部放大", hint)
        self.assertIn("局部预览不可用", hint)
        self.assertIn('operationHint = "点按文字块可定位并打开局部放大"', hint)

    def test_preview_hint_keeps_existing_state_gate_details(self) -> None:
        preview = braced_body(self.view, "private struct ImageTranslationPreview: View")
        hint = braced_body(preview, "private var previewAccessibilityHint: String")
        self.assertIn("var unavailableDetails: [String] = []", hint)
        self.assertIn("if !canEdit", hint)
        self.assertIn("modificationUnavailableHint", hint)
        self.assertIn("if !canReview", hint)
        self.assertIn("reviewUnavailableHint", hint)
        self.assertIn("unavailableDetails.joined(separator: \" \")", hint)

    def test_version_and_ci_route_follow_v369(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.69;", self.project)
        old = "python3 -B scripts/test-v369-image-geometry-availability-contract.py"
        new = "python3 -B scripts/test-v370-image-preview-geometry-hint-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74|75|76)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

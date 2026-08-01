#!/usr/bin/env python3
"""Contracts for v3.69 image geometry availability feedback."""

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


class ImageGeometryAvailabilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_geometry_presentation_reuses_the_model_boundary(self) -> None:
        presentation = braced_body(self.view, "private enum ImageOCRGeometryPresentation")
        self.assertIn("static func isLocatable(for block: ImageTranslationBlock) -> Bool", presentation)
        self.assertIn("block.boundingBox.normalizedToUnit() != nil", presentation)

    def test_preview_summary_reports_unlocatable_blocks(self) -> None:
        preview = braced_body(self.view, "private struct ImageTranslationPreview: View")
        value = braced_body(preview, "private var previewAccessibilityValue: String")
        self.assertIn("geometryUnavailableCount", value)
        self.assertIn("ImageOCRGeometryPresentation.isLocatable(for: $0)", value)
        self.assertIn('parts.append("定位不可用 \\(geometryUnavailableCount) 个")', value)

    def test_result_row_shows_and_explains_unlocatable_geometry(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        self.assertIn('Label("图片定位不可用", systemImage: "location.slash")', row)
        self.assertIn(".accessibilityHint(accessibilityHint)", row)
        value = braced_body(row, "private var accessibilityValue: String")
        self.assertIn('parts.append("图片定位不可用")', value)
        hint = braced_body(row, "private var accessibilityHint: String")
        self.assertIn("ImageOCRGeometryPresentation.isLocatable(for: block)", hint)
        self.assertIn("图片局部预览不可用", hint)
        self.assertIn("仍可修正 OCR 原文", hint)
        self.assertIn("可切换文字块", hint)

    def test_version_and_ci_route_follow_v368(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3.69;"), 2)
        self.assertNotIn("MARKETING_VERSION = 3.68;", self.project)
        old = "python3 -B scripts/test-v368-image-preview-invalid-geometry-contract.py"
        new = "python3 -B scripts/test-v369-image-geometry-availability-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

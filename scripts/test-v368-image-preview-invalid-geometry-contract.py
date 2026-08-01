#!/usr/bin/env python3
"""Contracts for v3.68 invalid image geometry preview feedback."""

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


class ImagePreviewInvalidGeometryContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_focus_crop_rejects_invalid_geometry_instead_of_using_the_whole_image(self) -> None:
        make = braced_body(self.view, "static func make(")
        focus = braced_body(self.view, "static func normalizedFocusRect(for block")
        self.assertIn("guard let normalizedRect = normalizedFocusRect(for: block) else", make)
        self.assertIn("return nil", make)
        self.assertIn("static func normalizedFocusRect(for block: ImageTranslationBlock) -> CGRect?", self.view)
        self.assertIn("block.boundingBox.normalizedToUnit() else", focus)
        self.assertIn("return nil", focus)
        self.assertNotIn("return CGRect(x: 0, y: 0, width: 1, height: 1)", focus)

    def test_focus_preview_explains_unavailable_geometry_and_preserves_actions(self) -> None:
        preview = braced_body(self.view, "private struct ImageTranslationFocusPreview: View")
        self.assertIn("unavailableFocusState", preview)
        self.assertIn("当前文字块局部预览不可用", preview)
        self.assertIn("仍可关闭、编辑 OCR 原文或切换文字块", preview)
        self.assertIn(".accessibilityValue(\"\\(positionText)，\\(accessibilityOriginalText)\")", preview)
        self.assertIn('block.original.isEmpty ? "空" : block.original', preview)
        self.assertIn(".accessibilityHint(focusPreviewAccessibilityHint)", preview)
        self.assertIn("return \"局部预览不可用；仍可关闭、编辑 OCR 原文或切换文字块\"", preview)
        self.assertIn("Button(\"关闭局部放大\"", preview)
        self.assertIn("Button(\"修正识别文字\"", preview)

    def test_invalid_reference_preview_remains_editable(self) -> None:
        reference = braced_body(self.view, "private struct ImageOCRCorrectionReferencePreview: View")
        self.assertIn("ImageTranslationBlockFocusCrop.make(from: sourceImage, block: block)", reference)
        self.assertIn("图片局部预览不可用，仍可编辑 OCR 原文", reference)
        self.assertNotIn("VisionOCRService", reference)

    def test_version_and_ci_route_follow_v367(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.68;", self.project)
        self.assertNotIn("MARKETING_VERSION = 3.67;", self.project)
        old = "python3 -B scripts/test-v367-image-block-geometry-safety-contract.py"
        new = "python3 -B scripts/test-v368-image-preview-invalid-geometry-contract.py"
        route = "grep -E '^scripts/test-v3(4[7-9]|[5-7][0-9]|8[01])-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

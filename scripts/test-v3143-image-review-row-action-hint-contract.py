#!/usr/bin/env python3
"""Contract for truthful dynamic VoiceOver action hints on image result rows."""

from pathlib import Path
import re
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
                return source[brace : index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class ImageReviewRowActionHintContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.row = braced_body(
            self.view,
            "private struct ImageTranslationBlockRow: View",
        )
        self.hint = braced_body(self.row, "private var accessibilityHint: String")
        self.action_hint = braced_body(self.row, "private func rowAccessibilityHint(appendingTo base: String)")

    def test_hint_preserves_location_and_geometry_context(self) -> None:
        self.assertIn("ImageOCRGeometryPresentation.isLocatable(for: block)", self.hint)
        self.assertIn('? "取消此文字块在图片中的定位"', self.hint)
        self.assertIn(': "在图片预览中定位此文字块"', self.hint)
        self.assertIn("图片局部预览不可用", self.hint)
        self.assertIn("仍可修正 OCR 原文", self.hint)
        self.assertIn("可切换文字块", self.hint)
        self.assertIn("return rowAccessibilityHint(appendingTo: locationHint)", self.hint)

    def test_hint_lists_only_actions_that_are_actually_exposed(self) -> None:
        self.assertIn("var actions: [String] = []", self.action_hint)
        self.assertIn("if canEdit", self.action_hint)
        self.assertIn('actions.append("修正识别文字")', self.action_hint)
        self.assertIn("if isManuallyCorrected && canEdit", self.action_hint)
        self.assertIn('actions.append("恢复 Vision OCR")', self.action_hint)
        self.assertIn("if ImageOCRResultSummary.requiresReview(block) && canReview", self.action_hint)
        self.assertIn('actions.append(isReviewCompleted ? "撤销本次复查" : "完成并继续复查")', self.action_hint)
        self.assertIn("guard !actions.isEmpty else { return base }", self.action_hint)
        self.assertIn("VoiceOver 可执行：", self.action_hint)
        self.assertIn('actions.joined(separator: "、")', self.action_hint)

    def test_hint_keeps_the_row_accessibility_element_and_actions_view_only(self) -> None:
        self.assertIn(".accessibilityElement(children: .combine)", self.row)
        self.assertIn(".accessibilityValue(accessibilityValue)", self.row)
        self.assertIn(".accessibilityFocused(", self.row)
        self.assertNotIn("rowAccessibilityHint", self.store)
        self.assertNotIn("runImageTranslationPipeline", self.row)
        self.assertNotIn("VisionOCRService", self.row)
        self.assertNotIn("MangaOverlayProbeService", self.row)

    def test_version_and_ci_route_follow_v3142(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 143) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.142;", self.project)
        old = "scripts/test-v3142-image-review-row-review-action-contract.py"
        new = "scripts/test-v3143-image-review-row-action-hint-contract.py"
        self.assertIn(f"python3 -B {old}", self.workflow)
        self.assertIn(f"python3 -B {new}", self.workflow)
        self.assertLess(self.workflow.index(f"python3 -B {old}"), self.workflow.index(f"python3 -B {new}"))
        self.assertIn("14[2]", self.workflow)
        self.assertIn("14[3]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)

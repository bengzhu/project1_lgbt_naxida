#!/usr/bin/env python3
"""Contract for de-duplicating unavailable focus-preview VoiceOver state."""

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


class FocusPreviewUnavailableVoiceOverContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.focus = braced_body(
            self.view,
            "private struct ImageTranslationFocusPreview: View",
        )

    def test_unavailable_state_is_hidden_and_parent_hint_preserves_actions(self) -> None:
        state = braced_body(self.focus, "private var unavailableFocusState")
        self.assertIn('.accessibilityLabel("当前文字块局部预览不可用")', state)
        self.assertIn('.accessibilityValue("仍可关闭、编辑 OCR 原文或切换文字块")', state)
        self.assertIn(".accessibilityHidden(true)", state)
        hint = braced_body(self.focus, "private var focusPreviewAccessibilityHint")
        self.assertIn("局部预览不可用", hint)
        self.assertIn("仍可关闭、编辑 OCR 原文或切换文字块", hint)

    def test_focus_container_and_actions_remain_accessible(self) -> None:
        self.assertIn(".accessibilityElement(children: .contain)", self.focus)
        self.assertIn('.accessibilityLabel("已定位文字块局部放大")', self.focus)
        self.assertIn("Button(\"关闭局部放大\", systemImage: \"xmark\", action: close)", self.focus)
        self.assertIn("Button(\"修正识别文字\", systemImage: \"pencil\", action: edit)", self.focus)
        self.assertIn("navigationPositionAccessibilityValue", self.focus)

    def test_change_is_view_only(self) -> None:
        self.assertNotIn("TranslationSessionStore", self.focus)
        self.assertNotIn("VisionOCRService", self.focus)
        self.assertNotIn("FileManager", self.focus)
        self.assertNotIn("runMangaOverlayProbe", self.focus)
        self.assertNotIn("store.", self.focus)

    def test_version_and_ci_route_follow_v376(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.76;", self.project)
        old = "python3 -B scripts/test-v376-image-focus-preview-decorative-label-contract.py"
        new = "python3 -B scripts/test-v377-image-focus-preview-unavailable-voiceover-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74|75|76|77|78|79|80)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

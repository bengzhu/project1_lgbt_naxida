#!/usr/bin/env python3
"""Contract for a direct VoiceOver close action on image focus previews."""

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


class ImageFocusPreviewCloseActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.focus = braced_body(
            self.view,
            "private struct ImageTranslationFocusPreview: View",
        )

    def test_focus_container_exposes_named_close_action(self) -> None:
        self.assertIn('.accessibilityAction(named: "关闭局部放大")', self.focus)
        action = braced_body(self.focus, '.accessibilityAction(named: "关闭局部放大")')
        self.assertIn("close()", action)
        self.assertIn('Button("关闭局部放大", systemImage: "xmark", action: close)', self.focus)
        self.assertIn("关闭局部放大并返回当前文字块结果行", self.focus)

    def test_close_action_keeps_context_and_focus_identity(self) -> None:
        self.assertIn('.accessibilityLabel("已定位文字块局部放大")', self.focus)
        self.assertIn('.accessibilityValue("\\(positionText)，\\(accessibilityOriginalText)")', self.focus)
        self.assertIn("focusPreviewAccessibilityHint", self.focus)
        self.assertIn('.accessibilityFocused(', self.focus)
        self.assertIn('"image-review-preview-\\(block.id.uuidString)"', self.focus)

    def test_panel_still_hands_focus_back_to_source_row(self) -> None:
        close = braced_body(self.panel, "private func closeImageTranslationFocusPreview()")
        self.assertIn("self.selectedImageTranslationBlockID = nil", close)
        self.assertIn(
            "moveReviewAccessibilityFocus(to: reviewRowAccessibilityFocusID(selectedImageTranslationBlockID))",
            close,
        )

    def test_close_action_is_view_only(self) -> None:
        self.assertNotIn("ImageTranslationFocusPreview", self.store)
        self.assertNotIn("VisionOCRService", self.focus)
        self.assertNotIn("runImageTranslationPipeline", self.focus)
        self.assertNotIn("MangaOverlayProbeService", self.focus)

    def test_version_and_ci_route_follow_v3135(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 136) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.135;", self.project)
        old = "scripts/test-v3135-image-preview-status-hint-contract.py"
        new = "scripts/test-v3136-image-focus-close-action-contract.py"
        self.assertIn(f"python3 -B {old}", self.workflow)
        self.assertIn(f"python3 -B {new}", self.workflow)
        self.assertLess(self.workflow.index(f"python3 -B {old}"), self.workflow.index(f"python3 -B {new}"))
        self.assertTrue("13[0-7]" in self.workflow or "13[0-8]" in self.workflow or "13[0-9]" in self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)

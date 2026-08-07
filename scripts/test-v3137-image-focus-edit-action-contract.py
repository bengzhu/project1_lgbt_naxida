#!/usr/bin/env python3
"""Contract for a gated direct VoiceOver OCR-edit action on image focus previews."""

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


class ImageFocusPreviewEditActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.focus = braced_body(
            self.view,
            "private struct ImageTranslationFocusPreview: View",
        )

    def test_focus_parent_exposes_gated_edit_action(self) -> None:
        modifier = braced_body(
            self.view,
            "private struct ImageFocusPreviewEditAccessibilityModifier",
        )
        self.assertIn("let canEdit: Bool", modifier)
        self.assertIn("if canEdit", modifier)
        self.assertIn('.accessibilityAction(named: "修正识别文字")', modifier)
        action = braced_body(modifier, '.accessibilityAction(named: "修正识别文字")')
        self.assertIn("edit()", action)
        self.assertIn("ImageFocusPreviewEditAccessibilityModifier", self.focus)

    def test_edit_action_is_not_exposed_when_locked(self) -> None:
        modifier = braced_body(
            self.view,
            "private struct ImageFocusPreviewEditAccessibilityModifier",
        )
        locked_branch = modifier[modifier.index("} else {") :]
        self.assertNotIn('.accessibilityAction(named: "修正识别文字")', locked_branch)
        self.assertIn(".disabled(!canEdit)", self.focus)
        self.assertIn("modificationUnavailableHint", self.focus)

    def test_edit_action_keeps_focus_preview_context(self) -> None:
        self.assertIn('.accessibilityLabel("已定位文字块局部放大")', self.focus)
        self.assertIn('.accessibilityValue("\\(positionText)，\\(accessibilityOriginalText)")', self.focus)
        self.assertIn("focusPreviewAccessibilityHint", self.focus)
        self.assertIn('"可执行“关闭局部放大”或“修正识别文字”', self.focus)
        self.assertIn('"局部预览不可用；仍可关闭、修正 OCR 原文或切换文字块"', self.focus)

    def test_edit_action_is_view_only(self) -> None:
        self.assertNotIn("ImageFocusPreviewEditAccessibilityModifier", self.store)
        self.assertNotIn("VisionOCRService", self.focus)
        self.assertNotIn("runImageTranslationPipeline", self.focus)
        self.assertNotIn("MangaOverlayProbeService", self.focus)

    def test_version_and_ci_route_follow_v3136(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 137) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.136;", self.project)
        old = "scripts/test-v3136-image-focus-close-action-contract.py"
        new = "scripts/test-v3137-image-focus-edit-action-contract.py"
        self.assertIn(f"python3 -B {old}", self.workflow)
        self.assertIn(f"python3 -B {new}", self.workflow)
        self.assertLess(self.workflow.index(f"python3 -B {old}"), self.workflow.index(f"python3 -B {new}"))
        self.assertTrue("13[0-7]" in self.workflow or "13[0-8]" in self.workflow or "13[0-9]" in self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)

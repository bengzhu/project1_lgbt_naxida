#!/usr/bin/env python3
"""Contract for direct VoiceOver navigation actions on image focus previews."""

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


class ImageFocusPreviewNavigationActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.focus = braced_body(
            self.view,
            "private struct ImageTranslationFocusPreview: View",
        )
        self.modifier = braced_body(
            self.view,
            "private struct ImageFocusPreviewNavigationAccessibilityModifier",
        )

    def test_focus_parent_exposes_available_navigation_actions(self) -> None:
        self.assertIn("let canSelectPrevious: Bool", self.modifier)
        self.assertIn("let canSelectNext: Bool", self.modifier)
        self.assertIn("if canSelectPrevious && canSelectNext", self.modifier)
        self.assertIn('.accessibilityAction(named: "上一个文字块")', self.modifier)
        self.assertIn('.accessibilityAction(named: "下一个文字块")', self.modifier)
        self.assertIn("selectPrevious()", self.modifier)
        self.assertIn("selectNext()", self.modifier)
        self.assertIn("ImageFocusPreviewNavigationAccessibilityModifier", self.focus)
        self.assertIn("canSelectPrevious: canSelectPrevious", self.focus)
        self.assertIn("canSelectNext: canSelectNext", self.focus)

    def test_navigation_actions_are_gated_by_available_neighbors(self) -> None:
        self.assertIn("else if canSelectPrevious", self.modifier)
        self.assertIn("else if canSelectNext", self.modifier)
        empty_branch = self.modifier[self.modifier.rfind("} else {") :]
        self.assertNotIn("accessibilityAction", empty_branch)
        self.assertIn(".disabled(!canSelectPrevious)", self.focus)
        self.assertIn(".disabled(!canSelectNext)", self.focus)

    def test_navigation_actions_keep_existing_position_and_focus_context(self) -> None:
        self.assertIn('.accessibilityLabel("已定位文字块局部放大")', self.focus)
        self.assertIn('.accessibilityValue("\\(positionText)，\\(accessibilityOriginalText)")', self.focus)
        self.assertIn("navigationPositionAccessibilityValue", self.focus)
        self.assertIn('Button("上一个文字块", systemImage: "chevron.left", action: selectPrevious)', self.focus)
        self.assertIn('Button("下一个文字块", systemImage: "chevron.right", action: selectNext)', self.focus)
        self.assertIn('"定位上一个文字块"', self.focus)
        self.assertIn('"定位下一个文字块"', self.focus)

    def test_navigation_actions_are_view_only(self) -> None:
        self.assertNotIn("ImageFocusPreviewNavigationAccessibilityModifier", self.store)
        self.assertNotIn("runImageTranslationPipeline", self.focus)
        self.assertNotIn("MangaOverlayProbeService", self.focus)

    def test_version_and_ci_route_follow_v3138(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 139) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.138;", self.project)
        old = "scripts/test-v3138-image-focus-review-action-contract.py"
        new = "scripts/test-v3139-image-focus-navigation-action-contract.py"
        self.assertIn(f"python3 -B {old}", self.workflow)
        self.assertIn(f"python3 -B {new}", self.workflow)
        self.assertLess(self.workflow.index(f"python3 -B {old}"), self.workflow.index(f"python3 -B {new}"))
        self.assertIn("13[0-9]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)

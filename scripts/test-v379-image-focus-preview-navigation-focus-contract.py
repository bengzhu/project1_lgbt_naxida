#!/usr/bin/env python3
"""Contract for VoiceOver focus handoff after adjacent focus-preview navigation."""

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
                return source[brace : index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class ImageFocusPreviewNavigationFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.workspace = braced_body(self.panel, "private var imageWorkspace: some View")
        self.preview = braced_body(
            self.view,
            "private struct ImageTranslationPreview: View",
        )
        self.focus = braced_body(
            self.view,
            "private struct ImageTranslationFocusPreview: View",
        )

    def test_adjacent_navigation_moves_focus_to_the_new_preview_container(self) -> None:
        navigation = braced_body(self.panel, "private func selectAdjacentBlock(offset: Int)")
        self.assertIn("let targetBlockID = visibleImageTranslationBlocks[targetIndex].id", navigation)
        self.assertIn("selectedImageTranslationBlockID = targetBlockID", navigation)
        self.assertIn(
            "moveReviewAccessibilityFocus(to: reviewPreviewAccessibilityFocusID(targetBlockID))",
            navigation,
        )
        self.assertIn("selectPrevious: { selectAdjacentBlock(offset: -1) }", self.workspace)
        self.assertIn("selectNext: { selectAdjacentBlock(offset: 1) }", self.workspace)

    def test_navigation_controls_keep_position_and_boundary_context(self) -> None:
        self.assertEqual(self.focus.count(".accessibilityValue(navigationPositionAccessibilityValue)"), 2)
        self.assertIn("当前已是筛选结果中的第一个文字块", self.focus)
        self.assertIn("当前已是筛选结果中的最后一个文字块", self.focus)
        self.assertIn("reviewPreviewAccessibilityFocusID", self.panel)

    def test_navigation_focus_remains_view_only(self) -> None:
        self.assertNotIn("ImageTranslationFocusPreview", self.store)
        self.assertNotIn("VisionOCRService", self.preview)
        self.assertNotIn("VisionOCRService", self.focus)

    def test_version_and_ci_route_follow_v378(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.78;", self.project)
        old = "python3 -B scripts/test-v378-image-focus-preview-close-focus-contract.py"
        new = "python3 -B scripts/test-v379-image-focus-preview-navigation-focus-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74|75|76|77|78|79|80)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Contracts for v3.14 image review focus navigation."""

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


class ImageReviewNavigationContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")

    def test_new_selection_reveals_one_unique_workspace_anchor(self) -> None:
        self.assertIn("ScrollViewReader { proxy in", self.view)
        self.assertIn('static let previewScrollID = "imageTranslationPreview"', self.view)
        self.assertEqual(self.view.count(".id(Self.previewScrollID)"), 1)
        self.assertIn(
            "proxy.scrollTo(ImageTranslationPanel.previewScrollID, anchor: .top)",
            self.view,
        )
        toggle = braced_body(self.view, "private func toggleSelection(of blockID: UUID)")
        self.assertIn("selectedImageTranslationBlockID = nil", toggle)
        self.assertEqual(toggle.count("revealPreview()"), 1)
        self.assertGreater(toggle.index("} else {"), toggle.index("selectedImageTranslationBlockID = nil"))
        self.assertGreater(toggle.index("revealPreview()"), toggle.index("} else {"))

    def test_scrolling_respects_reduce_motion(self) -> None:
        self.assertIn("@Environment(\\.accessibilityReduceMotion) private var reduceMotion", self.view)
        reveal = braced_body(self.view, "private func revealImagePreview(using proxy: ScrollViewProxy)")
        self.assertIn("if reduceMotion", reveal)
        self.assertIn("withAnimation(AppTheme.Motion.standard)", reveal)
        self.assertLess(reveal.index("if reduceMotion"), reveal.index("withAnimation"))

    def test_navigation_uses_current_visible_filter_order_and_bounds(self) -> None:
        self.assertIn("visibleImageTranslationBlocks.firstIndex", self.view)
        self.assertIn("visibleImageTranslationBlocks.indices.contains(targetIndex)", self.view)
        navigation = braced_body(self.view, "private func selectAdjacentBlock(offset: Int)")
        self.assertTrue(
            "selectedImageTranslationBlockID = visibleImageTranslationBlocks[targetIndex].id" in navigation
            or (
                "let targetBlockID = visibleImageTranslationBlocks[targetIndex].id" in navigation
                and "selectedImageTranslationBlockID = targetBlockID" in navigation
            ),
            "adjacent navigation must assign the visible target block, directly or through a local target ID",
        )
        self.assertIn("selectAdjacentBlock(offset: -1)", self.view)
        self.assertIn("selectAdjacentBlock(offset: 1)", self.view)

    def test_previous_and_next_commands_are_named_bounded_targets(self) -> None:
        self.assertIn(
            'Button("上一个文字块", systemImage: "chevron.left", action: selectPrevious)',
            self.view,
        )
        self.assertIn(
            'Button("下一个文字块", systemImage: "chevron.right", action: selectNext)',
            self.view,
        )
        self.assertGreaterEqual(
            self.view.count(
                ".frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)"
            ),
            2,
        )
        self.assertIn(".disabled(!canSelectPrevious)", self.view)
        self.assertIn(".disabled(!canSelectNext)", self.view)

    def test_position_is_visible_and_in_the_accessibility_value(self) -> None:
        self.assertIn('return "\\(selectedVisibleBlockIndex + 1) / \\(visibleImageTranslationBlocks.count)"', self.view)
        self.assertIn("Text(positionText)", self.view)
        self.assertIn('.accessibilityValue("\\(positionText)，\\(accessibilityOriginalText)")', self.view)
        self.assertIn('block.original.isEmpty ? "空" : block.original', self.view)

    def test_navigation_remains_view_private(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.assertNotIn("previewScrollID", store)
        self.assertNotIn("selectedVisibleBlockIndex", store)
        self.assertNotIn("selectAdjacentBlock", store)

    def test_ci_runs_v314_after_v313(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        contract_step = workflow[
            workflow.index("- name: UI interaction contract"):
            workflow.index("- name: v1.88 home UI contract")
        ]
        self.assertLess(
            contract_step.index("scripts/test-v313-image-block-focus-contract.py"),
            contract_step.index("scripts/test-v314-image-review-navigation-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

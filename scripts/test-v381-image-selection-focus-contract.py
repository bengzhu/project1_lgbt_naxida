#!/usr/bin/env python3
"""Contract for VoiceOver focus handoff after direct image-block selection."""

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


class ImageSelectionFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.preview = braced_body(
            self.view,
            "private struct ImageTranslationPreview: View",
        )

    def test_result_row_selection_moves_focus_to_the_new_preview(self) -> None:
        selection = braced_body(self.panel, "private func toggleSelection(of blockID: UUID)")
        self.assertIn("selectedImageTranslationBlockID = blockID", selection)
        self.assertIn("revealPreview()", selection)
        self.assertIn(
            "moveReviewAccessibilityFocus(to: reviewPreviewAccessibilityFocusID(blockID))",
            selection,
        )
        self.assertIn("select: { toggleSelection(of: block.id) }", self.panel)

    def test_direct_preview_selection_uses_preview_focus_and_deselects_to_the_row(self) -> None:
        selection = braced_body(
            self.panel,
            "private func selectBlockFromPreview(_ blockID: UUID)",
        )
        self.assertIn("selectedImageTranslationBlockID == blockID", selection)
        self.assertIn("selectedImageTranslationBlockID = nil", selection)
        self.assertIn(
            "moveReviewAccessibilityFocus(to: reviewRowAccessibilityFocusID(blockID))",
            selection,
        )
        self.assertIn("!visibleImageTranslationBlocks.contains", selection)
        self.assertIn("reviewFilter = .all", selection)
        self.assertIn(
            "moveReviewAccessibilityFocus(to: reviewPreviewAccessibilityFocusID(blockID))",
            selection,
        )
        self.assertIn("select: { selectBlock(block.id) }", self.preview)

    def test_selection_focus_remains_view_private(self) -> None:
        self.assertIn(
            "@AccessibilityFocusState private var reviewAccessibilityFocusID: String?",
            self.panel,
        )
        self.assertNotIn("selectedImageTranslationBlockID", self.store)
        self.assertNotIn("reviewFilter", self.store)
        self.assertNotIn("VisionOCRService", self.panel)
        self.assertNotIn("VisionOCRService", self.preview)

    def test_version_and_ci_route_follow_v380(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3.81;"), 2)
        self.assertNotIn("MARKETING_VERSION = 3.80;", self.project)
        old = "python3 -B scripts/test-v380-image-review-filter-focus-contract.py"
        new = "python3 -B scripts/test-v381-image-selection-focus-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74|75|76|77|78|79|80|81)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

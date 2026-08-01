#!/usr/bin/env python3
"""Contract for focus handoff when the image review filter hides the selection."""

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


class ImageReviewFilterFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.inspector = braced_body(self.panel, "private var inspector: some View")

    def test_hidden_selection_clears_and_moves_focus_to_a_live_destination(self) -> None:
        clear = braced_body(self.panel, "private func clearHiddenReviewSelection()")
        self.assertIn("visibleImageTranslationBlocks.contains", clear)
        self.assertIn("self.selectedImageTranslationBlockID = nil", clear)
        self.assertIn("let nextFocusID = visibleImageTranslationBlocks.first.map", clear)
        self.assertIn("reviewRowAccessibilityFocusID($0.id)", clear)
        self.assertIn("Self.reviewCompletionAccessibilityFocusID", clear)
        self.assertIn("Self.reviewFilterAccessibilityFocusID", clear)
        self.assertIn("moveReviewAccessibilityFocus(to: nextFocusID)", clear)

    def test_filter_picker_is_a_focus_destination(self) -> None:
        self.assertIn('Picker("识别结果筛选", selection: $reviewFilter)', self.inspector)
        self.assertIn(
            ".accessibilityFocused(\n"
            "                    $reviewAccessibilityFocusID,\n"
            "                    equals: Self.reviewFilterAccessibilityFocusID",
            self.inspector,
        )
        self.assertIn(
            'private static let reviewFilterAccessibilityFocusID = "image-review-filter"',
            self.panel,
        )

    def test_filter_change_keeps_handoff_view_private(self) -> None:
        self.assertIn(".onChange(of: reviewFilter)", self.panel)
        self.assertIn("clearHiddenReviewSelection()", self.panel)
        self.assertNotIn("selectedImageTranslationBlockID", self.store)
        self.assertNotIn("reviewFilter", self.store)
        self.assertNotIn("VisionOCRService", self.panel)

    def test_version_and_ci_route_follow_v379(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.80;", self.project)
        old = "python3 -B scripts/test-v379-image-focus-preview-navigation-focus-contract.py"
        new = "python3 -B scripts/test-v380-image-review-filter-focus-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74|75|76|77|78|79|80|81)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

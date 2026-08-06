#!/usr/bin/env python3
"""Contracts for v3.15 direct selection from image preview overlays."""

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
                return source[brace:index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class ImagePreviewDirectSelectionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")

    def test_full_preview_overlays_are_direct_selection_buttons(self) -> None:
        preview = braced_body(self.view, "private struct ImageTranslationPreview: View")
        self.assertIn("ForEach(store.imageTranslationBlocks)", preview)
        self.assertIn("select: { selectBlock(block.id) }", preview)
        overlay = braced_body(self.view, "private struct ImageTranslationOverlayBlock: View")
        self.assertEqual(overlay.count("Button(action: select)"), 2)
        self.assertEqual(overlay.count(".buttonStyle(.plain)"), 2)

    def test_preview_selection_toggles_and_reveals_hidden_blocks(self) -> None:
        selection = braced_body(
            self.view,
            "private func selectBlockFromPreview(_ blockID: UUID)",
        )
        self.assertIn("selectedImageTranslationBlockID == blockID", selection)
        self.assertIn("selectedImageTranslationBlockID = nil", selection)
        self.assertIn("return", selection)
        self.assertIn("!visibleImageTranslationBlocks.contains", selection)
        filter_reset = re.search(
            r"reviewFilter = \.all|prepareReviewFilterChange\(\s*to: \.all",
            selection,
        )
        self.assertIsNotNone(filter_reset)
        self.assertLess(
            filter_reset.start(),
            selection.rindex("selectedImageTranslationBlockID = blockID"),
        )
        self.assertNotIn("revealPreview()", selection)

    def test_overlay_buttons_have_named_accessibility_and_minimum_targets(self) -> None:
        overlay = braced_body(self.view, "private struct ImageTranslationOverlayBlock: View")
        self.assertEqual(
            overlay.count(
                ".frame(minWidth: AppTheme.Layout.minimumTarget, minHeight: AppTheme.Layout.minimumTarget)"
            ),
            2,
        )
        self.assertEqual(overlay.count('.accessibilityLabel("图片文字块 \\(accessibilityOriginalText)")'), 2)
        self.assertEqual(overlay.count(".accessibilityValue(accessibilityValue)"), 2)
        self.assertEqual(overlay.count(".accessibilityHint(accessibilityHint)"), 2)
        self.assertIn("private var accessibilityHint: String", overlay)
        self.assertIn("isSelected ?", overlay)
        self.assertIn(": \"在图片预览中定位此文字块\"", overlay)

    def test_preview_selection_remains_view_private(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.assertNotIn("selectBlockFromPreview", store)
        self.assertNotIn("selectedImageTranslationBlockID", store)
        self.assertNotIn("reviewFilter = .all", store)

    def test_ci_runs_v315_after_v314(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        contract_step = workflow[
            workflow.index("- name: UI interaction contract"):
            workflow.index("- name: v1.88 home UI contract")
        ]
        self.assertLess(
            contract_step.index("scripts/test-v314-image-review-navigation-contract.py"),
            contract_step.index("scripts/test-v315-image-preview-direct-selection-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

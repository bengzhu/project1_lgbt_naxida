#!/usr/bin/env python3
"""Contracts for v3.12 local OCR row-to-overlay selection."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class ImageBlockSelectionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")

    def test_selection_is_view_private_and_never_store_owned(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.assertIn("@State private var selectedImageTranslationBlockID: UUID?", self.view)
        self.assertNotIn("selectedImageTranslationBlockID", store)
        self.assertNotIn("@Published var selectedImageTranslationBlock", store)

    def test_result_row_toggles_selection_with_non_color_identity(self) -> None:
        self.assertIn("select: { toggleSelection(of: block.id) }", self.view)
        self.assertIn("Button(action: select)", self.view)
        self.assertIn('Image(systemName: "viewfinder.circle.fill")', self.view)
        self.assertIn('accessibilityValue(isSelected ? "已在图片中定位" : "未定位")', self.view)
        self.assertIn("selectedImageTranslationBlockID == blockID", self.view)

    def test_preview_highlights_only_the_matching_full_product_block(self) -> None:
        self.assertIn("selectedBlockID: selectedImageTranslationBlockID", self.view)
        self.assertIn("ForEach(store.imageTranslationBlocks)", self.view)
        self.assertIn("isSelected: selectedBlockID == block.id", self.view)
        self.assertIn("selectionBorder", self.view)
        self.assertNotIn("ForEach(visibleImageTranslationBlocks) { block in\n                            ImageTranslationOverlayBlock", self.view)

    def test_revision_and_hidden_filter_selection_are_cleared(self) -> None:
        self.assertIn(".onChange(of: store.imageTranslationRevision)", self.view)
        self.assertIn("selectedImageTranslationBlockID = nil", self.view)
        self.assertIn(".onChange(of: reviewFilter)", self.view)
        self.assertIn("clearHiddenReviewSelection()", self.view)
        self.assertIn("visibleImageTranslationBlocks.contains", self.view)

    def test_ci_runs_v312_after_v311(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        contract_step = workflow[
            workflow.index("- name: UI interaction contract"):
            workflow.index("- name: v1.88 home UI contract")
        ]
        self.assertLess(
            contract_step.index("scripts/test-v311-image-preview-state-contract.py"),
            contract_step.index("scripts/test-v312-image-block-selection-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

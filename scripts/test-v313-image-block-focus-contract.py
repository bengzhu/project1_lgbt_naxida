#!/usr/bin/env python3
"""Contracts for v3.13 selected OCR block focus preview."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class ImageBlockFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")

    def test_focus_uses_selected_full_product_block_and_preview_thumbnail(self) -> None:
        self.assertIn(
            "store.imageTranslationBlocks.first(where: { $0.id == selectedBlockID })",
            self.view,
        )
        self.assertIn("ImageTranslationFocusPreview(", self.view)
        self.assertIn("previewImage: previewImage", self.view)
        self.assertNotIn("imageTranslationData: store.imageTranslationData", self.view)

    def test_focus_crop_keeps_context_and_clamps_to_normalized_image(self) -> None:
        self.assertIn("max(sourceRect.width * 1.8, 0.16)", self.view)
        self.assertIn("max(sourceRect.height * 1.8, 0.10)", self.view)
        self.assertIn("let targetAspectRatio: CGFloat = 16.0 / 9.0", self.view)
        self.assertIn(".intersection(CGRect(x: 0, y: 0, width: 1, height: 1))", self.view)
        self.assertIn("sourceImage.cropping(to: pixelRect)", self.view)

    def test_focus_retains_non_color_bbox_identity(self) -> None:
        self.assertIn(".strokeBorder(Color.appWarning, lineWidth: 4)", self.view)
        self.assertIn("max(fittedSize.width * relativeRect.width, 24)", self.view)
        self.assertIn('Label("局部放大", systemImage: "magnifyingglass")', self.view)
        self.assertIn('accessibilityLabel("已定位文字块局部放大")', self.view)
        self.assertIn('.accessibilityValue("\\(positionText)，\\(block.original)")', self.view)

    def test_close_is_named_and_has_minimum_tap_target(self) -> None:
        self.assertIn(
            'Button("关闭局部放大", systemImage: "xmark", action: close)',
            self.view,
        )
        self.assertIn(".frame(minWidth: 44, minHeight: 44)", self.view)
        self.assertIn("clearSelection: { selectedImageTranslationBlockID = nil }", self.view)

    def test_focus_state_does_not_enter_store_or_product_pipeline(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        renderer = store[store.index("renderImageTranslationOverlay"):]
        self.assertNotIn("ImageTranslationFocusPreview", store)
        self.assertNotIn("normalizedFocusRect", store)
        self.assertNotIn("selectedBlockID", renderer)

    def test_ci_runs_v313_after_v312(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        contract_step = workflow[
            workflow.index("- name: UI interaction contract"):
            workflow.index("- name: v1.88 home UI contract")
        ]
        self.assertLess(
            contract_step.index("scripts/test-v312-image-block-selection-contract.py"),
            contract_step.index("scripts/test-v313-image-block-focus-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

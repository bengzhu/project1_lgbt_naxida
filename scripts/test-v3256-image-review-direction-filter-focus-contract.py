#!/usr/bin/env python3
"""Contract for keeping image-review focus valid after direction filter changes."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def braced_body(source: str, signature: str) -> str:
    start = source.index(signature)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace : index + 1]
    raise AssertionError(f"unterminated body for {signature}")


class ImageReviewDirectionFilterFocusContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.view = read("AITRANS/Views/ImageTranslationViews.swift")
        cls.direction = braced_body(
            cls.view,
            "private func setImageTranslationBlockDirection(\n",
        )
        cls.sheet_dismissal = braced_body(
            cls.view,
            "private func applyPendingCorrectionSheetDismissalFocus()",
        )
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.filter = read("AITRANS/Models/ImageOCRReviewFilter.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def test_direction_update_re_resolves_visible_selection_and_focus(self) -> None:
        self.assertIn(
            "deferFocusUntilCorrectionSheetDismissal: Bool = false",
            self.view,
        )
        for marker in [
            "visibleImageTranslationBlocks.contains(where: { $0.id == blockID })",
            "selectedImageTranslationBlockID = nil",
            "reviewFocusIDAfterHiddenDirectionBlock()",
            "moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(to: focusID)",
            "moveReviewAccessibilityFocus(to: focusID)",
        ]:
            self.assertIn(marker, self.direction)

        hidden_branch = self.direction.index(
            "selectedImageTranslationBlockID = nil"
        )
        fallback = self.direction.index(
            "focusID = reviewFocusIDAfterHiddenDirectionBlock()",
            hidden_branch,
        )
        self.assertLess(hidden_branch, fallback)

    def test_hidden_direction_block_uses_visible_row_or_filter_empty_state(self) -> None:
        helper = braced_body(
            self.view,
            "private func reviewFocusIDAfterHiddenDirectionBlock()",
        )
        for marker in [
            "visibleImageTranslationBlocks.first",
            "reviewFilter == .needsReview, reviewCompletedBlockCount > 0",
            "Self.reviewCompletionAccessibilityFocusID",
            "Self.reviewFilterAccessibilityFocusID",
            "Self.reviewFilterEmptyAccessibilityFocusID",
        ]:
            self.assertIn(marker, helper)
        self.assertIn("effectiveSourceDirection", self.filter)

    def test_correction_sheet_dismissal_rejects_stale_row_and_preview_focus(self) -> None:
        for marker in [
            "focusAfterHiddenCorrectionSheetTargetIfNeeded(focusID)",
            "return",
            "moveReviewAccessibilityFocus(to: focusID)",
        ]:
            self.assertIn(marker, self.sheet_dismissal)
        validator = braced_body(
            self.view,
            "private func focusAfterHiddenCorrectionSheetTargetIfNeeded(",
        )
        for marker in [
            "isVisibleReviewBlockFocusID",
            'focusID.hasPrefix("image-review-row-")',
            'focusID.hasPrefix("image-review-preview-")',
            "selectedImageTranslationBlockID = nil",
            "reviewFocusIDAfterHiddenDirectionBlock()",
        ]:
            self.assertIn(marker, validator)

    def test_sheet_direction_picker_uses_the_same_focus_safe_path(self) -> None:
        self.assertIn(
            "setImageTranslationBlockDirection(\n                        direction,\n                        for: block.id,\n                        focusInPreview: false,\n                        deferFocusUntilCorrectionSheetDismissal: true",
            self.view,
        )
        self.assertNotIn(
            "store.setImageTranslationBlockDirectionOverride(\n                        block.id,\n                        direction: direction\n                    )",
            self.view,
        )
        self.assertIn(
            "setImageTranslationBlockDirectionOverride(blockID, direction: direction)",
            self.direction,
        )
        self.assertNotIn("recognizeTextBlock(", self.direction)
        self.assertNotIn("rerunImageRecognition", self.direction)

    def test_ci_routes_ocr_resources_and_current_contract(self) -> None:
        self.assertIn(
            "AITRANS/Services/(ImageOCRLayoutEngine|TranslationSessionStore|VisionOCRService|ImagePreviewService|MangaOCRService)",
            self.workflow,
        )
        self.assertIn("AITRANS/Resources/MangaOCR/", self.workflow)
        self.assertIn(
            "scripts/test-v3256-image-review-direction-filter-focus-contract.py",
            self.workflow,
        )
        self.assertEqual(
            set(re.findall(r"MARKETING_VERSION = ([^;]+);", self.project)),
            {"3.256"},
        )
        self.assertIn(
            "python3 -B scripts/test-v3255-image-japanese-manga-ocr-batch-eos-alignment-contract.py",
            self.workflow,
        )

    def test_store_direction_override_stays_display_and_export_only(self) -> None:
        setter = braced_body(
            self.store,
            "func setImageTranslationBlockDirectionOverride(\n",
        )
        for marker in [
            "sourceDirectionOverride = direction",
            "updateImageTranslationTranscript(blocks: imageTranslationBlocks)",
            "rerenderImageTranslationExport()",
        ]:
            self.assertIn(marker, setter)
        for forbidden in [
            "recognizeTextBlock(",
            "recognizeJapaneseMangaOCR(",
            "rerunImageRecognition()",
        ]:
            self.assertNotIn(forbidden, setter)


if __name__ == "__main__":
    unittest.main(verbosity=2)

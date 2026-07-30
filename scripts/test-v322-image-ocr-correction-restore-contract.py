#!/usr/bin/env python3
"""Static contracts for v3.22 restoring manually corrected image OCR blocks."""

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


class ImageOCRCorrectionRestoreContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")

    def test_store_keeps_a_private_first_vision_baseline_per_block(self) -> None:
        self.assertIn(
            "private var imageTranslationVisionOriginalBlocks: [UUID: ImageTranslationBlock] = [:]",
            self.store,
        )
        correction = braced_body(self.store, "func correctImageTranslationBlock(")
        capture = "if imageTranslationVisionOriginalBlocks[blockID] == nil"
        self.assertIn(capture, correction)
        self.assertIn("imageTranslationVisionOriginalBlocks[blockID] = currentBlock", correction)
        self.assertLess(
            correction.index(capture),
            correction.index("correctedBlock.original = correctedOriginal"),
        )

    def test_new_image_and_clear_forget_the_nonpersistent_baselines(self) -> None:
        for marker in [
            "private func beginImageTranslationTask(",
            "func clearImageTranslation()",
        ]:
            body = braced_body(self.store, marker)
            self.assertIn("imageTranslationVisionOriginalBlocks = [:]", body)

    def test_restore_is_store_owned_and_never_retranslates(self) -> None:
        restore = braced_body(
            self.store,
            "func restoreImageTranslationBlockToVisionOCR(_ blockID: UUID) -> Bool",
        )
        self.assertIn("imageTranslationCorrectionBlockID == nil", restore)
        self.assertIn("imageTranslationState == .translated", restore)
        self.assertIn("imageTranslationVisionOriginalBlocks[blockID]", restore)
        self.assertIn("firstIndex(where: { $0.id == blockID })", restore)
        self.assertNotIn("translate(", restore)
        markers = [
            "imageTranslationBlocks[blockIndex] = originalBlock",
            "imageTranslationVisionOriginalBlocks.removeValue(forKey: blockID)",
            "imageTranslationCorrectedBlockIDs.remove(blockID)",
            "updateImageTranslationTranscript(blocks: imageTranslationBlocks)",
            "invalidateImageOverlayRender()",
            "discardImageTranslationExport()",
            "rerenderImageTranslationExport()",
        ]
        for marker in markers:
            self.assertIn(marker, restore)
        positions = [restore.index(marker) for marker in markers]
        self.assertEqual(positions, sorted(positions))

    def test_restore_control_is_named_accessible_and_minimum_sized(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        self.assertIn("if isManuallyCorrected", row)
        self.assertIn(
            'Button("恢复 Vision OCR", systemImage: "arrow.counterclockwise", action: restoreVisionOCR)',
            row,
        )
        self.assertIn("AppTheme.Layout.minimumTarget", row)
        self.assertIn("恢复此文字块的 Vision OCR 原文与初始译文", row)
        self.assertIn(".disabled(!canEdit)", row)

    def test_restore_reopens_local_review_and_returns_voiceover_to_the_row(self) -> None:
        action = braced_body(self.view, "private func restoreVisionOCR(for blockID: UUID)")
        self.assertIn("store.restoreImageTranslationBlockToVisionOCR(blockID)", action)
        self.assertIn("reviewedImageTranslationBlockIDs.remove(blockID)", action)
        self.assertIn("selectedImageTranslationBlockID = blockID", action)
        self.assertIn("moveReviewAccessibilityFocus(to: reviewRowAccessibilityFocusID(blockID))", action)

    def test_ci_runs_v322_after_v321(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        old = "python3 -B scripts/test-v321-image-ocr-correction-contract.py"
        new = "python3 -B scripts/test-v322-image-ocr-correction-restore-contract.py"
        self.assertIn(new, workflow)
        self.assertLess(workflow.index(old), workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

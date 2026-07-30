#!/usr/bin/env python3
"""Static contracts for v3.21 image OCR manual correction."""

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


class ImageOCRCorrectionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")

    def test_store_owns_correction_state_and_rejects_empty_text(self) -> None:
        self.assertIn(
            "@Published private(set) var imageTranslationCorrectionBlockID: UUID?",
            self.store,
        )
        self.assertIn(
            "@Published private(set) var imageTranslationCorrectedBlockIDs: Set<UUID>",
            self.store,
        )
        correction = braced_body(self.store, "func correctImageTranslationBlock(")
        self.assertIn("trimmingCharacters(in: .whitespacesAndNewlines)", correction)
        self.assertIn("guard !correctedOriginal.isEmpty", correction)
        self.assertIn("imageTranslationState == .translated", correction)

    def test_only_target_block_is_retranslated_with_content_identity_isolation(self) -> None:
        correction = braced_body(self.store, "func correctImageTranslationBlock(")
        self.assertEqual(correction.count("try await translate("), 1)
        self.assertIn("let contentTaskID = imageTranslationTaskID", correction)
        self.assertIn("imageTranslationCorrectionID == correctionID", correction)
        self.assertIn("imageTranslationTaskID == contentTaskID", correction)
        self.assertIn("firstIndex(where: { $0.id == blockID })", correction)
        self.assertIn(
            "imageTranslationBlocks[currentIndex].original == currentBlock.original",
            correction,
        )

    def test_success_commits_block_history_then_invalidates_and_rerenders(self) -> None:
        correction = braced_body(self.store, "func correctImageTranslationBlock(")
        markers = [
            "correctedBlock.original = correctedOriginal",
            "correctedBlock.translation = correctedTranslation",
            "imageTranslationBlocks[currentIndex] = correctedBlock",
            "updateImageTranslationTranscript(blocks: imageTranslationBlocks)",
            "invalidateImageOverlayRender()",
            "discardImageTranslationExport()",
            "rerenderImageTranslationExport()",
        ]
        for marker in markers:
            self.assertIn(marker, correction)
        positions = [correction.index(marker) for marker in markers]
        self.assertEqual(positions, sorted(positions))

    def test_failure_restores_completed_state_without_mutating_the_block(self) -> None:
        correction = braced_body(self.store, "func correctImageTranslationBlock(")
        failure = correction[correction.rindex("} catch {") :]
        self.assertIn("imageTranslationCorrectionID == correctionID", failure)
        self.assertIn("imageTranslationTaskID == contentTaskID", failure)
        self.assertIn("imageTranslationState = .translated", failure)
        self.assertNotIn("correctedBlock.original", failure)
        self.assertNotIn("imageTranslationBlocks[currentIndex]", failure)

    def test_new_image_clear_and_cancel_invalidate_pending_correction(self) -> None:
        for marker in [
            "private func beginImageTranslationTask(",
            "func clearImageTranslation()",
            "func cancelImageTranslation()",
        ]:
            self.assertIn(
                "invalidateImageTranslationCorrection()",
                braced_body(self.store, marker),
            )
        invalidate = braced_body(
            self.store,
            "private func invalidateImageTranslationCorrection()",
        )
        self.assertIn("imageTranslationCorrectionID = UUID()", invalidate)
        self.assertIn("imageTranslationCorrectionBlockID = nil", invalidate)

    def test_editor_is_accessible_validated_and_blocks_dismissal_while_saving(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        editor = braced_body(self.view, "private struct ImageOCRCorrectionSheet: View")
        self.assertIn('Button("修正识别文字", systemImage: "pencil", action: edit)', row)
        self.assertIn("AppTheme.Layout.minimumTarget", row)
        self.assertIn("编辑 OCR 原文并只重新翻译此文字块", row)
        self.assertIn('TextField("修正后的文字"', editor)
        self.assertIn('Button("保存并重译", action: save)', editor)
        self.assertIn(".disabled(!canSave || isSaving)", editor)
        self.assertIn(".interactiveDismissDisabled(isSaving)", editor)
        self.assertIn('ProgressView("正在重新翻译")', editor)

    def test_successful_risk_correction_advances_the_review_queue(self) -> None:
        completion = braced_body(
            self.view,
            "private func completeReviewAfterCorrection(_ blockID: UUID)",
        )
        self.assertIn("allReviewRequiredBlocks.contains", completion)
        self.assertIn("reviewedImageTranslationBlockIDs.insert(blockID)", completion)
        self.assertIn("let nextBlockID = reviewRequiredBlocks.first?.id", completion)
        self.assertIn("Self.reviewCompletionAccessibilityFocusID", completion)

    def test_ci_runs_v321_after_v320(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        old = "python3 -B scripts/test-v320-image-review-voiceover-focus-contract.py"
        new = "python3 -B scripts/test-v321-image-ocr-correction-contract.py"
        self.assertIn(new, workflow)
        self.assertLess(workflow.index(old), workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

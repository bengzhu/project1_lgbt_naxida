#!/usr/bin/env python3
"""Static contracts for v3.41 finalized-image review interaction locking."""

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


class ImageReviewFinalStateLockContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_mutating_image_actions_require_a_finalized_result(self) -> None:
        can_modify = braced_body(self.panel, "private var canModifyImageTranslation: Bool")
        self.assertIn("store.imageTranslationState == .translated", can_modify)
        self.assertIn("!isRenderingExport", can_modify)

        for marker in [
            "private func beginCorrection(of block: ImageTranslationBlock)",
            "private func beginCorrectionFromFocusPreview(of block: ImageTranslationBlock)",
            "private func restoreIgnoredImageTranslationBlock(_ block: ImageTranslationBlock)",
        ]:
            self.assertIn("canModifyImageTranslation", braced_body(self.panel, marker))

        restore = braced_body(
            self.panel,
            "private func requestVisionOCRRestore(\n"
            "        for block: ImageTranslationBlock,\n"
            "        focusOrigin: ImageTranslationRestoreFocusOrigin",
        )
        self.assertIn("canModifyImageTranslation", restore)
        self.assertIn("store.imageTranslationCorrectedBlockIDs.contains(block.id)", restore)

    def test_review_controls_stay_visible_but_lock_until_translation_finishes(self) -> None:
        can_review = braced_body(self.panel, "private var canReviewImageTranslation: Bool")
        self.assertIn("store.imageTranslationState == .translated", can_review)

        inspector = braced_body(self.panel, "private var inspector: some View")
        self.assertGreaterEqual(inspector.count(".disabled(!canReviewImageTranslation)"), 2)
        self.assertGreaterEqual(inspector.count(": imageReviewUnavailableDetail"), 2)
        self.assertIn("canEdit: canModifyImageTranslation", inspector)
        self.assertIn("canReview: canReviewImageTranslation", inspector)
        self.assertIn("canRestore: canModifyImageTranslation", inspector)

        preview = braced_body(self.view, "private struct ImageTranslationPreview: View")
        self.assertIn("let canReview: Bool", preview)
        self.assertIn("let reviewUnavailableHint: String", preview)
        self.assertIn("canReview: canReview", preview)
        self.assertIn("reviewUnavailableHint: reviewUnavailableHint", preview)

        focus = braced_body(self.view, "private struct ImageTranslationFocusPreview: View")
        self.assertIn("let canReview: Bool", focus)
        self.assertIn("let reviewUnavailableHint: String", focus)
        self.assertIn(".disabled(!canReview)", focus)
        self.assertIn(": reviewUnavailableHint", focus)

        row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        self.assertIn("let canReview: Bool", row)
        self.assertIn("let reviewUnavailableHint: String", row)
        self.assertIn(".disabled(!canReview)", row)
        self.assertIn(": reviewUnavailableHint", row)

    def test_panel_and_store_reject_premature_review_progress_mutation(self) -> None:
        for marker in [
            "private func beginReviewQueue()",
            "private func toggleReviewCompletion(_ blockID: UUID, focusInPreview: Bool)",
            "private func restartReviewQueue()",
        ]:
            self.assertIn("canReviewImageTranslation", braced_body(self.panel, marker))

        for marker in [
            "func markImageTranslationBlockReviewed(_ blockID: UUID) -> Bool",
            "func reopenImageTranslationBlockReview(_ blockID: UUID) -> Bool",
            "func resetImageTranslationReviewProgress()",
        ]:
            self.assertIn("guard imageTranslationState == .translated", braced_body(self.store, marker))

    def test_successful_correction_restores_final_state_before_marking_reviewed(self) -> None:
        correction = braced_body(self.store, "func correctImageTranslationBlock(")
        success_start = correction.index("imageTranslationBlocks[currentIndex] = correctedBlock")
        success = correction[success_start:]
        self.assertLess(
            success.index("imageTranslationCorrectionBlockID = nil"),
            success.index("imageTranslationState = .translated"),
        )
        self.assertLess(
            success.index("imageTranslationState = .translated"),
            success.index("markImageTranslationBlockReviewed(blockID)"),
        )

    def test_ci_runs_v341_after_v340(self) -> None:
        old = "python3 -B scripts/test-v340-image-ocr-correction-save-lock-contract.py"
        new = "python3 -B scripts/test-v341-image-review-final-state-lock-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v341-image-review-final-state-lock-contract.py' "
            "\"$RESULT_ROOT/changed-files.txt\" >/dev/null; then"
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

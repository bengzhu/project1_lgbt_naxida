#!/usr/bin/env python3
"""Static contracts for v3.28 current-image review session continuity."""

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


class ImageReviewSessionContinuityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")

    def test_store_is_the_single_owner_for_current_image_review_progress(self) -> None:
        self.assertIn(
            "@Published private(set) var imageTranslationReviewedBlockIDs: Set<UUID> = []",
            self.store,
        )
        self.assertNotIn("@State private var reviewedImageTranslationBlockIDs", self.view)
        self.assertIn(
            "reviewedBlockIDs: store.imageTranslationReviewedBlockIDs",
            self.view,
        )
        self.assertIn(
            "isReviewCompleted: store.imageTranslationReviewedBlockIDs.contains(block.id)",
            self.view,
        )

    def test_review_state_resets_only_when_the_current_image_session_is_replaced_or_abandoned(self) -> None:
        for marker in [
            "private func beginImageTranslationTask(",
            "func clearImageTranslation()",
            "func cancelImageTranslation()",
        ]:
            self.assertIn(
                "imageTranslationReviewedBlockIDs = []",
                braced_body(self.store, marker),
            )

    def test_store_transition_api_is_risk_scoped_and_supports_reset(self) -> None:
        mark = braced_body(
            self.store,
            "func markImageTranslationBlockReviewed(_ blockID: UUID) -> Bool",
        )
        self.assertIn("imageTranslationBlocks.first(where: { $0.id == blockID })", mark)
        self.assertIn("ImageOCRResultSummary.requiresReview(block)", mark)
        self.assertIn("imageTranslationReviewedBlockIDs.insert(blockID)", mark)

        reopen = braced_body(
            self.store,
            "func reopenImageTranslationBlockReview(_ blockID: UUID) -> Bool",
        )
        self.assertIn("ImageOCRResultSummary.requiresReview(block)", reopen)
        self.assertIn("imageTranslationReviewedBlockIDs.remove(blockID)", reopen)

        reset = braced_body(
            self.store,
            "func resetImageTranslationReviewProgress()",
        )
        self.assertIn("imageTranslationReviewedBlockIDs = []", reset)

    def test_correction_and_restore_keep_review_progress_consistent(self) -> None:
        correction = braced_body(self.store, "func correctImageTranslationBlock(")
        self.assertGreaterEqual(correction.count("markImageTranslationBlockReviewed(blockID)"), 2)

        restore = braced_body(
            self.store,
            "func restoreImageTranslationBlockToVisionOCR(_ blockID: UUID) -> Bool",
        )
        self.assertIn("imageTranslationReviewedBlockIDs.remove(blockID)", restore)

    def test_view_preserves_queue_order_and_accessibility_focus_while_delegating_mutation(self) -> None:
        transition = braced_body(
            self.view,
            "private func toggleReviewCompletion(_ blockID: UUID, focusInPreview: Bool)",
        )
        self.assertIn("store.reopenImageTranslationBlockReview(blockID)", transition)
        self.assertIn("store.markImageTranslationBlockReviewed(blockID)", transition)
        self.assertIn("selectedImageTranslationBlockID = nextBlockID", transition)
        self.assertIn("moveReviewAccessibilityFocus(to: nextFocusID)", transition)

        restart = braced_body(self.view, "private func restartReviewQueue()")
        self.assertIn("store.resetImageTranslationReviewProgress()", restart)
        self.assertIn("revealPreview()", restart)

    def test_ci_runs_v328_after_v327(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        old = "python3 -B scripts/test-v327-image-ocr-correction-reference-context-contract.py"
        new = "python3 -B scripts/test-v328-image-review-session-continuity-contract.py"
        self.assertIn(new, workflow)
        self.assertLess(workflow.index(old), workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

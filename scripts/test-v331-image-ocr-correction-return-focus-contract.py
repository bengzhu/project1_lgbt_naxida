#!/usr/bin/env python3
"""Static contracts for v3.31 OCR correction result-row focus return."""

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


class ImageOCRCorrectionReturnFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_completion_rejects_an_inactive_block_before_scheduling_focus(self) -> None:
        completion = braced_body(
            self.panel,
            "private func completeReviewAfterCorrection(_ blockID: UUID)",
        )
        self.assertIn(
            "guard store.imageTranslationBlocks.contains(where: { $0.id == blockID }) else { return }",
            completion,
        )

    def test_only_the_active_needs_review_queue_advances_after_correction(self) -> None:
        completion = braced_body(
            self.panel,
            "private func completeReviewAfterCorrection(_ blockID: UUID)",
        )
        for marker in [
            "let shouldAdvanceReviewQueue = reviewFilter == .needsReview",
            "allReviewRequiredBlocks.contains(where: { $0.id == blockID })",
            "store.imageTranslationReviewedBlockIDs.contains(blockID)",
            "guard shouldAdvanceReviewQueue else",
            "let nextBlockID = reviewRequiredBlocks.first?.id",
            "Self.reviewCompletionAccessibilityFocusID",
        ]:
            self.assertIn(marker, completion)

    def test_non_queue_success_returns_to_the_updated_result_row_after_sheet_dismissal(self) -> None:
        completion = braced_body(
            self.panel,
            "private func completeReviewAfterCorrection(_ blockID: UUID)",
        )
        self.assertIn(
            "moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(\n"
            "                to: reviewRowAccessibilityFocusID(blockID)",
            completion,
        )
        self.assertNotIn("moveReviewAccessibilityFocus(to: reviewRowAccessibilityFocusID(blockID))", completion)

        schedule = braced_body(
            self.panel,
            "private func moveReviewAccessibilityFocusAfterCorrectionSheetDismissal",
        )
        self.assertIn("pendingCorrectionSheetDismissalRevision = store.imageTranslationRevision", schedule)
        self.assertIn(
            "onDismiss: applyPendingCorrectionSheetDismissalFocus",
            self.panel,
        )

    def test_return_focus_remains_view_private_and_does_not_change_correction_ownership(self) -> None:
        self.assertNotIn("shouldAdvanceReviewQueue", self.store)
        self.assertNotIn("pendingCorrectionSheetDismissalFocus", self.store)
        completion = braced_body(
            self.panel,
            "private func completeReviewAfterCorrection(_ blockID: UUID)",
        )
        self.assertNotIn("correctImageTranslationBlock(", completion)
        self.assertNotIn("VisionOCRService", completion)

    def test_ci_routes_v331_after_v330(self) -> None:
        old = (
            "python3 -B "
            "scripts/test-v330-image-ocr-correction-sheet-focus-handoff-contract.py"
        )
        new = (
            "python3 -B "
            "scripts/test-v331-image-ocr-correction-return-focus-contract.py"
        )
        route = (
            "if grep -Fx "
            "'scripts/test-v331-image-ocr-correction-return-focus-contract.py' "
            "\"$RESULT_ROOT/changed-files.txt\" >/dev/null; then"
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

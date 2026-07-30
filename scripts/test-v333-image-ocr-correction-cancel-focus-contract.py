#!/usr/bin/env python3
"""Static contracts for v3.33 OCR correction cancellation focus return."""

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


class ImageOCRCorrectionCancelFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.editor = braced_body(
            self.view,
            "private struct ImageOCRCorrectionSheet: View",
        )

    def test_opening_a_correction_registers_its_result_row_as_the_dismissal_fallback(self) -> None:
        begin = braced_body(
            self.panel,
            "private func beginCorrection(of block: ImageTranslationBlock)",
        )
        schedule = (
            "moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(\n"
            "            to: reviewRowAccessibilityFocusID(block.id)\n"
            "        )"
        )
        self.assertIn("selectedImageTranslationBlockID = block.id", begin)
        self.assertIn(schedule, begin)
        self.assertIn("editingImageTranslationBlock = block", begin)
        self.assertLess(begin.index(schedule), begin.index("editingImageTranslationBlock = block"))
        self.assertNotIn("moveReviewAccessibilityFocus(to:", begin)
        self.assertNotIn("correctImageTranslationBlock(", begin)

    def test_dismissal_publishes_the_registered_fallback_only_after_the_sheet_closes(self) -> None:
        self.assertIn(
            "item: $editingImageTranslationBlock,\n"
            "            onDismiss: applyPendingCorrectionSheetDismissalFocus",
            self.panel,
        )
        apply = braced_body(
            self.panel,
            "private func applyPendingCorrectionSheetDismissalFocus()",
        )
        self.assertIn("guard let focusID = pendingCorrectionSheetDismissalFocusID", apply)
        self.assertIn(
            "pendingCorrectionSheetDismissalRevision == store.imageTranslationRevision",
            apply,
        )
        self.assertIn("clearPendingCorrectionSheetDismissalFocus()", apply)
        self.assertIn("moveReviewAccessibilityFocus(to: focusID)", apply)

    def test_cancel_discard_and_clean_interactive_dismissal_keep_the_same_sheet_close_path(self) -> None:
        request = braced_body(self.editor, "private func requestDismiss()")
        self.assertIn("guard hasUnsavedChanges else", request)
        self.assertIn("dismiss()", request)
        self.assertNotIn("moveReviewAccessibilityFocus(to:", request)
        self.assertIn(
            'Button("放弃修正", role: .destructive, action: dismiss.callAsFunction)',
            self.editor,
        )
        self.assertIn(
            ".interactiveDismissDisabled(isSaving || hasUnsavedChanges)",
            self.editor,
        )

    def test_success_and_ignore_can_replace_the_opening_fallback_with_their_existing_destinations(self) -> None:
        completion = braced_body(
            self.panel,
            "private func completeReviewAfterCorrection(_ blockID: UUID)",
        )
        self.assertIn("moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(", completion)
        self.assertIn("Self.reviewCompletionAccessibilityFocusID", completion)

        ignore = braced_body(
            self.panel,
            "private func ignoreImageTranslationBlock(_ block: ImageTranslationBlock) -> Bool",
        )
        self.assertEqual(
            ignore.count("moveReviewAccessibilityFocusAfterCorrectionSheetDismissal("),
            2,
        )
        self.assertIn("ignoredRowAccessibilityFocusID(block.id)", ignore)

    def test_fallback_stays_view_private_and_is_rejected_after_an_image_revision_change(self) -> None:
        self.assertIn(
            "@State private var pendingCorrectionSheetDismissalFocusID: String?",
            self.panel,
        )
        self.assertNotIn("pendingCorrectionSheetDismissalFocus", self.store)
        revision = braced_body(
            self.panel,
            ".onChange(of: store.imageTranslationRevision)",
        )
        self.assertIn("editingImageTranslationBlock = nil", revision)
        self.assertIn("clearPendingCorrectionSheetDismissalFocus()", revision)
        self.assertIn("reviewAccessibilityFocusID = nil", revision)

    def test_ci_routes_v333_after_v332(self) -> None:
        old = "python3 -B scripts/test-v332-image-ocr-restore-focus-handoff-contract.py"
        new = "python3 -B scripts/test-v333-image-ocr-correction-cancel-focus-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v333-image-ocr-correction-cancel-focus-contract.py' "
            "\"$RESULT_ROOT/changed-files.txt\" >/dev/null; then"
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

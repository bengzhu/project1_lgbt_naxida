#!/usr/bin/env python3
"""Static contracts for v3.30 image OCR correction-sheet focus handoff."""

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


class ImageOCRCorrectionSheetFocusHandoffContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_pending_focus_is_view_private_not_store_or_persistence_state(self) -> None:
        self.assertIn(
            "@State private var pendingCorrectionSheetDismissalFocusID: String?",
            self.panel,
        )
        self.assertIn(
            "@State private var pendingCorrectionSheetDismissalRevision: Int?",
            self.panel,
        )
        self.assertNotIn("pendingCorrectionSheetDismissalFocus", self.store)

    def test_correction_sheet_applies_a_pending_focus_only_after_dismissal(self) -> None:
        self.assertIn(
            "item: $editingImageTranslationBlock,\n"
            "            onDismiss: applyPendingCorrectionSheetDismissalFocus",
            self.panel,
        )
        self.assertIn("completeReviewAfterCorrection(block.id)", self.panel)
        self.assertIn("ignoreImageTranslationBlock(block)", self.panel)

    def test_successful_sheet_actions_defer_existing_destinations(self) -> None:
        ignore = braced_body(
            self.panel,
            "private func ignoreImageTranslationBlock(_ block: ImageTranslationBlock) -> Bool",
        )
        self.assertGreaterEqual(
            ignore.count("moveReviewAccessibilityFocusAfterCorrectionSheetDismissal("),
            2,
        )
        self.assertIn("reviewRowAccessibilityFocusID", ignore)
        self.assertIn("ignoredRowAccessibilityFocusID(block.id)", ignore)
        self.assertNotIn("moveReviewAccessibilityFocus(to:", ignore)

        correction = braced_body(
            self.panel,
            "private func completeReviewAfterCorrection(_ blockID: UUID)",
        )
        self.assertIn("moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(", correction)
        self.assertIn("Self.reviewCompletionAccessibilityFocusID", correction)
        self.assertNotIn("moveReviewAccessibilityFocus(to:", correction)

    def test_handoff_records_and_validates_the_image_revision_before_publishing(self) -> None:
        schedule = braced_body(
            self.panel,
            "private func moveReviewAccessibilityFocusAfterCorrectionSheetDismissal",
        )
        self.assertIn("pendingCorrectionSheetDismissalFocusID = focusID", schedule)
        self.assertIn(
            "pendingCorrectionSheetDismissalRevision = store.imageTranslationRevision",
            schedule,
        )

        apply = braced_body(
            self.panel,
            "private func applyPendingCorrectionSheetDismissalFocus()",
        )
        for marker in [
            "guard let focusID = pendingCorrectionSheetDismissalFocusID",
            "pendingCorrectionSheetDismissalRevision == store.imageTranslationRevision",
            "clearPendingCorrectionSheetDismissalFocus()",
            "moveReviewAccessibilityFocus(to: focusID)",
        ]:
            self.assertIn(marker, apply)

        clear = braced_body(
            self.panel,
            "private func clearPendingCorrectionSheetDismissalFocus()",
        )
        self.assertIn("pendingCorrectionSheetDismissalFocusID = nil", clear)
        self.assertIn("pendingCorrectionSheetDismissalRevision = nil", clear)

    def test_new_image_revision_clears_any_pending_sheet_handoff(self) -> None:
        revision = braced_body(
            self.panel,
            ".onChange(of: store.imageTranslationRevision)",
        )
        self.assertIn("editingImageTranslationBlock = nil", revision)
        self.assertIn("clearPendingCorrectionSheetDismissalFocus()", revision)
        self.assertIn("reviewAccessibilityFocusID = nil", revision)

    def test_ci_routes_v330_after_v329(self) -> None:
        old = "python3 -B scripts/test-v329-image-ocr-false-positive-dismissal-contract.py"
        new = (
            "python3 -B "
            "scripts/test-v330-image-ocr-correction-sheet-focus-handoff-contract.py"
        )
        route = (
            "if grep -Fx "
            "'scripts/test-v330-image-ocr-correction-sheet-focus-handoff-contract.py' "
            "\"$RESULT_ROOT/changed-files.txt\" >/dev/null; then"
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Static contracts for v3.35 focus-preview correction dismissal return."""

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


class ImageFocusPreviewReturnFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.focus = braced_body(
            self.view,
            "private struct ImageTranslationFocusPreview: View",
        )

    def test_focus_preview_uses_its_own_guarded_entry_and_preview_fallback(self) -> None:
        workspace = braced_body(self.panel, "private var imageWorkspace: some View")
        self.assertIn(
            "editBlock: { beginCorrectionFromFocusPreview(of: $0) }",
            workspace,
        )
        begin = braced_body(
            self.panel,
            "private func beginCorrectionFromFocusPreview(of block: ImageTranslationBlock)",
        )
        schedule = (
            "moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(\n"
            "            to: reviewPreviewAccessibilityFocusID(block.id)\n"
            "        )"
        )
        for marker in [
            "guard !isRunning",
            "!isRenderingExport",
            "store.imageTranslationBlocks.contains(where: { $0.id == block.id })",
            "selectedImageTranslationBlockID = block.id",
            schedule,
            "editingImageTranslationBlock = block",
        ]:
            self.assertIn(marker, begin)
        self.assertLess(begin.index(schedule), begin.index("editingImageTranslationBlock = block"))
        self.assertNotIn("moveReviewAccessibilityFocus(to:", begin)
        self.assertNotIn("correctImageTranslationBlock(", begin)
        self.assertNotIn("VisionOCRService", begin)

    def test_result_row_keeps_its_existing_result_row_fallback(self) -> None:
        begin = braced_body(
            self.panel,
            "private func beginCorrection(of block: ImageTranslationBlock)",
        )
        self.assertIn(
            "to: reviewRowAccessibilityFocusID(block.id)",
            begin,
        )
        self.assertNotIn("reviewPreviewAccessibilityFocusID(block.id)", begin)

    def test_preview_focus_destination_still_exists_after_sheet_dismissal(self) -> None:
        self.assertIn(
            'equals: "image-review-preview-\\(block.id.uuidString)"',
            self.focus,
        )
        self.assertIn(
            '"image-review-preview-\\(blockID.uuidString)"',
            self.panel,
        )
        apply = braced_body(
            self.panel,
            "private func applyPendingCorrectionSheetDismissalFocus()",
        )
        self.assertIn(
            "pendingCorrectionSheetDismissalRevision == store.imageTranslationRevision",
            apply,
        )
        self.assertIn("moveReviewAccessibilityFocus(to: focusID)", apply)

    def test_success_and_ignore_still_replace_the_preview_opening_fallback(self) -> None:
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

    def test_focus_origin_remains_view_only_and_new_revisions_clear_pending_handoff(self) -> None:
        self.assertNotIn("beginCorrectionFromFocusPreview", self.store)
        self.assertNotIn("pendingCorrectionSheetDismissalFocus", self.store)
        revision = braced_body(
            self.panel,
            ".onChange(of: store.imageTranslationRevision)",
        )
        self.assertIn("editingImageTranslationBlock = nil", revision)
        self.assertIn("clearPendingCorrectionSheetDismissalFocus()", revision)
        self.assertIn("reviewAccessibilityFocusID = nil", revision)

    def test_ci_routes_v335_after_v334(self) -> None:
        old = "python3 -B scripts/test-v334-image-focus-preview-correction-contract.py"
        new = "python3 -B scripts/test-v335-image-focus-preview-return-focus-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v335-image-focus-preview-return-focus-contract.py' "
            "\"$RESULT_ROOT/changed-files.txt\" >/dev/null; then"
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

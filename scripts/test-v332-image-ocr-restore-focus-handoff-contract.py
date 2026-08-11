#!/usr/bin/env python3
"""Static contracts for v3.32 OCR restore-confirmation focus handoff."""

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


class ImageOCRRestoreFocusHandoffContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_pending_restore_focus_is_view_private_not_store_or_persistence_state(self) -> None:
        self.assertIn(
            "@State private var pendingRestoreConfirmationDismissalFocusID: String?",
            self.panel,
        )
        self.assertIn(
            "@State private var pendingRestoreConfirmationDismissalRevision: Int?",
            self.panel,
        )
        self.assertNotIn("pendingRestoreConfirmationDismissalFocus", self.store)

    def test_destructive_restore_schedules_focus_without_publishing_inside_the_dialog(self) -> None:
        confirmation = braced_body(
            self.panel,
            "private func confirmVisionOCRRestore(_ block: ImageTranslationBlock)",
        )
        self.assertIn(
            "guard restoreConfirmationBlock?.id == block.id,\n"
            "              restoreVisionOCR(for: block.id) else { return }",
            confirmation,
        )
        self.assertIn("let focusID = restoreConfirmationFocusID(", confirmation)
        self.assertIn("origin: imageTranslationRestoreFocusOrigin ?? .row", confirmation)
        self.assertIn("to: focusID", confirmation)
        self.assertNotIn("restoreConfirmationBlock = nil", confirmation)
        self.assertNotIn("moveReviewAccessibilityFocus(to:", confirmation)

        restore = braced_body(
            self.panel,
            "private func restoreVisionOCR(for blockID: UUID) -> Bool",
        )
        self.assertIn("guard store.restoreImageTranslationBlockToVisionOCR(blockID) else { return false }", restore)
        self.assertIn("selectedImageTranslationBlockID = blockID", restore)
        self.assertIn("return true", restore)
        self.assertNotIn("moveReviewAccessibilityFocus(to:", restore)

    def test_binding_applies_pending_focus_only_when_the_confirmation_closes(self) -> None:
        binding = braced_body(
            self.panel,
            "private var isRestoreConfirmationPresented: Binding<Bool>",
        )
        self.assertIn("guard !isPresented else { return }", binding)
        self.assertIn("restoreConfirmationBlock = nil", binding)
        self.assertIn("applyPendingRestoreConfirmationDismissalFocus()", binding)
        self.assertLess(
            binding.index("restoreConfirmationBlock = nil"),
            binding.index("applyPendingRestoreConfirmationDismissalFocus()"),
        )

    def test_handoff_captures_and_validates_revision_before_publishing(self) -> None:
        schedule = braced_body(
            self.panel,
            "private func moveReviewAccessibilityFocusAfterRestoreConfirmationDismissal",
        )
        self.assertIn(
            "pendingRestoreConfirmationDismissalFocusID = focusID",
            schedule,
        )
        self.assertIn(
            "pendingRestoreConfirmationDismissalRevision = store.imageTranslationRevision",
            schedule,
        )

        apply = braced_body(
            self.panel,
            "private func applyPendingRestoreConfirmationDismissalFocus()",
        )
        for marker in [
            "guard let focusID = pendingRestoreConfirmationDismissalFocusID",
            "pendingRestoreConfirmationDismissalRevision == store.imageTranslationRevision",
            "clearPendingRestoreConfirmationDismissalFocus()",
            "moveReviewAccessibilityFocus(to: focusID)",
        ]:
            self.assertIn(marker, apply)

        clear = braced_body(
            self.panel,
            "private func clearPendingRestoreConfirmationDismissalFocus()",
        )
        self.assertIn("pendingRestoreConfirmationDismissalFocusID = nil", clear)
        self.assertIn("pendingRestoreConfirmationDismissalRevision = nil", clear)

    def test_new_image_revision_clears_pending_restore_focus_before_old_dialog_can_publish(self) -> None:
        revision = braced_body(
            self.panel,
            ".onChange(of: store.imageTranslationRevision)",
        )
        self.assertIn("restoreConfirmationBlock = nil", revision)
        self.assertIn("clearPendingRestoreConfirmationDismissalFocus()", revision)
        self.assertIn("reviewAccessibilityFocusID = nil", revision)

    def test_ci_routes_v332_after_v331(self) -> None:
        old = (
            "python3 -B "
            "scripts/test-v331-image-ocr-correction-return-focus-contract.py"
        )
        new = (
            "python3 -B "
            "scripts/test-v332-image-ocr-restore-focus-handoff-contract.py"
        )
        route = (
            "if grep -Fx "
            "'scripts/test-v332-image-ocr-restore-focus-handoff-contract.py' "
            "\"$RESULT_ROOT/changed-files.txt\" >/dev/null; then"
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

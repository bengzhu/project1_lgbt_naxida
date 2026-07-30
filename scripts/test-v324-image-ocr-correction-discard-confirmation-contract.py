#!/usr/bin/env python3
"""Static contracts for v3.24 unsaved image OCR correction protection."""

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


class ImageOCRCorrectionDiscardConfirmationContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.editor = braced_body(
            self.view,
            "private struct ImageOCRCorrectionSheet: View",
        )

    def test_editor_tracks_unsaved_original_text_locally(self) -> None:
        self.assertIn(
            "@State private var showDiscardCorrectionConfirmation = false",
            self.editor,
        )
        unsaved_changes = braced_body(
            self.editor,
            "private var hasUnsavedChanges: Bool",
        )
        self.assertIn("correctedOriginal != block.original", unsaved_changes)

    def test_cancel_requests_confirmation_only_for_unsaved_changes(self) -> None:
        self.assertIn('Button("取消", action: requestDismiss)', self.editor)
        request = braced_body(
            self.editor,
            "private func requestDismiss()",
        )
        self.assertIn("guard !isSaving else { return }", request)
        self.assertIn("guard hasUnsavedChanges else", request)
        self.assertIn("dismiss()", request)
        self.assertIn("showDiscardCorrectionConfirmation = true", request)
        self.assertLess(
            request.index("guard hasUnsavedChanges else"),
            request.index("showDiscardCorrectionConfirmation = true"),
        )

    def test_destructive_discard_is_explicit_and_editing_remains_available(self) -> None:
        self.assertIn('"放弃未保存的修正？"', self.editor)
        self.assertIn("isPresented: $showDiscardCorrectionConfirmation", self.editor)
        self.assertIn("titleVisibility: .visible", self.editor)
        self.assertIn(
            'Button("放弃修正", role: .destructive, action: dismiss.callAsFunction)',
            self.editor,
        )
        self.assertIn('Button("继续编辑", role: .cancel) {}', self.editor)
        self.assertIn("未保存的 OCR 原文不会用于重新翻译。", self.editor)

    def test_interactive_dismissal_is_blocked_while_saving_or_dirty(self) -> None:
        self.assertIn(
            ".interactiveDismissDisabled(isSaving || hasUnsavedChanges)",
            self.editor,
        )
        self.assertIn("有未保存的修正，取消前会要求确认", self.editor)

    def test_successful_save_still_dismisses_without_the_discard_flow(self) -> None:
        save = braced_body(self.editor, "private func save()")
        self.assertIn("didSave()", save)
        self.assertIn("dismiss()", save)
        self.assertLess(save.index("didSave()"), save.index("dismiss()"))
        self.assertNotIn("requestDismiss()", save)
        self.assertNotIn("showDiscardCorrectionConfirmation = true", save)

    def test_ci_runs_v324_after_v323(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        old = "python3 -B scripts/test-v323-image-ocr-restore-confirmation-contract.py"
        new = "python3 -B scripts/test-v324-image-ocr-correction-discard-confirmation-contract.py"
        self.assertIn(new, workflow)
        self.assertLess(workflow.index(old), workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

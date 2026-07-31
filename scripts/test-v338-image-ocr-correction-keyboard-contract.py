#!/usr/bin/env python3
"""Static contracts for v3.38 image OCR correction keyboard dismissal."""

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


class ImageOCRCorrectionKeyboardContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.editor = braced_body(
            self.view,
            "private struct ImageOCRCorrectionSheet: View",
        )

    def test_multiline_editor_uses_local_focus_state(self) -> None:
        self.assertIn(
            "@FocusState private var correctedOriginalFocused: Bool",
            self.editor,
        )
        self.assertIn(
            ".focused($correctedOriginalFocused)",
            self.editor,
        )
        self.assertNotIn("TranslationSessionStore(", self.editor)

    def test_keyboard_toolbar_has_accessible_done_action(self) -> None:
        keyboard_toolbar = braced_body(
            self.editor,
            "ToolbarItemGroup(placement: .keyboard)",
        )
        self.assertIn('Button("完成", action: dismissKeyboard)', keyboard_toolbar)
        self.assertIn(
            'accessibilityLabel("完成 OCR 原文输入并收起键盘")',
            keyboard_toolbar,
        )
        dismiss = braced_body(self.editor, "private func dismissKeyboard()")
        self.assertIn("correctedOriginalFocused = false", dismiss)

    def test_sheet_actions_hide_keyboard_without_changing_existing_semantics(self) -> None:
        dismiss = braced_body(self.editor, "private func requestDismiss()")
        self.assertIn("guard !isSaving else { return }", dismiss)
        self.assertIn("dismissKeyboard()", dismiss)
        self.assertLess(
            dismiss.index("dismissKeyboard()"),
            dismiss.index("guard hasUnsavedChanges else"),
        )
        ignore_request = braced_body(
            self.editor,
            "private func requestIgnoreConfirmation()",
        )
        self.assertIn("dismissKeyboard()", ignore_request)
        self.assertIn("showIgnoreBlockConfirmation = true", ignore_request)
        self.assertIn(
            "Button(role: .destructive, action: requestIgnoreConfirmation)",
            self.editor,
        )
        save = braced_body(self.editor, "private func save()")
        self.assertIn("dismissKeyboard()", save)
        self.assertLess(save.index("dismissKeyboard()"), save.index("Task {"))
        self.assertIn(
            "store.correctImageTranslationBlock(block.id, original: normalizedCorrectedOriginal)",
            save,
        )
        self.assertIn(".interactiveDismissDisabled(isSaving || hasUnsavedChanges)", self.editor)

    def test_ci_runs_v338_after_v337(self) -> None:
        old = "python3 -B scripts/test-v337-image-ocr-correction-normalized-dismissal-contract.py"
        new = "python3 -B scripts/test-v338-image-ocr-correction-keyboard-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v338-image-ocr-correction-keyboard-contract.py' "
            "\"$RESULT_ROOT/changed-files.txt\" >/dev/null; then"
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

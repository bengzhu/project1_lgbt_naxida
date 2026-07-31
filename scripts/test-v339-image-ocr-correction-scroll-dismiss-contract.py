#!/usr/bin/env python3
"""Static contracts for v3.39 interactive keyboard dismissal in OCR correction."""

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


class ImageOCRCorrectionScrollDismissContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.editor = braced_body(
            self.view,
            "private struct ImageOCRCorrectionSheet: View",
        )

    def test_correction_form_interactively_dismisses_keyboard_before_navigation(self) -> None:
        form = self.editor.index("Form {")
        scroll_dismiss = self.editor.index(".scrollDismissesKeyboard(.interactively)")
        navigation = self.editor.index('.navigationTitle("修正识别文字")')
        self.assertLess(form, scroll_dismiss)
        self.assertLess(scroll_dismiss, navigation)

    def test_explicit_done_and_action_dismissal_remain_available(self) -> None:
        self.assertIn('Button("完成", action: dismissKeyboard)', self.editor)
        self.assertIn(
            'accessibilityLabel("完成 OCR 原文输入并收起键盘")',
            self.editor,
        )
        for marker in [
            "private func requestDismiss()",
            "private func requestIgnoreConfirmation()",
            "private func save()",
        ]:
            self.assertIn("dismissKeyboard()", braced_body(self.editor, marker))

    def test_scroll_behavior_stays_view_only_and_preserves_correction_semantics(self) -> None:
        self.assertNotIn("TranslationSessionStore(", self.editor)
        self.assertIn(
            "store.correctImageTranslationBlock(block.id, original: normalizedCorrectedOriginal)",
            self.editor,
        )
        self.assertIn(".interactiveDismissDisabled(isSaving || hasUnsavedChanges)", self.editor)
        self.assertIn("normalizedCorrectedOriginal != block.original", self.editor)

    def test_ci_runs_v339_after_v338(self) -> None:
        old = "python3 -B scripts/test-v338-image-ocr-correction-keyboard-contract.py"
        new = "python3 -B scripts/test-v339-image-ocr-correction-scroll-dismiss-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v339-image-ocr-correction-scroll-dismiss-contract.py' "
            "\"$RESULT_ROOT/changed-files.txt\" >/dev/null; then"
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

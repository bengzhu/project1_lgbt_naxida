#!/usr/bin/env python3
"""Static contracts for v3.40 OCR correction save-time editor locking."""

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


class ImageOCRCorrectionSaveLockContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.editor = braced_body(
            self.view,
            "private struct ImageOCRCorrectionSheet: View",
        )

    def test_multiline_editor_is_locked_while_its_correction_is_saving(self) -> None:
        editor_section = self.editor[
            self.editor.index('Section("识别文字")'):
            self.editor.index('Section("当前翻译")')
        ]
        text_field = editor_section.index('TextField("修正后的文字", text: $correctedOriginal, axis: .vertical)')
        focus = editor_section.index(".focused($correctedOriginalFocused)")
        save_lock = editor_section.index(".disabled(isSaving)")
        self.assertLess(text_field, focus)
        self.assertLess(focus, save_lock)

    def test_save_lock_uses_the_existing_block_scoped_store_state(self) -> None:
        is_saving = braced_body(self.editor, "private var isSaving: Bool")
        self.assertIn("store.imageTranslationCorrectionBlockID == block.id", is_saving)
        self.assertIn(".disabled(isSaving)", self.editor)
        self.assertIn('ProgressView("正在重新翻译")', self.editor)

    def test_existing_keyboard_and_mutation_guards_remain_intact(self) -> None:
        save = braced_body(self.editor, "private func save()")
        self.assertIn("dismissKeyboard()", save)
        self.assertIn(
            "store.correctImageTranslationBlock(block.id, original: normalizedCorrectedOriginal)",
            save,
        )
        self.assertIn(".disabled(!canSave || isSaving)", self.editor)
        self.assertIn(".interactiveDismissDisabled(isSaving || hasUnsavedChanges)", self.editor)
        self.assertIn("normalizedCorrectedOriginal != block.original", self.editor)

    def test_ci_runs_v340_after_v339(self) -> None:
        old = "python3 -B scripts/test-v339-image-ocr-correction-scroll-dismiss-contract.py"
        new = "python3 -B scripts/test-v340-image-ocr-correction-save-lock-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v340-image-ocr-correction-save-lock-contract.py' "
            "\"$RESULT_ROOT/changed-files.txt\" >/dev/null; then"
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

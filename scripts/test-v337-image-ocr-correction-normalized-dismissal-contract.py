#!/usr/bin/env python3
"""Static contracts for v3.37 normalized no-op image OCR correction dismissal."""

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


class ImageOCRCorrectionNormalizedDismissalContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.editor = braced_body(
            self.view,
            "private struct ImageOCRCorrectionSheet: View",
        )

    def test_editor_has_one_store_equivalent_normalization_source(self) -> None:
        normalized = braced_body(
            self.editor,
            "private var normalizedCorrectedOriginal: String",
        )
        self.assertIn(
            "correctedOriginal.trimmingCharacters(in: .whitespacesAndNewlines)",
            normalized,
        )
        store_correction = braced_body(
            self.store,
            "func correctImageTranslationBlock(",
        )
        self.assertIn(
            "let correctedOriginal = correctedOriginal.trimmingCharacters(in: .whitespacesAndNewlines)",
            store_correction,
        )

    def test_whitespace_only_edits_are_not_dirty_or_retranslation_work(self) -> None:
        for marker in [
            "private var canSave: Bool",
            "private var hasUnsavedChanges: Bool",
            "private var requiresRetranslation: Bool",
        ]:
            body = braced_body(self.editor, marker)
            self.assertIn("normalizedCorrectedOriginal", body)
        self.assertIn(
            "normalizedCorrectedOriginal != block.original",
            braced_body(self.editor, "private var hasUnsavedChanges: Bool"),
        )
        self.assertIn(
            "normalizedCorrectedOriginal != block.original",
            braced_body(self.editor, "private var requiresRetranslation: Bool"),
        )
        self.assertIn(
            ".interactiveDismissDisabled(isSaving || hasUnsavedChanges)",
            self.editor,
        )

    def test_save_passes_the_same_normalized_value_to_existing_store_flow(self) -> None:
        save = braced_body(self.editor, "private func save()")
        self.assertIn(
            "store.correctImageTranslationBlock(block.id, original: normalizedCorrectedOriginal)",
            save,
        )
        self.assertIn("didSave()", save)
        self.assertIn("dismiss()", save)
        self.assertLess(save.index("didSave()"), save.index("dismiss()"))
        self.assertNotIn("TranslationSessionStore(", self.editor)

    def test_existing_discard_protection_and_confirmation_action_remain_present(self) -> None:
        self.assertIn('"放弃未保存的修正？"', self.editor)
        self.assertIn('requiresRetranslation ? "保存并重译" : "确认无误"', self.editor)
        self.assertIn("确认当前 OCR 原文无误；不会重新翻译", self.editor)
        self.assertIn(
            "guard correctedOriginal != currentBlock.original else {",
            self.store,
        )

    def test_ci_runs_v337_after_v336(self) -> None:
        old = "python3 -B scripts/test-v336-koharu-readiness-developer-summary-contract.py"
        new = "python3 -B scripts/test-v337-image-ocr-correction-normalized-dismissal-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v337-image-ocr-correction-normalized-dismissal-contract.py' "
            '"$RESULT_ROOT/changed-files.txt" >/dev/null; then'
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

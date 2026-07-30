#!/usr/bin/env python3
"""Static contracts for v3.25 image OCR confirmation without retranslating."""

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


class ImageOCRCorrectionConfirmationActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.editor = braced_body(
            self.view,
            "private struct ImageOCRCorrectionSheet: View",
        )

    def test_store_short_circuits_normalized_unchanged_text_before_translation(self) -> None:
        correction = braced_body(self.store, "func correctImageTranslationBlock(")
        unchanged = "guard correctedOriginal != currentBlock.original else {"
        self.assertIn(unchanged, correction)
        self.assertIn("imageTranslationCorrectionMessage = nil", correction)
        self.assertLess(
            correction.index(unchanged),
            correction.index("let correctionID = UUID()"),
        )
        unchanged_body = braced_body(correction, unchanged)
        self.assertIn("return true", unchanged_body)
        self.assertNotIn("translate(", unchanged_body)

    def test_editor_uses_store_equivalent_normalized_retranslation_decision(self) -> None:
        decision = braced_body(
            self.editor,
            "private var requiresRetranslation: Bool",
        )
        self.assertIn(
            "correctedOriginal.trimmingCharacters(in: .whitespacesAndNewlines) != block.original",
            decision,
        )

    def test_save_action_names_both_outcomes_and_explains_them_accessibly(self) -> None:
        title = braced_body(self.editor, "private var saveActionTitle: String")
        self.assertIn('requiresRetranslation ? "保存并重译" : "确认无误"', title)
        hint = braced_body(
            self.editor,
            "private var saveActionAccessibilityHint: String",
        )
        self.assertIn("保存修正后的 OCR 原文，并只重新翻译此文字块", hint)
        self.assertIn("确认当前 OCR 原文无误；不会重新翻译", hint)
        self.assertIn("Button(saveActionTitle, action: save)", self.editor)
        self.assertIn(".accessibilityHint(saveActionAccessibilityHint)", self.editor)

    def test_save_path_still_completes_the_existing_sheet_flow(self) -> None:
        save = braced_body(self.editor, "private func save()")
        self.assertIn("store.correctImageTranslationBlock(block.id, original: correctedOriginal)", save)
        self.assertIn("didSave()", save)
        self.assertIn("dismiss()", save)
        self.assertLess(save.index("didSave()"), save.index("dismiss()"))

    def test_ci_runs_v325_after_v324(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        old = "python3 -B scripts/test-v324-image-ocr-correction-discard-confirmation-contract.py"
        new = "python3 -B scripts/test-v325-image-ocr-correction-confirmation-action-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v325-image-ocr-correction-confirmation-action-contract.py' "
            "\"$RESULT_ROOT/changed-files.txt\" >/dev/null; then"
        )
        self.assertIn(new, workflow)
        self.assertIn(route, workflow)
        self.assertLess(workflow.index(old), workflow.index(new))
        self.assertLess(workflow.index(route), workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

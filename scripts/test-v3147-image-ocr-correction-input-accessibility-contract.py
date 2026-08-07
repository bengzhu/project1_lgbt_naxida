#!/usr/bin/env python3
"""Static contracts for v3.147 OCR correction input accessibility context."""

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


class ImageOCRCorrectionInputAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.editor = braced_body(
            self.view,
            "private struct ImageOCRCorrectionSheet: View",
        )

    def test_ocr_input_exposes_label_value_and_state_aware_hint(self) -> None:
        editor_section = self.editor[
            self.editor.index('Section("识别文字")'):
            self.editor.index('Section("当前翻译")')
        ]
        text_field = editor_section.index(
            'TextField("修正后的文字", text: $correctedOriginal, axis: .vertical)'
        )
        focus = editor_section.index(".focused($correctedOriginalFocused)")
        save_lock = editor_section.index(".disabled(isSaving)")
        label = editor_section.index('.accessibilityLabel("修正后的 OCR 原文")')
        value = editor_section.index(
            '.accessibilityValue(correctedOriginal.isEmpty ? "空" : correctedOriginal)'
        )
        hint = editor_section.index(
            ".accessibilityHint(correctedOriginalAccessibilityHint)"
        )
        self.assertLess(text_field, focus)
        self.assertLess(focus, save_lock)
        self.assertLess(save_lock, label)
        self.assertLess(label, value)
        self.assertLess(value, hint)

        accessibility_hint = braced_body(
            self.editor,
            "private var correctedOriginalAccessibilityHint: String",
        )
        for marker in [
            "if isSaving",
            "if !canSave",
            "if requiresRetranslation",
            "正在重新翻译当前文字块；暂不能编辑或忽略",
            "请输入非空 OCR 原文；保存后只会重新翻译当前文字块，不会重新识别整张图片",
            "保存会只重新翻译当前文字块，不会重新识别整张图片",
            "当前文字与 OCR 原文相同；保存会确认无误，不会重新翻译",
        ]:
            self.assertIn(marker, accessibility_hint)

    def test_ignore_action_explains_the_saving_lock_without_changing_its_scope(self) -> None:
        ignore_hint = braced_body(
            self.editor,
            "private var ignoreActionAccessibilityHint: String",
        )
        self.assertIn("isSaving", ignore_hint)
        self.assertIn("正在重新翻译当前文字块；完成前不能忽略", ignore_hint)
        self.assertIn(
            "从本次图片的预览、导出和当前转录中移除此 OCR 文字块；稍后可在图片检查区恢复",
            ignore_hint,
        )
        self.assertIn(".accessibilityHint(ignoreActionAccessibilityHint)", self.editor)
        self.assertIn(".disabled(isSaving)", self.editor)
        self.assertIn("requestIgnoreConfirmation", self.editor)

    def test_input_context_is_view_only_and_reuses_existing_save_gates(self) -> None:
        for marker in [
            "private var correctedOriginalAccessibilityHint: String",
            "private var ignoreActionAccessibilityHint: String",
        ]:
            helper = braced_body(self.editor, marker)
            for forbidden in [
                "store.",
                "VisionOCRService",
                "TranslationSessionStore(",
                "imageTranslationBlocks =",
                "persist(",
                "groundTruth",
            ]:
                self.assertNotIn(forbidden, helper)
        self.assertIn("private var normalizedCorrectedOriginal: String", self.editor)
        self.assertIn("private var canSave: Bool", self.editor)
        self.assertIn("private var requiresRetranslation: Bool", self.editor)
        self.assertIn(".disabled(!canSave || isSaving)", self.editor)
        self.assertIn(".interactiveDismissDisabled(isSaving || hasUnsavedChanges)", self.editor)
        self.assertIn(".accessibilityHint(saveActionAccessibilityHint)", self.editor)

    def test_version_and_ci_route_follow_v3146(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.147;", self.project)
        old = "python3 -B scripts/test-v3146-image-ignored-row-restore-action-contract.py"
        new = "python3 -B scripts/test-v3147-image-ocr-correction-input-accessibility-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v3147-image-ocr-correction-input-accessibility-contract.py' "
            '"$RESULT_ROOT/changed-files.txt" >/dev/null; then'
        )
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertIn(route, self.workflow)
        self.assertIn("14[7]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)

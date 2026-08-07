#!/usr/bin/env python3
"""Static contracts for v3.145 file-import replacement accessibility feedback."""

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


class ImageFileSelectionReplacementHintContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_file_picker_hint_distinguishes_first_selection_and_replacement(self) -> None:
        command_bar = braced_body(self.view, "private struct ImageCommandBar: View")
        commands = braced_body(command_bar, "@ViewBuilder private var commands: some View")
        hint = braced_body(command_bar, "private var fileSelectionAccessibilityHint: String")

        self.assertIn(".accessibilityHint(fileSelectionAccessibilityHint)", commands)
        self.assertIn("if isRunning", hint)
        self.assertIn(
            "从文件选择新图片会取消当前图片读取、OCR 或翻译，并开始新的本机 OCR 与翻译",
            hint,
        )
        self.assertIn("if store.imageTranslationData == nil", hint)
        self.assertIn('return "从文件选择图片并开始本机 OCR 与翻译"', hint)
        self.assertIn('return "更换当前图片并开始新的本机 OCR 与翻译"', hint)

    def test_hint_is_view_only_and_keeps_import_available(self) -> None:
        command_bar = braced_body(self.view, "private struct ImageCommandBar: View")
        commands = braced_body(command_bar, "@ViewBuilder private var commands: some View")
        hint = braced_body(command_bar, "private var fileSelectionAccessibilityHint: String")

        self.assertNotIn("imageTranslationState =", hint)
        self.assertNotIn("imageTranslationData = nil", hint)
        self.assertNotIn("store.clearImageTranslation", hint)
        self.assertIn('AppSecondaryButton(title: "图片文件", systemImage: "folder", action: openImporter)', commands)
        self.assertNotIn(".disabled(isRunning)", commands)

    def test_version_and_ci_route_follow_v3144(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertEqual(self.project.count("MARKETING_VERSION = 3.145;"), 2)
        old = "python3 -B scripts/test-v3144-image-empty-result-rerun-action-contract.py"
        new = "python3 -B scripts/test-v3145-image-file-selection-replacement-hint-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertIn("14[5]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)

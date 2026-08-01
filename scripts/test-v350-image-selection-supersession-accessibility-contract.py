#!/usr/bin/env python3
"""Static contracts for v3.50 image import supersession accessibility feedback."""

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


class ImageSelectionSupersessionAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_photo_picker_hint_explains_running_supersession(self) -> None:
        command_bar = braced_body(self.view, "private struct ImageCommandBar: View")
        commands = braced_body(command_bar, "@ViewBuilder private var commands: some View")
        hint = braced_body(command_bar, "private var imageSelectionAccessibilityHint: String")

        self.assertIn("accessibilityHint: imageSelectionAccessibilityHint", commands)
        self.assertIn("if isRunning", hint)
        self.assertIn(
            "选择新图片会取消当前图片读取、OCR 或翻译，并开始新的本机 OCR 与翻译",
            hint,
        )
        self.assertIn('? "从照片图库选择图片并开始本机 OCR 与翻译"', hint)
        self.assertIn(': "更换当前图片并开始新的本机 OCR 与翻译"', hint)

    def test_file_picker_hint_explains_running_supersession(self) -> None:
        command_bar = braced_body(self.view, "private struct ImageCommandBar: View")
        commands = braced_body(command_bar, "@ViewBuilder private var commands: some View")
        hint = braced_body(command_bar, "private var fileSelectionAccessibilityHint: String")

        self.assertIn(".accessibilityHint(fileSelectionAccessibilityHint)", commands)
        self.assertIn("if isRunning", hint)
        self.assertIn(
            "从文件选择新图片会取消当前图片读取、OCR 或翻译，并开始新的本机 OCR 与翻译",
            hint,
        )
        self.assertIn('return "从文件选择图片并开始本机 OCR 与翻译"', hint)

    def test_import_controls_remain_available_during_supersession(self) -> None:
        command_bar = braced_body(self.view, "private struct ImageCommandBar: View")
        commands = braced_body(command_bar, "@ViewBuilder private var commands: some View")

        self.assertIn("if store.isProUnlocked", commands)
        self.assertIn("PhotoPickerCommand(", commands)
        self.assertIn('AppSecondaryButton(title: "图片文件", systemImage: "folder", action: openImporter)', commands)
        self.assertNotIn(".disabled(isRunning)", commands)

    def test_version_and_ci_route_follow_v349(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.50;", self.project)
        old = "python3 -B scripts/test-v349-image-language-accessibility-contract.py"
        new = "python3 -B scripts/test-v350-image-selection-supersession-accessibility-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74|75|76|77|78|79|80|81)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Static contracts for v3.47 image command scope accessibility feedback."""

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


class ImageCommandAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_command_hints_explain_operation_scope(self) -> None:
        command_bar = braced_body(self.view, "private struct ImageCommandBar: View")
        commands = braced_body(command_bar, "@ViewBuilder private var commands: some View")
        self.assertIn("accessibilityHint: imageSelectionAccessibilityHint", commands)
        self.assertIn(".accessibilityHint(fileSelectionAccessibilityHint)", commands)
        self.assertIn(
            '.accessibilityHint("图片翻译需要 Pro；不会修改当前图片或文本页语言")',
            commands,
        )
        self.assertIn(
            '.accessibilityHint("取消当前图片读取、OCR 或翻译；保留已载入图片以便重试")',
            commands,
        )
        self.assertIn(
            '.accessibilityHint("使用当前重试语言重新识别并翻译这张图片")',
            commands,
        )
        self.assertIn(
            '.accessibilityHint("使用当前图片语言重新运行 Vision OCR，并重新翻译识别到的文字")',
            commands,
        )
        self.assertIn(
            '.accessibilityHint("重新生成旁贴或覆盖导出图；不会重新识别或翻译图片")',
            commands,
        )
        self.assertIn('? "导出图正在准备分享"', commands)
        self.assertIn(': "准备当前图片导出图并打开分享"', commands)
        self.assertIn(
            '.accessibilityHint("请求确认后删除当前图片、识别结果、译文和导出文件")',
            commands,
        )

    def test_photo_picker_exposes_dynamic_selection_scope(self) -> None:
        picker = braced_body(self.view, "private struct PhotoPickerCommand: View")
        self.assertIn("let accessibilityHint: String", picker)
        self.assertIn(".accessibilityHint(accessibilityHint)", picker)
        command_bar = braced_body(self.view, "private struct ImageCommandBar: View")
        self.assertIn("private var imageSelectionAccessibilityHint: String", command_bar)
        self.assertIn("private var fileSelectionAccessibilityHint: String", command_bar)
        self.assertIn(
            '? "从照片图库选择图片并开始本机 OCR 与翻译"',
            command_bar,
        )
        self.assertIn(
            ': "更换当前图片并开始新的本机 OCR 与翻译"',
            command_bar,
        )

    def test_version_is_bumped_consistently(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.47;", self.project)

    def test_ci_runs_v347_after_v346(self) -> None:
        old = "python3 -B scripts/test-v346-image-preview-status-accessibility-contract.py"
        new = "python3 -B scripts/test-v347-image-command-accessibility-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

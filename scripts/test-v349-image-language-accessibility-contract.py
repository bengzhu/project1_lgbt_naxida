#!/usr/bin/env python3
"""Static contracts for v3.49 image language control accessibility context."""

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


class ImageLanguageAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_source_hint_reflects_running_access_and_retry_states(self) -> None:
        control = braced_body(self.view, "private struct ImageSourceLanguageControl: View")
        hint = braced_body(control, "private var imageSourceLanguageAccessibilityHint: String")

        self.assertIn(".accessibilityHint(imageSourceLanguageAccessibilityHint)", control)
        self.assertIn("if isRunning", hint)
        self.assertIn("图片正在读取、识别或翻译；完成或取消后才能更改输入语言", hint)
        self.assertIn("if !store.isProUnlocked", hint)
        self.assertIn("图片输入语言设置需要 Pro；不会修改当前图片或文本页语言", hint)
        self.assertIn("输入语言设置已解锁", hint)
        self.assertIn("store.imageTranslationData == nil", hint)
        self.assertIn("选择图片后可设置图片 OCR 输入语言", hint)
        self.assertIn("case .translated:", hint)
        self.assertIn("case .idle, .failed:", hint)
        self.assertIn("选回当前内容语言会撤销待重试更改", hint)

    def test_target_hint_reflects_running_and_content_lifecycle(self) -> None:
        control = braced_body(self.view, "private struct ImageTargetLanguageControl: View")
        hint = braced_body(control, "private var imageTargetLanguageAccessibilityHint: String")

        self.assertIn(".accessibilityHint(imageTargetLanguageAccessibilityHint)", control)
        self.assertIn("if isRunning", hint)
        self.assertIn("图片正在读取、识别或翻译；完成或取消后才能更改目标语言", hint)
        self.assertIn("store.imageTranslationData == nil", hint)
        self.assertIn("选择图片后可设置图片翻译目标语言", hint)
        self.assertIn("case .translated:", hint)
        self.assertIn("已完成的图片会重新翻译当前图片", hint)
        self.assertIn("case .idle, .failed:", hint)
        self.assertIn("失败或取消后会在重试时使用新目标语言", hint)
        self.assertIn("选回当前内容语言会撤销待重试更改", hint)
        self.assertNotIn("图片输入语言设置需要 Pro", hint)

    def test_language_controls_keep_running_guard(self) -> None:
        source = braced_body(self.view, "private struct ImageSourceLanguageControl: View")
        target = braced_body(self.view, "private struct ImageTargetLanguageControl: View")
        self.assertEqual(source.count(".disabled(isRunning)"), 1)
        self.assertEqual(target.count(".disabled(isRunning)"), 1)
        self.assertIn("private var isRunning: Bool", source)
        self.assertIn("private var isRunning: Bool", target)

    def test_version_and_ci_route_follow_v348(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.49;", self.project)
        old = "python3 -B scripts/test-v348-image-preview-context-accessibility-contract.py"
        new = "python3 -B scripts/test-v349-image-language-accessibility-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

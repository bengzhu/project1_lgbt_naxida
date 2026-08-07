#!/usr/bin/env python3
"""Contract for stable VoiceOver context on empty image preview/result surfaces."""

from pathlib import Path
import re
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
                return source[brace : index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class ImageEmptyResultAccessibilityContextContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.inspector = braced_body(self.panel, "private var inspector: some View")
        self.preview = braced_body(
            self.view,
            "private struct ImageTranslationPreview: View",
        )

    def test_preview_empty_state_is_a_stable_preview_context(self) -> None:
        empty = self.preview[self.preview.index('title: "选择图片"') :]
        for marker in [
            '.accessibilityElement(children: .ignore)',
            '.accessibilityLabel("图片翻译预览")',
            '.accessibilityValue("当前没有图片")',
            "从上方照片或图片文件按钮选择图片",
            "本机执行 OCR、翻译和屏幕预览",
        ]:
            self.assertIn(marker, empty)

    def test_result_empty_state_reads_dynamic_pipeline_context(self) -> None:
        for marker in [
            'title: "正在准备识别结果"',
            ".accessibilityLabel(imageResultEmptyStateAccessibilityLabel)",
            ".accessibilityValue(store.imageTranslationMessage)",
            ".accessibilityHint(imageResultEmptyStateAccessibilityHint)",
        ]:
            self.assertIn(marker, self.inspector)

        label = braced_body(
            self.panel,
            "private var imageResultEmptyStateAccessibilityLabel",
        )
        for marker in [
            "store.imageTranslationData == nil",
            "case .loading, .recognizing, .translating:",
            "case .translated:",
            "case .failed:",
        ]:
            self.assertIn(marker, label)

    def test_empty_result_hint_explains_recovery_boundary(self) -> None:
        hint = braced_body(
            self.panel,
            "private var imageResultEmptyStateAccessibilityHint",
        )
        for marker in [
            "从上方照片或文件按钮选择图片",
            "图片正在读取、识别或翻译",
            "当前没有可显示的 OCR 文字块",
            "store.canRetryImageTranslation",
        ]:
            self.assertIn(marker, hint)

    def test_context_is_view_only_and_does_not_change_pipeline(self) -> None:
        self.assertNotIn("imageResultEmptyStateAccessibility", self.store)
        self.assertNotIn("runImageTranslationPipeline", self.preview)
        self.assertNotIn("VisionOCRService", self.preview)
        self.assertIn("ImageTranslationPreview", self.panel)

    def test_version_and_ci_route_follow_v3132(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 133) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.132;", self.project)
        script = "scripts/test-v3133-image-empty-result-accessibility-context-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3132-image-ignored-empty-state-action-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))
        self.assertTrue("13[0-7]" in self.workflow or "13[0-8]" in self.workflow or "13[0-9]" in self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)

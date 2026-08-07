#!/usr/bin/env python3
"""Contract for a local retry action on retryable empty image results."""

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


class ImageEmptyResultRetryActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.inspector = braced_body(self.panel, "private var inspector: some View")
        self.empty_result = braced_body(
            self.inspector,
            "if store.imageTranslationBlocks.isEmpty",
        )

    def test_retryable_empty_result_has_local_visible_retry_button(self) -> None:
        for marker in [
            "else if canRetryFromImageStatus",
            'title: "重试当前图片"',
            'systemImage: "arrow.clockwise"',
            "tone: .warning",
            "action: store.retryImageTranslation",
            "imageResultEmptyStateRetryHint",
        ]:
            self.assertIn(marker, self.empty_result)
        self.assertIn('title: "重新识别"', self.empty_result)
        self.assertIn("if store.canRerunImageRecognition", self.empty_result)

    def test_local_retry_action_reuses_existing_store_gate(self) -> None:
        helper = braced_body(
            self.panel,
            "private func imageResultEmptyStateAccessibility<Content: View>",
        )
        for marker in [
            "else if canRetryFromImageStatus",
            '.accessibilityAction(named: "重试当前图片")',
            "guard store.canRetryImageTranslation else { return }",
            "store.retryImageTranslation()",
        ]:
            self.assertIn(marker, helper)
        gate = braced_body(self.panel, "private var canRetryFromImageStatus")
        self.assertIn("store.canRetryImageTranslation", gate)
        self.assertIn("store.imageTranslationRetryLanguageSummary == nil", gate)
        self.assertIn("func retryImageTranslation()", self.store)

    def test_retryable_empty_result_context_explains_language_boundary(self) -> None:
        hint = braced_body(
            self.panel,
            "private var imageResultEmptyStateAccessibilityHint: String",
        )
        for marker in [
            "case .idle:",
            "case .failed:",
            "canRetryFromImageStatus",
            "重试语言已更新",
            "重试当前图片",
            "重新识别和翻译",
            "可选择新图片",
        ]:
            self.assertIn(marker, hint)
        retry_hint = braced_body(
            self.panel,
            "private var imageResultEmptyStateRetryHint: String",
        )
        self.assertIn("当前图片语言", retry_hint)
        self.assertIn("重新识别并翻译", retry_hint)

    def test_retry_action_is_view_only_and_does_not_duplicate_pipeline(self) -> None:
        helper = braced_body(
            self.panel,
            "private func imageResultEmptyStateAccessibility<Content: View>",
        )
        self.assertNotIn("@State", helper)
        self.assertNotIn("imageTranslationState =", helper)
        self.assertNotIn("imageTranslationBlocks =", helper)
        self.assertNotIn("runImageTranslationPipeline", helper)
        self.assertNotIn("VisionOCRService", helper)

    def test_version_and_ci_route_follow_v3154(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 155) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.154;", self.project)
        old = "python3 -B scripts/test-v3154-image-empty-result-state-contract.py"
        new = "python3 -B scripts/test-v3155-image-empty-result-retry-action-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertIn("15[5]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)

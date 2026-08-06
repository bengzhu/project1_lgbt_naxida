#!/usr/bin/env python3
"""Contract for v3.121 making retryable image status rows actionable."""

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


class ImageStatusRetryAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_retryable_status_row_exposes_only_a_view_scoped_action(self) -> None:
        row = braced_body(self.panel, "private func imageStatusAccessibilityRow")
        self.assertIn("if canRetryFromImageStatus", row)
        self.assertIn('.accessibilityAction(named: "重试当前图片")', row)
        self.assertIn("guard store.canRetryImageTranslation else { return }", row)
        self.assertIn("store.retryImageTranslation()", row)
        self.assertIn("content", row)

    def test_pending_language_summary_avoids_duplicate_status_action(self) -> None:
        gate = braced_body(self.panel, "private var canRetryFromImageStatus")
        self.assertIn("store.canRetryImageTranslation", gate)
        self.assertIn("store.imageTranslationRetryLanguageSummary == nil", gate)
        summary = braced_body(
            self.panel,
            'if let retryLanguageSummary = store.imageTranslationRetryLanguageSummary',
        )
        self.assertIn('.accessibilityAction(named: "重试当前图片")', summary)
        self.assertIn("guard store.canRetryImageTranslation else { return }", summary)

    def test_status_row_keeps_existing_context_and_dynamic_retry_hint(self) -> None:
        row = braced_body(self.panel, "private var inspector: some View")
        for marker in [
            'accessibilityLabel("图片翻译状态")',
            ".accessibilityValue(imageStatusAccessibilityValue)",
            ".accessibilityHint(imageStatusAccessibilityHint)",
            "Self.imageTranslationStatusAccessibilityFocusID",
        ]:
            self.assertIn(marker, row)
        hint = braced_body(self.panel, "private var imageStatusAccessibilityHint")
        self.assertIn("store.canRetryImageTranslation", hint)
        self.assertIn("store.imageTranslationRetryLanguageSummary == nil", hint)
        self.assertIn("可以在此状态上执行“重试当前图片”", hint)
        self.assertIn("当前图片文件不可重试，请选择新图片", hint)

    def test_retry_reuses_store_without_new_state_or_pipeline(self) -> None:
        self.assertNotIn("imageStatusAccessibilityRow", self.store)
        self.assertNotIn("imageStatusAccessibilityHint", self.store)
        self.assertNotIn("runBubbleFirstProbe", self.panel)

    def test_version_and_ci_route_follow_v3120(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 121) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.120;", self.project)
        script = "scripts/test-v3121-image-status-retry-accessibility-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3120-image-retry-language-accessibility-action-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)

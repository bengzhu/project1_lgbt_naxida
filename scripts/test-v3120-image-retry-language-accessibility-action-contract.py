#!/usr/bin/env python3
"""Contract for v3.120 making the pending retry-language status actionable."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
PANEL = ROOT / "AITRANS/Views/ImageTranslationViews.swift"
PROJECT = ROOT / "AITRANS.xcodeproj/project.pbxproj"
WORKFLOW = ROOT / ".github/workflows/ci-results.yml"


def function_slice(source: str, start: str, end: str) -> str:
    start_index = source.index(start)
    end_index = source.index(end, start_index)
    return source[start_index:end_index]


class ImageRetryLanguageAccessibilityActionContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.panel = PANEL.read_text()
        cls.project = PROJECT.read_text()
        cls.workflow = WORKFLOW.read_text()

    def test_pending_retry_status_exposes_a_guarded_action(self):
        summary = function_slice(
            self.panel,
            'if let retryLanguageSummary = store.imageTranslationRetryLanguageSummary',
            'AppSectionHeader(\n                title: "识别结果"',
        )
        self.assertIn('.accessibilityAction(named: "重试当前图片")', summary)
        self.assertIn('guard store.canRetryImageTranslation else { return }', summary)
        self.assertIn('store.retryImageTranslation()', summary)
        self.assertIn('可在此状态上执行“重试当前图片”', summary)

    def test_action_reuses_store_retry_without_new_state(self):
        summary = function_slice(
            self.panel,
            'if let retryLanguageSummary = store.imageTranslationRetryLanguageSummary',
            'AppSectionHeader(\n                title: "识别结果"',
        )
        self.assertNotIn('imageTranslationRetryLanguageSummary =', summary)
        self.assertNotIn('imageTranslationRetrySourceLanguage =', summary)
        self.assertNotIn('imageTranslationRetryTargetLanguage =', summary)
        self.assertEqual(summary.count('store.retryImageTranslation()'), 1)

    def test_version_and_ci_route_follow_v3119(self):
        versions = re.findall(r'MARKETING_VERSION = ([0-9.]+);', self.project)
        self.assertTrue(versions)
        self.assertTrue(all(tuple(map(int, v.split('.'))) >= (3, 120) for v in versions))
        self.assertNotIn('MARKETING_VERSION = 3.119;', self.project)
        self.assertIn('scripts/test-v3120-image-retry-language-accessibility-action-contract.py', self.workflow)
        self.assertLess(
            self.workflow.index('scripts/test-v3119-image-retry-language-focus-contract.py'),
            self.workflow.index('scripts/test-v3120-image-retry-language-accessibility-action-contract.py'),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

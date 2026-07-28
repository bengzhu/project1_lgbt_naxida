#!/usr/bin/env python3
"""Contracts for v3.4 image target-language retry credentials."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def function_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing function signature: {signature}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise AssertionError(f"unterminated function body: {signature}")


class ImageRetryLanguageContractTests(unittest.TestCase):
    def test_target_selector_uses_state_scoped_credentials(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        selector = function_body(store, "func selectImageTargetLanguage(_ language: SupportedLanguage)")

        self.assertIn("selectTargetLanguage(language)", selector)
        self.assertIn("guard targetLanguage == language", selector)
        self.assertNotIn("isProUnlocked", selector)
        self.assertIn("switch imageTranslationState", selector)
        self.assertIn("case .translated:", selector)
        self.assertIn("case .idle, .failed:", selector)
        self.assertIn("case .loading, .recognizing, .translating:", selector)

    def test_completed_content_retranslates_only_with_live_source(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        selector = function_body(store, "func selectImageTargetLanguage(_ language: SupportedLanguage)")
        completed = selector[
            selector.index("case .translated:"):selector.index("case .idle, .failed:")
        ]

        self.assertIn("let url = imageTranslationSourceURL", completed)
        self.assertIn("FileManager.default.fileExists(atPath: url.path)", completed)
        self.assertLess(
            completed.index("FileManager.default.fileExists(atPath: url.path)"),
            completed.index("imageTranslationContentTargetLanguage = language"),
        )
        self.assertLess(
            completed.index("imageTranslationContentTargetLanguage = language"),
            completed.index("retryImageTranslation()"),
        )

    def test_failed_or_cancelled_content_updates_next_retry_without_running(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        selector = function_body(store, "func selectImageTargetLanguage(_ language: SupportedLanguage)")
        retained = selector[
            selector.index("case .idle, .failed:"):
            selector.index("case .loading, .recognizing, .translating:")
        ]
        running = selector[selector.index("case .loading, .recognizing, .translating:"):]

        self.assertLess(
            retained.index("guard canRetryImageTranslation else { return }"),
            retained.index("imageTranslationContentTargetLanguage = language"),
        )
        self.assertNotIn("retryImageTranslation()", retained)
        self.assertNotIn("imageTranslationContentTargetLanguage = language", running)
        self.assertNotIn("retryImageTranslation()", running)

    def test_retry_and_clear_preserve_the_credential_boundary(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        retry = function_body(store, "func retryImageTranslation()")
        clear = function_body(store, "func clearImageTranslation()")
        cancel = function_body(store, "func cancelImageTranslation()")

        self.assertIn("imageTranslationContentTargetLanguage ?? targetLanguage", retry)
        self.assertIn("imageTranslationContentTargetLanguage = nil", clear)
        self.assertNotIn("imageTranslationContentTargetLanguage = nil", cancel)

    def test_view_and_ci_expose_the_v34_contract(self) -> None:
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        workflow = read(".github/workflows/ci-results.yml")

        self.assertIn("store.selectImageTargetLanguage(language)", view)
        self.assertIn("失败或取消的图片会在重试时使用新语言", view)
        self.assertIn("34-image-retry-language", workflow)
        self.assertLess(
            workflow.index("scripts/test-v310-image-ocr-review-filter-contract.py"),
            workflow.index("scripts/test-v34-image-retry-language-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Contracts for v3.5 content versus pending image retry languages."""

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


class ImageRetryCredentialDisplayContractTests(unittest.TestCase):
    def test_content_and_pending_retry_languages_are_separate(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.assertIn("var imageTranslationContentSourceLanguage: SupportedLanguage?", store)
        self.assertIn("var imageTranslationContentTargetLanguage: SupportedLanguage?", store)
        self.assertIn("var imageTranslationRetrySourceLanguage: SupportedLanguage?", store)
        self.assertIn("var imageTranslationRetryTargetLanguage: SupportedLanguage?", store)

        displayed_source = function_body(store, "var imageTranslationDisplayedSourceLanguage: SupportedLanguage")
        displayed_target = function_body(store, "var imageTranslationDisplayedTargetLanguage: SupportedLanguage")
        self.assertNotIn("imageTranslationRetrySourceLanguage", displayed_source)
        self.assertNotIn("imageTranslationRetryTargetLanguage", displayed_target)

    def test_controls_prefer_pending_retry_languages_without_relabelling_content(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        selected_source = function_body(store, "var imageTranslationSelectedSourceLanguage: SupportedLanguage")
        selected_target = function_body(store, "var imageTranslationSelectedTargetLanguage: SupportedLanguage")
        summary = function_body(store, "var imageTranslationRetryLanguageSummary: String?")

        self.assertIn("guard canRetryImageTranslation", selected_source)
        self.assertIn("imageTranslationRetrySourceLanguage ?? imageTranslationDisplayedSourceLanguage", selected_source)
        self.assertIn("guard canRetryImageTranslation", selected_target)
        self.assertIn("imageTranslationRetryTargetLanguage ?? imageTranslationDisplayedTargetLanguage", selected_target)
        self.assertIn("imageTranslationRetrySourceLanguage != nil || imageTranslationRetryTargetLanguage != nil", summary)

    def test_retry_consumes_pending_before_content_and_task_clears_pending(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        retry = function_body(store, "func retryImageTranslation()")
        begin = function_body(store, "private func beginImageTranslationTask(")
        clear = function_body(store, "func clearImageTranslation()")
        cancel = function_body(store, "func cancelImageTranslation()")

        self.assertLess(retry.index("imageTranslationRetrySourceLanguage"), retry.index("imageTranslationContentSourceLanguage"))
        self.assertLess(retry.index("imageTranslationRetryTargetLanguage"), retry.index("imageTranslationContentTargetLanguage"))
        for body in (begin, clear):
            self.assertIn("imageTranslationRetrySourceLanguage = nil", body)
            self.assertIn("imageTranslationRetryTargetLanguage = nil", body)
        self.assertNotIn("imageTranslationRetrySourceLanguage = nil", cancel)
        self.assertNotIn("imageTranslationRetryTargetLanguage = nil", cancel)

    def test_failed_and_cancelled_selectors_only_write_pending_credentials(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        for signature, pending, content in (
            ("func selectImageSourceLanguage(_ language: SupportedLanguage)", "imageTranslationRetrySourceLanguage", "imageTranslationContentSourceLanguage"),
            ("func selectImageTargetLanguage(_ language: SupportedLanguage)", "imageTranslationRetryTargetLanguage", "imageTranslationContentTargetLanguage"),
        ):
            selector = function_body(store, signature)
            retained = selector[
                selector.index("case .idle, .failed:"):
                selector.index("case .loading, .recognizing, .translating:")
            ]
            self.assertIn(f"{pending} = language", retained)
            self.assertNotIn(f"{content} = language", retained)
            self.assertNotIn("retryImageTranslation()", retained)

    def test_view_distinguishes_actual_content_from_retry_selection(self) -> None:
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        workflow = read(".github/workflows/ci-results.yml")

        self.assertIn("store.imageTranslationDisplayedSourceLanguage.rawValue", view)
        self.assertIn("store.imageTranslationDisplayedTargetLanguage.rawValue", view)
        self.assertGreaterEqual(view.count("store.imageTranslationSelectedSourceLanguage"), 3)
        self.assertGreaterEqual(view.count("store.imageTranslationSelectedTargetLanguage"), 3)
        self.assertIn("store.imageTranslationRetryLanguageSummary", view)
        self.assertIn('title: "重试语言已更新"', view)
        self.assertIn("35-image-retry-credential-display", workflow)
        self.assertLess(
            workflow.index("scripts/test-v34-image-retry-language-contract.py"),
            workflow.index("scripts/test-v35-image-retry-credential-display-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

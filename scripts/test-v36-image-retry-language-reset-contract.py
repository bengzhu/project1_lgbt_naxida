#!/usr/bin/env python3
"""Contracts for v3.6 reversible pending image retry languages."""

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


class ImageRetryLanguageResetContractTests(unittest.TestCase):
    def test_displayed_languages_keep_task_credentials_without_result_data(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        for signature, content, global_language in (
            (
                "var imageTranslationDisplayedSourceLanguage: SupportedLanguage",
                "imageTranslationContentSourceLanguage",
                "sourceLanguage",
            ),
            (
                "var imageTranslationDisplayedTargetLanguage: SupportedLanguage",
                "imageTranslationContentTargetLanguage",
                "targetLanguage",
            ),
        ):
            displayed = function_body(store, signature)
            self.assertIn(f"{content} ?? {global_language}", displayed)
            self.assertNotIn("imageTranslationData", displayed)
            self.assertNotIn("imageTranslationBlocks", displayed)

    def test_selectors_snapshot_actual_content_before_global_mutation(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        for signature, displayed, global_mutation in (
            (
                "func selectImageSourceLanguage(_ language: SupportedLanguage)",
                "imageTranslationDisplayedSourceLanguage",
                "sourceLanguage = language",
            ),
            (
                "func selectImageTargetLanguage(_ language: SupportedLanguage)",
                "imageTranslationDisplayedTargetLanguage",
                "selectTargetLanguage(language)",
            ),
        ):
            selector = function_body(store, signature)
            snapshot = f"let displayedLanguage = {displayed}"
            self.assertIn(snapshot, selector)
            self.assertLess(selector.index(snapshot), selector.index(global_mutation))

    def test_selecting_actual_content_language_clears_only_matching_pending_value(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        for signature, pending in (
            (
                "func selectImageSourceLanguage(_ language: SupportedLanguage)",
                "imageTranslationRetrySourceLanguage",
            ),
            (
                "func selectImageTargetLanguage(_ language: SupportedLanguage)",
                "imageTranslationRetryTargetLanguage",
            ),
        ):
            selector = function_body(store, signature)
            retained = selector[
                selector.index("case .idle, .failed:"):
                selector.index("case .loading, .recognizing, .translating:")
            ]
            self.assertIn("guard canRetryImageTranslation else { return }", retained)
            self.assertIn(
                f"{pending} = language == displayedLanguage ? nil : language",
                retained,
            )
            self.assertNotIn("retryImageTranslation()", retained)

    def test_target_authorization_and_content_display_boundary_remain_intact(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        selector = function_body(store, "func selectImageTargetLanguage(_ language: SupportedLanguage)")
        summary = function_body(store, "var imageTranslationRetryLanguageSummary: String?")

        self.assertIn("selectTargetLanguage(language)", selector)
        self.assertIn("guard targetLanguage == language", selector)
        self.assertNotIn("isProUnlocked", selector)
        self.assertIn(
            "imageTranslationRetrySourceLanguage != nil || imageTranslationRetryTargetLanguage != nil",
            summary,
        )

    def test_accessibility_and_ci_expose_the_reversible_selection_contract(self) -> None:
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        workflow = read(".github/workflows/ci-results.yml")

        self.assertGreaterEqual(view.count("选回当前内容语言会撤销待重试更改"), 2)
        self.assertIn("36-image-retry-language-reset", workflow)
        self.assertLess(
            workflow.index("scripts/test-v35-image-retry-credential-display-contract.py"),
            workflow.index("scripts/test-v36-image-retry-language-reset-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

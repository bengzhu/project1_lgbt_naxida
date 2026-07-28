#!/usr/bin/env python3
"""Contracts for v3.7 image source-language Pro rejection feedback."""

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


class ImageSourceProFeedbackContractTests(unittest.TestCase):
    def test_source_selector_authorizes_before_any_global_or_task_mutation(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        selector = function_body(store, "func selectImageSourceLanguage(_ language: SupportedLanguage)")

        authorization = selector.index("guard isProUnlocked else")
        rejection = selector.index('dataTransferMessage = "图片输入语言设置需要 Pro"')
        global_mutation = selector.index("sourceLanguage = language")
        content_mutation = selector.index("imageTranslationContentSourceLanguage = language")
        pending_mutation = selector.index("imageTranslationRetrySourceLanguage = language")
        self.assertLess(authorization, rejection)
        self.assertLess(rejection, global_mutation)
        self.assertLess(authorization, content_mutation)
        self.assertLess(authorization, pending_mutation)

    def test_rejection_returns_before_snapshot_and_state_switch(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        selector = function_body(store, "func selectImageSourceLanguage(_ language: SupportedLanguage)")
        rejected = selector[
            selector.index("guard isProUnlocked else"):
            selector.index("let displayedLanguage")
        ]

        self.assertIn("return", rejected)
        self.assertNotIn("sourceLanguage = language", rejected)
        self.assertNotIn("imageTranslationContentSourceLanguage", rejected)
        self.assertNotIn("imageTranslationRetrySourceLanguage", rejected)

    def test_source_menu_reports_the_store_owned_pro_rejection(self) -> None:
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        control = view[
            view.index("private struct ImageSourceLanguageControl"):
            view.index("private struct ImageTargetLanguageControl")
        ]

        self.assertIn("@State private var showLockedLanguage = false", control)
        self.assertIn("store.selectImageSourceLanguage(language)", control)
        self.assertIn("if !store.isProUnlocked", control)
        self.assertIn("showLockedLanguage = true", control)
        self.assertIn('.alert("Pro 功能", isPresented: $showLockedLanguage)', control)
        self.assertIn("Text(store.dataTransferMessage)", control)
        self.assertIn('return store.isProUnlocked ? "circle" : "lock.fill"', control)
        self.assertIn("图片输入语言设置需要 Pro", control)

    def test_target_language_policy_is_unchanged_and_ci_runs_after_v36(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        target = function_body(store, "func selectImageTargetLanguage(_ language: SupportedLanguage)")
        workflow = read(".github/workflows/ci-results.yml")

        self.assertIn("selectTargetLanguage(language)", target)
        self.assertIn("guard targetLanguage == language", target)
        self.assertNotIn("isProUnlocked", target)
        self.assertIn("37-image-source-pro-feedback", workflow)
        self.assertLess(
            workflow.index("scripts/test-v36-image-retry-language-reset-contract.py"),
            workflow.index("scripts/test-v37-image-source-pro-feedback-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

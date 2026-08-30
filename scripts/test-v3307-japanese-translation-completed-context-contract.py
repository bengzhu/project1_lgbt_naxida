#!/usr/bin/env python3
"""Static contract for the v3.307 completed-context prompt boundary."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


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
                return source[brace + 1 : index]
    raise AssertionError(f"unterminated function body: {signature}")


class JapaneseTranslationCompletedContextContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.test_log = read("md/test/test.md")
        cls.update_log = read("update_log.md")

    def test_summary_eligibility_is_completed_only_and_non_empty(self) -> None:
        body_start = self.context.index("var isEligibleForPrompt: Bool")
        body = self.context[body_start : self.context.index("\n    init(", body_start)]
        for marker in (
            "isReadOnly",
            "!containsPendingInputBlocks",
            "generatedFromCompletedBlocks",
            "!items.isEmpty",
            "item.ordinal > 0",
            "item.sourceExcerpt.trimmingCharacters",
            "item.targetExcerpt.trimmingCharacters",
        ):
            self.assertIn(marker, body)

    def test_normalized_context_drops_ineligible_summaries(self) -> None:
        body = function_body(self.context, "func normalized(")
        self.assertIn(
            "if let previousBatchSummary,\n           previousBatchSummary.isEligibleForPrompt",
            body,
        )
        self.assertIn("summary = nil", body)
        self.assertIn("generatedFromCompletedBlocks", self.context)

    def test_qa_uses_the_same_normalized_read_only_context(self) -> None:
        configuration = function_body(
            self.store,
            "private func japaneseTranslationQAConfiguration(\n",
        )
        self.assertIn("let normalizedContext = translationContext.normalized()", configuration)
        for marker in (
            "confirmedTerms: normalizedContext.confirmedTerms",
            "previousBatchSummary: normalizedContext.previousBatchSummary",
            "maximumOutputCharacters: normalizedContext.maxOutputCharacters",
        ):
            self.assertIn(marker, configuration)

        failures = function_body(self.context, "private static func textFailures(")
        self.assertIn("previousBatchSummary.isEligibleForPrompt", failures)

    def test_prompt_section_cannot_reintroduce_pending_context(self) -> None:
        prompt = function_body(self.context, "func promptSection()")
        self.assertIn("let context = normalized()", prompt)
        self.assertIn("previousBatchSummary", prompt)
        self.assertIn("禁止翻译、复述或为上下文生成任何编号标签", prompt)
        self.assertNotIn("TranslationSessionStore", self.context)
        self.assertNotIn("persist()", self.context)
        self.assertNotIn("VNRecognizeTextRequest", self.context)

    def test_translation_and_ocr_scope_remain_unchanged(self) -> None:
        for marker in (
            "translateJapaneseImageBlockWithQA(",
            "TranslationBatchQualityEvaluator.evaluate(",
            "recognizeTextBlocks(",
            "imageTranslationBlocks",
        ):
            self.assertIn(marker, self.store)
        self.assertIn("request.translationContext.promptSection()", self.gemma)
        self.assertNotIn("TranslationSessionStore", self.gemma)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.361", "3.361"],
        )
        for marker in (
            "scripts/test-v3307-japanese-translation-completed-context-contract.py",
            "v3.307",
            "japanese-benchmark-v3.307-",
        ):
            self.assertIn(marker, self.workflow)
        for document in (self.flow, self.route, self.test_log, self.update_log):
            self.assertIn("v3.307", document)


if __name__ == "__main__":
    unittest.main(verbosity=2)

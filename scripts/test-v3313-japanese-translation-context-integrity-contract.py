#!/usr/bin/env python3
"""Static contract for v3.313 cross-batch context identity/language safety."""

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


class JapaneseTranslationContextIntegrityContractTests(unittest.TestCase):
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

    def test_summary_requires_identity_and_strict_ordinals(self) -> None:
        start = self.context.index("var isEligibleForPrompt: Bool")
        body = self.context[start : self.context.index("\n    /// A structurally", start)]
        for marker in (
            "!batchID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty",
            "let ordinals = items.map(\\.ordinal)",
            "Set(ordinals).count == ordinals.count",
            "item.ordinal != items[index - 1].ordinal + 1",
            "item.ordinal > 0",
            "item.sourceExcerpt.trimmingCharacters",
            "item.targetExcerpt.trimmingCharacters",
        ):
            self.assertIn(marker, body)

    def test_summary_language_pair_is_checked_against_request(self) -> None:
        method = function_body(
            self.context,
            "func isEligibleForPrompt(\n        sourceLanguage:",
        )
        self.assertIn("isEligibleForPrompt", method)
        self.assertIn("self.sourceLanguage == sourceLanguage", method)
        self.assertIn("self.targetLanguage == targetLanguage", method)

        normalized = function_body(self.context, "func normalized(")
        self.assertIn(
            "previousBatchSummary.isEligibleForPrompt(\n                   sourceLanguage: requestSourceLanguage",
            normalized,
        )
        self.assertIn("summary = nil", normalized)

    def test_language_binding_is_transient_and_fail_closed_when_unbound(self) -> None:
        self.assertIn("func bound(\n        to sourceLanguage:", self.context)
        coding_start = self.context.index("private enum CodingKeys")
        coding_end = self.context.index("\n    init(from decoder:", coding_start)
        coding_keys = self.context[coding_start:coding_end]
        self.assertNotIn("requestSourceLanguage", coding_keys)
        self.assertNotIn("requestTargetLanguage", coding_keys)
        normalized = function_body(self.context, "func normalized(")
        self.assertIn("let requestSourceLanguage", normalized)
        self.assertIn("let requestTargetLanguage", normalized)

    def test_both_image_qa_boundaries_use_current_language_pair(self) -> None:
        for signature in (
            "private func japaneseTranslationQAConfiguration(\n",
            "private func imageTranslationQAConfiguration(\n",
        ):
            signature_start = self.store.index(signature)
            signature_end = self.store.index("{", signature_start)
            declaration = self.store[signature_start:signature_end]
            self.assertIn("sourceLanguage: SupportedLanguage", declaration)
            body = function_body(self.store, signature)
            self.assertIn("let translationContext = incomingContext.bound(", body)
            self.assertIn("to: sourceLanguage", body)
            self.assertIn("targetLanguage: targetLanguage", body)
            self.assertIn("let normalizedContext = translationContext.normalized()", body)

        failures = function_body(self.context, "private static func textFailures(")
        self.assertIn("previousBatchSummary.isEligibleForPrompt", failures)
        self.assertIn("sourceLanguage: configuration.sourceLanguage", failures)
        self.assertIn("targetLanguage: configuration.targetLanguage", failures)

        batch = function_body(self.store, "private func translateJapaneseImageBatch(\n")
        self.assertIn("sourceLanguage: sourceLanguage", batch)
        single = function_body(
            self.store,
            "private func translateJapaneseImageBlockWithQA(\n",
        )
        self.assertIn("sourceLanguage: sourceLanguage", single)

    def test_model_prompt_boundary_binds_resolved_languages(self) -> None:
        request = function_body(self.store, "private func makeRequest(\n")
        self.assertIn("let resolvedSourceLanguage", request)
        self.assertIn("let resolvedTargetLanguage", request)
        self.assertIn(".bound(\n                    to: resolvedSourceLanguage", request)
        self.assertIn("targetLanguage: resolvedTargetLanguage", request)
        self.assertIn("translationContext: (translationContext", request)
        self.assertIn("request.translationContext.promptSection()", self.gemma)

    def test_single_block_context_uses_one_based_contiguous_ordinals(self) -> None:
        prompt = function_body(
            self.store,
            "private func japaneseImageTranslationPrompt(\n",
        )
        self.assertIn("TranslationReadOnlyBatchSummary(", prompt)
        self.assertIn(
            "(imageTranslationOriginalBlockOrder[previousBlock.id]\n                                ?? previousStartIndex + offset) + 1",
            prompt,
        )
        self.assertIn("sourceLanguage: contextSourceLanguage", prompt)
        self.assertIn("targetLanguage: contextTargetLanguage", prompt)

    def test_context_remains_outside_persistence_ocr_and_store_state(self) -> None:
        self.assertNotIn("persist()", self.context)
        self.assertNotIn("VNRecognizeTextRequest", self.context)
        prompt_start = self.store.index("private func japaneseImageTranslationPrompt(")
        prompt_end = self.store.index("\n    /// Returns the current page", prompt_start)
        prompt = self.store[prompt_start:prompt_end]
        self.assertNotIn("persist()", prompt)
        self.assertNotIn("imageTranslationBlocks =", prompt)
        self.assertNotIn("recognizeText", prompt)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.343", "3.343"],
        )
        for marker in (
            "scripts/test-v3313-japanese-translation-context-integrity-contract.py",
            "v3.313",
            "japanese-benchmark-v3.313-",
        ):
            self.assertIn(marker, self.workflow + self.route + self.flow + self.test_log + self.update_log)

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3313-japanese-translation-context-integrity-contract.py"
        )
        for source in (self.context, self.store, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

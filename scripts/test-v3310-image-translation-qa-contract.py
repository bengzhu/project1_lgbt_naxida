#!/usr/bin/env python3
"""Static contract for v3.310 ordinary image translation QA."""

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


class ImageTranslationQAContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.test_log = read("md/test/test.md")
        cls.update_log = read("update_log.md")

    def test_non_japanese_full_page_uses_single_block_quality_gate(self) -> None:
        body = function_body(
            self.store,
            "private func runImageTranslationPipeline(\n",
        )
        branch_start = body.index("} else {")
        branch_end = body.index("\n        }\n\n        imageTranslationBlocks = translatedBlocks", branch_start)
        non_japanese = body[branch_start:branch_end]
        self.assertIn("translateImageBlockWithQA(", non_japanese)
        self.assertIn("confirmedTerms: translationTermMemory", non_japanese)
        self.assertIn("textKind: block.textKind ?? .dialogue", non_japanese)
        self.assertNotIn("translatedBlocks[index].translation = try await translate(", non_japanese)

    def test_non_japanese_correction_retry_and_reread_share_gate(self) -> None:
        correction = function_body(
            self.store,
            "func correctImageTranslationBlock(",
        )
        retry = function_body(
            self.store,
            "func retryImageTranslationBlock(",
        )
        reread = function_body(
            self.store,
            "func rerecognizeImageTranslationBlock(\n",
        )
        for body in (correction, retry, reread):
            self.assertIn("translateImageBlockWithQA(", body)
            self.assertIn("confirmedTerms:", body)
            self.assertIn("textKind:", body)

    def test_gate_calls_standard_translation_then_shared_fail_closed_qa(self) -> None:
        body = function_body(
            self.store,
            "private func translateImageBlockWithQA(\n",
        )
        for marker in (
            "let candidate = try await translate(",
            "try Task.checkCancellation()",
            "TranslationBatchQualityEvaluator.singleOutputFailures(",
            "imageTranslationQAConfiguration(",
            "guard failures.isEmpty else",
            "ImageMangaBatchTranslationError.qualityFailure([0])",
            "return cleanCandidate",
        ):
            self.assertIn(marker, body)
        self.assertNotIn("recognizeTextBlocks(", body)
        self.assertNotIn("ImageOCRLayoutEngine.layout", body)
        self.assertNotIn("cancelImageTranslation()", body)

    def test_context_is_normalized_for_both_qa_paths(self) -> None:
        generic = function_body(
            self.store,
            "private func imageTranslationQAConfiguration(\n",
        )
        japanese = function_body(
            self.store,
            "private func japaneseTranslationQAConfiguration(\n",
        )
        self.assertIn("let normalizedContext = translationContext.normalized()", generic)
        for marker in (
            "let normalizedContext = translationContext.normalized()",
            "confirmedTerms: normalizedContext.confirmedTerms",
            "previousBatchSummary: normalizedContext.previousBatchSummary",
            "maximumOutputCharacters: normalizedContext.maxOutputCharacters",
        ):
            self.assertIn(marker, generic)
        self.assertIn("let normalizedContext = translationContext.normalized()", japanese)

    def test_japanese_tagged_path_remains_primary_and_qa_backed(self) -> None:
        pipeline = function_body(
            self.store,
            "private func runImageTranslationPipeline(\n",
        )
        self.assertIn("if sourceLanguage == .japanese {", pipeline)
        self.assertIn("translateJapaneseImageBatch(", pipeline)
        japanese_batch = function_body(
            self.store,
            "private func translateJapaneseImageBatch(\n",
        )
        self.assertIn("TranslationBatchQualityEvaluator.evaluate(", japanese_batch)
        self.assertIn("translateJapaneseImageBlockWithQA(", japanese_batch)

    def test_qa_path_does_not_change_ocr_or_session_boundaries(self) -> None:
        body = function_body(
            self.store,
            "private func translateImageBlockWithQA(\n",
        )
        for forbidden in (
            "recognizeTextBlock(",
            "recognizeTextBlocks(",
            "imageTranslationBlocks =",
            "imageTranslationOriginalBlockOrder =",
            "imageTranslationJapaneseBatchPlan =",
            "persist()",
            "Koharu",
            "MangaOCRService",
        ):
            self.assertNotIn(forbidden, body)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.335", "3.335"],
        )
        for marker in (
            "scripts/test-v3310-image-translation-qa-contract.py",
            "v3.310",
            "japanese-benchmark-v3.310-",
        ):
            self.assertIn(marker, self.workflow)
        for document in (
            self.flow,
            self.route,
            self.test_log,
            self.update_log,
        ):
            self.assertIn("v3.310", document)

    def test_contract_and_store_have_no_process_entry(self) -> None:
        contract = read("scripts/test-v3310-image-translation-qa-contract.py")
        for source in (contract, self.store):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

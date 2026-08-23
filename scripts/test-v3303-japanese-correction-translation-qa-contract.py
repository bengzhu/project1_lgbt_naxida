#!/usr/bin/env python3
"""Static contract for v3.303 Japanese correction/retry context and QA."""

from __future__ import annotations

import copy
import importlib.util
import json
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


def load_evaluator():
    path = ROOT / "scripts/evaluate-japanese-translation-context-qa.py"
    spec = importlib.util.spec_from_file_location("v3303_context_qa", path)
    if spec is None or spec.loader is None:
        raise AssertionError("unable to load translation context evaluator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class JapaneseCorrectionTranslationQAContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.update_log = read("update_log.md")
        cls.test_log = read("md/test/test.md")
        cls.fixture = json.loads(
            read("benchmarks/japanese_translation/examples/translation_context_qa/input.json")
        )
        cls.evaluator = load_evaluator()

    def test_japanese_correction_uses_temporary_block_and_shared_qa(self) -> None:
        body = function_body(self.store, "func correctImageTranslationBlock(")
        japanese_branch = body[body.index("if sourceLanguage == .japanese") : body.index("} else {")]
        for marker in (
            "var correctedBlock = currentBlock",
            "correctedBlock.original = correctedOriginal",
            "correctedBlock.translation = \"\"",
            "japaneseImageTranslationPrompt(",
            "translateJapaneseImageBlockWithQA(",
            "expectedID: prompt.startIndex + 1",
            "translationContext: prompt.context",
        ):
            self.assertIn(marker, japanese_branch)
        self.assertNotIn("correctedTranslation = try await translate(\n", japanese_branch)
        self.assertLess(
            japanese_branch.index("translateJapaneseImageBlockWithQA("),
            body.index("imageTranslationBlocks[currentIndex] = correctedBlock"),
        )

    def test_non_japanese_correction_uses_current_image_translation_qa_path(self) -> None:
        body = function_body(self.store, "func correctImageTranslationBlock(")
        non_japanese_branch = body[body.index("} else {") :]
        self.assertIn("correctedTranslation = try await translateImageBlockWithQA(", non_japanese_branch)
        self.assertIn("TranslationPromptContext(", non_japanese_branch)
        self.assertNotIn("translateJapaneseImageBlockWithQA(", non_japanese_branch)

    def test_retry_reuses_page_ordinal_and_rebuilt_context(self) -> None:
        body = function_body(self.store, "func retryImageTranslationBlock(")
        japanese_branch = body[
            body.index("if sourceLanguage == .japanese") : body.index("} else {")
        ]
        for marker in (
            "let prompt = self.japaneseImageTranslationPrompt(for: blockID)",
            "startIndex: prompt.startIndex",
            "translationContext: prompt.context",
            "translateJapaneseImageBatch(",
        ):
            self.assertIn(marker, japanese_branch)
        self.assertNotIn("recognizeTextBlock", body)
        self.assertNotIn("recognizeTextBlocks", body)

    def test_scoped_rerecognition_uses_same_qa_when_japanese_text_changes(self) -> None:
        body = function_body(self.store, "func rerecognizeImageTranslationBlock(")
        japanese_branch = body[body.index("if sourceLanguage == .japanese") :]
        for marker in (
            "japaneseImageTranslationPrompt(",
            "textKindOverride: translationBlock.textKind",
            "translateJapaneseImageBlockWithQA(",
            "expectedID: prompt.startIndex + 1",
            "translationContext: prompt.context",
        ):
            self.assertIn(marker, japanese_branch)

    def test_context_rebuild_reads_only_previous_completed_batch(self) -> None:
        helper = function_body(
            self.store,
            "private func japaneseImageTranslationPrompt(\n",
        )
        for marker in (
            "let contextBlocks = imageTranslationContextBlocks()",
            "let batchPlan = currentJapaneseImageTranslationBatchPlan()",
            "let currentBatchIndex = batchPlan.firstIndex",
            "currentBatchIndex > 0",
            "let previousPlan = batchPlan[currentBatchIndex - 1]",
            "let previousBlocks = previousPlan.blockIDs.compactMap",
            "let previousBatchComplete",
            "previousBlocks.count == previousPlan.blockIDs.count",
            "previousBlocks.allSatisfy",
            "TranslationReadOnlyBatchSummary(",
            "sourceExcerpt: previousBlock.original",
            "targetExcerpt: previousBlock.translation",
            "confirmedTerms: translationTermMemory",
            "batchStartIndex: startIndex",
            "textKind: textKindOverride ?? block?.textKind ?? .dialogue",
        ):
            self.assertIn(marker, helper)
        self.assertNotIn("persist()", helper)
        self.assertNotIn("imageTranslationBlocks =", helper)
        self.assertNotIn("recognizeText", helper)

    def test_context_and_qa_remain_fail_closed_for_correction_output(self) -> None:
        fixture = copy.deepcopy(self.fixture)
        batch = fixture["batches"][0]
        batch["rawOutput"] = "[1] 无法翻译，请提供文本"
        report = self.evaluator.evaluate_batch(batch, fixture["context"])
        self.assertIn("placeholderOutput", report["failureReasons"]["1"])

        fixture = copy.deepcopy(self.fixture)
        batch = fixture["batches"][0]
        fixture["context"]["confirmedTerms"] = []
        batch["rawOutput"] = "[1] Koharu先生、9時に来て。"
        report = self.evaluator.evaluate_batch(batch, fixture["context"])
        self.assertIn("sourceLeakage", report["failureReasons"]["1"])

    def test_commit_and_persistence_happen_only_after_qa_result(self) -> None:
        body = function_body(self.store, "func correctImageTranslationBlock(")
        self.assertLess(
            body.index("translateJapaneseImageBlockWithQA("),
            body.index("imageTranslationBlocks[currentIndex] = correctedBlock"),
        )
        self.assertLess(
            body.index("imageTranslationBlocks[currentIndex] = correctedBlock"),
            body.index("persist()"),
        )
        self.assertIn("imageTranslationCorrectionID == correctionID", body)
        self.assertIn("imageTranslationTaskID == contentTaskID", body)

    def test_version_workflow_and_docs_are_current(self) -> None:
        combined = (
            self.workflow
            + self.route
            + self.flow
            + self.update_log
            + self.test_log
        )
        for marker in (
            "scripts/test-v3303-japanese-correction-translation-qa-contract.py",
            "v3.303",
            "japanese-benchmark-v3.306-",
        ):
            self.assertIn(marker, combined)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.333", "3.333"],
        )

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read("scripts/test-v3303-japanese-correction-translation-qa-contract.py")
        for source in (self.store, self.context, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

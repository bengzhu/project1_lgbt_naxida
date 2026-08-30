#!/usr/bin/env python3
"""Static and pure-policy contract for v3.296 per-block fallback QA."""

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


def load_evaluator():
    path = ROOT / "scripts/evaluate-japanese-translation-context-qa.py"
    spec = importlib.util.spec_from_file_location("v3296_context_qa", path)
    if spec is None or spec.loader is None:
        raise AssertionError("unable to load translation context evaluator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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


class JapaneseTranslationFallbackQAContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.context_source = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.update_log = read("update_log.md")
        cls.test_log = read("md/test/test.md")
        cls.fixture = json.loads(
            read("benchmarks/japanese_translation/examples/translation_context_qa/input.json")
        )
        cls.evaluator = load_evaluator()

    def test_single_block_helper_reuses_batch_qa_and_fails_closed(self) -> None:
        body = function_body(
            self.store,
            "private func translateJapaneseImageBlockWithQA(\n",
        )
        for marker in (
            "let candidate = try await translate(",
            "try Task.checkCancellation()",
            "TranslationBatchQualityEvaluator.singleOutputFailures(",
            "japaneseTranslationQAConfiguration(",
            "guard failures.isEmpty else",
            "ImageMangaBatchTranslationError.qualityFailure([expectedID])",
        ):
            self.assertIn(marker, body)
        self.assertLess(body.index("let candidate ="), body.index("guard failures.isEmpty"))
        self.assertLess(body.index("guard failures.isEmpty"), body.index("return cleanCandidate"))

    def test_fallback_routes_every_candidate_through_the_same_qa(self) -> None:
        body = function_body(
            self.store,
            "private func translateJapaneseImageBatch(\n",
        )
        fallback_start = body.index("正在逐块安全回退并复用质量检查")
        fallback = body[fallback_start:]
        self.assertIn("for (offset, block) in blocks.enumerated()", fallback)
        self.assertIn("expectedID: expectedIDs[offset]", fallback)
        self.assertIn("let candidate = try await translateJapaneseImageBlockWithQA(", fallback)
        self.assertIn("fallbackTranslations.append(candidate)", fallback)
        self.assertNotIn("fallbackTranslations.append(try await translate(", fallback)

    def test_retry_does_not_swallow_cancellation_or_assign_before_qa(self) -> None:
        body = function_body(
            self.store,
            "private func translateJapaneseImageBatch(\n",
        )
        retry_start = body.index("var failedOffsets = Set<Int>()")
        retry_end = body.index("guard failedOffsets.isEmpty", retry_start)
        retry = body[retry_start:retry_end]
        self.assertIn("catch is CancellationError", retry)
        self.assertIn("throw CancellationError()", retry)
        self.assertLess(retry.index("let candidate ="), retry.index("translations[offset] = candidate"))

    def test_placeholder_and_target_language_failures_are_reported(self) -> None:
        batch = copy.deepcopy(self.fixture["batches"][0])
        context = self.fixture["context"]

        batch["rawOutput"] = "[1] 无法翻译，请提供文本"
        placeholder_report = self.evaluator.evaluate_batch(batch, context)
        self.assertIn("placeholderOutput", placeholder_report["failureReasons"]["1"])

        batch["rawOutput"] = "[1] This is an English-only answer"
        english_report = self.evaluator.evaluate_batch(batch, context)
        self.assertIn("targetLanguageDensity", english_report["failureReasons"]["1"])

    def test_context_and_length_rules_reach_single_block_fallback(self) -> None:
        helper = function_body(
            self.store,
            "private func japaneseTranslationQAConfiguration(\n",
        )
        for marker in (
            "let normalizedContext = translationContext.normalized()",
            "confirmedTerms: normalizedContext.confirmedTerms",
            "previousBatchSummary: normalizedContext.previousBatchSummary",
            "maximumOutputCharacters: normalizedContext.maxOutputCharacters",
        ):
            self.assertIn(marker, helper)
        self.assertIn("previousContextLeakage", self.context_source)
        self.assertIn("outputTooLong", self.context_source)
        self.assertIn("placeholderOutput", self.context_source)
        report = self.evaluator.evaluate(copy.deepcopy(self.fixture))
        qa_gate = next(gate for gate in report["gateLedger"] if gate["gateID"] == "G-translation-QA")
        self.assertIn("placeholder outputs", qa_gate["detail"])

    def test_failed_fallback_candidate_cannot_be_returned_or_persisted(self) -> None:
        batch = function_body(
            self.store,
            "private func translateJapaneseImageBatch(\n",
        )
        fallback_start = batch.index("正在逐块安全回退并复用质量检查")
        fallback = batch[fallback_start:]
        helper_start = self.store.index("private func translateJapaneseImageBlockWithQA(")
        helper = self.store[helper_start:]
        self.assertIn("var fallbackTranslations: [String] = []", fallback)
        self.assertIn("throw ImageMangaBatchTranslationError.qualityFailure([expectedID])", helper)
        self.assertNotIn("persist()", fallback)
        self.assertNotIn("imageTranslationBlocks =", fallback)

    def test_project_workflow_route_and_version_are_explicit(self) -> None:
        combined = (
            self.project
            + self.workflow
            + self.store
            + self.route
            + self.update_log
            + self.test_log
        )
        for marker in (
            "scripts/test-v3296-japanese-translation-fallback-qa-contract.py",
            "v3.296",
            "逐块安全回退并复用质量检查",
            "placeholderOutput",
            "japanese-benchmark-v3.301-",
        ):
            self.assertIn(marker, combined)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.349", "3.349"],
        )

    def test_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3296-japanese-translation-fallback-qa-contract.py"
        )
        process_word = "sub" + "process"
        popen_word = "Po" + "pen"
        system_word = "os." + "system"
        for source in (contract, self.context_source, self.store):
            self.assertNotIn(process_word, source)
            self.assertNotIn(popen_word, source)
            self.assertNotIn(system_word, source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

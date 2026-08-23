#!/usr/bin/env python3
"""Static and pure-policy contract for the v3.319 shared-Han QA boundary."""

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


def load_module(relative: str, name: str):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"unable to load {relative}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class JapaneseSharedHanTranslationQAContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.test_log = read("md/test/test.md")
        cls.update_log = read("update_log.md")
        cls.fixture = json.loads(
            read("benchmarks/japanese_translation/examples/translation_context_qa/input.json")
        )
        cls.context_evaluator = load_module(
            "scripts/evaluate-japanese-translation-context-qa.py",
            "v3319_context_qa",
        )
        cls.translation_evaluator = load_module(
            "scripts/evaluate-japanese-translation-benchmark.py",
            "v3319_translation_benchmark",
        )

    def test_product_qa_uses_language_aware_source_leakage(self) -> None:
        start = self.context.index("private static func isSourceLeakage(")
        body = self.context[start:]
        for marker in (
            "normalizedSource",
            "normalizedOutput",
            "sourceLanguage",
            "targetLanguage",
            "sourceLanguage == .japanese",
            "targetLanguage == .simplifiedChinese",
            "isSharedHanOnlyJapaneseSource(source)",
        ):
            self.assertIn(marker, body)
        self.assertIn("isSourceLeakage(", self.context)
        self.assertIn('failures.append("sourceLeakage")', self.context)
        self.assertNotIn("if normalizedSource.count > 1,", self.context)

    def test_shared_han_translation_is_not_false_leakage(self) -> None:
        shared_han = copy.deepcopy(self.fixture)
        shared_han["batches"][0]["sourceBlocks"][0]["sourceText"] = "日本"
        shared_han["batches"][0]["rawOutput"] = "[1] 日本"
        report = self.context_evaluator.evaluate_batch(
            shared_han["batches"][0], shared_han["context"]
        )
        self.assertNotIn("sourceLeakage", report["failureReasons"].get("1", []))
        self.assertEqual(report["failedBlockIDs"], [])

    def test_kana_bearing_original_still_rejects_exact_leakage(self) -> None:
        leaked = copy.deepcopy(self.fixture)
        leaked["batches"][0]["sourceBlocks"][0]["sourceText"] = "日本の"
        leaked["batches"][0]["rawOutput"] = "[1] 日本の"
        report = self.context_evaluator.evaluate_batch(
            leaked["batches"][0], leaked["context"]
        )
        self.assertIn("sourceLeakage", report["failureReasons"]["1"])

    def test_generic_benchmark_and_product_evaluator_share_exception(self) -> None:
        evaluator = self.translation_evaluator
        self.assertFalse(evaluator._source_leakage("日本", "日本", "ja", "zh-CN"))
        self.assertTrue(evaluator._source_leakage("日本の", "日本の", "ja", "zh-CN"))
        self.assertTrue(evaluator._source_leakage("Koharu先生", "Koharu先生", "ja", "zh-CN"))
        self.assertTrue(evaluator._source_leakage("hello", "hello", "en", "zh-CN"))

    def test_ocr_translation_and_persistence_boundaries_are_unchanged(self) -> None:
        for marker in (
            "TranslationBatchQualityEvaluator.singleOutputFailures(",
            "TranslationBatchQualityEvaluator.evaluate(",
            "translateImageBlockWithQA(",
            "persist()",
            "cancelImageTranslation()",
        ):
            self.assertIn(marker, self.store)
        for forbidden in (
            "recognizeTextBlocks(in: data",
            "ImageOCRLayoutEngine.layout",
            "MangaOCRService.shared",
        ):
            self.assertNotIn(forbidden, self.context)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.328", "3.328"],
        )
        for marker in (
            "scripts/test-v3319-japanese-shared-han-translation-qa-contract.py",
            "v3.319",
            "japanese-benchmark-v3.319-",
        ):
            self.assertIn(marker, self.workflow)
        for document in (
            self.flow,
            self.route,
            self.test_log,
            self.update_log,
        ):
            self.assertIn("v3.319", document)

    def test_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3319-japanese-shared-han-translation-qa-contract.py"
        )
        for source in (contract, self.context, self.store):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

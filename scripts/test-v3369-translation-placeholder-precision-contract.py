#!/usr/bin/env python3
"""Static and pure-policy contract for v3.375 translation placeholder precision."""

from __future__ import annotations

import importlib.util
import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def load_evaluator():
    path = ROOT / "scripts/evaluate-japanese-translation-context-qa.py"
    spec = importlib.util.spec_from_file_location("v3369_context_qa", path)
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


class TranslationPlaceholderPrecisionContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.policy = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.qa = read("scripts/evaluate-japanese-translation-context-qa.py")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.docs = "".join(
            read(path)
            for path in (
                "README.md",
                "md/flow/flow.md",
                "md/flow/flowchart.md",
                "md/test/test.md",
                "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md",
                "update_log.md",
            )
        )
        cls.evaluator = load_evaluator()

    def test_short_dialogue_requests_are_not_placeholder_only_by_generic_noun(self) -> None:
        accepted = (
            "请提供文本。",
            "请输入内容。",
            "请给出句子。",
            "请提供原文。",
            "请提供译文。",
            "Please provide the content.",
            "我说：请提供需要翻译的文本。",
        )
        for value in accepted:
            self.assertFalse(self.evaluator.is_placeholder_response(value), value)

    def test_explicit_translation_input_requests_are_still_placeholder(self) -> None:
        rejected = (
            "请提供需要翻译的文本",
            "请输入待翻译内容",
            "请给出翻译以下文本",
            "Please provide the text to translate.",
            "Kindly provide the source text to translate.",
        )
        for value in rejected:
            self.assertTrue(self.evaluator.is_placeholder_response(value), value)

    def test_embedded_request_phrase_is_not_metadata(self) -> None:
        self.assertFalse(
            self.evaluator.is_placeholder_response("我说：请提供需要翻译的文本。")
        )
        self.assertFalse(
            self.evaluator.is_placeholder_response("他说 Please enter the content.")
        )

    def test_existing_refusal_and_meta_boundaries_remain(self) -> None:
        rejected = (
            "无法翻译，请提供需要翻译的文本",
            "Please provide more context.",
            "翻译失败",
            "N/A",
            "翻译是：",
            "翻译成中文",
        )
        accepted = (
            "谢谢",
            "Thank you",
            "请提供证件。",
            "翻译是：你好。",
            "这里有更多上下文。",
        )
        for value in rejected:
            self.assertTrue(self.evaluator.is_placeholder_response(value), value)
        for value in accepted:
            self.assertFalse(self.evaluator.is_placeholder_response(value), value)

    def test_swift_and_cloud_policy_use_same_narrow_shape(self) -> None:
        policy_body = function_body(
            self.policy,
            "static func isPlaceholderResponse(_ text: String) -> Bool",
        )
        self.assertIn("let requestMarkers", policy_body)
        self.assertIn("let translationInputMarkers", policy_body)
        self.assertIn("startsWithRequestMarker", policy_body)
        self.assertIn("hasExplicitTranslationInput", policy_body)
        self.assertIn("compact.hasPrefix", policy_body)
        self.assertNotIn("translationInputMarkers.contains(where: { compact.contains", policy_body)
        self.assertIn("normalized_request_markers", self.qa)
        self.assertIn("normalized_input_markers", self.qa)
        self.assertIn("compact.startswith(marker)", self.qa)

    def test_product_qa_and_fallback_wiring_remain(self) -> None:
        self.assertIn("TranslationOutputPolicy.isPlaceholderResponse(translatedText)", self.policy)
        self.assertIn("TranslationOutputPolicy.isPlaceholderResponse(output)", self.gemma)
        self.assertIn("translateJapaneseImageBlockWithQA(", self.store)
        self.assertIn("TranslationBatchQualityEvaluator.evaluate(", self.policy + self.store)
        self.assertNotIn("VisionOCRService", self.policy)
        self.assertNotIn("MangaOCRService.shared", self.policy)
        self.assertNotIn("persist()", self.policy)
        self.assertNotIn("KOHARU_DATA_ROOT", self.policy + self.store)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.375", "3.375"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3369-translation-placeholder-precision-contract.py",
            "v3.375",
            "japanese-benchmark-v3.375-",
        ):
            self.assertIn(marker, combined)

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read("scripts/test-v3369-translation-placeholder-precision-contract.py")
        for source in (self.policy, self.gemma, self.store, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

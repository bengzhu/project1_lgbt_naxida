#!/usr/bin/env python3
"""Static and pure-policy contract for v3.375 refusal-marker boundaries."""

from __future__ import annotations

import importlib.util
import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def load_evaluator():
    evaluator_path = ROOT / "scripts/evaluate-japanese-translation-context-qa.py"
    spec = importlib.util.spec_from_file_location("v3375_context_qa", evaluator_path)
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


class TranslationRefusalMarkerBoundaryContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.policy = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.evaluator_source = read("scripts/evaluate-japanese-translation-context-qa.py")
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

    def test_embedded_refusal_phrases_remain_translation_content(self) -> None:
        accepted = (
            "他说：无法翻译这句话。",
            "这段对白写着：翻译失败，但故事还在继续。",
            "我记得他曾说：无法提供译文。",
            "这个角色说：请提供更多信息，然后离开。",
            "她引用了 unable to translate，却没有拒绝当前请求。",
        )
        for value in accepted:
            self.assertFalse(self.evaluator.is_placeholder_response(value), value)

    def test_response_level_refusals_and_limited_apologies_still_fail_closed(self) -> None:
        rejected = (
            "无法翻译，请提供需要翻译的文本",
            "翻译失败",
            "Please provide more context.",
            "抱歉，无法翻译。",
            "很抱歉，无法提供译文。",
            "I'm sorry, unable to translate.",
        )
        for value in rejected:
            self.assertTrue(self.evaluator.is_placeholder_response(value), value)

    def test_short_and_exact_meta_boundaries_remain(self) -> None:
        rejected = ("N/A", "翻译是：", "翻译成中文", "Translation unavailable")
        accepted = ("谢谢", "Thank you", "翻译是：你好。", "这里有更多上下文。")
        for value in rejected:
            self.assertTrue(self.evaluator.is_placeholder_response(value), value)
        for value in accepted:
            self.assertFalse(self.evaluator.is_placeholder_response(value), value)

    def test_swift_policy_uses_leading_refusal_shape(self) -> None:
        body = function_body(
            self.policy,
            "static func isPlaceholderResponse(_ text: String) -> Bool",
        )
        for marker in (
            "let compactRefusalMarkers = refusalMarkers.map",
            "let compactApologyPrefixes = [",
            "let hasLeadingRefusalMarker = compactRefusalMarkers.contains",
            "compact.hasPrefix(marker)",
            "compact.dropFirst(prefix.count).hasPrefix(marker)",
            "if compact.count <= 96, hasLeadingRefusalMarker",
        ):
            self.assertIn(marker, body)
        self.assertNotIn("compact.contains($0.filter", body)

    def test_cloud_shadow_policy_matches_without_arbitrary_substring_match(self) -> None:
        self.assertIn("normalized_refusal_markers = tuple", self.evaluator_source)
        self.assertIn("apology_prefixes = tuple", self.evaluator_source)
        self.assertIn("has_leading_refusal_marker = any(", self.evaluator_source)
        self.assertIn("compact.startswith(marker)", self.evaluator_source)
        self.assertNotIn("any(marker in compact for marker in refusal_markers)", self.evaluator_source)

    def test_product_and_batch_qa_wiring_remain_shared(self) -> None:
        self.assertIn("TranslationOutputPolicy.isPlaceholderResponse(output)", self.gemma)
        self.assertIn("TranslationOutputPolicy.isPlaceholderResponse(translatedText)", self.policy)
        self.assertIn("TranslationBatchQualityEvaluator.singleOutputFailures(", self.store)
        self.assertIn("TranslationBatchQualityEvaluator.evaluate(", self.store)
        self.assertIn("targetLanguageDensity", self.policy)
        self.assertIn("confirmedTermMismatch", self.policy)

    def test_ocr_budget_cancellation_persistence_and_research_boundaries_remain(self) -> None:
        for source in (self.policy, self.gemma):
            for forbidden in (
                "VisionOCRService",
                "MangaOCRService.shared",
                "persist()",
                "groundTruth",
                "KOHARU_DATA_ROOT",
            ):
                self.assertNotIn(forbidden, source)
        self.assertIn("VisionOCRService()", self.store)
        self.assertIn("persist()", self.store)
        self.assertNotIn("KOHARU_DATA_ROOT", self.store)

    def test_version_workflow_docs_and_contract_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.380", "3.380"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3375-translation-refusal-marker-boundary-contract.py",
            "v3.375",
            "japanese-benchmark-v3.375-",
        ):
            self.assertIn(marker, combined)

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read("scripts/test-v3375-translation-refusal-marker-boundary-contract.py")
        for source in (self.policy, self.gemma, self.store, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

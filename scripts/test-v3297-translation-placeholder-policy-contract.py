#!/usr/bin/env python3
"""Static and pure-policy contract for v3.297 translation placeholder precision."""

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
    spec = importlib.util.spec_from_file_location("v3297_context_qa", path)
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


class TranslationPlaceholderPolicyContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.policy_source = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.qa = read("scripts/evaluate-japanese-translation-context-qa.py")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.update_log = read("update_log.md")
        cls.test_log = read("md/test/test.md")
        cls.evaluator = load_evaluator()

    def test_policy_rejects_only_explicit_translation_meta_responses(self) -> None:
        rejected = (
            "无法翻译，请提供需要翻译的文本",
            "Please provide the text to translate.",
            "翻译失败",
            "N/A",
            "翻译是：",
            "翻译成中文",
            "Please provide more context.",
        )
        accepted_dialogue = (
            "谢谢",
            "Thank you",
            "请提供证件。",
            "翻译是：你好。",
            "翻译",
            "这里有更多上下文。",
        )
        for value in rejected:
            self.assertTrue(
                self.evaluator.is_placeholder_response(value),
                value,
            )
        for value in accepted_dialogue:
            self.assertFalse(
                self.evaluator.is_placeholder_response(value),
                value,
            )

    def test_swift_qa_gemma_and_probe_share_policy(self) -> None:
        self.assertIn("enum TranslationOutputPolicy", self.policy_source)
        self.assertIn(
            "TranslationOutputPolicy.isPlaceholderResponse(translatedText)",
            self.policy_source,
        )
        self.assertIn(
            "TranslationOutputPolicy.isPlaceholderResponse(output)",
            self.gemma,
        )
        body = function_body(
            self.store,
            "private static func isPlaceholderTranslationOutput(_ output: String) -> Bool",
        )
        self.assertEqual(
            body.strip(),
            "TranslationOutputPolicy.isPlaceholderResponse(output)",
        )
        self.assertNotIn('"谢谢"', body)
        self.assertNotIn('"thank you"', body)

    def test_policy_does_not_use_broad_substring_markers(self) -> None:
        policy_body = function_body(
            self.policy_source,
            "static func isPlaceholderResponse(_ text: String) -> Bool",
        )
        self.assertIn("exactMetaResponses", policy_body)
        self.assertIn("requestMarkers", policy_body)
        self.assertIn("translationInputMarkers", policy_body)
        self.assertIn("compact.count <= 96", policy_body)
        self.assertNotIn('return markers.contains { normalized.contains($0) }', policy_body)

    def test_version_workflow_and_docs_are_current(self) -> None:
        combined = self.policy_source + self.gemma + self.store + self.qa
        combined += self.workflow + self.route + self.update_log + self.test_log
        for marker in (
            "scripts/test-v3297-translation-placeholder-policy-contract.py",
            "v3.297",
            "TranslationOutputPolicy",
            "japanese-benchmark-v3.301-",
        ):
            self.assertIn(marker, combined)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.364", "3.364"],
        )

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        process_word = "sub" + "process"
        popen_word = "Po" + "pen"
        system_word = "os." + "system"
        contract = read("scripts/test-v3297-translation-placeholder-policy-contract.py")
        for source in (self.policy_source, self.gemma, self.store, contract):
            self.assertNotIn(process_word, source)
            self.assertNotIn(popen_word, source)
            self.assertNotIn(system_word, source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

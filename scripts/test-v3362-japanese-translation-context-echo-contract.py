#!/usr/bin/env python3
"""Static and pure-policy contract for v3.362 context-echo QA."""

from pathlib import Path
import re
import unicodedata
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


def comparable_text(value: str) -> str:
    folded = unicodedata.normalize("NFKC", value).casefold()
    return "".join(
        character
        for character in folded
        if not character.isspace()
        and not unicodedata.category(character).startswith("P")
    )


def is_previous_context_echo(
    current_source: str,
    current_output: str,
    previous_source: str,
    previous_target: str,
) -> bool:
    normalized_source = comparable_text(current_source)
    normalized_output = comparable_text(current_output)
    normalized_previous_source = comparable_text(previous_source)
    normalized_previous_target = comparable_text(previous_target)
    return (
        len(normalized_previous_target) >= 4
        and normalized_output == normalized_previous_target
        and normalized_previous_source != normalized_source
    )


class JapaneseTranslationContextEchoContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.evaluator = read("scripts/evaluate-japanese-translation-context-qa.py")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.docs = (
            read("README.md")
            + read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
            + read("update_log.md")
        )

    def test_product_gate_requires_exact_echo_and_different_source(self) -> None:
        failures = function_body(
            self.context,
            "private static func textFailures(\n",
        )
        for marker in (
            "let previousTarget = comparableText(item.targetExcerpt)",
            "previousTarget.count >= 4",
            "normalizedOutput == previousTarget",
            "let previousSource = comparableText(item.sourceExcerpt)",
            "previousSource != normalizedSource",
            "failures.append(\"previousContextLeakage\")",
        ):
            self.assertIn(marker, failures)
        self.assertNotIn("normalizedOutput.contains(previousTarget)", failures)

    def test_cloud_policy_matches_product_echo_boundary(self) -> None:
        start = self.evaluator.index("if previous_summary is not None:")
        end = self.evaluator.index("    for term in terms:", start)
        policy = self.evaluator[start:end]
        for marker in (
            'normalize_text(item["targetExcerpt"]) == output_normalized',
            'normalize_text(item["sourceExcerpt"]) != source_normalized',
            'failures.append("previousContextLeakage")',
        ):
            self.assertIn(marker, policy)
        self.assertNotIn('normalize_text(item["targetExcerpt"]) in output_normalized', policy)

    def test_exact_echo_is_rejected_but_repeated_phrase_is_not(self) -> None:
        previous_source = "Koharu先生、9時に来て。"
        previous_target = "小春老师，9点来。"
        self.assertTrue(
            is_previous_context_echo(
                "殿は3人を待つ。",
                "小春老师，9点来。",
                previous_source,
                previous_target,
            )
        )
        self.assertFalse(
            is_previous_context_echo(
                "小春先生今天9点来，记得。",
                "小春老师，9点来，记得。",
                previous_source,
                previous_target,
            )
        )
        self.assertFalse(
            is_previous_context_echo(
                previous_source,
                previous_target,
                previous_source,
                previous_target,
            )
        )
        self.assertFalse(
            is_previous_context_echo(
                "来。",
                "来。",
                previous_source,
                "来。",
            )
        )

    def test_existing_context_fixture_still_rejects_cross_batch_echo(self) -> None:
        import copy
        import importlib.util
        import json

        evaluator_path = ROOT / "scripts/evaluate-japanese-translation-context-qa.py"
        spec = importlib.util.spec_from_file_location("v3362_context_qa", evaluator_path)
        if spec is None or spec.loader is None:
            raise AssertionError("unable to load context evaluator")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        fixture = json.loads(
            read("benchmarks/japanese_translation/examples/translation_context_qa/input.json")
        )
        payload = copy.deepcopy(fixture)
        payload["batches"][1]["rawOutput"] = "[2] 小春老师，9点来。"
        report = module.evaluate_batch(payload["batches"][1], payload["context"])
        self.assertIn("previousContextLeakage", report["failureReasons"]["2"])

    def test_failure_remains_block_scoped_and_does_not_rerun_ocr(self) -> None:
        for marker in (
            "TranslationBatchQualityEvaluator.singleOutputFailures(",
            "TranslationBatchQualityEvaluator.evaluate(",
            "translateJapaneseImageBlockWithQA(",
            "正在只补译",
            "recognizeTextBlocks(",
        ):
            self.assertIn(marker, self.store)
        self.assertNotIn("recognizeTextBlocks(in: data", self.store[
            self.store.index("private func translateJapaneseImageBatch(") :
            self.store.index("private static func imageTranslationBatches(")
        ])

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.386", "3.386"],
        )
        combined = self.workflow + self.docs
        self.assertIn(
            "python3 -B scripts/test-v3362-japanese-translation-context-echo-contract.py",
            self.workflow,
        )
        for marker in (
            "scripts/test-v3362-japanese-translation-context-echo-contract.py",
            "v3.362",
            "japanese-benchmark-v3.386-",
        ):
            self.assertIn(marker, combined)
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, read(
                "scripts/test-v3362-japanese-translation-context-echo-contract.py"
            ))


if __name__ == "__main__":
    unittest.main(verbosity=2)

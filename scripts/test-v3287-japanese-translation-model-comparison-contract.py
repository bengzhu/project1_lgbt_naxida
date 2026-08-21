#!/usr/bin/env python3
"""Static and in-process contract for v3.287 clean-text model comparison."""

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


def load_json(relative: str) -> dict:
    payload = json.loads(read(relative))
    if not isinstance(payload, dict):
        raise AssertionError(f"expected object JSON: {relative}")
    return payload


def load_evaluator():
    path = ROOT / "scripts/evaluate-japanese-translation-model-comparison.py"
    spec = importlib.util.spec_from_file_location("aitrans_translation_model_comparison_v3287", path)
    if spec is None or spec.loader is None:
        raise AssertionError("cannot import v3.287 evaluator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class JapaneseTranslationModelComparisonContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.evaluator = load_evaluator()
        cls.manifest = load_json("benchmarks/japanese_translation/examples/model_comparison/manifest.json")
        cls.input = load_json("benchmarks/japanese_translation/examples/model_comparison/input.json")
        cls.manifest_schema = load_json("benchmarks/japanese_translation/schema/model-comparison-manifest.schema.json")
        cls.input_schema = load_json("benchmarks/japanese_translation/schema/model-comparison-input.schema.json")
        cls.report_schema = load_json("benchmarks/japanese_translation/schema/model-comparison-report.schema.json")
        cls.evaluator_source = read("scripts/evaluate-japanese-translation-model-comparison.py")
        cls.wrapper = read("scripts/run-japanese-translation-model-comparison-cloud-smoke.sh")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
        cls.update_log = read("update_log.md")
        cls.service = read("AITRANS/Services/GemmaLocalService.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def evaluate(self, payload=None):
        return self.evaluator.evaluate(
            self.manifest,
            copy.deepcopy(payload or self.input),
            manifest_path=ROOT / "benchmarks/japanese_translation/examples/model_comparison/manifest.json",
            repo_root=ROOT,
            verify_assets=True,
        )

    def test_schema_and_corpus_are_strict_clean_text_and_three_way(self) -> None:
        self.assertEqual(self.manifest_schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
        self.assertFalse(self.manifest_schema["additionalProperties"])
        self.assertFalse(self.input_schema["additionalProperties"])
        self.assertFalse(self.report_schema["additionalProperties"])
        self.assertTrue(self.manifest["contractExampleOnly"])
        self.assertEqual(
            {tuple(pair) for pair in self.manifest["requiredLanguagePairs"]},
            {("ja", "zh-CN"), ("ja", "en"), ("en", "zh-CN")},
        )
        self.assertEqual(len(self.manifest["cases"]), 3)
        self.assertEqual({case["inputKind"] for case in self.manifest["cases"]}, {"cleanSource"})
        self.assertEqual({(case["sourceLanguage"], case["targetLanguage"]) for case in self.manifest["cases"]}, {("ja", "zh-CN"), ("ja", "en"), ("en", "zh-CN")})
        self.assertNotIn("ocrCorrupted", read("benchmarks/japanese_translation/examples/model_comparison/clean-corpus.json"))

    def test_models_keep_270m_as_floor_and_candidates_disabled(self) -> None:
        models = {model["modelID"]: model for model in self.input["models"]}
        self.assertEqual(len(models), 3)
        floor = models["gemma-270m-floor"]
        self.assertEqual(floor["comparisonRole"], "floor")
        self.assertEqual(floor["modelFamily"], "Gemma")
        self.assertTrue(floor["defaultEnabled"])
        self.assertEqual({model["comparisonRole"] for model in models.values()}, {"floor", "candidate"})
        self.assertTrue(all(not model["defaultEnabled"] for model in models.values() if model["comparisonRole"] == "candidate"))
        self.assertEqual(self.input["selection"]["defaultModelID"], floor["modelID"])
        self.assertFalse(self.input["selection"]["productSelectionChanged"])
        self.assertFalse(self.input["selection"]["groundTruthUsedForSelection"])
        self.assertEqual({model["template"]["applyAPI"] for model in models.values()}, {"llama_chat_apply_template"})
        self.assertIn("Q4_0", {model["quantization"] for model in models.values()})
        self.assertIn("Q4_K_M", {model["quantization"] for model in models.values()})

    def test_evaluator_reports_cold_warm_percentiles_and_fail_closed_promotion(self) -> None:
        report = self.evaluate()
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["corpus"]["requiredLanguagePairs"], ["en->zh-CN", "ja->en", "ja->zh-CN"])
        rows = {row["modelID"]: row for row in report["runtime"]["rows"]}
        self.assertEqual(rows["gemma-270m-floor"]["byWarmState"]["cold"]["latencyMilliseconds"]["p50"], 220.0)
        self.assertEqual(rows["gemma-270m-floor"]["byWarmState"]["cold"]["latencyMilliseconds"]["p95"], 230.0)
        self.assertEqual(rows["qwen-1.5b-candidate"]["byWarmState"]["warm"]["firstTokenMilliseconds"]["p50"], 20.0)
        self.assertEqual(rows["sakura-7b-candidate"]["peakMemoryBytesMax"], 3221225472)
        self.assertTrue(all(row["byWarmState"]["cold"]["completeSampleCount"] == 3 for row in rows.values()))
        self.assertTrue(all(row["byWarmState"]["warm"]["completeSampleCount"] == 3 for row in rows.values()))
        self.assertTrue(report["artifactGate"]["reasons"])
        self.assertFalse(report["promotion"]["productSelectionChanged"])
        self.assertFalse(report["promotion"]["groundTruthUsedForSelection"])
        self.assertEqual(report["promotion"]["status"], "notEligible")

    def test_mutations_fail_closed_without_ground_truth_or_model_selection(self) -> None:
        mutation = copy.deepcopy(self.input)
        mutation["selection"]["groundTruthUsedForSelection"] = True
        with self.assertRaises(self.evaluator.ModelComparisonError):
            self.evaluate(mutation)

        mutation = copy.deepcopy(self.input)
        mutation["models"][1]["defaultEnabled"] = True
        with self.assertRaises(self.evaluator.ModelComparisonError):
            self.evaluate(mutation)

        mutation = copy.deepcopy(self.input)
        mutation["predictions"][0]["caseID"] = "missing-case"
        with self.assertRaises(self.evaluator.ModelComparisonError):
            self.evaluate(mutation)

        mutation = copy.deepcopy(self.input)
        mutation["measurements"] = mutation["measurements"][:-1]
        with self.assertRaises(self.evaluator.ModelComparisonError):
            self.evaluate(mutation)

        mutation = copy.deepcopy(self.input)
        mutation["models"][0]["comparisonRole"] = "candidate"
        mutation["models"][0]["defaultEnabled"] = False
        with self.assertRaises(self.evaluator.ModelComparisonError):
            self.evaluate(mutation)

        mutation = copy.deepcopy(self.input)
        mutation["models"][0]["artifactStatus"] = "available"
        with self.assertRaises(self.evaluator.ModelComparisonError):
            self.evaluate(mutation)

        mutation = copy.deepcopy(self.input)
        mutation["measurements"][0]["contextOverflow"] = True
        report = self.evaluate(mutation)
        floor_runtime = next(row for row in report["runtime"]["rows"] if row["modelID"] == "gemma-270m-floor")
        self.assertEqual(floor_runtime["contextOverflowCount"], 1)
        self.assertAlmostEqual(floor_runtime["contextOverflowRate"], 1 / 6)

    def test_runtime_and_quality_layers_stay_separate(self) -> None:
        for marker in (
            "nearest-rank",
            "contextOverflow",
            "firstTokenMilliseconds",
            "warmState",
            "groundTruthUsedForSelection",
            "productSelectionChanged",
            "humanReviewDimensions",
            "ocrCorruptedExcluded",
            "contractExampleOnly",
        ):
            self.assertIn(marker, self.evaluator_source)
        self.assertIn("qualityMetricsAreNotSelectionInputs", self.evaluator_source)
        self.assertNotIn("AITRANS/", self.evaluator_source)
        self.assertNotIn("sub" + "process", self.evaluator_source)
        self.assertNotIn("ocrCorrupted", self.input)

    def test_cloud_route_version_and_product_boundary_are_explicit(self) -> None:
        for marker in (
            "scripts/test-v3287-japanese-translation-model-comparison-contract.py",
            "scripts/run-japanese-translation-model-comparison-cloud-smoke.sh",
            "japanese-translation-model-comparison-report.json",
            "japanese-benchmark-v3.301-",
        ):
            self.assertIn(marker, self.workflow)
        self.assertIn("GITHUB_ACTIONS", self.wrapper)
        self.assertIn("cloud-only", self.wrapper)
        self.assertIn("evaluate-japanese-translation-model-comparison.py", self.wrapper)
        self.assertNotIn("xcodebuild", self.wrapper)
        self.assertNotIn("swiftc", self.wrapper)
        versions = re.findall(r"MARKETING_VERSION = ([^;]+);", self.project)
        self.assertEqual(versions, ["3.305", "3.305"])
        self.assertIn("v3.287", self.route)
        self.assertIn("v3.287", self.update_log)
        self.assertNotIn("qwen-1.5b-candidate", self.service)
        self.assertNotIn("sakura-7b-candidate", self.service)

    def test_docs_state_real_evidence_is_still_missing(self) -> None:
        for marker in (
            "270M 只能作为 floor",
            "同一 clean-text",
            "p50",
            "p95",
            "context overflow",
            "不立即更换默认模型",
            "不声称翻译质量提升",
        ):
            self.assertIn(marker, self.route + self.update_log)


if __name__ == "__main__":
    unittest.main(verbosity=2)

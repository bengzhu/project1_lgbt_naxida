#!/usr/bin/env python3
"""Static and deterministic contract for v3.292 corpus readiness."""

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
    value = json.loads(read(relative))
    if not isinstance(value, dict):
        raise AssertionError(f"expected object JSON: {relative}")
    return value


def load_evaluator():
    path = ROOT / "scripts/evaluate-japanese-corpus-readiness.py"
    spec = importlib.util.spec_from_file_location("v3292_corpus_readiness", path)
    if spec is None or spec.loader is None:
        raise AssertionError("unable to load v3.292 evaluator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class JapaneseCorpusReadinessContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.schema = load_json("benchmarks/japanese_ocr/schema/corpus-readiness-manifest.schema.json")
        cls.report_schema = load_json("benchmarks/japanese_ocr/schema/corpus-readiness-report.schema.json")
        cls.manifest = load_json("benchmarks/japanese_ocr/examples/corpus_readiness/manifest.json")
        cls.evaluator = load_evaluator()
        cls.evaluator_source = read("scripts/evaluate-japanese-corpus-readiness.py")
        cls.wrapper = read("scripts/run-japanese-corpus-readiness-cloud-smoke.sh")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
        cls.update_log = read("update_log.md")
        cls.readme = read("benchmarks/japanese_ocr/examples/corpus_readiness/README.md")

    def test_schema_and_fixture_are_strict_and_versioned(self) -> None:
        self.assertEqual(self.schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
        self.assertFalse(self.schema["additionalProperties"])
        self.assertFalse(self.report_schema["additionalProperties"])
        self.assertEqual(self.schema["properties"]["benchmark"]["const"], "japanese-corpus-readiness")
        self.assertEqual(self.manifest["schemaVersion"], "1.1.0")
        self.assertTrue(self.manifest["contractExampleOnly"])

    def test_manifest_hash_split_and_prediction_matrix_are_explicit(self) -> None:
        self.assertEqual(
            {split["splitID"] for split in self.manifest["splits"]},
            {"train", "dev", "holdout"},
        )
        self.assertEqual(len(self.manifest["predictionMatrix"]["requiredRows"]), 12)
        self.assertEqual(self.manifest["predictionMatrix"]["rows"], [])
        self.evaluator.validate_manifest(self.manifest)
        self.assertEqual(
            self.manifest["manifestSha256"],
            self.evaluator.manifest_sha256(self.manifest),
        )

    def test_route_requirements_are_frozen_in_annotation_profile(self) -> None:
        profile = self.manifest["annotationProfile"]
        self.assertEqual(
            set(profile["requiredFields"]),
            {
                "blockPolygon",
                "linePolygonOrLineOrder",
                "writingDirection",
                "exactSourceText",
                "blockReadingOrder",
                "bubbleAssociation",
                "textType",
            },
        )
        self.assertGreaterEqual(profile["minimumFullPages"], 20)
        self.assertGreaterEqual(profile["minimumAnnotatedRegions"], 150)
        for marker in (
            "verticalDialogue",
            "horizontalDialogue",
            "slantedText",
            "halftoneBackground",
            "mixedScript",
        ):
            self.assertIn(marker, profile["requiredScenarios"])

    def test_missing_evidence_is_blocked_without_product_mutation(self) -> None:
        report = self.evaluator.evaluate_manifest(copy.deepcopy(self.manifest))
        self.assertEqual(set(report), set(self.report_schema["required"]))
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["datasetStatus"], "missing")
        self.assertEqual(report["splitIsolationStatus"], "missing")
        self.assertEqual(report["predictionMatrixStatus"], "missing")
        self.assertEqual(report["holdoutPolicyStatus"], "missing")
        self.assertFalse(report["productPathEnabled"])
        self.assertFalse(report["productSelectionChanged"])
        self.assertFalse(report["groundTruthUsedForDecision"])
        reasons = " | ".join(report["reasons"])
        for marker in ("corpus", "pages", "TextRegions", "train", "dev", "holdout", "prediction", "policy"):
            self.assertIn(marker, reasons)

    def test_manifest_hash_and_split_overlap_fail_closed(self) -> None:
        mutated = copy.deepcopy(self.manifest)
        mutated["dataset"]["datasetID"] = "changed"
        with self.assertRaises(self.evaluator.CorpusReadinessError):
            self.evaluator.evaluate_manifest(mutated)

        mutated = copy.deepcopy(self.manifest)
        mutated["splits"][1]["assetIDs"] = ["same-page"]
        mutated["splits"][2]["assetIDs"] = ["same-page"]
        with self.assertRaises(self.evaluator.CorpusReadinessError):
            self.evaluator.evaluate_manifest(mutated)

    def test_holdout_policy_cannot_be_tuned_after_evaluation(self) -> None:
        mutated = copy.deepcopy(self.manifest)
        mutated["holdoutPolicy"]["holdoutTunedAfterEvaluation"] = True
        with self.assertRaises(self.evaluator.CorpusReadinessError):
            self.evaluator.evaluate_manifest(mutated)

        mutated = copy.deepcopy(self.manifest)
        mutated["promotion"]["productSelectionChanged"] = True
        with self.assertRaises(self.evaluator.CorpusReadinessError):
            self.evaluator.evaluate_manifest(mutated)

    def test_evaluator_is_a_pure_cloud_only_shadow_boundary(self) -> None:
        for source in (self.evaluator_source, self.wrapper):
            self.assertNotIn("subprocess", source)
            self.assertNotIn("MangaOverlayProbeService", source)
            self.assertNotIn("ImageTranslationBlock", source)
            self.assertNotIn("ground_truth", source.lower())
        self.assertIn('GITHUB_ACTIONS:-false', self.wrapper)
        self.assertIn("cloud-only", self.wrapper)
        self.assertIn("evaluate-japanese-corpus-readiness.py", self.wrapper)

    def test_workflow_docs_and_project_route_are_wired(self) -> None:
        for marker in (
            "scripts/test-v3292-japanese-corpus-readiness-contract.py",
            "scripts/run-japanese-corpus-readiness-cloud-smoke.sh",
            "japanese-corpus-readiness-report.json",
            "japanese-benchmark-v3.299-",
        ):
            self.assertIn(marker, self.workflow)
        versions = re.findall(r"MARKETING_VERSION = ([^;]+);", self.project)
        self.assertEqual(versions, ["3.299", "3.299"])
        for marker in (
            "v3.292",
            "共享日语 OCR/translation corpus",
            "holdout",
            "productSelectionChanged=false",
            "不接入产品候选选择",
        ):
            self.assertIn(marker, self.route + self.update_log + self.readme)


if __name__ == "__main__":
    unittest.main(verbosity=2)

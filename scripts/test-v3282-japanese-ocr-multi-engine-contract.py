#!/usr/bin/env python3
"""In-process contract for v3.282 same-crop OCR oracle comparison."""

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


def load_module(relative: str):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location("aitrans_japanese_ocr_multi_engine_v3282", path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"could not load {relative}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class JapaneseOCRMultiEngineContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.evaluator = load_module("scripts/evaluate-japanese-ocr-multi-engine.py")
        cls.input_payload = load_json("benchmarks/japanese_ocr/examples/multi_engine/input.json")
        cls.input_schema = load_json("benchmarks/japanese_ocr/schema/multi-engine-input.schema.json")
        cls.report_schema = load_json("benchmarks/japanese_ocr/schema/multi-engine-report.schema.json")
        cls.readme = read("benchmarks/japanese_ocr/oracle/README.md")
        cls.example_readme = read("benchmarks/japanese_ocr/examples/multi_engine/README.md")
        cls.shell = read("scripts/run-japanese-ocr-multi-engine-cloud-smoke.sh")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def expect_error(self, payload: dict, needle: str) -> None:
        with self.assertRaises(self.evaluator.MultiEngineBenchmarkError) as context:
            self.evaluator.evaluate(payload)
        self.assertIn(needle, str(context.exception))

    def ready_payload(self) -> dict:
        payload = copy.deepcopy(self.input_payload)
        engine = next(item for item in payload["engines"] if item["engineID"] == "koharu-paddleocr-vl")
        engine["artifactStatus"] = "available"
        engine["failureReason"] = None
        engine["model"]["sha256"] = "4444444444444444444444444444444444444444444444444444444444444444"
        for result in payload["results"]:
            if result["engineID"] == "koharu-paddleocr-vl":
                result["status"] = "success"
                result["text"] = "ニコッ"
                result["rawText"] = "ニコッ"
                result["confidence"] = 0.97
                result["failureReason"] = None
        return payload

    def test_schema_and_identity_fields_are_fail_closed(self) -> None:
        for schema in (self.input_schema, self.report_schema):
            self.assertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
            self.assertEqual(schema["type"], "object")
            self.assertFalse(schema["additionalProperties"])
            self.assertIn("required", schema)
        self.assertEqual(self.input_payload["benchmark"], "japanese-ocr-multi-engine")
        self.assertRegex(self.input_payload["datasetSha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(len(self.input_payload["engines"]), 4)
        self.assertTrue(all(re.fullmatch(r"[0-9a-f]{64}", crop["cropSha256"]) for crop in self.input_payload["cropSet"]))
        for engine in self.input_payload["engines"]:
            self.assertIn("sourceRevision", engine)
            self.assertIn("runtimeRevision", engine)
            self.assertIn("model", engine)
            self.assertIn("license", engine)
            self.assertIn("artifactStatus", engine)
            self.assertIn("failureReason", engine)

    def test_alignment_is_key_based_and_tables_are_separate(self) -> None:
        first = self.evaluator.evaluate(self.ready_payload())
        reordered = self.ready_payload()
        reordered["results"].reverse()
        second = self.evaluator.evaluate(reordered)
        self.assertEqual(first, second)
        self.assertEqual(first["status"], "success")
        self.assertEqual(
            first["alignment"]["keyFields"],
            ["datasetSha256", "pageID", "regionID", "cropLevel"],
        )
        self.assertFalse(first["alignment"]["joinedByArrayIndex"])
        self.assertIn("oracleCrop", first["tables"])
        self.assertIn("detectedCrop", first["tables"])
        self.assertEqual(first["tables"]["oracleCrop"]["sampleCount"], 1)
        self.assertEqual(first["tables"]["detectedCrop"]["sampleCount"], 1)
        self.assertIsNone(first["tables"]["detectedCrop"]["rows"][0]["referenceText"])
        self.assertRegex(first["tables"]["oracleCrop"]["rows"][0]["cropSha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(first["tables"]["oracleCrop"]["engineMetrics"][0]["metrics"]["exactMatchRate"], 1.0)

    def test_missing_duplicate_and_ground_truth_leakage_fail_closed(self) -> None:
        missing = copy.deepcopy(self.input_payload)
        missing["results"].pop()
        self.expect_error(missing, "missing explicit result rows")

        duplicate = copy.deepcopy(self.input_payload)
        duplicate["results"].append(copy.deepcopy(duplicate["results"][0]))
        self.expect_error(duplicate, "duplicate engine/crop result")

        detected_truth = copy.deepcopy(self.input_payload)
        detected_truth["cropSet"][1]["expectedText"] = "ニコッ"
        detected_truth["cropSet"][1]["expectedTextNFC"] = "ニコッ"
        self.expect_error(detected_truth, "detectedCrop must not carry ground-truth text")

        changed_key = copy.deepcopy(self.input_payload)
        changed_key["results"][0]["regionID"] = "different-region"
        self.expect_error(changed_key, "unknown comparison key")

    def test_unavailable_reference_is_explicit_blocked_state_with_failure_rows(self) -> None:
        blocked = copy.deepcopy(self.input_payload)
        engine = next(item for item in blocked["engines"] if item["engineID"] == "koharu-paddleocr-vl")
        engine["artifactStatus"] = "missing"
        engine["failureReason"] = "pinned PaddleOCR-VL artifact was not provided"
        engine["model"]["sha256"] = None
        for result in blocked["results"]:
            if result["engineID"] == "koharu-paddleocr-vl":
                result["status"] = "failure"
                result["text"] = ""
                result["failureReason"] = "pinned PaddleOCR-VL artifact was not provided"
        report = self.evaluator.evaluate(blocked)
        self.assertEqual(report["status"], "blocked")
        paddle_metrics = next(
            item["metrics"]
            for item in report["tables"]["oracleCrop"]["engineMetrics"]
            if item["engineID"] == "koharu-paddleocr-vl"
        )
        self.assertEqual(paddle_metrics["failureCount"], 1)
        paddle_rows = [
            item
            for table in report["tables"].values()
            for row in table["rows"]
            for item in row["engines"]
            if item["engineID"] == "koharu-paddleocr-vl"
        ]
        self.assertEqual(len(paddle_rows), 2)
        self.assertTrue(all(item["status"] == "failure" for item in paddle_rows))
        self.assertIn("blocked until every declared engine artifact is available", report["qualityClaim"])

    def test_cloud_route_and_product_boundary_are_explicit(self) -> None:
        for marker in (
            "GITHUB_ACTIONS:-",
            "JAPANESE_OCR_MULTI_ENGINE_INPUT",
            "evaluate-japanese-ocr-multi-engine.py",
            "--allow-missing-artifacts",
        ):
            self.assertIn(marker, self.shell)
        self.assertNotIn("xcodebuild", self.shell)
        self.assertNotIn("cargo", self.shell)
        self.assertNotIn("model.safetensors", self.shell)
        for marker in (
            "scripts/run-japanese-ocr-multi-engine-cloud-smoke.sh",
            "japanese-ocr-multi-engine-report.json",
            "Aggregate v3.282 same-crop oracle contract",
        ):
            self.assertIn(marker, self.workflow)
        self.assertNotIn("AITRANS/", read("scripts/evaluate-japanese-ocr-multi-engine.py"))
        self.assertIn("MIT48 and PaddleOCR-VL remain", self.readme)
        self.assertIn("not an OCR result", self.example_readme)
        self.assertIn("同一 crop 的多引擎结果", self.route)
        self.assertIn("禁止按数组下标拼不同 engine 的结果", self.route)
        self.assertEqual(re.findall(r"MARKETING_VERSION = ([^;]+);", self.project), ["3.362", "3.362"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

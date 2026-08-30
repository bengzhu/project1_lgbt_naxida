#!/usr/bin/env python3
"""In-process contract for v3.284 distributable OCR candidate shadow evidence."""

from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
INPUT_RELATIVE = "benchmarks/japanese_ocr/examples/engine_candidate/input.json"


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def load_json(relative: str) -> dict:
    value = json.loads(read(relative))
    if not isinstance(value, dict):
        raise AssertionError(f"expected object JSON: {relative}")
    return value


def load_module(relative: str):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location("aitrans_japanese_ocr_engine_candidate_v3284", path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"could not load {relative}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class JapaneseOCREngineCandidateContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.evaluator = load_module("scripts/evaluate-japanese-ocr-engine-candidate.py")
        cls.input_payload = load_json(INPUT_RELATIVE)
        cls.input_schema = load_json("benchmarks/japanese_ocr/schema/engine-candidate-input.schema.json")
        cls.report_schema = load_json("benchmarks/japanese_ocr/schema/engine-candidate-report.schema.json")
        cls.example_readme = read("benchmarks/japanese_ocr/examples/engine_candidate/README.md")
        cls.protocol_readme = read("benchmarks/japanese_ocr/engine_candidate/README.md")
        cls.shell = read("scripts/run-japanese-ocr-engine-candidate-cloud-smoke.sh")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def evaluate(self, payload: dict | None = None) -> dict:
        return self.evaluator.evaluate(copy.deepcopy(self.input_payload if payload is None else payload))

    def expect_error(self, payload: dict, needle: str) -> None:
        with self.assertRaises(self.evaluator.EngineCandidateError) as context:
            self.evaluate(payload)
        self.assertIn(needle, str(context.exception))

    def test_schema_identity_and_blocked_contract_fixture(self) -> None:
        for schema in (self.input_schema, self.report_schema):
            self.assertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
            self.assertEqual(schema["type"], "object")
            self.assertFalse(schema["additionalProperties"])
            self.assertIn("required", schema)
        self.assertEqual(self.input_payload["benchmark"], "japanese-ocr-engine-candidate")
        self.assertTrue(self.input_payload["contractExampleOnly"])
        self.assertEqual({engine["candidateRole"] for engine in self.input_payload["engines"]}, {"baseline", "candidate"})
        self.assertTrue(all(engine["defaultEnabled"] is False for engine in self.input_payload["engines"] if engine["candidateRole"] == "candidate"))

        report = self.evaluate()
        self.assertEqual(report["status"], "blocked")
        self.assertFalse(report["artifactGate"]["allArtifactsAvailable"])
        self.assertFalse(report["artifactGate"]["resourceMatrixComplete"])
        self.assertEqual(report["promotion"]["status"], "notEligible")
        self.assertFalse(report["promotion"]["groundTruthUsedForSelection"])
        self.assertFalse(report["promotion"]["productSelectionChanged"])
        self.assertEqual(report["promotion"]["defaultEnabledCandidateCount"], 0)
        self.assertEqual(report["sameCrop"]["alignment"]["keyFields"], ["datasetSha256", "pageID", "regionID", "cropLevel"])
        baseline_resource = next(row for row in report["resources"]["rows"] if row["engineID"] == "bundled-manga-ocr")
        self.assertEqual(baseline_resource["coldLatencyMs"]["p50"], 42.0)
        self.assertEqual(baseline_resource["warmLatencyMs"]["p95"], 9.4)
        self.assertIsNone(baseline_resource["energyMilliwattHours"])

    def test_report_is_order_invariant_and_quality_resource_layers_stay_separate(self) -> None:
        first = self.evaluate()
        reordered = copy.deepcopy(self.input_payload)
        reordered["engines"].reverse()
        reordered["results"].reverse()
        reordered["measurementRuns"].reverse()
        second = self.evaluate(reordered)
        self.assertEqual(first, second)
        self.assertIn("tables", first["sameCrop"])
        self.assertIn("resources", first)
        self.assertIn("licenseMatrix", first)
        self.assertNotIn("latencyMs", first["sameCrop"])
        self.assertNotIn("characterErrorRate", first["resources"])

    def test_artifact_measurement_and_result_fail_closed(self) -> None:
        available = copy.deepcopy(self.input_payload)
        candidate = next(engine for engine in available["engines"] if engine["candidateRole"] == "candidate")
        candidate["referenceOnly"] = False
        candidate["distribution"] = "userProvided"
        candidate["engineVersion"] = "contract-available"
        candidate["sourceRevision"] = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        candidate["runtimeRevision"] = "runtime-contract"
        candidate["license"] = "Apache-2.0"
        candidate["model"]["license"] = "Apache-2.0"
        candidate["model"]["sha256"] = "3333333333333333333333333333333333333333333333333333333333333333"
        candidate["artifact"]["license"] = "Apache-2.0"
        candidate["artifact"]["sha256"] = "3333333333333333333333333333333333333333333333333333333333333333"
        candidate["artifact"]["sizeBytes"] = 2048
        candidate["artifact"]["quantization"] = "INT8"
        candidate["artifact"]["downloadPolicy"] = "userProvided"
        candidate["artifactStatus"] = "available"
        candidate["failureReason"] = None
        for result in available["results"]:
            if result["engineID"] == "candidate-ocr-vl":
                result["status"] = "success"
                result["text"] = "ニコッ"
                result["rawText"] = "ニコッ"
                result["confidence"] = 0.9
                result["failureReason"] = None
                result["referenceOnly"] = False
        next(measurement for measurement in available["measurementRuns"] if measurement["engineID"] == "candidate-ocr-vl")["referenceOnly"] = False
        report = self.evaluate(available)
        self.assertEqual(report["status"], "blocked")
        self.assertFalse(report["artifactGate"]["resourceMatrixComplete"])

        complete_energy_missing = copy.deepcopy(available)
        baseline_measurement = complete_energy_missing["measurementRuns"][0]
        baseline_measurement["status"] = "complete"
        baseline_measurement["failureReason"] = "energy unavailable"
        self.expect_error(complete_energy_missing, "complete energy is required")

        candidate_default = copy.deepcopy(self.input_payload)
        next(engine for engine in candidate_default["engines"] if engine["candidateRole"] == "candidate")["defaultEnabled"] = True
        self.expect_error(candidate_default, "candidate cannot be default enabled")

        result_status = copy.deepcopy(self.input_payload)
        bad_result = next(result for result in result_status["results"] if result["engineID"] == "candidate-ocr-vl")
        bad_result["status"] = "success"
        bad_result["text"] = "候補"
        bad_result["failureReason"] = None
        self.expect_error(result_status, "must be an explicit failure")

        duplicate_measurement = copy.deepcopy(self.input_payload)
        duplicate_measurement["measurementRuns"].append(copy.deepcopy(duplicate_measurement["measurementRuns"][0]))
        self.expect_error(duplicate_measurement, "duplicate measurement run")

    def test_same_crop_and_license_boundaries_fail_closed(self) -> None:
        detected_truth = copy.deepcopy(self.input_payload)
        detected = next(crop for crop in detected_truth["cropSet"] if crop["cropLevel"] == "detectedCrop")
        detected["expectedText"] = "ニコッ"
        detected["expectedTextNFC"] = "ニコッ"
        self.expect_error(detected_truth, "detectedCrop must not carry ground-truth text")

        crop_id_mismatch = copy.deepcopy(self.input_payload)
        crop_id_mismatch["results"][0]["cropID"] = "different-crop"
        self.expect_error(crop_id_mismatch, "cropID does not match")

        license_mismatch = copy.deepcopy(self.input_payload)
        next(engine for engine in license_mismatch["engines"] if engine["candidateRole"] == "candidate")["artifact"]["license"] = "GPL-3.0-only"
        self.expect_error(license_mismatch, "artifact.license must match engine license")

    def test_cloud_route_and_product_boundary_are_explicit(self) -> None:
        for marker in (
            "GITHUB_ACTIONS:-",
            "JAPANESE_OCR_ENGINE_CANDIDATE_INPUT",
            "JAPANESE_OCR_ENGINE_CANDIDATE_OUTPUT",
            "evaluate-japanese-ocr-engine-candidate.py",
            "allow-missing-artifacts",
        ):
            self.assertIn(marker, self.shell)
        self.assertNotIn("xcodebuild", self.shell)
        self.assertNotIn("cargo", self.shell)
        self.assertNotIn("model.safetensors", self.shell)
        for marker in (
            "scripts/test-v3284-japanese-ocr-engine-candidate-contract.py",
            "scripts/run-japanese-ocr-engine-candidate-cloud-smoke.sh",
            "japanese-ocr-engine-candidate-report.json",
            "Aggregate v3.284 OCR engine candidate shadow contract",
            "japanese-benchmark-v3.301-",
        ):
            self.assertIn(marker, self.workflow)
        evaluator_source = read("scripts/evaluate-japanese-ocr-engine-candidate.py")
        self.assertNotIn("AITRANS/", evaluator_source)
        self.assertIn("candidate artifact is deliberately missing", self.example_readme)
        self.assertIn("license", self.protocol_readme)
        self.assertIn("v3.284", self.route)
        self.assertIn("CER/exact/latency/memory/energy/license", self.route)
        self.assertIn("不默认启用", self.route)
        self.assertEqual(re.findall(r"MARKETING_VERSION = ([^;]+);", self.project), ["3.344", "3.344"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

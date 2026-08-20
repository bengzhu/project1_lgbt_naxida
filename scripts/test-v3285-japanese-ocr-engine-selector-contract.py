#!/usr/bin/env python3
"""In-process contract for v3.285 GT-isolated OCR selector and rollback policy."""

from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
INPUT_RELATIVE = "benchmarks/japanese_ocr/examples/engine_selector/input.json"


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def load_json(relative: str) -> dict:
    value = json.loads(read(relative))
    if not isinstance(value, dict):
        raise AssertionError(f"expected object JSON: {relative}")
    return value


def load_module(relative: str):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location("aitrans_japanese_ocr_engine_selector_v3285", path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"could not load {relative}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class JapaneseOCREngineSelectorContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.evaluator = load_module("scripts/evaluate-japanese-ocr-engine-selector.py")
        cls.input_payload = load_json(INPUT_RELATIVE)
        cls.input_schema = load_json("benchmarks/japanese_ocr/schema/engine-selector-input.schema.json")
        cls.report_schema = load_json("benchmarks/japanese_ocr/schema/engine-selector-report.schema.json")
        cls.example_readme = read("benchmarks/japanese_ocr/examples/engine_selector/README.md")
        cls.protocol_readme = read("benchmarks/japanese_ocr/engine_selector/README.md")
        cls.shell = read("scripts/run-japanese-ocr-engine-selector-cloud-smoke.sh")
        cls.runtime_shell = read("scripts/test-v3285-image-ocr-selector-policy-runtime.sh")
        cls.fixture = read("scripts/fixtures/v3285-image-ocr-selector-policy-evaluator.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.provenance_source = read("AITRANS/Models/ImageOCRProvenance.swift")

    def evaluate(self, payload: dict | None = None) -> dict:
        return self.evaluator.evaluate(copy.deepcopy(self.input_payload if payload is None else payload))

    def expect_error(self, payload: dict, needle: str) -> None:
        with self.assertRaises(self.evaluator.EngineSelectorError) as context:
            self.evaluate(payload)
        self.assertIn(needle, str(context.exception))

    def make_available_candidate(self, payload: dict, *, enable: bool = True) -> None:
        payload["policy"]["selectorMode"] = "controlled-rollout"
        payload["policy"]["featureFlagEnabled"] = enable
        for case in payload["runtimeCases"]:
            candidate = next(engine for engine in case["engines"] if engine["candidateRole"] == "candidate")
            candidate.update(
                {
                    "artifactStatus": "available",
                    "licenseReviewed": True,
                    "supportsCropRoles": [case["cropRole"]],
                    "outputStatus": "success",
                    "text": "候选运行时输出",
                    "calibratedQuality": 0.91,
                    "calibrationProfileID": "ocr-calibration-v1",
                    "warmLatencyMs": 32.0,
                    "peakMemoryBytes": 134217728,
                    "failureReason": None,
                }
            )

    def test_schema_identity_and_blocked_fixture(self) -> None:
        for schema in (self.input_schema, self.report_schema):
            self.assertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
            self.assertEqual(schema["type"], "object")
            self.assertFalse(schema["additionalProperties"])
            self.assertIn("required", schema)
        self.assertEqual(self.input_payload["benchmark"], "japanese-ocr-engine-selector")
        self.assertTrue(self.input_payload["contractExampleOnly"])
        self.assertFalse(self.input_payload["policy"]["featureFlagEnabled"])
        self.assertTrue(self.input_payload["policy"]["thresholdsFrozen"])

        report = self.evaluate()
        self.assertEqual(report["status"], "blocked")
        self.assertTrue(all(decision["selectedEngineID"] == "bundled-manga-ocr" for decision in report["decisions"]))
        self.assertTrue(all(not decision["candidateAccepted"] for decision in report["decisions"]))
        self.assertTrue(any("candidateArtifactUnavailable" in decision["fallbackReasons"] for decision in report["decisions"]))
        self.assertEqual(report["promotion"]["status"], "notEligible")
        self.assertFalse(report["promotion"]["groundTruthUsedForSelection"])
        self.assertFalse(report["promotion"]["productSelectionChanged"])
        self.assertFalse(report["promotion"]["defaultCandidateEnabled"])
        self.assertTrue(report["promotion"]["rollbackAvailable"])

    def test_candidate_can_be_shadow_selected_without_product_selection_change(self) -> None:
        payload = copy.deepcopy(self.input_payload)
        self.make_available_candidate(payload)
        report = self.evaluate(payload)
        first = next(decision for decision in report["decisions"] if decision["blockID"] == "block-001")
        self.assertEqual(first["selectedEngineID"], "candidate-ocr-vl")
        self.assertTrue(first["candidateAccepted"])
        self.assertEqual(first["selectionReason"], "candidateShadowEligible")
        self.assertEqual(report["promotion"]["shadowCandidateSelectedCount"], 1)
        self.assertFalse(report["promotion"]["productSelectionChanged"])
        self.assertTrue(all(decision["requestBudgetDelta"] == 0 for decision in report["decisions"]))
        self.assertTrue(all(decision["pixelBudgetDelta"] == 0 for decision in report["decisions"]))

    def test_runtime_guards_force_baseline_or_no_engine(self) -> None:
        payload = copy.deepcopy(self.input_payload)
        self.make_available_candidate(payload)
        mutations = (
            ("geometryValid", False, "geometryInvalid"),
            ("duplicateRisk", True, "duplicateRisk"),
            ("requestBudgetRemaining", 0, "requestBudgetExhausted"),
            ("pixelBudgetRemaining", 0, "pixelBudgetExhausted"),
            ("cancellationState", "cancelled", "cancelledOrCancelRequested"),
            ("generationMatches", False, "staleGeneration"),
        )
        for field, value, reason in mutations:
            mutated = copy.deepcopy(payload)
            mutated["runtimeCases"][0][field] = value
            report = self.evaluate(mutated)
            decision = next(item for item in report["decisions"] if item["blockID"] == "block-001")
            self.assertEqual(decision["selectedEngineID"], "bundled-manga-ocr", field)
            self.assertIn(reason, decision["fallbackReasons"], field)
            if field in {"cancellationState", "generationMatches"}:
                self.assertTrue(decision["rollbackApplied"], field)
            else:
                self.assertFalse(decision["rollbackApplied"], field)

        low_quality = copy.deepcopy(payload)
        candidate = next(engine for engine in low_quality["runtimeCases"][0]["engines"] if engine["candidateRole"] == "candidate")
        candidate["calibratedQuality"] = 0.20
        report = self.evaluate(low_quality)
        decision = next(item for item in report["decisions"] if item["blockID"] == "block-001")
        self.assertEqual(decision["selectedEngineID"], "bundled-manga-ocr")
        self.assertIn("candidateQualityBelowThreshold", decision["fallbackReasons"])

    def test_evidence_gate_cannot_change_runtime_decisions(self) -> None:
        payload = copy.deepcopy(self.input_payload)
        self.make_available_candidate(payload)
        payload["contractExampleOnly"] = False
        missing = self.evaluate(payload)
        ready_payload = copy.deepcopy(payload)
        ready_payload["evidenceGate"] = {
            "status": "ready",
            "candidateArtifactReady": True,
            "authorizedCorpusReady": True,
            "policyFrozenBeforeHoldout": True,
            "holdoutEvaluatedOnce": True,
            "holdoutTunedAfterEvaluation": False,
            "outputMetricsPassed": True,
            "duplicateOmissionOrderPassed": True,
            "cancellationPassed": True,
            "memoryPassed": True,
            "rollbackVerified": True,
            "reason": "controlled contract mutation only",
        }
        ready = self.evaluate(ready_payload)
        self.assertEqual(missing["decisions"], ready["decisions"])
        self.assertEqual(ready["status"], "readyForReview")
        self.assertEqual(ready["promotion"]["status"], "eligibleForReview")
        self.assertFalse(ready["promotion"]["productSelectionChanged"])

        post_holdout_tune = copy.deepcopy(ready_payload)
        post_holdout_tune["evidenceGate"]["holdoutTunedAfterEvaluation"] = True
        self.expect_error(post_holdout_tune, "holdout cannot tune")

    def test_order_invariance_and_ground_truth_raw_confidence_rejection(self) -> None:
        first = self.evaluate()
        reordered = copy.deepcopy(self.input_payload)
        reordered["runtimeCases"].reverse()
        for case in reordered["runtimeCases"]:
            case["engines"].reverse()
        self.assertEqual(first, self.evaluate(reordered))

        confidence = copy.deepcopy(self.input_payload)
        confidence["runtimeCases"][0]["engines"][0]["confidence"] = 0.99
        self.expect_error(confidence, "unknown fields")
        expected = copy.deepcopy(self.input_payload)
        expected["runtimeCases"][0]["expectedText"] = "禁止读取"
        self.expect_error(expected, "unknown fields")
        ground_truth_flag = copy.deepcopy(self.input_payload)
        ground_truth_flag["policy"]["groundTruthUsedForSelection"] = True
        self.expect_error(ground_truth_flag, "ground truth cannot")

    def test_cloud_route_and_product_boundary_are_explicit(self) -> None:
        for marker in (
            "GITHUB_ACTIONS:-",
            "JAPANESE_OCR_ENGINE_SELECTOR_INPUT",
            "JAPANESE_OCR_ENGINE_SELECTOR_OUTPUT",
            "evaluate-japanese-ocr-engine-selector.py",
            "allow-not-ready",
        ):
            self.assertIn(marker, self.shell)
        self.assertNotIn("xcodebuild", self.shell)
        self.assertNotIn("cargo", self.shell)
        self.assertNotIn("model.safetensors", self.shell)
        for marker in (
            "scripts/test-v3285-japanese-ocr-engine-selector-contract.py",
            "scripts/run-japanese-ocr-engine-selector-cloud-smoke.sh",
            "scripts/test-v3285-image-ocr-selector-policy-runtime.sh",
            "japanese-ocr-engine-selector-report.json",
            "Aggregate v3.285 GT-isolated OCR selector shadow contract",
            "japanese-benchmark-v3.301-",
        ):
            self.assertIn(marker, self.workflow)
        evaluator_source = read("scripts/evaluate-japanese-ocr-engine-selector.py")
        self.assertNotIn("AITRANS/", evaluator_source)
        self.assertIn("xcrun swiftc", self.runtime_shell)
        self.assertIn("let encodedPolicy = try JSONEncoder().encode(policy)", self.fixture)
        self.assertIn("let decodedPolicy = try JSONDecoder().decode(", self.fixture)
        self.assertIn("precondition(decodedPolicy == policy)", self.fixture)
        self.assertNotIn("precondition(try JSONDecoder().decode(", self.fixture)
        runtime_sources = (
            "AITRANS/Models/ImageOCRProvenance.swift",
            "AITRANS/Services/ImageOCRLayoutEngine.swift",
            "scripts/fixtures/v3285-image-ocr-selector-policy-evaluator.swift",
        )
        previous_position = -1
        for relative in runtime_sources:
            source = f'"$repo_root/{relative}"'
            position = self.runtime_shell.find(source)
            self.assertGreater(position, previous_position, relative)
            previous_position = position
        self.assertNotIn("AITRANS/Models/TranscriptModels.swift", self.runtime_shell)
        self.assertIn("v3285-image-ocr-selector-policy-evaluator.swift", self.runtime_shell)
        self.assertIn("v3.285 image OCR selector policy evaluator passed", self.runtime_shell)
        self.assertIn("ground truth", self.protocol_readme)
        self.assertIn("candidate artifact", self.example_readme)
        self.assertIn("v3.285", self.route)
        self.assertIn("GT 隔离", self.route)
        self.assertIn("rollback", self.route)
        self.assertEqual(re.findall(r"MARKETING_VERSION = ([^;]+);", self.project), ["3.303", "3.303"])
        for marker in (
            "struct ImageOCRSelectorPolicy",
            "struct ImageOCRSelectorEngineSignal",
            "struct ImageOCRSelectorDecision",
            "enum ImageOCREngineSelector",
            "featureFlagEnabled: Bool = false",
            "requestBudgetDelta: Int = 0",
            "preserveReviewStateOnRollback: Bool = true",
        ):
            self.assertIn(marker, self.provenance_source)
        self.assertNotIn("groundTruth", self.provenance_source[self.provenance_source.index("struct ImageOCRSelectorEngineSignal"):])
        for relative in (
            "AITRANS/Services/VisionOCRService.swift",
            "AITRANS/Services/MangaOCRService.swift",
            "AITRANS/Services/ImageOCRLayoutEngine.swift",
        ):
            self.assertNotIn("ImageOCREngineSelector.select", read(relative))


if __name__ == "__main__":
    unittest.main(verbosity=2)

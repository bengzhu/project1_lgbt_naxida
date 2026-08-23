#!/usr/bin/env python3
"""In-process contract for v3.283 native line/TextRegion shadow geometry."""

from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_RELATIVE = "benchmarks/japanese_ocr/examples/line_signal/manifest.json"
INPUT_RELATIVE = "benchmarks/japanese_ocr/examples/line_signal/input.json"


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def load_json(relative: str) -> dict:
    value = json.loads(read(relative))
    if not isinstance(value, dict):
        raise AssertionError(f"expected object JSON: {relative}")
    return value


def load_module(relative: str):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location("aitrans_japanese_ocr_line_signal_v3283", path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"could not load {relative}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class JapaneseOCRLineSignalContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.evaluator = load_module("scripts/evaluate-japanese-ocr-line-signal.py")
        cls.manifest = load_json(MANIFEST_RELATIVE)
        cls.input_payload = load_json(INPUT_RELATIVE)
        cls.input_schema = load_json("benchmarks/japanese_ocr/schema/line-signal-input.schema.json")
        cls.report_schema = load_json("benchmarks/japanese_ocr/schema/line-signal-report.schema.json")
        cls.benchmark_readme = read("benchmarks/japanese_ocr/README.md")
        cls.example_readme = read("benchmarks/japanese_ocr/examples/line_signal/README.md")
        cls.protocol_readme = read("benchmarks/japanese_ocr/line_signal/README.md")
        cls.shell = read("scripts/run-japanese-ocr-line-signal-cloud-smoke.sh")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def evaluate(self, payload: dict | None = None, manifest: dict | None = None) -> dict:
        return self.evaluator.evaluate(
            self.manifest if manifest is None else manifest,
            copy.deepcopy(self.input_payload if payload is None else payload),
            manifest_path=ROOT / MANIFEST_RELATIVE,
            repo_root=ROOT,
        )

    def expect_error(self, payload: dict, needle: str) -> None:
        with self.assertRaises(self.evaluator.LineSignalError) as context:
            self.evaluate(payload)
        self.assertIn(needle, str(context.exception))

    def test_schema_identity_and_contract_fixture_are_explicit(self) -> None:
        for schema in (self.input_schema, self.report_schema):
            self.assertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
            self.assertEqual(schema["type"], "object")
            self.assertFalse(schema["additionalProperties"])
            self.assertIn("required", schema)
        self.assertEqual(self.input_payload["benchmark"], "japanese-ocr-line-signal")
        self.assertRegex(self.input_payload["datasetSha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(self.input_payload["budgets"]["maxTotalCandidates"], 12)
        self.assertEqual(self.input_payload["run"]["parameters"]["mode"], "shadow-only")
        self.assertTrue(all("regionID" not in candidate for candidate in self.input_payload["candidates"]))
        self.assertTrue(all(candidate["referenceOnly"] is False for candidate in self.input_payload["candidates"]))

        report = self.evaluate()
        self.assertEqual(report["status"], "insufficientCorpus")
        self.assertEqual(report["totals"]["textRegions"]["recall"], 1.0)
        self.assertEqual(report["totals"]["lines"]["recall"], 1.0)
        self.assertEqual(report["totals"]["orphanLineCount"], 0)
        self.assertEqual(report["promotion"]["status"], "notEligible")
        self.assertFalse(report["config"]["groundTruthUsedForSelection"])
        self.assertFalse(report["promotion"]["groundTruthUsedForSelection"])

    def test_geometry_merge_and_cut_metrics_are_observable_without_selection(self) -> None:
        merged = copy.deepcopy(self.input_payload)
        merged["budgets"]["maxLineCandidates"] = 9
        merged["budgets"]["maxTotalCandidates"] = 13
        geometry_manifest = copy.deepcopy(self.manifest)
        geometry_manifest["fixtures"][0]["regions"].append(
            {
                "regionID": "line-signal-region-adjacent",
                "bbox": [0.269, 0.1, 0.06, 0.08],
                "polygon": [[0.269, 0.1], [0.329, 0.1], [0.329, 0.18], [0.269, 0.18]],
                "linePolygons": [
                    [[0.269, 0.1], [0.329, 0.1], [0.329, 0.18], [0.269, 0.18]]
                ],
                "sourceText": "隣接候補",
                "sourceTextNFC": "隣接候補",
                "writingDirection": "vertical",
                "readingOrder": 2,
                "textType": "dialogue",
                "tags": ["vertical", "dialogue", "lineSignal"],
            }
        )
        geometry_manifest["manifestSha256"] = self.evaluator.BASE.manifest_sha256(geometry_manifest)
        merged["datasetSha256"] = geometry_manifest["manifestSha256"]
        merged["candidates"].append(
            {
                "candidateID": "native-line-adjacent-merge",
                "pageID": "line-signal-contract-jap",
                "kind": "line",
                "status": "success",
                "bbox": [0.21, 0.1, 0.119, 0.08],
                "polygon": [[0.21, 0.1], [0.329, 0.1], [0.329, 0.18], [0.21, 0.18]],
                "confidence": 0.4,
                "writingDirection": "vertical",
                "readingOrder": None,
                "parentCandidateID": "native-region-1",
                "source": "nativeLine",
                "referenceOnly": False,
                "failureReason": None,
            }
        )
        report = self.evaluate(merged, geometry_manifest)
        self.assertEqual(report["totals"]["lines"]["crossRegionMergeCount"], 1)
        self.assertGreater(report["totals"]["lines"]["duplicateCount"], 0)
        self.assertEqual(report["promotion"]["status"], "notEligible")
        self.assertFalse(report["config"]["groundTruthUsedForSelection"])

        cut = copy.deepcopy(self.input_payload)
        cut["budgets"]["maxLineCandidates"] = 9
        cut["budgets"]["maxTotalCandidates"] = 13
        cut["candidates"].append(
            {
                "candidateID": "native-line-1-cut",
                "pageID": "line-signal-contract-jap",
                "kind": "line",
                "status": "success",
                "bbox": [0.2, 0.1, 0.08, 0.24],
                "polygon": [[0.2, 0.1], [0.28, 0.1], [0.28, 0.34], [0.2, 0.34]],
                "confidence": 0.35,
                "writingDirection": "vertical",
                "readingOrder": None,
                "parentCandidateID": "native-region-1",
                "source": "nativeLine",
                "referenceOnly": False,
                "failureReason": None,
            }
        )
        cut_report = self.evaluate(cut)
        self.assertGreaterEqual(cut_report["totals"]["lines"]["cutCandidateCount"], 1)

    def test_status_coverage_budget_and_ground_truth_leakage_fail_closed(self) -> None:
        leaked = copy.deepcopy(self.input_payload)
        leaked["candidates"][0]["regionID"] = "line-signal-region-niko"
        self.expect_error(leaked, "unknown fields")

        missing_status = copy.deepcopy(self.input_payload)
        missing_status["pages"][0]["lineStatus"] = "success"
        missing_status["candidates"] = [candidate for candidate in missing_status["candidates"] if candidate["kind"] != "line"]
        self.expect_error(missing_status, "line success without a candidate")

        explicit_empty = copy.deepcopy(self.input_payload)
        explicit_empty["pages"][0]["lineStatus"] = "empty"
        explicit_empty["candidates"] = [candidate for candidate in explicit_empty["candidates"] if candidate["kind"] != "line"]
        report = self.evaluate(explicit_empty)
        self.assertEqual(report["pages"][0]["budget"]["declaredPageLineStatus"], "empty")
        self.assertEqual(report["totals"]["lines"]["omissionCount"], 4)

        over_budget = copy.deepcopy(self.input_payload)
        over_budget["budgets"]["maxLineCandidates"] = 3
        self.expect_error(over_budget, "line candidate budget exceeded")

        orphan = copy.deepcopy(self.input_payload)
        orphan["candidates"][2]["parentCandidateID"] = "unknown-region"
        self.expect_error(orphan, "candidate parent is unknown")

    def test_cloud_route_and_product_boundary_are_explicit(self) -> None:
        for marker in (
            "GITHUB_ACTIONS:-",
            "JAPANESE_OCR_LINE_SIGNAL_MANIFEST",
            "JAPANESE_OCR_LINE_SIGNAL_INPUT",
            "evaluate-japanese-ocr-line-signal.py",
            "shadow",
        ):
            self.assertIn(marker, self.shell)
        self.assertNotIn("xcodebuild", self.shell)
        self.assertNotIn("cargo", self.shell)
        self.assertNotIn("model.safetensors", self.shell)
        for marker in (
            "scripts/test-v3283-japanese-ocr-line-signal-contract.py",
            "scripts/run-japanese-ocr-line-signal-cloud-smoke.sh",
            "japanese-ocr-line-signal-report.json",
            "Aggregate v3.283 native line/TextRegion shadow contract",
            "japanese-benchmark-v3.301-",
        ):
            self.assertIn(marker, self.workflow)
        evaluator_source = read("scripts/evaluate-japanese-ocr-line-signal.py")
        self.assertNotIn("AITRANS/", evaluator_source)
        self.assertIn("contract-only", self.example_readme)
        self.assertIn("shadow-only", self.protocol_readme)
        self.assertIn("Native line/TextRegion shadow signal (v3.283)", self.benchmark_readme)
        self.assertIn("v3.283", self.route)
        self.assertIn("TextRegion/line", self.route)
        self.assertIn("shadow", self.route)
        self.assertEqual(re.findall(r"MARKETING_VERSION = ([^;]+);", self.project), ["3.323", "3.323"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

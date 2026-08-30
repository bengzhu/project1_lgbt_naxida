#!/usr/bin/env python3
"""Static and in-process contract for the v3.280 benchmark boundary.

This contract deliberately imports the pure scorers instead of launching a
child process. It is safe for the local no-process validation tier.
"""

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


def load_module(relative: str, name: str):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"could not load {relative}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class JapaneseBenchmarkContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.ocr = load_module("scripts/evaluate-japanese-ocr-benchmark.py", "aitrans_ocr_benchmark_v3280")
        cls.translation = load_module("scripts/evaluate-japanese-translation-benchmark.py", "aitrans_translation_benchmark_v3280")
        cls.ocr_manifest_path = ROOT / "benchmarks/japanese_ocr/examples/minimal/manifest.json"
        cls.ocr_prediction_path = ROOT / "benchmarks/japanese_ocr/examples/minimal/predictions.json"
        cls.ocr_manifest = load_json("benchmarks/japanese_ocr/examples/minimal/manifest.json")
        cls.ocr_predictions = load_json("benchmarks/japanese_ocr/examples/minimal/predictions.json")
        cls.translation_manifest_path = ROOT / "benchmarks/japanese_translation/examples/minimal/manifest.json"
        cls.translation_prediction_path = ROOT / "benchmarks/japanese_translation/examples/minimal/predictions.json"
        cls.translation_manifest = load_json("benchmarks/japanese_translation/examples/minimal/manifest.json")
        cls.translation_predictions = load_json("benchmarks/japanese_translation/examples/minimal/predictions.json")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def expect_error(self, callback, needle: str) -> None:
        with self.assertRaises(self.ocr.BenchmarkError) as context:
            callback()
        self.assertIn(needle, str(context.exception))

    def expect_translation_error(self, callback, needle: str) -> None:
        with self.assertRaises(self.translation.BenchmarkError) as context:
            callback()
        self.assertIn(needle, str(context.exception))

    def test_schema_files_are_json_and_fail_closed_shapes_are_declared(self) -> None:
        paths = [
            "benchmarks/japanese_ocr/schema/fixture-manifest.schema.json",
            "benchmarks/japanese_ocr/schema/prediction.schema.json",
            "benchmarks/japanese_ocr/schema/report.schema.json",
            "benchmarks/japanese_translation/schema/fixture-manifest.schema.json",
            "benchmarks/japanese_translation/schema/prediction.schema.json",
            "benchmarks/japanese_translation/schema/report.schema.json",
        ]
        for path in paths:
            schema = load_json(path)
            self.assertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
            self.assertEqual(schema["type"], "object")
            self.assertFalse(schema["additionalProperties"])
            self.assertIn("required", schema)
        self.assertIn("status", load_json("benchmarks/japanese_ocr/schema/prediction.schema.json")["$defs"]["prediction"]["required"])
        self.assertIn("rawResponse", load_json("benchmarks/japanese_translation/schema/prediction.schema.json")["properties"]["predictions"]["items"]["required"])

    def test_manifest_and_source_sha_boundaries_are_real(self) -> None:
        ocr_info = self.ocr.validate_manifest(
            self.ocr_manifest,
            manifest_path=self.ocr_manifest_path,
            repo_root=ROOT,
            verify_assets=True,
        )
        self.assertEqual(ocr_info["manifestSha256"], self.ocr_manifest["manifestSha256"])
        translation_info = self.translation.validate_manifest(
            self.translation_manifest,
            manifest_path=self.translation_manifest_path,
            repo_root=ROOT,
            verify_assets=True,
        )
        self.assertEqual(translation_info["manifestSha256"], self.translation_manifest["manifestSha256"])
        translation_root_path = ROOT / "benchmarks/japanese_translation/fixtures/manifest.json"
        translation_root = load_json("benchmarks/japanese_translation/fixtures/manifest.json")
        self.assertEqual(
            self.translation.validate_manifest(
                translation_root,
                manifest_path=translation_root_path,
                repo_root=ROOT,
                verify_assets=True,
            )["manifestSha256"],
            translation_root["manifestSha256"],
        )
        legacy = load_json("benchmarks/japanese_ocr/fixtures/manifest.json")
        self.assertTrue(legacy["fixtures"][0]["legacyRegression"])
        self.assertEqual(legacy["fixtures"][0]["annotationStatus"], "legacyRegressionOnly")
        self.assertEqual(len(legacy["fixtures"][0]["regions"]), 0)
        self.assertEqual(len(legacy["fixtures"][0]["oracleCrops"]), 7)
        self.assertTrue(all(crop["referenceOnly"] for crop in legacy["fixtures"][0]["oracleCrops"]))

    def test_ocr_scorer_is_deterministic_and_reports_real_layers(self) -> None:
        first = self.ocr.score(
            self.ocr_manifest,
            self.ocr_predictions,
            manifest_path=self.ocr_manifest_path,
            repo_root=ROOT,
        )
        second = self.ocr.score(
            self.ocr_manifest,
            self.ocr_predictions,
            manifest_path=self.ocr_manifest_path,
            repo_root=ROOT,
        )
        self.assertEqual(first, second)
        self.assertEqual(first["status"], "success")
        self.assertEqual(first["metrics"]["ocr"]["micro"]["exactMatchRate"], 1.0)
        self.assertEqual(first["metrics"]["ocr"]["micro"]["characterErrorRate"], 0.0)
        self.assertEqual(first["metrics"]["detector"]["f1"], 1.0)
        self.assertIn("SFX", first["metrics"]["ocr"]["byCategory"])
        self.assertIn("vertical", first["metrics"]["ocr"]["byCategory"])
        self.assertEqual(first["metrics"]["lineGeometry"]["regionPolygonValidityRate"], 1.0)
        self.assertIn("！", self.ocr_manifest["fixtures"][0].get("oracleCrops", [{}])[0].get("expectedText", "") + "！")

        for level in ("detectedCrop", "fullPage"):
            geometry_payload = copy.deepcopy(self.ocr_predictions)
            geometry_payload["predictions"][0]["evaluationLevel"] = level
            geometry_payload["predictions"][0]["regionID"] = None
            geometry_report = self.ocr.score(
                self.ocr_manifest,
                geometry_payload,
                manifest_path=self.ocr_manifest_path,
                repo_root=ROOT,
            )
            self.assertEqual(geometry_report["metrics"]["detector"]["f1"], 1.0)
            self.assertEqual(geometry_report["metrics"]["ocr"]["micro"]["exactMatchRate"], 1.0)

    def test_ocr_malformed_geometry_sha_duplicate_missing_and_empty_gt_fail(self) -> None:
        malformed = copy.deepcopy(self.ocr_manifest)
        malformed["fixtures"][0]["regions"][0]["polygon"] = [[0.46, 0.65], [0.51, 0.71], [0.51, 0.65], [0.46, 0.71]]
        malformed["manifestSha256"] = self.ocr.manifest_sha256(malformed)
        self.expect_error(
            lambda: self.ocr.validate_manifest(malformed, repo_root=ROOT, verify_assets=False),
            "degenerate",
        )

        mismatch = copy.deepcopy(self.ocr_manifest)
        mismatch["fixtures"][0]["asset"]["sha256"] = "0" * 64
        mismatch["manifestSha256"] = self.ocr.manifest_sha256(mismatch)
        self.expect_error(
            lambda: self.ocr.validate_manifest(mismatch, manifest_path=self.ocr_manifest_path, repo_root=ROOT, verify_assets=True),
            "asset SHA mismatch",
        )

        duplicate_region = copy.deepcopy(self.ocr_manifest)
        duplicate_region["fixtures"][0]["regions"].append(copy.deepcopy(duplicate_region["fixtures"][0]["regions"][0]))
        duplicate_region["manifestSha256"] = self.ocr.manifest_sha256(duplicate_region)
        self.expect_error(
            lambda: self.ocr.validate_manifest(duplicate_region, repo_root=ROOT, verify_assets=False),
            "duplicate regionID",
        )

        duplicate_prediction = copy.deepcopy(self.ocr_predictions)
        duplicate_prediction["predictions"].append(copy.deepcopy(duplicate_prediction["predictions"][0]))
        info = self.ocr.validate_manifest(self.ocr_manifest, manifest_path=self.ocr_manifest_path, repo_root=ROOT)
        self.expect_error(
            lambda: self.ocr.validate_predictions(duplicate_prediction, self.ocr_manifest, info),
            "duplicate predictionID",
        )

        unknown_prediction_field = copy.deepcopy(self.ocr_predictions)
        unknown_prediction_field["unexpected"] = True
        self.expect_error(
            lambda: self.ocr.validate_predictions(unknown_prediction_field, self.ocr_manifest, info),
            "unknown fields",
        )

        missing_prediction = copy.deepcopy(self.ocr_predictions)
        missing_prediction["predictions"] = []
        self.expect_error(
            lambda: self.ocr.validate_predictions(missing_prediction, self.ocr_manifest, info),
            "missing explicit prediction row",
        )

        explicit_empty = copy.deepcopy(self.ocr_predictions)
        explicit_empty["predictions"][0]["status"] = "empty"
        explicit_empty["predictions"][0]["text"] = ""
        explicit_empty["predictions"][0]["failureReason"] = "contract-empty"
        empty_report = self.ocr.score(
            self.ocr_manifest,
            explicit_empty,
            manifest_path=self.ocr_manifest_path,
            repo_root=ROOT,
        )
        self.assertEqual(empty_report["counts"]["omissions"], 1)

        mixed_levels = copy.deepcopy(self.ocr_predictions)
        extra_prediction = copy.deepcopy(mixed_levels["predictions"][0])
        extra_prediction["predictionID"] = "contract-p-niko-full-page"
        extra_prediction["evaluationLevel"] = "fullPage"
        mixed_levels["predictions"].append(extra_prediction)
        self.expect_error(
            lambda: self.ocr.validate_predictions(mixed_levels, self.ocr_manifest, info),
            "cannot be mixed",
        )

        oracle_without_region = copy.deepcopy(self.ocr_predictions)
        oracle_without_region["predictions"][0]["regionID"] = None
        self.expect_error(
            lambda: self.ocr.validate_predictions(oracle_without_region, self.ocr_manifest, info),
            "oracleCrop prediction must identify its region",
        )

        detected_with_ground_truth_id = copy.deepcopy(self.ocr_predictions)
        detected_with_ground_truth_id["predictions"][0]["evaluationLevel"] = "detectedCrop"
        self.expect_error(
            lambda: self.ocr.validate_predictions(detected_with_ground_truth_id, self.ocr_manifest, info),
            "must not use ground-truth regionID",
        )

        empty_gt = copy.deepcopy(self.ocr_manifest)
        empty_gt["fixtures"][0]["annotationStatus"] = "human"
        empty_gt["fixtures"][0]["exampleOnly"] = False
        empty_gt["fixtures"][0]["regions"] = []
        empty_gt["manifestSha256"] = self.ocr.manifest_sha256(empty_gt)
        self.expect_error(
            lambda: self.ocr.validate_manifest(empty_gt, repo_root=ROOT, verify_assets=False),
            "empty ground truth",
        )

    def test_ocr_split_isolation_and_no_ground_truth_status(self) -> None:
        holdout = copy.deepcopy(self.ocr_manifest)
        extra = copy.deepcopy(holdout["fixtures"][0])
        extra["pageID"] = "contract-holdout-page"
        extra["split"] = "holdout"
        extra["legacyRegression"] = False
        extra["annotationStatus"] = "contractExampleOnly"
        extra["exampleOnly"] = True
        extra["regions"] = []
        # A legacy fixture is sufficient to prove that a prediction from a
        # different split is rejected without adding another ground-truth row.
        holdout["fixtures"].append(extra)
        holdout["manifestSha256"] = self.ocr.manifest_sha256(holdout)
        split_payload = copy.deepcopy(self.ocr_predictions)
        split_payload["predictions"][0]["pageID"] = "contract-holdout-page"
        split_payload["predictions"][0]["split"] = "holdout"
        split_payload["datasetSha256"] = holdout["manifestSha256"]
        info = self.ocr.validate_manifest(holdout, repo_root=ROOT, verify_assets=False)
        self.expect_error(
            lambda: self.ocr.validate_predictions(split_payload, holdout, info, split="dev"),
            "crosses requested split",
        )
        legacy = load_json("benchmarks/japanese_ocr/fixtures/manifest.json")
        legacy_predictions = load_json("benchmarks/japanese_ocr/fixtures/predictions.empty.json")
        report = self.ocr.score(
            legacy,
            legacy_predictions,
            manifest_path=ROOT / "benchmarks/japanese_ocr/fixtures/manifest.json",
            repo_root=ROOT,
            allow_no_ground_truth=True,
        )
        self.assertEqual(report["status"], "noGroundTruth")

    def test_translation_clean_corrupted_separation_and_tag_qa(self) -> None:
        first = self.translation.score(
            self.translation_manifest,
            self.translation_predictions,
            manifest_path=self.translation_manifest_path,
            repo_root=ROOT,
        )
        second = self.translation.score(
            self.translation_manifest,
            self.translation_predictions,
            manifest_path=self.translation_manifest_path,
            repo_root=ROOT,
        )
        self.assertEqual(first, second)
        self.assertEqual(first["metrics"]["all"]["hardGatePassRate"], 1.0)
        self.assertEqual(first["metrics"]["byInputKind"]["cleanSource"]["fixtureCount"], 1)
        self.assertEqual(first["metrics"]["byInputKind"]["ocrCorrupted"]["fixtureCount"], 1)
        broken = copy.deepcopy(self.translation_predictions)
        broken["predictions"][0]["rawResponse"] = "[b1] 今度こそ"
        broken_report = self.translation.score(
            self.translation_manifest,
            broken,
            manifest_path=self.translation_manifest_path,
            repo_root=ROOT,
        )
        self.assertGreater(broken_report["metrics"]["all"]["missingTagCount"], 0)
        self.assertTrue(any(item["kind"] == "missingTag" for item in broken_report["failures"]))

    def test_translation_sha_empty_unicode_and_split_guards(self) -> None:
        mismatch = copy.deepcopy(self.translation_manifest)
        mismatch["fixtures"][0]["input"]["sha256"] = "0" * 64
        mismatch["manifestSha256"] = self.translation.manifest_sha256(mismatch)
        self.expect_translation_error(
            lambda: self.translation.validate_manifest(mismatch, manifest_path=self.translation_manifest_path, repo_root=ROOT, verify_assets=True),
            "input SHA mismatch",
        )
        unknown_prediction_field = copy.deepcopy(self.translation_predictions)
        unknown_prediction_field["unexpected"] = True
        translation_info = self.translation.validate_manifest(
            self.translation_manifest,
            manifest_path=self.translation_manifest_path,
            repo_root=ROOT,
        )
        self.expect_translation_error(
            lambda: self.translation._validate_predictions(unknown_prediction_field, translation_info, split=None),
            "unknown fields",
        )
        empty = copy.deepcopy(self.translation_manifest)
        empty["fixtures"][0]["blocks"] = []
        empty["manifestSha256"] = self.translation.manifest_sha256(empty)
        self.expect_translation_error(
            lambda: self.translation.validate_manifest(empty, repo_root=ROOT, verify_assets=False),
            "empty translation ground truth",
        )
        split_payload = copy.deepcopy(self.translation_predictions)
        split_payload["predictions"][0]["split"] = "holdout"
        info = self.translation.validate_manifest(self.translation_manifest, manifest_path=self.translation_manifest_path, repo_root=ROOT)
        self.expect_translation_error(
            lambda: self.translation._validate_predictions(split_payload, info, split="dev"),
            "split mismatch",
        )
        self.assertEqual(self.translation.manifest_sha256(self.translation_manifest), self.translation_manifest["manifestSha256"])
        self.assertEqual(self.translation.unicodedata.normalize("NFC", "ニコッ"), "ニコッ")
        self.assertIn("rawResponse", read("benchmarks/japanese_translation/schema/prediction.schema.json"))

    def test_workflow_is_benchmark_only_and_product_sources_are_untouched_by_route(self) -> None:
        for marker in (
            "  japanese_benchmark:",
            "evaluate-japanese-ocr-benchmark.py",
            "evaluate-japanese-translation-benchmark.py",
            "japanese-ocr-benchmark-report.json",
            "japanese-translation-benchmark-report.json",
            "japanese-benchmark-summary.md",
        ):
            self.assertIn(marker, self.workflow)
        benchmark_start = self.workflow.index("  japanese_benchmark:")
        benchmark_end = self.workflow.index("\n  koharu_mit48_reference_parity:", benchmark_start)
        benchmark_job = self.workflow[benchmark_start:benchmark_end]
        self.assertNotIn("xcodebuild", benchmark_job)
        self.assertNotIn("xcrun", benchmark_job)
        self.assertNotIn("cargo", benchmark_job)
        self.assertNotIn("swiftc", benchmark_job)
        self.assertNotIn("AITRANS/Services/", benchmark_job)
        for source_path in (
            "AITRANS/Services/VisionOCRService.swift",
            "AITRANS/Services/MangaOCRService.swift",
            "AITRANS/Services/TranslationSessionStore.swift",
        ):
            source = read(source_path)
            self.assertNotIn("evaluate-japanese-ocr-benchmark.py", source)
            self.assertNotIn("benchmarks/japanese_ocr", source)
        self.assertEqual(re.findall(r"MARKETING_VERSION = ([^;]+);", self.project), ["3.360", "3.360"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

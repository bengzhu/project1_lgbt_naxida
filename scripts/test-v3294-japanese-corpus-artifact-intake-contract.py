#!/usr/bin/env python3
"""Static and deterministic contract for v3.294 evidence artifact intake."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile
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
    spec = importlib.util.spec_from_file_location("v3294_corpus_artifact_intake", path)
    if spec is None or spec.loader is None:
        raise AssertionError("unable to load v3.294 evaluator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class JapaneseCorpusArtifactIntakeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = load_json("benchmarks/japanese_ocr/examples/corpus_readiness/manifest.json")
        cls.evaluator = load_evaluator()
        cls.schema = load_json("benchmarks/japanese_ocr/schema/corpus-readiness-manifest.schema.json")
        cls.report_schema = load_json("benchmarks/japanese_ocr/schema/corpus-readiness-report.schema.json")
        cls.source = read("scripts/evaluate-japanese-corpus-readiness.py")
        cls.wrapper = read("scripts/run-japanese-corpus-readiness-cloud-smoke.sh")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
        cls.update_log = read("update_log.md")
        cls.test_log = read("md/test/test.md")

    @classmethod
    def rehash(cls, manifest: dict) -> dict:
        manifest["manifestSha256"] = cls.evaluator.manifest_sha256(manifest)
        return manifest

    @staticmethod
    def file_sha256(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    @staticmethod
    def write_json(path: Path, payload: dict) -> str:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return JapaneseCorpusArtifactIntakeContractTests.file_sha256(path)

    @classmethod
    def make_ready_fixture(cls):
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        manifest = copy.deepcopy(cls.manifest)
        dataset_sha = "a" * 64
        manifest["contractExampleOnly"] = False
        manifest["dataset"].update(
            {
                "status": "available",
                "datasetID": "authorized-contract-dataset",
                "datasetVersion": "2026-08-20-contract",
                "sha256": dataset_sha,
                "pageCount": 20,
                "annotatedRegionCount": 150,
                "license": "authorized-test-use",
                "authorized": True,
                "permittedUses": ["benchmark", "holdout"],
                "artifactPath": "dataset/corpus.tar",
                "artifactSha256": None,
                "sourceManifestPath": "dataset/source-manifest.json",
                "sourceManifestSha256": None,
            }
        )
        train_pages = [f"train-page-{index}" for index in range(10)]
        dev_pages = [f"dev-page-{index}" for index in range(5)]
        holdout_pages = [f"holdout-page-{index}" for index in range(5)]
        train_regions = [f"train-region-{index}" for index in range(75)]
        dev_regions = [f"dev-region-{index}" for index in range(40)]
        holdout_regions = [f"holdout-region-{index}" for index in range(35)]
        manifest["splits"] = [
            {
                "splitID": "train", "status": "available", "pageCount": 10, "regionCount": 75,
                "assetIDs": train_pages, "regionIDs": train_regions,
                "annotationStatus": "complete", "groundTruthStatus": "available",
            },
            {
                "splitID": "dev", "status": "available", "pageCount": 5, "regionCount": 40,
                "assetIDs": dev_pages, "regionIDs": dev_regions,
                "annotationStatus": "complete", "groundTruthStatus": "available",
            },
            {
                "splitID": "holdout", "status": "available", "pageCount": 5, "regionCount": 35,
                "assetIDs": holdout_pages, "regionIDs": holdout_regions,
                "annotationStatus": "complete", "groundTruthStatus": "available",
            },
        ]
        manifest["holdoutPolicy"].update(
            {
                "status": "verified",
                "splitIsolation": "verified",
                "datasetFrozen": True,
                "policyFrozenBeforeHoldout": True,
                "holdoutEvaluatedOnce": False,
                "holdoutTunedAfterEvaluation": False,
                "holdoutUsedForProductSelection": False,
                "groundTruthUsedForDecision": False,
                "protocolSha256": "d" * 64,
            }
        )
        manifest["promotion"].update(
            {
                "status": "readyForHoldout",
                "reasons": ["materialized contract intake fixture"],
                "requiredEvidence": ["one-time holdout receipt"],
            }
        )

        dataset_path = root / "dataset/corpus.tar"
        dataset_path.parent.mkdir(parents=True, exist_ok=True)
        dataset_path.write_bytes(b"authorized dataset contract bytes\n")
        source_manifest_path = root / "dataset/source-manifest.json"
        cls.write_json(source_manifest_path, {"datasetSha256": dataset_sha, "authorized": True})
        manifest["dataset"]["artifactSha256"] = cls.file_sha256(dataset_path)
        manifest["dataset"]["sourceManifestSha256"] = cls.file_sha256(source_manifest_path)

        rows = []
        for required_row in manifest["predictionMatrix"]["requiredRows"]:
            row = copy.deepcopy(required_row)
            row.update(
                {
                    "status": "available",
                    "path": f"predictions/{row['artifactID']}.json",
                    "datasetSha256": dataset_sha,
                    "authorized": True,
                }
            )
            if row["cropLevel"] == "oracleCrop":
                selected = [
                    (page_id, region_id)
                    for index, region_id in enumerate(dev_regions)
                    for page_id in [dev_pages[index % len(dev_pages)]]
                ]
            else:
                selected = [(page_id, None) for page_id in dev_pages]
            predictions = []
            for index, (page_id, region_id) in enumerate(selected):
                predictions.append(
                    {
                        "predictionID": f"{row['artifactID']}-{index}",
                        "pageID": page_id,
                        "split": "dev",
                        "evaluationLevel": row["cropLevel"],
                        "regionID": region_id,
                        "lineID": None,
                        "status": "empty",
                        "text": "",
                        "rawText": None,
                        "confidence": None,
                        "bbox": None,
                        "polygon": None,
                        "writingDirection": None,
                        "readingOrder": None,
                        "engine": row["engineID"],
                        "cropVariant": row["cropLevel"],
                        "referenceOnly": row["referenceOnly"],
                        "failureReason": "contract intake fixture",
                    }
                )
            row["predictionCount"] = len(predictions)
            payload = {
                "schemaVersion": "1.0.0",
                "benchmark": "japanese-ocr",
                "datasetSha256": dataset_sha,
                "run": {
                    "appSha": "b" * 40,
                    "engineID": row["engineID"],
                    "engineVersion": "contract-intake",
                    "model": {
                        "id": f"{row['engineID']}-contract",
                        "version": "contract",
                        "sha256": "c" * 64,
                        "license": row["license"],
                    },
                    "license": row["license"],
                    "device": "cloud-contract",
                    "parameters": {"status": "contract-only"},
                },
                "predictions": predictions,
            }
            artifact_path = root / row["path"]
            row["sha256"] = cls.write_json(artifact_path, payload)
            rows.append(row)
        manifest["predictionMatrix"]["status"] = "available"
        manifest["predictionMatrix"]["rows"] = rows
        cls.rehash(manifest)
        return temporary, root, manifest

    def test_contract_fixture_is_blocked_without_intake(self) -> None:
        validated = self.evaluator.validate_manifest(self.manifest)
        self.assertEqual(validated["artifactIntakeStatus"], "notRequired")
        report = self.evaluator.evaluate_manifest(self.manifest)
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["artifactIntakeStatus"], "notRequired")
        self.assertFalse(report["productPathEnabled"])

    def test_available_evidence_requires_an_explicit_artifact_root(self) -> None:
        mutated = copy.deepcopy(self.manifest)
        mutated["dataset"].update(
            {
                "status": "available",
                "sha256": "a" * 64,
                "artifactPath": "dataset/corpus.tar",
                "artifactSha256": "b" * 64,
                "sourceManifestPath": "dataset/source-manifest.json",
                "sourceManifestSha256": "c" * 64,
                "authorized": True,
            }
        )
        self.rehash(mutated)
        with self.assertRaisesRegex(self.evaluator.CorpusReadinessError, "artifact-root"):
            self.evaluator.validate_manifest(mutated)

    def test_materialized_artifacts_verify_to_ready_for_holdout_without_product_change(self) -> None:
        temporary, root, manifest = self.make_ready_fixture()
        try:
            report = self.evaluator.evaluate_manifest(manifest, root)
            self.assertEqual(report["status"], "readyForHoldout")
            self.assertEqual(report["artifactIntakeStatus"], "verified")
            self.assertFalse(report["productPathEnabled"])
            self.assertFalse(report["productSelectionChanged"])
            self.assertFalse(report["groundTruthUsedForDecision"])
        finally:
            temporary.cleanup()

    def test_prediction_artifact_hash_mismatch_fails_closed(self) -> None:
        temporary, root, manifest = self.make_ready_fixture()
        try:
            artifact = root / manifest["predictionMatrix"]["rows"][0]["path"]
            artifact.write_text("tampered\n", encoding="utf-8")
            with self.assertRaisesRegex(self.evaluator.CorpusReadinessError, "artifact SHA-256"):
                self.evaluator.validate_manifest(manifest, root)
        finally:
            temporary.cleanup()

    def test_path_escape_and_symlink_are_rejected(self) -> None:
        mutated = copy.deepcopy(self.manifest)
        row = copy.deepcopy(mutated["predictionMatrix"]["requiredRows"][0])
        row.update({"status": "available", "path": "../outside.json", "sha256": "a" * 64, "datasetSha256": "b" * 64, "authorized": True, "predictionCount": 1})
        mutated["predictionMatrix"]["rows"] = [row]
        self.rehash(mutated)
        with self.assertRaisesRegex(self.evaluator.CorpusReadinessError, "must not escape"):
            self.evaluator.validate_manifest(mutated)

        temporary, root, ready = self.make_ready_fixture()
        try:
            source = root / ready["predictionMatrix"]["rows"][0]["path"]
            link = root / "predictions/symlink.json"
            link.symlink_to(source)
            symlink_row = ready["predictionMatrix"]["rows"][1]
            symlink_row["path"] = "predictions/symlink.json"
            symlink_row["sha256"] = self.file_sha256(source)
            self.rehash(ready)
            with self.assertRaisesRegex(self.evaluator.CorpusReadinessError, "symlinks"):
                self.evaluator.validate_manifest(ready, root)
        finally:
            temporary.cleanup()

    def test_prediction_payload_identity_and_count_are_verified(self) -> None:
        temporary, root, manifest = self.make_ready_fixture()
        try:
            row = manifest["predictionMatrix"]["rows"][0]
            artifact = root / row["path"]
            payload = json.loads(artifact.read_text(encoding="utf-8"))
            payload["datasetSha256"] = "e" * 64
            artifact.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            row["sha256"] = self.file_sha256(artifact)
            self.rehash(manifest)
            with self.assertRaisesRegex(self.evaluator.CorpusReadinessError, "dataset SHA"):
                self.evaluator.validate_manifest(manifest, root)

            temporary.cleanup()
            temporary, root, manifest = self.make_ready_fixture()
            row = manifest["predictionMatrix"]["rows"][0]
            artifact = root / row["path"]
            payload = json.loads(artifact.read_text(encoding="utf-8"))
            payload["predictions"].pop()
            artifact.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            row["sha256"] = self.file_sha256(artifact)
            self.rehash(manifest)
            with self.assertRaisesRegex(self.evaluator.CorpusReadinessError, "predictionCount"):
                self.evaluator.validate_manifest(manifest, root)
        finally:
            temporary.cleanup()

    def test_prediction_payload_covers_dev_pages_and_oracle_regions(self) -> None:
        temporary, root, manifest = self.make_ready_fixture()
        try:
            row = next(item for item in manifest["predictionMatrix"]["rows"] if item["cropLevel"] == "detectedCrop")
            artifact = root / row["path"]
            payload = json.loads(artifact.read_text(encoding="utf-8"))
            payload["predictions"] = payload["predictions"][:-1]
            row["predictionCount"] = len(payload["predictions"])
            artifact.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            row["sha256"] = self.file_sha256(artifact)
            self.rehash(manifest)
            with self.assertRaisesRegex(self.evaluator.CorpusReadinessError, "every dev page"):
                self.evaluator.validate_manifest(manifest, root)
        finally:
            temporary.cleanup()

    def test_schema_report_and_ci_route_are_versioned(self) -> None:
        self.assertEqual(self.schema["properties"]["schemaVersion"]["const"], "1.1.0")
        self.assertIn("artifactPath", self.schema["$defs"]["dataset"]["required"])
        self.assertIn("regionIDs", self.schema["$defs"]["split"]["required"])
        self.assertEqual(self.report_schema["properties"]["schemaVersion"]["const"], "1.1.0")
        self.assertIn("artifactIntakeStatus", self.report_schema["required"])
        for marker in (
            "--artifact-root",
            "artifactIntakeStatus",
            "dataset artifact SHA-256",
            "predictionCount does not match",
            "v3.294",
            "test-v3294-japanese-corpus-artifact-intake-contract.py",
            "japanese-benchmark-v3.301-",
        ):
            self.assertIn(marker, self.source + self.wrapper + self.workflow + self.route + self.update_log + self.test_log)
        self.assertNotIn("subprocess", self.source)
        self.assertNotIn("MangaOverlayProbeService", self.source)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.331", "3.331"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

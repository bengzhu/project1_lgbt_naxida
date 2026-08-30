#!/usr/bin/env python3
"""Static and deterministic contract for v3.293 corpus matrix integrity."""

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
    spec = importlib.util.spec_from_file_location("v3293_corpus_matrix_integrity", path)
    if spec is None or spec.loader is None:
        raise AssertionError("unable to load v3.293 evaluator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class JapaneseCorpusMatrixIntegrityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = load_json("benchmarks/japanese_ocr/examples/corpus_readiness/manifest.json")
        cls.evaluator = load_evaluator()
        cls.schema = load_json("benchmarks/japanese_ocr/schema/corpus-readiness-manifest.schema.json")
        cls.source = read("scripts/evaluate-japanese-corpus-readiness.py")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
        cls.update_log = read("update_log.md")
        cls.test_log = read("md/test/test.md")

    @classmethod
    def rehash(cls, manifest: dict) -> dict:
        manifest["manifestSha256"] = cls.evaluator.manifest_sha256(manifest)
        return manifest

    def test_required_matrix_is_canonical_four_engine_dev_matrix(self) -> None:
        expected = set(self.evaluator.EXPECTED_PREDICTION_MATRIX)
        required = {
            (row["engineID"], row["cropLevel"], row["splitID"])
            for row in self.manifest["predictionMatrix"]["requiredRows"]
        }
        self.assertEqual(required, expected)
        self.assertEqual(len(required), 12)
        self.evaluator.validate_manifest(self.manifest)

        mutated = copy.deepcopy(self.manifest)
        mutated["predictionMatrix"]["requiredRows"].pop()
        self.rehash(mutated)
        with self.assertRaisesRegex(self.evaluator.CorpusReadinessError, "canonical four-engine dev matrix"):
            self.evaluator.validate_manifest(mutated)

    def test_artifact_identity_and_reference_only_role_are_locked(self) -> None:
        mutated = copy.deepcopy(self.manifest)
        mutated["predictionMatrix"]["requiredRows"][0]["artifactID"] = "vision-oracle"
        self.rehash(mutated)
        with self.assertRaises(self.evaluator.CorpusReadinessError):
            self.evaluator.validate_manifest(mutated)

        mutated = copy.deepcopy(self.manifest)
        mutated["predictionMatrix"]["requiredRows"][0]["referenceOnly"] = True
        self.rehash(mutated)
        with self.assertRaises(self.evaluator.CorpusReadinessError):
            self.evaluator.validate_manifest(mutated)

    def test_failed_or_missing_actual_rows_never_become_ready(self) -> None:
        mutated = copy.deepcopy(self.manifest)
        failed_row = copy.deepcopy(mutated["predictionMatrix"]["requiredRows"][0])
        failed_row["status"] = "failed"
        mutated["predictionMatrix"]["rows"] = [failed_row]
        self.rehash(mutated)

        report = self.evaluator.evaluate_manifest(mutated)
        self.assertEqual(report["status"], "blocked")
        reasons = " | ".join(report["reasons"])
        self.assertIn("prediction row aitrans-oracle is failed", reasons)
        self.assertIn("prediction row is missing", reasons)

    def test_holdout_selection_and_ground_truth_flags_are_fail_closed(self) -> None:
        for field in ("holdoutUsedForProductSelection", "groundTruthUsedForDecision"):
            mutated = copy.deepcopy(self.manifest)
            mutated["holdoutPolicy"][field] = True
            self.rehash(mutated)
            with self.subTest(field=field):
                with self.assertRaises(self.evaluator.CorpusReadinessError):
                    self.evaluator.validate_manifest(mutated)

    def test_split_counts_must_cover_available_dataset(self) -> None:
        mutated = copy.deepcopy(self.manifest)
        mutated["contractExampleOnly"] = False
        mutated["dataset"].update(
            {
                "status": "available",
                "datasetID": "authorized-corpus",
                "datasetVersion": "2026-08-20",
                "sha256": "a" * 64,
                "pageCount": 5,
                "annotatedRegionCount": 5,
                "license": "authorized-test-use",
                "authorized": True,
                "permittedUses": ["benchmark"],
                "artifactPath": "handoff/corpus.bin",
                "artifactSha256": None,
                "sourceManifestPath": "handoff/manifest.json",
                "sourceManifestSha256": None,
            }
        )
        for index, split in enumerate(mutated["splits"]):
            split.update(
                {
                    "status": "available",
                    "pageCount": 1,
                    "regionCount": 1,
                    "assetIDs": [f"page-{index}"],
                    "regionIDs": [f"region-{index}"],
                    "annotationStatus": "complete",
                    "groundTruthStatus": "available",
                }
            )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifact = root / "handoff/corpus.bin"
            artifact.parent.mkdir(parents=True, exist_ok=True)
            artifact.write_bytes(b"corpus")
            source_manifest = root / "handoff/manifest.json"
            source_manifest.write_text("{\"authorized\":true}\n", encoding="utf-8")
            mutated["dataset"]["artifactSha256"] = hashlib.sha256(artifact.read_bytes()).hexdigest()
            mutated["dataset"]["sourceManifestSha256"] = hashlib.sha256(source_manifest.read_bytes()).hexdigest()
            self.rehash(mutated)
            report = self.evaluator.evaluate_manifest(mutated, root)
        self.assertEqual(report["status"], "blocked")
        reasons = " | ".join(report["reasons"])
        self.assertIn("split page counts do not cover", reasons)
        self.assertIn("split region counts do not cover", reasons)

    def test_contract_is_static_and_route_is_wired(self) -> None:
        self.assertNotIn("subprocess", self.source)
        self.assertNotIn("MangaOverlayProbeService", self.source)
        self.assertNotIn("ImageTranslationBlock", self.source)
        self.assertNotIn("ground_truth", self.source.lower())
        for marker in (
            "EXPECTED_PREDICTION_MATRIX",
            "holdoutUsedForProductSelection",
            "split page counts do not cover",
            "scripts/test-v3293-japanese-corpus-matrix-integrity-contract.py",
            "japanese-benchmark-v3.301-",
            "v3.293",
            "canonical four-engine dev matrix",
        ):
            self.assertIn(marker, self.source + self.workflow + self.route + self.update_log + self.test_log)
        self.assertEqual(re.findall(r"MARKETING_VERSION = ([^;]+);", self.project), ["3.352", "3.352"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

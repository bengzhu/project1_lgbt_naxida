#!/usr/bin/env python3
"""Static and deterministic contract for v3.291 mask readiness preflight."""

from __future__ import annotations

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
    path = ROOT / "scripts/evaluate-japanese-mask-artifact-readiness.py"
    spec = importlib.util.spec_from_file_location("v3291_mask_artifact_readiness", path)
    if spec is None or spec.loader is None:
        raise AssertionError("unable to load v3.291 evaluator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MaskArtifactReadinessContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.schema = load_json("benchmarks/japanese_render/schema/mask-artifact-manifest.schema.json")
        cls.report_schema = load_json("benchmarks/japanese_render/schema/mask-artifact-report.schema.json")
        cls.manifest = load_json("benchmarks/japanese_render/examples/mask_artifacts/manifest.json")
        cls.evaluator = load_evaluator()
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
        cls.update_log = read("update_log.md")
        cls.readme = read("benchmarks/japanese_render/README.md")

    def test_manifest_and_report_schemas_are_strict_and_versioned(self) -> None:
        self.assertEqual(self.schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
        self.assertFalse(self.schema["additionalProperties"])
        self.assertEqual(self.schema["properties"]["benchmark"]["const"], "japanese-render-mask-artifacts")
        self.assertEqual(self.report_schema["properties"]["productPathEnabled"]["const"], False)
        self.assertFalse(self.report_schema["additionalProperties"])

    def test_manifest_hash_roles_and_exact_identity_are_present(self) -> None:
        self.assertEqual(self.manifest["schemaVersion"], "1.0.0")
        self.assertTrue(self.manifest["contractExampleOnly"])
        self.assertRegex(self.manifest["manifestSha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(self.manifest["run"]["appSha"], r"^[0-9a-f]{40}$")
        self.assertEqual(
            {artifact["role"] for artifact in self.manifest["artifacts"]},
            {"BubbleMask", "SegmentMask"},
        )
        self.evaluator.validate_manifest(self.manifest)
        self.assertEqual(
            self.manifest["manifestSha256"],
            self.evaluator.manifest_sha256(self.manifest),
        )

    def test_unavailable_artifacts_fail_closed_and_never_become_default(self) -> None:
        for artifact in self.manifest["artifacts"]:
            self.assertEqual(artifact["artifactStatus"], "missing")
            self.assertIsNone(artifact["filename"])
            self.assertIsNone(artifact["sha256"])
            self.assertIsNone(artifact["sizeBytes"])
            self.assertIsNone(artifact["quantization"])
            self.assertFalse(artifact["licenseReviewed"])
            self.assertTrue(artifact["referenceOnly"])
            self.assertFalse(artifact["defaultEnabled"])
            self.assertIn(artifact["distribution"], {"cloudOnlyReference", "notDistributable"})

    def test_corpus_and_target_device_gates_are_explicitly_missing(self) -> None:
        corpus = self.manifest["evaluationCorpus"]
        self.assertEqual(corpus["status"], "missing")
        self.assertFalse(corpus["authorized"])
        self.assertEqual(self.manifest["targetDeviceEvidence"]["status"], "missing")
        self.assertEqual(self.manifest["targetDeviceEvidence"]["runs"], [])

    def test_promotion_boundary_cannot_enable_product_or_read_ground_truth(self) -> None:
        promotion = self.manifest["promotion"]
        self.assertEqual(promotion["status"], "blocked")
        self.assertFalse(promotion["productPathEnabled"])
        self.assertFalse(promotion["productSelectionChanged"])
        self.assertFalse(promotion["groundTruthUsedForDecision"])
        self.assertGreaterEqual(len(promotion["requiredEvidence"]), 5)

    def test_evaluator_reports_blocked_with_all_missing_reasons(self) -> None:
        report = self.evaluator.evaluate_manifest(self.manifest)
        self.assertEqual(set(report), set(self.report_schema["required"]))
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["artifactStatusByRole"], {"BubbleMask": "missing", "SegmentMask": "missing"})
        self.assertEqual(report["targetDeviceEvidenceStatus"], "missing")
        self.assertFalse(report["productPathEnabled"])
        self.assertFalse(report["productSelectionChanged"])
        self.assertFalse(report["groundTruthUsedForDecision"])
        reasons = " | ".join(report["reasons"])
        for marker in ("corpus", "BubbleMask", "SegmentMask", "license", "target-device"):
            self.assertIn(marker, reasons)

    def test_evaluator_rejects_manifest_hash_mutation(self) -> None:
        mutated = json.loads(json.dumps(self.manifest))
        mutated["artifacts"][0]["modelID"] = "different-model"
        with self.assertRaises(self.evaluator.MaskArtifactReadinessError):
            self.evaluator.evaluate_manifest(mutated)

    def test_route_and_ci_keep_readiness_cloud_only_and_report_only(self) -> None:
        for marker in (
            "v3.291",
            "BubbleMask",
            "SegmentMask",
            "productPathEnabled",
            "referenceOnly",
            "真实 mask artifact",
            "不引入 native mask",
        ):
            self.assertIn(marker, self.route + self.update_log + self.readme)
        for marker in (
            "scripts/test-v3291-mask-artifact-readiness-contract.py",
            "scripts/run-japanese-mask-artifact-readiness-cloud-smoke.sh",
            "japanese-render-mask-artifact-report.json",
        ):
            self.assertIn(marker, self.workflow)
        self.assertIn("GITHUB_ACTIONS", read("scripts/run-japanese-mask-artifact-readiness-cloud-smoke.sh"))

    def test_readiness_preflight_does_not_enter_product_mask_or_renderer_paths(self) -> None:
        evaluator_source = read("scripts/evaluate-japanese-mask-artifact-readiness.py")
        self.assertNotIn("MangaOverlayProbeService", evaluator_source)
        self.assertNotIn("ImageTranslationBlock", evaluator_source)
        self.assertNotIn("inpaint", evaluator_source.lower())
        self.assertIn("productPathEnabled", self.readme)

    def test_project_version_is_v3291_and_history_remains_currently_versioned(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = ([^;]+);", self.project)
        self.assertEqual(versions, ["3.359", "3.359"])
        self.assertIn("v3.291", self.update_log)


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Focused contract tests for Koharu v2 mask payload validation."""

from __future__ import annotations

import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "scripts/validate-koharu-artifacts.py"
VALID_FIXTURE = ROOT / "md/人工空间/koharu研究/artifact_contract/examples/valid_v2_mask_payload"
INVALID_FIXTURE = ROOT / "md/人工空间/koharu研究/artifact_contract/examples/invalid/v2_mask_payload_mismatch"


def load_validator():
    spec = importlib.util.spec_from_file_location("koharu_validator_v32", VALIDATOR)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load Koharu validator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class KoharuMaskPayloadContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.validator = load_validator()
        cls.bubbles = read_json(VALID_FIXTURE / "1.bubbles.json")
        cls.segment = read_json(VALID_FIXTURE / "1.segment_mask.json")

    def test_v1_remains_accepted_without_a_ready_payload_gate(self) -> None:
        report = self.validator.validate(
            ROOT / "md/人工空间/koharu研究/artifact_contract/examples/valid",
            False,
            ROOT / "test/1.png",
        )
        self.assertTrue(report["validationPassed"])
        self.assertEqual(report["schemaVersion"], self.validator.LEGACY_SCHEMA_VERSION)
        self.assertFalse(report["maskPayloadGateReady"])
        self.assertEqual(
            report["maskPayloadValidation"],
            {
                "required": False,
                "ready": False,
                "legacySummaryOnlyAccepted": True,
                "bubbleMask": None,
                "segmentMask": None,
            },
        )

    def test_valid_v2_payload_recomputes_bubble_and_segment_statistics(self) -> None:
        report = self.validator.validate(VALID_FIXTURE, False, ROOT / "test/1.png")
        self.assertEqual(report["verdict"], "contractExampleOnly")
        self.assertTrue(report["validationPassed"])
        self.assertEqual(report["payloadErrors"], [])
        self.assertTrue(report["maskPayloadGateReady"])
        payload = report["maskPayloadValidation"]
        self.assertTrue(payload["required"])
        self.assertTrue(payload["ready"])
        self.assertEqual(payload["bubbleMask"]["decodedPixelCount"], 576 * 1280)
        self.assertEqual(payload["segmentMask"]["glyphPixelCount"], 3)
        self.assertEqual(payload["segmentMask"]["connectedComponentCount"], 2)

    def test_mismatched_declared_statistics_block_v2(self) -> None:
        result = subprocess.run(
            ["python3", "-B", str(VALIDATOR), "--root", str(INVALID_FIXTURE), "--expect-fail"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        report = json.loads(result.stdout)
        self.assertEqual(report["verdict"], "maskPayloadValidationFailed")
        self.assertEqual(
            report["payloadErrors"],
            [
                "bubbleMask:v2-bubble-1:bboxMismatch",
                "bubbleMask:v2-bubble-1:pixelCountMismatch:5:4",
                "segmentMask:glyphPixelCountMismatch:4:3",
                "segmentMask:connectedComponentCountMismatch:1:2",
            ],
        )
        self.assertFalse(report["maskPayloadValidation"]["ready"])
        self.assertFalse(report["maskPayloadGateReady"])

    def test_decode_is_bounded_and_requires_exact_pixel_total(self) -> None:
        oversized = copy.deepcopy(self.segment)
        oversized["runs"] = [[0, 576 * 1280 + 1]]
        errors: list[str] = []
        result = self.validator.validate_segment_mask_payload(oversized, 576, 1280, errors)
        self.assertIsNone(result["decodedPixelCount"])
        self.assertEqual(errors, ["segmentMask:decodedPixelLimitExceeded:0"])

        short = copy.deepcopy(self.segment)
        short["runs"][-1][1] -= 1
        errors = []
        self.validator.validate_segment_mask_payload(short, 576, 1280, errors)
        self.assertEqual(errors, ["segmentMask:decodedPixelCountMismatch:737279:737280"])

    def test_bubble_labels_match_unique_nonzero_instance_values(self) -> None:
        duplicate = copy.deepcopy(self.bubbles)
        duplicate["bubbleInstances"].append(
            {"id": "duplicate", "bbox": [1, 1, 2, 2], "maskValue": 7, "pixelCount": 4}
        )
        errors: list[str] = []
        self.validator.validate_bubble_mask_payload(
            duplicate,
            duplicate["bubbleInstances"],
            576,
            1280,
            errors,
        )
        self.assertIn("bubbleMask:duplicate:maskValueDuplicate:7", errors)

        unknown_label = copy.deepcopy(self.bubbles)
        unknown_label["runs"][1][0] = 8
        errors = []
        self.validator.validate_bubble_mask_payload(
            unknown_label,
            unknown_label["bubbleInstances"],
            576,
            1280,
            errors,
        )
        self.assertIn("bubbleMask:runLabelInvalid:1:8", errors)

    def test_swift_evaluator_compiles_and_runs_with_warnings_as_errors(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v32-mask-") as temporary_directory:
            executable = Path(temporary_directory) / "mask-payload-evaluator"
            module_cache = Path(temporary_directory) / "module-cache"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-warnings-as-errors",
                    "-module-cache-path",
                    str(module_cache),
                    "AITRANS/Models/KoharuMaskPayloadEvaluator.swift",
                    "scripts/test-v32-koharu-mask-payload-evaluator.swift",
                    "-o",
                    str(executable),
                ],
                cwd=ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                [str(executable)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("Koharu mask payload evaluator contract passed", result.stdout)

    def test_app_report_store_project_and_ci_are_wired(self) -> None:
        models = (ROOT / "AITRANS/Models/TranscriptModels.swift").read_text(encoding="utf-8")
        store = (ROOT / "AITRANS/Services/TranslationSessionStore.swift").read_text(encoding="utf-8")
        project = (ROOT / "AITRANS.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/ci-results.yml").read_text(encoding="utf-8")
        for field in [
            "bubbleMajorityMaskValue",
            "bubblePixelCoverageRatio",
            "segmentPixelCoverageRatio",
            "textBoxSegmentContainmentRatio",
            "bubbleMaskPayloadVerdict",
            "segmentMaskPayloadVerdict",
            "maskPayloadGateReady",
        ]:
            self.assertIn(f"var {field}:", models)
        for needle in [
            "KoharuMaskPayloadEvaluator.evaluateBubble(",
            "KoharuMaskPayloadEvaluator.evaluateSegment(",
            'bubbleMaskPayloadVerdict = "validated"',
            'segmentMaskPayloadVerdict = "validated"',
            "let maskPayloadGateReady = maskPayloadRequired",
            'readinessVerdict == "readyForShadowOCR"',
            'workItem("WI-external-mask-pixel-payload"',
            'gate("G-external-mask-pixel-payload"',
            "pixel payload statistics do not change OCR, translation, rendering, blockPassed, or currentBlockSource",
        ]:
            self.assertIn(needle, store)
        self.assertIn("KoharuMaskPayloadEvaluator.swift in Sources", project)
        for needle in [
            "scripts/test-v32-koharu-mask-payload-contract.py",
            "valid_v2_mask_payload",
            "v2_mask_payload_mismatch",
            'data.get("maskPayloadGateReady") is not True',
            '"koharuArtifactValidationMaskPayloadGateReady"',
            '"maskPayloadGateReady": (external_readiness or {}).get("maskPayloadGateReady")',
            'convergence_item_summary("workItem", "WI-external-mask-pixel-payload")',
            'convergence_item_summary("gate", "G-external-mask-pixel-payload")',
        ]:
            self.assertIn(needle, workflow)
        probe = (ROOT / "AITRANS/Services/MangaOverlayProbeService.swift").read_text(encoding="utf-8")
        for needle in [
            "externalMaskPixelPayload: bubbleVerdict=",
            "convergenceExternalMaskPixelPayload=",
            "bubbleMajorityMaskValue=",
            "textBoxSegmentContainment=",
        ]:
            self.assertIn(needle, probe)


if __name__ == "__main__":
    unittest.main(verbosity=2)

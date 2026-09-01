#!/usr/bin/env python3
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VALID = ROOT / "md/人工空间/koharu研究/artifact_contract/examples/valid_v2_mask_topology"
INVALID = ROOT / "md/人工空间/koharu研究/artifact_contract/examples/invalid/v2_mask_topology_cross_assignment"
LEGACY = ROOT / "md/人工空间/koharu研究/artifact_contract/examples/valid"


def validate(path: Path) -> dict:
    completed = subprocess.run(
        [
            "python3",
            "-B",
            str(ROOT / "scripts/validate-koharu-artifacts.py"),
            "--root",
            str(path),
            "--image",
            str(ROOT / "test/1.png"),
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(completed.stdout)


class KoharuMaskTopologyContractTests(unittest.TestCase):
    def test_valid_topology_partitions_every_component_once(self) -> None:
        report = validate(VALID)
        topology = report["maskTopologyValidation"]
        self.assertTrue(report["maskPayloadGateReady"])
        self.assertTrue(report["maskTopologyGateReady"])
        self.assertTrue(topology["ready"])
        self.assertEqual(topology["errors"], [])
        self.assertEqual(topology["summary"]["topologyVerdict"], "complete")
        self.assertTrue(topology["summary"]["partitionConserved"])
        self.assertEqual(topology["summary"]["duplicateAssignedComponentIDs"], [])
        self.assertEqual(topology["summary"]["unassignedComponentIDs"], [])

    def test_valid_textboxes_have_unique_bubble_ownership(self) -> None:
        ledgers = validate(VALID)["maskTopologyValidation"]["summary"]["textBoxLedgers"]
        self.assertEqual([ledger["expectedBubbleMaskValue"] for ledger in ledgers], [7, 9])
        self.assertEqual([ledger["segmentPixelCount"] for ledger in ledgers], [2, 2])
        self.assertTrue(all(ledger["foreignBubbleSegmentPixels"] == 0 for ledger in ledgers))
        self.assertTrue(all(ledger["orphanSegmentPixels"] == 0 for ledger in ledgers))
        self.assertTrue(all(ledger["topologyVerdict"] == "complete" for ledger in ledgers))

    def test_cross_bubble_textbox_is_rejected_without_breaking_payload_gate(self) -> None:
        report = validate(INVALID)
        topology = report["maskTopologyValidation"]
        self.assertTrue(report["maskPayloadGateReady"])
        self.assertFalse(report["maskTopologyGateReady"])
        self.assertFalse(topology["ready"])
        self.assertIn("maskTopology:topology-textbox-cross:expectedBubbleAmbiguous", topology["errors"])
        self.assertIn("maskTopology:topology-textbox-cross:foreignBubbleSegmentPixels", topology["errors"])
        self.assertIn("maskTopology:duplicateComponentAssignment", topology["errors"])
        self.assertEqual(topology["summary"]["duplicateAssignedComponentIDs"], [1, 3])

    def test_legacy_summary_only_artifact_cannot_close_topology_gate(self) -> None:
        report = validate(LEGACY)
        self.assertFalse(report["maskTopologyGateReady"])
        self.assertFalse(report["maskTopologyValidation"]["required"])
        self.assertFalse(report["maskTopologyValidation"]["ready"])

    def test_topology_fields_remain_separate_from_payload_errors(self) -> None:
        report = validate(INVALID)
        self.assertEqual(report["payloadErrors"], [])
        self.assertNotEqual(report["maskTopologyValidation"]["errors"], [])
        self.assertEqual(report["maskTopologyValidation"]["summary"]["topologyVerdict"], "blocked")

    def test_app_reuses_shadow_ocr_assignment_and_keeps_topology_shadow_only(self) -> None:
        store = (ROOT / "AITRANS/Services/TranslationSessionStore.swift").read_text(encoding="utf-8")
        models = (ROOT / "AITRANS/Models/TranscriptModels.swift").read_text(encoding="utf-8")
        probe = (ROOT / "AITRANS/Services/MangaOverlayProbeService.swift").read_text(encoding="utf-8")
        for token in [
            "let stableMatching = Self.stableOneToOneExternalTextBoxShadowMatching(",
            "matching: stableMatching",
            "KoharuMaskPayloadEvaluator.evaluateTopology(",
            'assignmentSource: "stableOneToOneExternalTextBoxShadowMatching"',
            '"WI-external-mask-topology-linkage"',
            '"G-external-mask-topology-linkage"',
            '"topology evidence does not change OCR, translation, rendering, blockPassed, or currentBlockSource"',
        ]:
            self.assertIn(token, store)
        for token in [
            "MangaOverlayExternalMaskTopologyReport",
            "duplicateAssignedTextBoxIDs",
            "foreignBubbleSegmentPixels",
            "orphanSegmentPixels",
            "crossBubbleComponentIndexes",
            "partitionConserved",
        ]:
            self.assertIn(token, models)
        self.assertIn("externalMaskTopology: gateReady=", probe)
        self.assertIn("convergenceExternalMaskTopologyLinkage=", probe)

    def test_ci_routes_and_hard_gates_topology_evidence(self) -> None:
        workflow = (ROOT / ".github/workflows/ci-results.yml").read_text(encoding="utf-8")
        for token in [
            "test-v33-koharu-mask-topology-contract.py",
            "3-koharu-mask-topology)-evaluator\\.swift",
            'data.get("maskTopologyGateReady") is not True',
            '"maskTopologyGateReady": True',
            '"WI-external-mask-topology-linkage"',
            '"G-external-mask-topology-linkage"',
            "koharuArtifactValidationMaskTopologySummary",
            "externalMaskTopologyGate",
        ]:
            self.assertIn(token, workflow)

    def test_swift_topology_evaluator_compiles_with_warnings_as_errors(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v33-topology-") as temporary_directory:
            executable = Path(temporary_directory) / "mask-topology-evaluator"
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
                    "scripts/test-v33-koharu-mask-topology-evaluator.swift",
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
            self.assertIn("v3.3 Koharu mask topology evaluator contract passed", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Contracts for v2.1 trusted geometry coverage and Bubble identity."""

from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = "scripts/validate-koharu-artifacts.py"


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class KoharuGeometryCoverageContractTests(unittest.TestCase):
    def test_swift_geometry_evaluator_and_legacy_decode(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v201-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v201-geometry-coverage-contract"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            try:
                subprocess.run(
                    [
                        "xcrun", "--sdk", "macosx", "swiftc",
                        "-parse-as-library",
                        "-module-cache-path", str(Path(temporary_directory) / "module-cache"),
                        "AITRANS/Models/ImageOCRProvenance.swift",
                        "AITRANS/Services/ImageOCRLayoutEngine.swift",
                        "AITRANS/Models/TranslationContextQuality.swift",
                        "AITRANS/Models/TranscriptModels.swift",
                        "scripts/test-v201-koharu-geometry-coverage-evaluator.swift",
                        "-o", str(executable),
                    ],
                    cwd=ROOT,
                    env=environment,
                    check=True,
                    capture_output=True,
                    text=True,
                )
            except subprocess.CalledProcessError as error:
                self.fail(
                    "geometry coverage evaluator compilation failed:\n"
                    f"stdout={error.stdout}\nstderr={error.stderr}"
                )
            result = subprocess.run([str(executable)], cwd=ROOT, check=True, capture_output=True, text=True)
            self.assertIn("v2.1 Swift geometry coverage contract passed", result.stdout)

    def test_validator_rejects_missing_blank_non_string_and_duplicate_bubble_ids(self) -> None:
        result = subprocess.run(
            [
                "python3",
                "-B",
                VALIDATOR,
                "--root",
                "md/人工空间/koharu研究/artifact_contract/examples/invalid/bubble_identity_invalid",
                "--expect-fail",
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        report = json.loads(result.stdout)
        self.assertEqual(report["verdict"], "coordinateValidationFailed")
        self.assertEqual(
            [
                error
                for error in report["coordinateErrors"]
                if error.startswith(("bubbleIDMissing:", "duplicateBubbleID:"))
            ],
            [
                "bubbleIDMissing:1",
                "bubbleIDMissing:2",
                "bubbleIDMissing:3",
                "duplicateBubbleID:duplicate-bubble",
            ],
        )
        self.assertEqual(
            report["invalidBubbleInstanceIDs"],
            ["duplicate-bubble", "index-1", "index-2", "index-3"],
        )
        self.assertEqual(report["parseErrors"], [])

    def test_validator_and_swift_use_the_same_bubble_identity_reasons(self) -> None:
        validator = read(VALIDATOR)
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        models = read("AITRANS/Models/TranscriptModels.swift")
        for reason in ["bubbleIDMissing:", "duplicateBubbleID:"]:
            self.assertIn(reason, validator)
            self.assertIn(reason, store)
        self.assertIn(
            'id = (try? container.decode(String.self, forKey: .id)) ?? ""',
            models,
        )
        self.assertNotIn("UUID().uuidString", models)

    def test_validator_handoff_requires_geometry_evidence(self) -> None:
        validator = read(VALIDATOR)
        for field in [
            "minimumTrustedIoU",
            "geometryWeakBlockIndexes",
            "geometryUnknownBubbleBlockIndexes",
            "geometryCoverageRatio",
            "geometryCoverageVerdict",
        ]:
            self.assertIn(field, validator)
        self.assertIn(
            "externalTextBoxShadowOCRSummary.geometryCoverageVerdict == complete",
            validator,
        )

    def test_report_requires_trusted_geometry_for_complete_coverage(self) -> None:
        models = read("AITRANS/Models/TranscriptModels.swift")
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        for field in [
            "minimumTrustedIoU",
            "geometryTrustedBlockIndexes",
            "geometryWeakBlockIndexes",
            "geometryUnknownBubbleBlockIndexes",
            "geometryCoverageRatio",
            "geometryCoverageVerdict",
            "spatialGeometryVerdict",
            "bubbleAlignmentVerdict",
            "assignmentGeometryTrusted",
        ]:
            self.assertIn(field, models)
        self.assertIn("minimumTrustedIoU", store)
        self.assertIn("0.10", models)
        self.assertIn('bubbleAlignmentVerdict == "matched"', store)
        self.assertIn("assignmentGeometryTrusted", store)
        self.assertIn('geometryCoverageVerdict == "complete"', store)

    def test_ci_and_txt_expose_geometry_gate_evidence(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        probe = read("AITRANS/Services/MangaOverlayProbeService.swift")
        self.assertIn("scripts/test-v201-koharu-geometry-coverage-contract.py", workflow)
        self.assertIn(
            "md/人工空间/koharu研究/artifact_contract/examples/invalid/bubble_identity_invalid",
            workflow,
        )
        for field in [
            "geometryTrustedBlockIndexes",
            "geometryWeakBlockIndexes",
            "geometryUnknownBubbleBlockIndexes",
            "geometryCoverageRatio",
            "geometryCoverageVerdict",
        ]:
            self.assertIn(field, workflow)
            self.assertIn(field, probe)
        self.assertIn('external_shadow.get("geometryCoverageVerdict") != "complete"', workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)

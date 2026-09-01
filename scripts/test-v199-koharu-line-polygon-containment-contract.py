#!/usr/bin/env python3
"""Contracts for v1.99 line polygon ownership validation."""

from pathlib import Path
import importlib.util
import json
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR_PATH = ROOT / "scripts/validate-koharu-artifacts.py"


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def load_validator():
    spec = importlib.util.spec_from_file_location("koharu_validator_v199", VALIDATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("unable to load Koharu validator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class KoharuLinePolygonContainmentContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.validator = load_validator()

    def validate(self, polygon: list[list[float]]) -> list[str]:
        errors: list[str] = []
        valid = self.validator.validate_textbox_metadata(
            {"linePolygons": [polygon]},
            "fixture",
            (100.0, 100.0, 100.0, 50.0),
            576,
            1280,
            errors,
        )
        self.assertEqual(valid, not errors)
        return errors

    def test_accepts_points_inside_bbox_and_rounding_tolerance(self) -> None:
        self.assertEqual(
            self.validate([[98, 100], [200, 98], [202, 150], [100, 152]]),
            [],
        )

    def test_rejects_partial_and_fully_detached_polygons(self) -> None:
        partial = self.validate([[97, 100], [200, 100], [200, 150], [100, 150]])
        detached = self.validate([[300, 400], [380, 400], [380, 430], [300, 430]])
        self.assertIn(
            "textBox:fixture:linePolygonOutsideTextBoxBBox:0:0",
            partial,
        )
        self.assertEqual(
            len([error for error in detached if "linePolygonOutsideTextBoxBBox" in error]),
            4,
        )

    def test_invalid_fixture_reports_detached_polygon(self) -> None:
        result = subprocess.run(
            [
                "python3",
                "-B",
                str(VALIDATOR_PATH),
                "--root",
                "md/人工空间/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid",
                "--expect-fail",
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        report = json.loads(result.stdout)
        self.assertEqual(report["verdict"], "coordinateValidationFailed")
        self.assertIn("bad-textbox-line-polygon-detached", report["invalidTextBoxIDs"])
        self.assertTrue(
            any(
                error.startswith(
                    "textBox:bad-textbox-line-polygon-detached:linePolygonOutsideTextBoxBBox"
                )
                for error in report["coordinateErrors"]
            )
        )

    def test_swift_readiness_uses_the_same_tolerance_and_error(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.assertIn("max(2.0, min(bbox.width, bbox.height) * 0.02)", store)
        self.assertIn("let toleratedBBox = bbox.insetBy(dx: -bboxTolerance", store)
        self.assertIn('errors.append("linePolygonOutsideTextBoxBBox:', store)

    def test_ci_runs_this_contract_for_koharu_scope(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        self.assertIn(
            "python3 -B scripts/test-v199-koharu-line-polygon-containment-contract.py",
            workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

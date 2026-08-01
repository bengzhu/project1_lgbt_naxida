#!/usr/bin/env python3
"""Contracts for v3.66 image OCR geometry normalization and safety."""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def braced_body(source: str, marker: str) -> str:
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace : index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class ImageOCRGeometrySafetyContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_layout_has_a_single_finite_unit_space_boundary(self) -> None:
        rect_body = braced_body(self.layout, "func normalizedToUnit")
        for required in [
            "x.isFinite",
            "y.isFinite",
            "width.isFinite",
            "height.isFinite",
            "width > 0",
            "height > 0",
            "right.isFinite",
            "bottom.isFinite",
            "clippedRight > left",
            "clippedBottom > top",
        ]:
            self.assertIn(required, rect_body)

    def test_layout_filters_invalid_observations_before_direction_and_clustering(self) -> None:
        body = braced_body(self.layout, "static func layout(")
        self.assertIn("observations.compactMap", body)
        self.assertIn("guard let rect = observation.rect.normalizedToUnit() else { return nil }", body)
        self.assertIn("safeObservation.rect = rect", body)
        self.assertIn("among: safeObservations", body)

    def test_vision_normalizes_bounding_boxes_before_layout(self) -> None:
        body = braced_body(self.vision, "private static func normalizedRect")
        for required in [
            "rawBox.origin.x.isFinite",
            "rawBox.origin.y.isFinite",
            "rawBox.width.isFinite",
            "rawBox.height.isFinite",
            "rawBox.width > 0",
            "rawBox.height > 0",
            "return rect.normalizedToUnit()",
        ]:
            self.assertIn(required, body)
        self.assertIn("guard let rect = Self.normalizedRect(from: observation.boundingBox) else", self.vision)
        self.assertNotIn("clampNormalized", self.vision)

    def test_executable_geometry_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v366-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v366-image-ocr-geometry-safety"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-module-cache-path",
                    str(Path(temporary_directory) / "module-cache"),
                    "AITRANS/Services/ImageOCRLayoutEngine.swift",
                    "scripts/test-v366-image-ocr-geometry-safety-evaluator.swift",
                    "-o",
                    str(executable),
                ],
                cwd=ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run([str(executable)], cwd=ROOT, check=True, capture_output=True, text=True)
            self.assertIn("v3.66 image OCR geometry safety evaluator passed", result.stdout)

    def test_version_and_ci_route_follow_v365(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.65;", self.project)
        old = "python3 -B scripts/test-v365-image-confidence-display-contract.py"
        new = "python3 -B scripts/test-v366-image-ocr-geometry-safety-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74|75)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

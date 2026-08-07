#!/usr/bin/env python3
"""Contract for Koharu's explicit target geometry on Japanese line warps."""

from pathlib import Path
import re
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


class JapaneseLineWarpTargetContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.perspective = braced_body(
            self.vision,
            "private static func perspectiveCorrectedLineImage(",
        )
        self.perspective_reader = braced_body(
            self.vision,
            "private static func recognizeJapanesePerspectiveLineCrop(",
        )
        self.target = braced_body(
            self.vision,
            "private static func koharuVerticalLineWarpTargetSize(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_target_geometry_mirrors_koharu_quad_axis_lengths(self) -> None:
        for marker in [
            "let top = midpoint(points[0], points[1])",
            "let right = midpoint(points[1], points[2])",
            "let bottom = midpoint(points[2], points[3])",
            "let left = midpoint(points[3], points[0])",
            "let verticalLength = distance(top, bottom)",
            "let horizontalLength = distance(left, right)",
            "let textHeight = max(horizontalLength.rounded(), 1)",
            "let ratio = verticalLength / horizontalLength",
            "let rawWidth = textHeight",
            "let rawHeight = max((textHeight * ratio).rounded(), 1)",
            "return CGSize(width: width, height: height)",
        ]:
            self.assertIn(marker, self.target)

    def test_projection_uses_bounded_target_canvas_with_natural_fallback(self) -> None:
        for marker in [
            "guard let rendered = context.createCGImage(output, from: outputExtent)",
            "koharuVerticalLineWarpTargetSize(",
            "maximumDimension: 4_096",
            "maximumPixels: 4_000_000",
            "let targetWidth = Int(targetSize.width.rounded())",
            "let targetHeight = Int(targetSize.height.rounded())",
            "resizedImage(",
            "pixelWidth: targetWidth",
            "pixelHeight: targetHeight",
            "return rendered",
        ]:
            self.assertIn(marker, self.perspective)
        self.assertLess(
            self.perspective.index("context.createCGImage(output, from: outputExtent)"),
            self.perspective.index("koharuVerticalLineWarpTargetSize("),
        )
        self.assertLess(
            self.perspective.index("koharuVerticalLineWarpTargetSize("),
            self.perspective.index("resizedImage("),
        )

    def test_line_budget_and_scope_remain_safe(self) -> None:
        line_path = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        for marker in [
            "let perspectiveCandidates = Array(uniqueCandidates.prefix(24))",
            "consumedPixels: &perspectiveWarpPixels",
            "prepareJapaneseCropForVision(warped)",
            "consumedPixels + preparedPixels <= 16_000_000",
        ]:
            self.assertIn(marker, line_path + self.perspective_reader)
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3182(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 183) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.182;", self.project)
        old = "python3 -B scripts/test-v3182-image-japanese-synthetic-line-replacement-contract.py"
        new = "python3 -B scripts/test-v3183-image-japanese-line-warp-target-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

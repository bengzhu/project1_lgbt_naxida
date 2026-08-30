#!/usr/bin/env python3
"""Contract for Koharu-style local bbox cropping before Japanese line warp."""

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


class JapaneseLineWarpBBoxContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.lines = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        self.perspective = braced_body(
            self.vision,
            "private static func recognizeJapanesePerspectiveLineCrop(",
        )
        self.warp = braced_body(
            self.vision,
            "private static func perspectiveCorrectedLineImage(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_perspective_candidates_keep_bounded_koharu_line_path(self) -> None:
        for marker in [
            "let perspectiveCandidates = Array(",
            "recognizeJapanesePerspectiveLineCrop(",
            "consumedPixels: &perspectiveWarpPixels",
            "prepareJapaneseCropForVision(warped)",
            "consumedPixels + preparedPixels <= 16_000_000",
        ]:
            self.assertIn(marker, self.lines + self.perspective)

    def test_warp_crops_source_bbox_before_projection(self) -> None:
        for marker in [
            "let imageBounds = CGRect(x: 0, y: 0, width: width, height: height)",
            "let cropBounds = bounds.intersection(imageBounds)",
            "let croppedImage = image.cropping(to: cropBounds)",
            "let localPoints = points.map",
            "x: $0.x - cropBounds.minX",
            "y: $0.y - cropBounds.minY",
            "let croppedHeight = CGFloat(croppedImage.height)",
            "CIImage(cgImage: croppedImage)",
            'forKey: "inputTopLeft"',
            'forKey: "inputBottomRight"',
            "CIPerspectiveCorrection",
        ]:
            self.assertIn(marker, self.warp)
        self.assertLess(
            self.warp.index("image.cropping(to: cropBounds)"),
            self.warp.index("CIImage(cgImage: croppedImage)"),
        )
        self.assertLess(
            self.warp.index("let localPoints = points.map"),
            self.warp.index('forKey: "inputTopLeft"'),
        )

    def test_warp_and_scope_retain_safe_fallbacks(self) -> None:
        for marker in [
            "guard cropBounds.width >= 2",
            "cropBounds.width <= 4096",
            "guard let output = filter?.outputImage else { return nil }",
            "context.createCGImage(output, from: outputExtent)",
        ]:
            self.assertIn(marker, self.warp)
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

    def test_version_and_ci_route_follow_v3179(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 180) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.179;", self.project)
        old = "python3 -B scripts/test-v3179-image-japanese-koharu-postprocess-order-contract.py"
        new = "python3 -B scripts/test-v3180-image-japanese-line-warp-bbox-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)

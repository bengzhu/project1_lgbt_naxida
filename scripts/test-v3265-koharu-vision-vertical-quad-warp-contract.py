#!/usr/bin/env python3
"""Contract for sharing Koharu's direct vertical quad sampler with Vision OCR."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


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
    raise AssertionError(f"unterminated body for {marker}")


class KoharuVisionVerticalQuadWarpContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.manga = read("AITRANS/Services/MangaOCRService.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.perspective = braced_body(
            cls.vision,
            "private static func perspectiveCorrectedLineImage(",
        )
        cls.perspective_reader = braced_body(
            cls.vision,
            "private static func recognizeJapanesePerspectiveLineCrop(",
        )

    def test_vision_line_crop_uses_shared_direct_sampler_first(self) -> None:
        direct = "MangaOCRService.koharuVerticalQuadWarp("
        target = "MangaOCRService.koharuVerticalQuadWarpTargetSize("
        ci = 'CIFilter(name: "CIPerspectiveCorrection")'
        self.assertIn(target, self.perspective)
        self.assertIn(direct, self.perspective)
        self.assertIn("sourcePoints: localPoints", self.perspective)
        self.assertIn("let rotated = try? rotatedImage(bounded, angle: 270)", self.perspective)
        self.assertLess(self.perspective.index(target), self.perspective.index(ci))
        self.assertLess(self.perspective.index(direct), self.perspective.index(ci))
        self.assertIn("return rotated", self.perspective)

    def test_natural_projection_remains_only_compatibility_fallback(self) -> None:
        ci = 'CIFilter(name: "CIPerspectiveCorrection")'
        for marker in [
            ci,
            "guard let rendered = context.createCGImage(output, from: outputExtent)",
            "return rendered",
            "resizedImage(",
            "pixelWidth: targetWidth",
        ]:
            self.assertIn(marker, self.perspective)
        self.assertLess(
            self.perspective.index("return rotated"),
            self.perspective.index(ci),
        )
        self.assertIn("compatibility", self.perspective)
        self.assertNotIn("MangaOCRService.diagnosticKoharuVerticalQuadWarp", self.perspective)

    def test_shared_sampler_is_internal_and_keeps_pixel_contract(self) -> None:
        target = braced_body(
            self.manga,
            "static func koharuVerticalQuadWarpTargetSize(",
        )
        warp = braced_body(self.manga, "static func koharuVerticalQuadWarp(")
        self.assertNotIn("private static func koharuVerticalQuadWarp(", self.manga)
        for marker in [
            "let verticalLength = distance(top, bottom)",
            "let horizontalLength = distance(left, right)",
            "let textHeight = max(horizontalLength.rounded(), 1)",
            "sqrt(maximumPixels / (rawWidth * rawHeight))",
            "width * height <= maximumPixels + 1",
        ]:
            self.assertIn(marker, target)
        for marker in [
            "projectiveMapping(",
            "bilinearRGBSample(",
            "let left = Int(floor(x))",
            "sourceX >= 0",
            "sourceY >= 0",
            "return 0",
            "output[targetOffset + 3] = 255",
        ]:
            self.assertIn(marker, warp + self.manga)

    def test_line_budget_and_ownership_boundaries_remain_unchanged(self) -> None:
        line_path = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        for marker in [
            "let perspectiveCandidates = Array(",
            "consumedPixels: &perspectiveWarpPixels",
            "prepareJapaneseCropForVision(warped)",
            "consumedPixels + preparedPixels <= 16_000_000",
        ]:
            self.assertIn(marker, line_path + self.perspective_reader + self.perspective)
        for forbidden in [
            "detectorConfidence = candidate.confidence",
            "TranslationSessionStore",
            "test/koharu_artifacts",
            "groundTruth",
        ]:
            self.assertNotIn(forbidden, self.perspective + line_path)

    def test_checksum_runtime_route_and_version(self) -> None:
        contract = "scripts/test-v3265-koharu-vision-vertical-quad-warp-contract.py"
        runtime = "scripts/test-v3265-koharu-vision-vertical-quad-warp-runtime.sh"
        for path in [contract, runtime]:
            self.assertIn(f"# if grep -Fx '{path}'", self.workflow)
            self.assertIn(f"if grep -Fx '{path}'", self.workflow)
        self.assertIn(f"python3 -B {contract}", self.workflow)
        self.assertIn(f"bash {runtime}", self.workflow)
        previous = "bash scripts/test-v3264-koharu-vertical-quad-warp-runtime.sh"
        current = f"bash {runtime}"
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertTrue((ROOT / "test/jap.jpg").is_file())
        versions = re.findall(r"MARKETING_VERSION = ([^;]+);", self.project)
        self.assertEqual(versions, ["3.371", "3.371"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

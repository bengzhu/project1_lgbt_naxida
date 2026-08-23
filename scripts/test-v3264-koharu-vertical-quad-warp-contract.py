#!/usr/bin/env python3
"""Contract for Koharu's direct bilinear vertical line-quad warp."""

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


class KoharuVerticalQuadWarpContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.service = read("AITRANS/Services/MangaOCRService.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.harness = read(
            "scripts/fixtures/v3264-koharu-vertical-quad-warp-harness.swift"
        )
        cls.runtime = read(
            "scripts/test-v3264-koharu-vertical-quad-warp-runtime.sh"
        )

    def test_bbox_primary_and_direct_vertical_fallback_boundary(self) -> None:
        crop_images = braced_body(self.service, "private static func cropImages(")
        for marker in [
            "let boundingBoxCrop = cropImage(image, normalizedRect: request.cropRect)",
            "let perspectiveCrop = request.cropQuad.flatMap",
            "primaryBoundingBoxCrop: boundingBoxCrop",
            "lineQuadFallbackCrop: perspectiveCrop",
            "Self.shouldRetryLineQuad(after: primaryRecognitions[index])",
        ]:
            self.assertIn(marker, crop_images + self.service)
        perspective = braced_body(
            self.service, "private static func perspectiveCorrectedCrop("
        )
        self.assertIn("if applyVerticalWarp,", perspective)
        self.assertIn("let rotated = rotateImage270(bounded)", perspective)
        self.assertIn("koharuVerticalQuadWarp(", perspective)
        self.assertIn("sourcePoints: localPoints", perspective)
        self.assertLess(
            perspective.index("koharuVerticalQuadWarp("),
            perspective.index('CIFilter(name: "CIPerspectiveCorrection")'),
        )
        self.assertNotIn("interpolationQuality = .high", perspective)
        self.assertNotIn("resizedImage(", perspective)

    def test_target_canvas_and_projection_use_koharu_pixel_geometry(self) -> None:
        target = braced_body(
            self.service, "static func koharuVerticalQuadWarpTargetSize("
        )
        for marker in [
            "let verticalLength = distance(top, bottom)",
            "let horizontalLength = distance(left, right)",
            "let textHeight = max(horizontalLength.rounded(), 1)",
            "let ratio = verticalLength / horizontalLength",
            "sqrt(maximumPixels / (rawWidth * rawHeight))",
            "width * height <= maximumPixels + 1",
        ]:
            self.assertIn(marker, target)
        warp = braced_body(self.service, "static func koharuVerticalQuadWarp(")
        for marker in [
            "CGPoint(x: 0, y: 0)",
            "CGFloat(targetWidth - 1)",
            "CGFloat(targetHeight - 1)",
            "projectiveMapping(",
            "bilinearRGBSample(",
            "CGFloat(targetWidth) * CGFloat(targetHeight) <= maximumQuadWarpPixels",
        ]:
            self.assertIn(marker, warp)

    def test_bilinear_sampler_matches_imageproc_boundary_semantics(self) -> None:
        sampler = braced_body(self.service, "private static func bilinearRGBSample(")
        for marker in [
            "let left = Int(floor(x))",
            "let top = Int(floor(y))",
            "let rightWeight = Float(x - CGFloat(left))",
            "let bottomWeight = Float(y - CGFloat(top))",
            "sourceX >= 0",
            "sourceX < width",
            "sourceY >= 0",
            "sourceY < height",
            "return 0",
            "UInt8(min(max(result, 0), 255))",
        ]:
            self.assertIn(marker, sampler)
        self.assertIn("private struct ProjectiveMapping", self.service)
        self.assertIn("coefficients[6] * x", self.service)

    def test_source_and_output_channels_are_explicit(self) -> None:
        canonical = braced_body(self.service, "private static func canonicalRGBBytes(")
        for marker in [
            "CGColorSpaceCreateDeviceRGB()",
            "context.interpolationQuality = .none",
            "CGBitmapInfo.byteOrder32Little.rawValue",
            "rgb[targetOffset] = source[sourceOffset + 2]",
            "rgb[targetOffset + 1] = source[sourceOffset + 1]",
            "rgb[targetOffset + 2] = source[sourceOffset]",
        ]:
            self.assertIn(marker, canonical)
        self.assertIn("output[targetOffset + 3] = 255", self.service)
        self.assertIn("diagnosticKoharuVerticalQuadWarp", self.service)

    def test_runtime_contract_and_ci_route(self) -> None:
        contract = "scripts/test-v3264-koharu-vertical-quad-warp-contract.py"
        runtime = "scripts/test-v3264-koharu-vertical-quad-warp-runtime.sh"
        for path in [contract, runtime]:
            self.assertIn(f"# if grep -Fx '{path}'", self.workflow)
            self.assertIn(f"if grep -Fx '{path}'", self.workflow)
        self.assertIn(f"python3 -B {contract}", self.workflow)
        self.assertIn(f"bash {runtime}", self.workflow)
        self.assertIn("v3264-koharu-vertical-quad-warp-harness.swift", self.runtime)
        self.assertIn("AITRANS/Models/ImageOCRProvenance.swift", self.runtime)
        self.assertNotIn("AITRANS/Services/ImageOCRLayoutEngine.swift", self.runtime)
        self.assertIn(
            "struct ImageOCRLayoutRect: Equatable, Codable, Sendable",
            self.harness,
        )
        self.assertLess(
            self.runtime.index("AITRANS/Models/ImageOCRProvenance.swift"),
            self.runtime.index("AITRANS/Services/MangaOCRService.swift"),
        )
        self.assertIn("projective+bilinear", self.runtime)

    def test_version_is_3264(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = ([^;]+);", self.project)
        self.assertEqual(versions, ["3.324", "3.324"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

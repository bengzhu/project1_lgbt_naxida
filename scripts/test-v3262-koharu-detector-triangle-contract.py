#!/usr/bin/env python3
"""Contract for Koharu RT-DETR Triangle detector preprocessing parity."""

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


class KoharuDetectorTriangleContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.detector = read("AITRANS/Services/ComicTextBubbleDetectorService.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.harness = read(
            "scripts/fixtures/v3262-koharu-detector-triangle-harness.swift"
        )
        cls.runtime = read(
            "scripts/test-v3262-koharu-detector-triangle-runtime.sh"
        )

    def test_detector_uses_koharu_triangle_not_core_graphics_high(self) -> None:
        make_buffer = braced_body(self.detector, "private static func makePixelBuffer")
        self.assertIn("makeKoharuTriangleRGB(image)", make_buffer)
        self.assertNotIn("interpolationQuality = .high", make_buffer)
        helper = braced_body(
            self.detector,
            "private static func makeKoharuTriangleRGB(_ image: CGImage)",
        )
        for marker in [
            "CGColorSpaceCreateDeviceRGB()",
            "context.interpolationQuality = .none",
            "return triangleResize(",
            "targetWidth: imageSize",
            "targetHeight: imageSize",
        ]:
            self.assertIn(marker, helper)

    def test_triangle_kernel_matches_image_rs_sampling_boundaries(self) -> None:
        resize = braced_body(self.detector, "private static func triangleResize(")
        for marker in [
            "let inputY = (Float(outputY) + 0.5) * verticalRatio",
            "let inputX = (Float(outputX) + 0.5) * horizontalRatio",
            "let verticalScale = max(verticalRatio, 1)",
            "let horizontalScale = max(horizontalRatio, 1)",
            "Int(floor(inputY - verticalSupport))",
            "Int(ceil(inputY + verticalSupport))",
            "Int(floor(inputX - horizontalSupport))",
            "Int(ceil(inputX + horizontalSupport))",
            "let kernelOrigin = inputY - 0.5",
            "let kernelOrigin = inputX - 0.5",
            "let value = abs(distance) < 1 ? 1 - abs(distance) : 0",
            "sum += Float(source[sourceOffset]) * weight.value / weightSum",
            "let rounded = sum.rounded()",
        ]:
            self.assertIn(marker, resize)

    def test_rgb_channel_order_and_alpha_are_explicit(self) -> None:
        self.assertIn("targetRow[targetOffset] = resizedRGB[sourceOffset + 2]", self.detector)
        self.assertIn("targetRow[targetOffset + 1] = resizedRGB[sourceOffset + 1]", self.detector)
        self.assertIn("targetRow[targetOffset + 2] = resizedRGB[sourceOffset]", self.detector)
        self.assertIn("targetRow[targetOffset + 3] = 255", self.detector)
        self.assertIn("diagnosticKoharuTriangleRGB", self.harness)

    def test_runtime_is_sample_specific_and_ci_routed(self) -> None:
        contract = "scripts/test-v3262-koharu-detector-triangle-contract.py"
        runtime = "scripts/test-v3262-koharu-detector-triangle-runtime.sh"
        for path in [contract, runtime]:
            self.assertIn(f"# if grep -Fx '{path}'", self.workflow)
            self.assertIn(f"if grep -Fx '{path}'", self.workflow)
        self.assertIn(f"python3 -B {contract}", self.workflow)
        self.assertIn(f"bash {runtime}", self.workflow)
        self.assertIn("test/jap.jpg", self.runtime)
        self.assertIn("detectorRegions=", self.runtime)
        self.assertNotIn("general Japanese OCR quality", self.runtime)

    def test_version_is_3262(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = ([^;]+);", self.project)
        self.assertEqual(versions, ["3.319", "3.319"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

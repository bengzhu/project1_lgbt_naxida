#!/usr/bin/env python3
"""Contract for Koharu Manga OCR RGB-to-luma floor parity."""

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


class KoharuMangaOCRRGBLumaContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manga = read("AITRANS/Services/MangaOCRService.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def test_manga_ocr_uses_explicit_image_rs_luma_floor(self) -> None:
        helper = braced_body(
            self.manga,
            "private static func makeKoharuNearestGrayscale(_ image: CGImage)",
        )
        for marker in [
            "CGColorSpaceCreateDeviceRGB()",
            "let blue = Int(source[sourceOffset])",
            "let green = Int(source[sourceOffset + 1])",
            "let red = Int(source[sourceOffset + 2])",
            "2126 * red + 7152 * green + 722 * blue",
            "/ 10_000",
            "let scaleX = Double(image.width) / Double(imageSize)",
            "let scaleY = Double(image.height) / Double(imageSize)",
        ]:
            self.assertIn(marker, helper)
        self.assertNotIn("CGColorSpaceCreateDeviceGray()", helper)

    def test_nearest_sampling_remains_after_luma_conversion(self) -> None:
        helper = braced_body(
            self.manga,
            "private static func makeKoharuNearestGrayscale(_ image: CGImage)",
        )
        self.assertLess(
            helper.index("source[sourceOffset] = UInt8"),
            helper.index("let scaleX"),
        )
        self.assertIn(
            "resized[targetRow + targetX] = source[(sourceRow + sourceX) * 4]",
            helper,
        )
        self.assertIn("context.interpolationQuality = .none", helper)

    def test_ci_routes_contract_and_runtime(self) -> None:
        contract = "scripts/test-v3260-koharu-manga-ocr-rgb-luma-contract.py"
        runtime = "scripts/test-v3260-koharu-manga-ocr-rgb-luma-runtime.sh"
        for path in [contract, runtime]:
            self.assertIn(f"# if grep -Fx '{path}'", self.workflow)
            self.assertIn(f"if grep -Fx '{path}'", self.workflow)
        self.assertIn(f"python3 -B {contract}", self.workflow)
        self.assertIn(f"bash {runtime}", self.workflow)

    def test_project_version_is_3260(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = ([^;]+);", self.project)
        self.assertEqual(versions, ["3.377", "3.377"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

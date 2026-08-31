#!/usr/bin/env python3
"""Static contract for the Vision Japanese vertical line single-rotation boundary."""

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


class JapaneseLineSingleRotationContractTests(unittest.TestCase):
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
        cls.line_path = braced_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        cls.manga_perspective = braced_body(
            cls.manga,
            "private static func perspectiveCorrectedCrop(",
        )
        cls.orientation = braced_body(
            cls.vision,
            "private static func koharuPreferredJapaneseVerticalLineOrientation(",
        )
        cls.docs = [
            read("README.md"),
            read("md/flow/flow.md"),
            read("md/flow/flowchart.md"),
            read("md/test/test.md"),
            read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"),
            read("update_log.md"),
        ]

    def test_direct_warp_is_unrotated_and_reader_rotates_once(self) -> None:
        target = "MangaOCRService.koharuVerticalQuadWarpTargetSize("
        direct = "MangaOCRService.koharuVerticalQuadWarp("
        ci = 'CIFilter(name: "CIPerspectiveCorrection")'
        self.assertIn(target, self.perspective)
        self.assertIn(direct, self.perspective)
        self.assertIn("sourcePoints: localPoints", self.perspective)
        self.assertIn("return bounded", self.perspective)
        self.assertLess(self.perspective.index(target), self.perspective.index(ci))
        self.assertLess(self.perspective.index(direct), self.perspective.index(ci))
        self.assertNotIn(
            "let rotated = try? rotatedImage(bounded, angle: 270)",
            self.perspective,
        )
        self.assertNotIn("return rotated", self.perspective)

        rotation = "guard let rotated = try? rotatedImage(preparedCrop.image, angle: angle)"
        self.assertIn(rotation, self.perspective_reader)
        self.assertEqual(self.perspective_reader.count("rotatedImage("), 1)
        self.assertIn("rotationApplied: angle", self.perspective_reader)

    def test_core_image_fallback_keeps_the_same_unrotated_boundary(self) -> None:
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
            self.perspective.index("return bounded"),
            self.perspective.index(ci),
        )
        self.assertNotIn("rotateImage270", self.perspective)
        self.assertIn("compatibility fallback", self.perspective)

    def test_manga_detector_quad_path_retains_its_single_rotate270(self) -> None:
        self.assertIn(
            "let rotated = rotateImage270(bounded)",
            self.manga_perspective,
        )
        self.assertIn("return rotated", self.manga_perspective)

    def test_line_budget_quality_and_orientation_boundaries_remain(self) -> None:
        combined = self.line_path + self.perspective_reader
        for marker in [
            "let angle = koharuPreferredJapaneseVerticalLineOrientation()",
            "consumedPixels: &perspectiveWarpPixels",
            "consumedPixels + preparedPixels <= 16_000_000",
            "observationRole: .verticalLine",
            "requiresMeaningfulJapaneseRecoveryText: true",
        ]:
            self.assertIn(marker, combined)
        self.assertIn("angle: angle", self.line_path)
        self.assertIn("270", self.orientation)
        self.assertNotIn("maximumJapaneseMangaLineOCRRequests = 9", self.vision)

    def test_workflow_project_and_records_are_advanced(self) -> None:
        contract = "scripts/test-v3372-image-japanese-line-single-rotation-contract.py"
        current = f"python3 -B {contract}"
        previous = (
            "python3 -B scripts/test-v3371-translation-leading-prompt-recovery-contract.py"
        )
        self.assertGreaterEqual(self.workflow.count(current), 1)
        self.assertGreaterEqual(self.workflow.count(previous), 1)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.387", "3.387"],
        )
        for document in self.docs:
            self.assertIn("v3.387", document)
            self.assertIn(contract, document)
            self.assertIn("test/3.png", document)
            self.assertIn("未提供", document)


if __name__ == "__main__":
    unittest.main(verbosity=2)

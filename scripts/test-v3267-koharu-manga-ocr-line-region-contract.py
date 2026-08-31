#!/usr/bin/env python3
"""Contract for routing tight Japanese vertical line regions through Manga OCR."""

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


class KoharuMangaOCRLineRegionContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.manga = read("AITRANS/Services/MangaOCRService.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.line_path = braced_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        cls.line_candidates = braced_body(
            cls.vision,
            "private static func japaneseMangaLineOCRCandidates(",
        )
        cls.line_ocr = braced_body(
            cls.vision,
            "private static func recognizeJapaneseMangaLineOCR(",
        )
        cls.crop = braced_body(
            cls.manga,
            "private static func orientedBoundingBoxCrop(",
        )

    def test_line_path_calls_manga_ocr_before_vision_recovery(self) -> None:
        self.assertIn(
            "let lineRefined = try await Self.recognizeJapaneseVerticalLineCrops(",
            self.vision,
        )
        self.assertIn("let mangaLineRefined = try await recognizeJapaneseMangaLineOCR(", self.line_path)
        self.assertLess(
            self.line_path.index("mangaLineRefined"),
            self.line_path.index("recognizeJapanesePerspectiveLineCrop("),
        )
        self.assertIn("refined.append(contentsOf: mangaLineRefined)", self.line_path)

    def test_candidate_gate_is_tight_japanese_vertical_and_bounded(self) -> None:
        for marker in [
            "candidate.observationRole != .detectorTextRegion",
            "isVerticalLineCandidate(region)",
            "japaneseScriptDensity(in: text) >= 0.5",
            "maximumJapaneseMangaLineOCRRequests = 8",
            "prefix(maximumJapaneseMangaLineOCRRequests)",
        ]:
            self.assertIn(marker, self.line_candidates + self.vision)
        self.assertIn(
            "synthesizedCandidates + uniqueCandidates",
            self.line_candidates,
        )

    def test_requests_use_koharu_line_crop_orientation_and_quad(self) -> None:
        for marker in [
            "textRect: lineRect",
            "expandedVerticalLineCropRect(",
            "cropOrientation: .koharuVerticalLine270",
            "cropQuad: candidate.lineRegionQuad",
            "cropQuadIsVertical: candidate.lineRegionQuad != nil",
            "try await MangaOCRService.shared.recognize(",
            "sourceDirectionHint: .vertical",
            "observationRole: .verticalLine",
        ]:
            self.assertIn(marker, self.line_ocr)
        self.assertIn("case koharuVerticalLine270 = 271", self.manga)
        self.assertIn("case .koharuVerticalLine270:", self.crop)
        self.assertIn("return rotateImage270(crop) ?? crop", self.crop)

    def test_geometry_mapping_does_not_promote_detector_ownership(self) -> None:
        self.assertIn("lineRegionRect: candidate.lineRegionRect ?? candidate.rect", self.line_ocr)
        self.assertIn("lineRegionQuad: candidate.lineRegionQuad", self.line_ocr)
        self.assertNotIn("preservesDetectorTextRegionBoundary: true", self.line_ocr)
        self.assertIn("catch is CancellationError", self.line_ocr)
        self.assertIn("throw CancellationError()", self.line_ocr)
        self.assertIn("catch {\n            return []", self.line_ocr)

    def test_output_gate_rejects_weak_or_non_japanese_line_reads(self) -> None:
        for marker in [
            "cleanRecognizedBlockText(result.text)",
            "let confidence = Self.validOCRConfidence(result.confidence)",
            "confidence >= 0.55",
            "japaneseScriptDensity(in: text) >= 0.5",
        ]:
            self.assertIn(marker, self.line_ocr)
        self.assertIn("text: text", self.line_ocr)

    def test_project_version_and_ci_route_follow_v3266(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(versions, ["3.380", "3.380"])
        previous = "python3 -B scripts/test-v3266-image-ocr-inline-rerecognition-cancel-contract.py"
        current = "python3 -B scripts/test-v3267-koharu-manga-ocr-line-region-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3267-koharu-manga-ocr-line-region-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

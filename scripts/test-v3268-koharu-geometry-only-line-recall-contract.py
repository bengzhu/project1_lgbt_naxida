#!/usr/bin/env python3
"""Contract for geometry-only Japanese vertical line recall.

The candidate may start without recognized text, but it must come from Vision
character geometry, belong to exactly one vertical Japanese layout block, and
remain recognition-only. Empty/weak model output must never reach layout.
"""

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


class KoharuGeometryOnlyLineRecallContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.geometry = braced_body(
            cls.vision,
            "private static func japaneseGeometryOnlyVerticalLineCandidates(",
        )
        cls.pixel_detector = braced_body(
            cls.vision,
            "private static func detectJapanesePixelFirstVerticalRegions(",
        )
        cls.candidates = braced_body(
            cls.vision,
            "private static func japaneseMangaLineOCRCandidates(",
        )
        cls.line_ocr = braced_body(
            cls.vision,
            "private static func recognizeJapaneseMangaLineOCR(",
        )

    def test_geometry_can_start_without_text_but_requires_safe_owner_context(self) -> None:
        for marker in [
            "let lineSeedObservations = observations.filter",
            "observationRole == .verticalLine",
            "characterCount >= 2",
            "cropQuadHint != nil",
            "isVerticalLineCandidate(region.rect)",
            "block.direction == .vertical",
            "validJapaneseDirectionConfidence(",
            "directionConfidence >= 0.25",
            "japaneseScriptDensity(in: block.text) >= 0.5",
            "matchingBlocks.count == 1",
        ]:
            self.assertIn(marker, self.geometry)
        self.assertIn("detection.characterBoxes", self.pixel_detector)

    def test_geometry_has_strict_overlap_and_duplicate_gates(self) -> None:
        for marker in [
            "candidateCoverage >= 0.10",
            "areaRatio <= 1.25",
            "region.rect.width <= max(block.rect.width * 1.25, 0.05)",
            "region.rect.height <= max(block.rect.height * 1.25, 0.05)",
            "duplicatesTextBackedGeometry",
            "overlapRatio(tightRegion, region.rect) >= 0.72",
            "isSameJapaneseLineRegion(candidate, as: $0)",
        ]:
            self.assertIn(marker, self.geometry)

    def test_geometry_is_bounded_and_reserved_without_changing_total_budget(self) -> None:
        for marker in [
            "geometryOnlyCandidates: [VisionOCRObservation]",
            "min(2, maximumJapaneseMangaLineOCRRequests)",
            "maximumJapaneseMangaLineOCRRequests - geometryReserve",
            "let selectedGeometry = boundedJapaneseGeometryOnlyLineCandidates(",
            ".prefix(maximumJapaneseMangaLineOCRRequests)",
        ]:
            self.assertIn(marker, self.candidates + self.vision)
        self.assertTrue(
            "textBacked.prefix(textLimit)" in self.candidates
            or "boundedJapaneseMangaLineTextCandidates(" in self.candidates
        )
        self.assertIn(
            "geometryOnlyCandidates = japaneseGeometryOnlyVerticalLineCandidates(",
            self.vision,
        )

    def test_geometry_result_remains_recognition_only_and_never_emits_empty_layout_text(self) -> None:
        self.assertIn("observationRole: .verticalLine", self.geometry)
        self.assertNotIn("preservesDetectorTextRegionBoundary: true", self.geometry)
        for marker in [
            "cleanRecognizedBlockText(result.text)",
            "let confidence = Self.validOCRConfidence(result.confidence)",
            "confidence >= 0.55",
            "japaneseScriptDensity(in: text) >= 0.5",
        ]:
            self.assertIn(marker, self.line_ocr)

    def test_detector_owner_and_cancellation_boundaries_remain_unchanged(self) -> None:
        self.assertIn("candidate.observationRole != .detectorTextRegion", self.candidates)
        self.assertIn("cropOrientation: .koharuVerticalLine270", self.line_ocr)
        self.assertIn("cropQuad: candidate.lineRegionQuad", self.line_ocr)
        self.assertIn("catch is CancellationError", self.line_ocr)
        self.assertIn("throw CancellationError()", self.line_ocr)
        self.assertIn("catch {\n            return []", self.line_ocr)

    def test_version_and_ci_route(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(versions, ["3.383", "3.383"])
        current = "python3 -B scripts/test-v3268-koharu-geometry-only-line-recall-contract.py"
        self.assertIn(current, self.workflow)
        self.assertIn(
            "if grep -Fx 'scripts/test-v3268-koharu-geometry-only-line-recall-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

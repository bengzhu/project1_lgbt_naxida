#!/usr/bin/env python3
"""Contract for detector-owned Japanese OCR suppressing overlapping page noise."""

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


class JapaneseDetectorOwnedVisionNoiseContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.manga = read("AITRANS/Services/MangaOCRService.swift")
        self.runtime = read(
            "scripts/test-v3218-image-japanese-long-page-manga-ocr-runtime.sh"
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_detector_results_are_kept_as_explicit_owners(self) -> None:
        manga = braced_body(self.vision, "private static func recognizeJapaneseMangaOCR(")
        for marker in [
            "observationRole: .verticalLine",
            "preservesDetectorTextRegionBoundary: true",
            "detectorMangaOCRObservations = await Self.recognizeJapaneseMangaOCR(",
            "observations.append(contentsOf: detectorMangaOCRObservations)",
        ]:
            self.assertIn(marker, self.vision if "detectorManga" in marker else manga)

    def test_page_supplements_are_filtered_before_final_japanese_dedupe(self) -> None:
        helper = braced_body(
            self.vision,
            "private static func suppressJapaneseDetectorOwnedPageSupplements(",
        )
        for marker in [
            "observation.observationRole == .verticalLine",
            "observation.preservesDetectorTextRegionBoundary",
            "observation.observationRole == .page",
            "japaneseScriptDensity(in: observation.text) >= 0.5",
            "overlapRatio(observation.rect, owner.rect) >= 0.60",
            "guard !detectorOwners.isEmpty else { return observations }",
        ]:
            self.assertIn(marker, helper)
        call = "Self.suppressJapaneseDetectorOwnedPageSupplements("
        final_start = self.vision.index("let finalObservations")
        call_index = self.vision.index(call, final_start)
        dedupe_index = self.vision.index(
            "Self.deduplicateJapaneseObservations(", final_start
        )
        self.assertLess(dedupe_index, call_index)

    def test_detector_failure_keeps_historical_vision_fallback(self) -> None:
        helper = braced_body(
            self.vision,
            "private static func suppressJapaneseDetectorOwnedPageSupplements(",
        )
        self.assertIn("guard !detectorOwners.isEmpty else { return observations }", helper)
        self.assertIn("var detectorMangaOCRObservations: [VisionOCRObservation] = []", self.vision)
        self.assertNotIn("suppressJapaneseDetectorOwnedPageSupplements(", self.manga)

    def test_runtime_rejects_only_overlapping_horizontal_detector_duplicates(self) -> None:
        for marker in [
            "horizontal_blocks = [",
            "def minimum_area_overlap(lhs, rhs):",
            "minimum_area_overlap(rect, vertical) >= 0.60",
            '"retained page-level horizontal OCR inside a detector-owned vertical region',
            'sum("爆乳" in value for value in vertical_texts) < 4',
            'sum("挨拶" in value for value in vertical_texts) < 4',
        ]:
            self.assertIn(marker, self.runtime)
        self.assertNotIn('if "ニコッ" in text', self.runtime)

    def test_scope_is_japanese_ocr_only(self) -> None:
        for source in [self.vision, self.manga]:
            for forbidden in [
                "TranslationSessionStore",
                "MangaOverlayProbeService",
                "groundTruth",
                "test/koharu_artifacts",
                "metrics/version_history.csv",
                "output/",
            ]:
                self.assertNotIn(forbidden, source)
        self.assertIn("sourceLanguage == .japanese", self.vision)
        self.assertIn("Self.deduplicateObservations(observations)", self.vision)

    def test_version_and_ci_route_follow_v3220(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 221) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.220;", self.project)
        previous = "python3 -B scripts/test-v3220-image-japanese-long-page-resolution-contract.py"
        current = "python3 -B scripts/test-v3221-image-japanese-detector-owned-vision-noise-contract.py"
        runtime = "bash scripts/test-v3218-image-japanese-long-page-manga-ocr-runtime.sh"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertIn(runtime, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertLess(self.workflow.index(current), self.workflow.index(runtime))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3221-image-japanese-detector-owned-vision-noise-contract.py'",
            self.workflow,
        )

    def test_reference_fixture_is_present(self) -> None:
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 100_000)


if __name__ == "__main__":
    unittest.main(verbosity=2)

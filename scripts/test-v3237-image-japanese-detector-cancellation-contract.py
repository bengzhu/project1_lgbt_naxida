#!/usr/bin/env python3
"""Contract for preserving cancellation across the Japanese detector fallback."""

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


class JapaneseDetectorCancellationContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.detector = read("AITRANS/Services/ComicTextBubbleDetectorService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.manga = braced_body(
            self.vision,
            "private static func recognizeJapaneseMangaOCR(",
        )

    def test_detector_errors_keep_vision_fallback_but_cancellation_escapes(self) -> None:
        self.assertIn(
            "let detectorRegions: [ComicTextDetectorRegion]",
            self.manga,
        )
        self.assertIn(
            "detectorRegions = try await ComicTextBubbleDetectorService.shared.detectTextRegions(",
            self.manga,
        )
        cancellation_index = self.manga.index("catch is CancellationError")
        ordinary_index = self.manga.index("catch {", cancellation_index)
        self.assertLess(cancellation_index, ordinary_index)
        cancellation_body = self.manga[cancellation_index:ordinary_index]
        self.assertIn("throw CancellationError()", cancellation_body)
        ordinary_body = self.manga[ordinary_index:]
        self.assertIn("try Task.checkCancellation()", ordinary_body)
        self.assertIn("detectorRegions = []", ordinary_body)
        self.assertNotIn(
            "try? await ComicTextBubbleDetectorService.shared.detectTextRegions(",
            self.manga,
        )
        self.assertIn("detectJapanesePixelFirstVerticalRegions(", self.manga)
        self.assertIn("japaneseMangaOCRRegions(", self.manga)

    def test_detector_service_checks_cancellation_at_batch_boundaries(self) -> None:
        self.assertIn("try Task.checkCancellation()", self.detector)
        self.assertGreaterEqual(
            self.detector.count("try Task.checkCancellation()"),
            2,
        )

    def test_scope_does_not_change_ocr_ownership_or_non_japanese_paths(self) -> None:
        for marker in [
            "sourceLanguage == .japanese",
            "detectorMangaOCRObservations = try await Self.recognizeJapaneseMangaOCR(",
            "Self.recognizeJapaneseVerticalCrops(",
            "catch is CancellationError",
            "return []",
        ]:
            self.assertIn(marker, self.vision)
        for forbidden in [
            "reference/koharu-main",
            "test/koharu_artifacts",
            "TranslationSessionStore",
            "groundTruth",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.manga)

    def test_version_and_ci_route_follow_v3236(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 237) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.236;", self.project)
        previous = "python3 -B scripts/test-v3236-image-japanese-koharu-tolerant-batch-translation-contract.py"
        current = "python3 -B scripts/test-v3237-image-japanese-detector-cancellation-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3237-image-japanese-detector-cancellation-contract.py'",
            self.workflow,
        )

    def test_fixture_is_present(self) -> None:
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 100_000)


if __name__ == "__main__":
    unittest.main(verbosity=2)

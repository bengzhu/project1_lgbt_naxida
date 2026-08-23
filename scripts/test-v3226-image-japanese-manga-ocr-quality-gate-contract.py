#!/usr/bin/env python3
"""Contract for confidence-gated Japanese Manga OCR detector ownership."""

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


class JapaneseMangaOCRQualityGateContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.manga = read("AITRANS/Services/MangaOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.runtime = read(
            "scripts/test-v3218-image-japanese-long-page-manga-ocr-runtime.sh"
        )
        self.gate = braced_body(
            self.vision,
            "private static func isReliableJapaneseMangaOCRResult(",
        )
        self.manga_path = braced_body(
            self.vision,
            "private static func recognizeJapaneseMangaOCR(",
        )
        self.supplement_gate = braced_body(
            self.vision,
            "private static func suppressJapaneseDetectorOwnedPageSupplements(",
        )

    def test_detector_owner_requires_finite_confidence_and_japanese_evidence(self) -> None:
        for marker in [
            "let confidence = validOCRConfidence(result.confidence)",
            "confidence >= 0.55",
            "japaneseScriptDensity(in: result.text) >= 0.5",
        ]:
            self.assertIn(marker, self.gate)
        self.assertIn(
            "preservesDetectorTextRegionBoundary:\n                    Self.isReliableJapaneseMangaOCRResult(result)",
            self.manga_path,
        )

    def test_weak_results_remain_candidates_without_suppressing_page_fallback(self) -> None:
        self.assertIn(
            "guard !detectorOwners.isEmpty else { return observations }",
            self.supplement_gate,
        )
        self.assertIn(
            "observation.preservesDetectorTextRegionBoundary",
            self.supplement_gate,
        )
        self.assertIn(
            "observation.observationRole == .page",
            self.supplement_gate,
        )
        self.assertIn(
            "overlapRatio(observation.rect, owner.rect) >= 0.60",
            self.supplement_gate,
        )
        self.assertNotIn(
            "preservesDetectorTextRegionBoundary: true",
            self.manga_path,
        )

    def test_failure_and_cancellation_boundaries_remain_unchanged(self) -> None:
        self.assertIn(
            "detectorMangaOCRObservations = try await Self.recognizeJapaneseMangaOCR(",
            self.vision,
        )
        self.assertIn("catch is CancellationError", self.vision)
        self.assertIn("throw CancellationError()", self.vision)
        self.assertIn("catch {\n            // Model loading remains", self.manga_path)
        self.assertIn("return []", self.manga_path)
        self.assertIn("Self.deduplicateObservations(observations)", self.vision)

    def test_scope_is_japanese_only_and_does_not_touch_translation_or_artifacts(self) -> None:
        self.assertIn("sourceLanguage == .japanese", self.vision)
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

    def test_existing_long_page_gate_and_version_route_remain(self) -> None:
        for marker in [
            "minimum_area_overlap(rect, vertical) >= 0.60",
            'sum("爆乳" in value for value in vertical_texts) < 4',
            'sum("挨拶" in value for value in vertical_texts) < 4',
        ]:
            self.assertIn(marker, self.runtime)
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 226) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.225;", self.project)
        previous = "python3 -B scripts/test-v3225-image-japanese-vertical-render-contract.py"
        current = "python3 -B scripts/test-v3226-image-japanese-manga-ocr-quality-gate-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3226-image-japanese-manga-ocr-quality-gate-contract.py'",
            self.workflow,
        )

    def test_reference_fixture_is_present(self) -> None:
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 100_000)


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Contract for preserving Koharu-style vertical direction provenance."""

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


class JapaneseCropDirectionHintContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.resolve = braced_body(
            self.layout,
            "private static func resolveDirection(",
        )
        self.crop_mapper = braced_body(
            self.vision,
            "private static func mapRotatedCropObservation(",
        )
        self.page_mapper = braced_body(
            self.vision,
            "private static func mapRotatedObservation(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_layout_observation_carries_optional_direction_provenance(self) -> None:
        observation = braced_body(
            self.layout,
            "struct ImageOCRLayoutObservation",
        )
        for marker in [
            "var sourceDirectionHint: ImageOCRLayoutDirection? = nil",
            "sourceDirectionHint == .vertical",
            "reason: \"koharuVerticalCropHint\"",
            "observation.sourceDirectionHint == .vertical",
        ]:
            self.assertIn(marker, observation if marker.startswith("var ") else self.resolve)

    def test_hint_precedes_wide_box_fallback_and_stays_japanese_only(self) -> None:
        hint = self.resolve.index("observation.sourceDirectionHint == .vertical")
        wide = self.resolve.index("if horizontalRatio >= 1.35")
        self.assertLess(hint, wide)
        for marker in [
            "allowsVerticalText",
            "prefersMangaReadingOrder",
            "containsTextRun",
            "confidence: 0.84",
        ]:
            self.assertIn(marker, self.resolve)

    def test_only_vertical_japanese_crop_paths_set_the_hint(self) -> None:
        for marker in [
            "sourceDirectionHint: $0.sourceDirectionHint",
            "sourceDirectionHint: .vertical",
        ]:
            self.assertIn(marker, self.vision)
        self.assertIn("sourceDirectionHint: .vertical", self.crop_mapper)
        self.assertNotIn("sourceDirectionHint: .vertical", self.page_mapper)
        self.assertIn("sourceDirectionHint: .vertical", braced_body(
            self.vision,
            "private static func recognizeJapanesePerspectiveLineCrop(",
        ))
        self.assertIn("sourceDirectionHint: .vertical", braced_body(
            self.vision,
            "private static func synthesizeJapaneseVerticalLineCandidates(",
        ))

    def test_boundaries_and_fixture_remain_closed(self) -> None:
        for source in [self.vision, self.layout]:
            for forbidden in [
                "TranslationSessionStore",
                "MangaOverlayProbeService",
                "groundTruth",
                "test/koharu_artifacts",
                "metrics/version_history.csv",
                "output/",
            ]:
                self.assertNotIn(forbidden, source)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3186(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 187) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.186;", self.project)
        old = "python3 -B scripts/test-v3186-image-japanese-vertical-tile-filter-contract.py"
        new = "python3 -B scripts/test-v3187-image-japanese-crop-direction-hint-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
